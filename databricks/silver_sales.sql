-- =============================================================================
-- silver_sales.sql
-- Silver Layer: Cleansed & Deduplicated Entity (Delta Live Tables)
--
-- Design Reference: .agents/rules/08_medallion_architecture_modeling.md
-- Pattern: Streaming View (Cleanse) -> APPLY CHANGES INTO (Deduplicate)
--
-- Responsibilities:
--   1. Type cast and standardize formats (e.g., Currency to UPPER, Amounts to DECIMAL).
--   2. Enforce Syntactic Data Quality (Drop records missing Primary Keys).
--   3. Deduplicate events using SCD Type 1 based on upstream updated_at timestamp.
--   4. Maintain strict idempotency and zero data loss for valid records.
--
-- Unity Catalog target: catalog.silver.sales_orders
-- Owned by:            Data Engineering (TRANSFORM_ROLE)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- SECTION 1: Data Cleansing & Quality View
-- -----------------------------------------------------------------------------
-- We use a Streaming View to act as a staging area for data quality checks
-- and transformations before deduplication. This ensures bad data is filtered
-- out or flagged before it enters the state store.

CREATE OR REFRESH STREAMING LIVE VIEW catalog.silver.vw_sales_orders_clean
(
  -- 1.1 Syntactic Data Quality Constraints
  -- Following Medallion rules: Drop records that cannot be successfully joined downstream.
  CONSTRAINT valid_order_id EXPECT (order_id IS NOT NULL AND order_id != '') ON VIOLATION DROP,
  
  -- We WARN for missing customer_id because a guest checkout might genuinely lack one,
  -- but we still want to flag it for Data Stewards to investigate.
  CONSTRAINT valid_customer_id EXPECT (customer_id IS NOT NULL AND customer_id != '') ON VIOLATION WARN
)
COMMENT "Intermediate streaming view for data cleansing, type casting, and DQ enforcement."
AS SELECT
  -- -------------------------------------------------------------------------
  -- 1.2 Standardization & Type Casting
  -- -------------------------------------------------------------------------
  order_id,
  customer_id,
  store_id,
  
  -- Standardize categorical strings
  UPPER(TRIM(channel))                            AS channel,
  UPPER(TRIM(order_status))                       AS order_status,
  UPPER(TRIM(currency))                           AS currency,
  
  -- Cast financial amounts to precise DECIMALS to avoid floating point drift
  CAST(total_amount AS DECIMAL(18,2))             AS total_amount,
  CAST(tax_amount AS DECIMAL(18,2))               AS tax_amount,
  CAST(discount_amount AS DECIMAL(18,2))          AS discount_amount,
  CAST(shipping_amount AS DECIMAL(18,2))          AS shipping_amount,
  
  UPPER(TRIM(payment_method))                     AS payment_method,
  UPPER(TRIM(payment_status))                     AS payment_status,
  
  -- Address info
  TRIM(shipping_city)                             AS shipping_city,
  UPPER(TRIM(shipping_country))                   AS shipping_country,
  TRIM(billing_city)                              AS billing_city,
  UPPER(TRIM(billing_country))                    AS billing_country,
  
  -- Pass through nested array structure (Items)
  items,
  
  -- Time dimensions
  created_at,
  updated_at,
  CAST(created_at AS DATE)                        AS order_date,

  -- -------------------------------------------------------------------------
  -- 1.3 Medallion Audit Columns (Lineage)
  -- -------------------------------------------------------------------------
  kafka_offset                                    AS _source_kafka_offset,
  _ingested_at                                    AS _bronze_ingested_at,
  current_timestamp()                             AS _silver_processed_at

FROM STREAM(catalog.bronze.sales_orders);


-- -----------------------------------------------------------------------------
-- SECTION 2: Target Table Definition
-- -----------------------------------------------------------------------------
-- Define the target structure for the Silver table. Because we are using 
-- APPLY CHANGES INTO (CDC), we must define the table metadata separately.

CREATE OR REFRESH STREAMING TABLE catalog.silver.sales_orders
COMMENT "Cleansed, deduplicated, and conformed single-source-of-truth for Sales Orders."
TBLPROPERTIES (
  "quality" = "silver",
  "pipelines.autoOptimize.managed" = "true",  -- Enable Auto-Optimize
  "delta.enableChangeDataFeed" = "true"       -- Enabled: Gold layer Materialized Views can compute incrementally
)
CLUSTER BY (order_date, store_id);            -- Liquid Clustering replacing Partitioning


-- -----------------------------------------------------------------------------
-- SECTION 3: Idempotent Deduplication (APPLY CHANGES INTO)
-- -----------------------------------------------------------------------------
-- The APPLY CHANGES INTO operation is strictly idempotent. If the pipeline
-- processes duplicate Kafka offsets, this MERGE operation ensures the target
-- table only reflects the final state based on the updated_at timestamp.

APPLY CHANGES INTO catalog.silver.sales_orders
FROM STREAM(catalog.silver.vw_sales_orders_clean)
  -- Deduplicate based on the Primary Key
  KEYS (order_id)
  
  -- Handle out-of-order arrivals: 
  -- If an older event arrives late, it will NOT overwrite a newer event.
  SEQUENCE BY updated_at
  
  -- Maintain the current state only (SCD Type 1)
  -- For history tracking, use SCD TYPE 2
  STORED AS SCD TYPE 1;
