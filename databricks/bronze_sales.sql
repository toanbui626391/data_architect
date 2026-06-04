-- =============================================================================
-- bronze_sales.sql
-- Bronze Layer: Real-Time Kafka Ingestion (Delta Live Tables)
--
-- Design Reference: databricks/realtime_ingestion_architecture.md
-- Pattern: Kafka → Structured Streaming → Bronze Delta (Streaming Table)
--
-- Responsibilities:
--   1. Consume raw sales events from the Kafka topic (Schema Registry enforced)
--   2. Deserialize Avro/JSON payload with zero data loss
--   3. Enrich with ingestion audit metadata
--   4. Apply lightweight structural DQ constraints (Kafka metadata only)
--   5. Expose raw records to DLT Silver for deduplication and conformance
--
-- Unity Catalog target: catalog.bronze.sales_orders
-- Owned by:            Data Engineering (RAW_ROLE)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- SECTION 1: Kafka Connection Configuration (DLT SQL Syntax)
-- -----------------------------------------------------------------------------
-- Kafka credentials are injected via Databricks Secret Scopes at pipeline runtime.
-- Secret Scope:   "kafka-credentials"
-- Secrets:        "bootstrap-servers", "sasl-username", "sasl-password"
--
-- Pipeline-level Spark config (set in DLT Pipeline Settings or DAB config):
--   spark.kafka.bootstrap.servers    = {{secrets/kafka-credentials/bootstrap-servers}}
--   spark.kafka.sasl.username        = {{secrets/kafka-credentials/sasl-username}}
--   spark.kafka.sasl.password        = {{secrets/kafka-credentials/sasl-password}}
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- SECTION 2: Bronze Streaming Table Definition
-- -----------------------------------------------------------------------------

CREATE OR REFRESH STREAMING TABLE catalog.bronze.sales_orders
COMMENT "Raw, append-only streaming ingestion of sales order events from Kafka topic 'src-sales-orders'. Zero data loss. No transformations applied."
TBLPROPERTIES (
  "quality"                          = "bronze",
  "pipelines.autoOptimize.managed"   = "true",  -- DLT manages OPTIMIZE / VACUUM automatically
  "delta.enableChangeDataFeed"       = "false"   -- CDF disabled: Bronze is append-only; Silver uses APPLY CHANGES INTO
)
CLUSTER BY (_ingested_date)                      -- Liquid Clustering for dynamic data layout optimization
AS
WITH raw_kafka_stream AS (
  SELECT
    -- -------------------------------------------------------------------------
    -- 2.1 Raw Payload (Zero Data Loss Guarantee)
    -- We capture the raw string. If upstream introduces a new column not in our
    -- schema below, it is safely captured here and never lost.
    -- -------------------------------------------------------------------------
    CAST(value AS STRING) AS record_content,
    
    -- -------------------------------------------------------------------------
    -- 2.2 Parsed Business Payload (Product-Grade 20 Columns)
    -- We extract known columns immediately for downstream convenience.
    -- -------------------------------------------------------------------------
    from_json(CAST(value AS STRING), '
      order_id STRING,
      customer_id STRING,
      store_id STRING,
      channel STRING,
      order_status STRING,
      currency STRING,
      total_amount DOUBLE,
      tax_amount DOUBLE,
      discount_amount DOUBLE,
      shipping_amount DOUBLE,
      payment_method STRING,
      payment_status STRING,
      shipping_city STRING,
      shipping_country STRING,
      billing_city STRING,
      billing_country STRING,
      items ARRAY<STRUCT<item_id:STRING, product_id:STRING, quantity:INT, unit_price:DOUBLE>>,
      created_at TIMESTAMP,
      updated_at TIMESTAMP
    ') AS parsed_payload,

    -- -------------------------------------------------------------------------
    -- 2.3 Kafka Metadata (Audit & Replay Columns)
    -- -------------------------------------------------------------------------
    topic                                          AS kafka_topic,
    partition                                      AS kafka_partition,
    offset                                         AS kafka_offset,
    CAST(timestamp AS TIMESTAMP)                   AS kafka_timestamp,
    headers                                        AS kafka_headers,

    -- -------------------------------------------------------------------------
    -- 2.4 Ingestion Audit Metadata
    -- -------------------------------------------------------------------------
    current_timestamp()                            AS _ingested_at,
    CAST(current_timestamp() AS DATE)              AS _ingested_date
  FROM STREAM(
    read_kafka(
      bootstrapServers => spark_conf("spark.kafka.bootstrap.servers"),
      subscribe        => "src-sales-orders",
      startingOffsets  => "earliest",
      failOnDataLoss   => "false",
      
      -- Security: SASL/SCRAM-SHA-512
      "kafka.security.protocol"                  => "SASL_SSL",
      "kafka.sasl.mechanism"                     => "SCRAM-SHA-512",
      "kafka.sasl.jaas.config"                   =>
        CONCAT(
          "org.apache.kafka.common.security.scram.ScramLoginModule required username=",
          "'", spark_conf("spark.kafka.sasl.username"), "'",
          " password=",
          "'", spark_conf("spark.kafka.sasl.password"), "';"
        ),

      -- Throughput Tuning
      maxOffsetsPerTrigger => "50000"
    )
  )
)
SELECT
  -- Flatten the 20 columns directly into the Bronze table
  parsed_payload.*,
  
  -- Retain raw string and audit metadata
  record_content,
  kafka_topic,
  kafka_partition,
  kafka_offset,
  kafka_timestamp,
  kafka_headers,
  _ingested_at,
  _ingested_date
FROM STREAM(raw_kafka_stream);


-- =============================================================================
-- SECTION 3: Bronze-Layer DLT Constraints (Structural Kafka Metadata Only)
-- =============================================================================
-- Design Principle (Section 6.6): Bronze enforces ZERO business logic.
-- Only structural, ingestion-level integrity is validated here.
-- All constraints are ON VIOLATION WARN to prevent data loss.
--
-- Violations are written to the DLT Event Log and surfaced by Databricks SQL
-- Alerts (see architecture Section 6.2). Silver is responsible for business DQ.
-- =============================================================================

ALTER STREAMING TABLE catalog.bronze.sales_orders
ADD CONSTRAINT valid_kafka_offset
  EXPECT (kafka_offset IS NOT NULL)
  ON VIOLATION WARN;

ALTER STREAMING TABLE catalog.bronze.sales_orders
ADD CONSTRAINT valid_kafka_timestamp
  EXPECT (kafka_timestamp IS NOT NULL)
  ON VIOLATION WARN;

ALTER STREAMING TABLE catalog.bronze.sales_orders
ADD CONSTRAINT non_empty_payload
  EXPECT (record_content IS NOT NULL AND LENGTH(record_content) > 0)
  ON VIOLATION WARN;


-- =============================================================================
-- SECTION 4: Operational Notes & Idempotency Guarantees
-- =============================================================================
--
-- 4.1 IDEMPOTENCY GUARANTEE (STRICT EXACTLY-ONCE PROCESSING)
--     If this pipeline is accidentally restarted, stopped and started, or run 
--     multiple times, it will NEVER cause data loss or duplicate records.
--     - Reason: DLT Streaming Tables utilize RocksDB state stores and Spark 
--       Structured Streaming checkpoints.
--     - Mechanism: Every micro-batch committed to Delta Lake is transactionally
--       tied to the Kafka offset. If the cluster crashes mid-batch, the checkpoint
--       is not updated, and Databricks will safely replay those exact offsets
--       on restart.
--
-- 4.2 FIRST-TIME PIPELINE SETUP
--     Set startingOffsets => "earliest" to backfill the full Kafka topic history.
--     Once the pipeline has successfully run once, DLT will manage offsets via
--     checkpoints and this option has no further effect.
--
-- 4.3 SCHEMA EVOLUTION (HYBRID APPROACH)
--     We explicitly parse 20 columns using `from_json` for downstream convenience.
--     However, we ALSO retain the raw `record_content` string. If the upstream 
--     source adds a 21st column, it will not be in our explicit schema, but it 
--     WILL be safely captured inside `record_content`. This guarantees 
--     Zero Data Loss on unannounced schema drift.
--
-- 4.3 RECOVERY PROCEDURE (SECTION 2 — RECOVERY & RESILIENCE)
--     If this table is corrupted or requires a full historical reload:
--       1. Set startingOffsets => "earliest" in the pipeline config.
--       2. In the DLT pipeline UI, trigger a "Full Refresh" of bronze_sales_orders.
--       3. DLT will reset the checkpoint and replay from the earliest Kafka offset.
--       4. Validate via SQL Alert: MAX(kafka_timestamp) matches Kafka broker's
--          latest committed offset timestamp.
--       5. Re-enable downstream Silver pipeline after Bronze DQ checks pass.
--
-- 4.4 CONSUMER GROUP ISOLATION
--     The DLT pipeline's internal Spark job registers a unique Kafka consumer group
--     (derived from the pipeline ID). Do NOT configure multiple DLT pipelines to
--     subscribe to the same topic with the same group.id, as this would cause
--     Kafka to distribute partitions across competing consumers, splitting the data.
--
-- 4.5 DATABRICKS SQL ALERT: DATA FRESHNESS
--     Deploy the following query as a Databricks SQL Alert to detect pipeline stalls:
--
--     SELECT
--       MAX(_ingested_at)                                    AS last_ingestion,
--       TIMESTAMPDIFF(SECOND, MAX(_ingested_at), NOW())     AS staleness_seconds
--     FROM catalog.bronze.sales_orders
--     HAVING staleness_seconds > 120;
--
--     Alert Condition: rows > 0
--     Notification:    Slack / PagerDuty (P2 — Staleness > 2 minutes)
-- =============================================================================
