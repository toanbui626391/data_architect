# =============================================================================
# fabric_silver_sales.py
# Microsoft Fabric Lakehouse: Cleansed & Deduplicated Entity (PySpark)
#
# Pattern: Bronze Delta -> Spark Streaming -> Silver Delta (SCD Type 1)
#
# Target Table: Files/Tables/silver_sales_orders (Managed OneLake Table)
# Design Rules: .agents/rules/12_elt_pipeline_quality_observability.md
# =============================================================================

from pyspark.sql import SparkSession
from pyspark.sql.functions import col, current_timestamp, to_date, upper, trim
from pyspark.sql.functions import array, lit, when

# Initialize Spark Session
spark = SparkSession.builder.getOrCreate()

# Ensure target tables exist with proper schema and properties
spark.sql("""
  CREATE TABLE IF NOT EXISTS silver_sales_orders (
    order_id STRING,
    customer_id STRING,
    store_id STRING,
    channel STRING,
    order_status STRING,
    currency STRING,
    total_amount DECIMAL(18,2),
    tax_amount DECIMAL(18,2),
    discount_amount DECIMAL(18,2),
    shipping_amount DECIMAL(18,2),
    payment_method STRING,
    payment_status STRING,
    shipping_city STRING,
    shipping_country STRING,
    billing_city STRING,
    billing_country STRING,
    items ARRAY<STRUCT<
      item_id: STRING,
      product_id: STRING,
      quantity: INT,
      unit_price: DOUBLE
    >>,
    created_at TIMESTAMP,
    updated_at TIMESTAMP,
    order_date DATE,
    _source_kafka_offset LONG,
    _bronze_ingested_at TIMESTAMP,
    _silver_processed_at TIMESTAMP,
    _dq_flags ARRAY<STRING>
  )
  USING DELTA
  TBLPROPERTIES (
    "quality" = "silver",
    "delta.enableChangeDataFeed" = "true",
    "delta.autoOptimize.optimizeWrite" = "true"
  )
  CLUSTER BY (order_date, store_id)
""")

spark.sql("""
  CREATE TABLE IF NOT EXISTS silver_sales_orders_dlq (
    record_content STRING,
    kafka_topic STRING,
    kafka_partition INT,
    kafka_offset LONG,
    kafka_timestamp TIMESTAMP,
    _ingested_at TIMESTAMP,
    _dq_failure_reason STRING
  )
  USING DELTA
  TBLPROPERTIES (
    "quality" = "dlq"
  )
  CLUSTER BY (_ingested_at)
""")

# -----------------------------------------------------------------------------
# 1. Read Stream from Bronze Lakehouse Table
# -----------------------------------------------------------------------------
bronze_stream = (
    spark.readStream
    .format("delta")
    .table("bronze_sales_orders")
)

# -----------------------------------------------------------------------------
# 2. Cleanse, Cast, and Add Observability Columns
# -----------------------------------------------------------------------------
cleansed_df = (
    bronze_stream
    .select(
        col("order_id"),
        col("customer_id"),
        col("store_id"),
        upper(trim(col("channel"))).alias("channel"),
        upper(trim(col("order_status"))).alias("order_status"),
        upper(trim(col("currency"))).alias("currency"),
        col("total_amount").cast("decimal(18,2)").alias("total_amount"),
        col("tax_amount").cast("decimal(18,2)").alias("tax_amount"),
        col("discount_amount").cast("decimal(18,2)").alias("discount_amount"),
        col("shipping_amount").cast("decimal(18,2)").alias("shipping_amount"),
        upper(trim(col("payment_method"))).alias("payment_method"),
        upper(trim(col("payment_status"))).alias("payment_status"),
        trim(col("shipping_city")).alias("shipping_city"),
        upper(trim(col("shipping_country"))).alias("shipping_country"),
        trim(col("billing_city")).alias("billing_city"),
        upper(trim(col("billing_country"))).alias("billing_country"),
        col("items"),
        col("created_at"),
        col("updated_at"),
        to_date(col("created_at")).alias("order_date"),
        col("kafka_offset").alias("_source_kafka_offset"),
        col("_ingested_at").alias("_bronze_ingested_at"),
        current_timestamp().alias("_silver_processed_at"),
        col("record_content"),
        col("kafka_topic"),
        col("kafka_partition"),
        col("kafka_timestamp")
    )
    .withColumn(
        "_dq_flags",
        array(
            when(
                col("customer_id").isNull() | (trim(col("customer_id")) == ""),
                lit("WARN_MISSING_CUSTOMER")
            ).otherwise(lit(None))
        )
    )
)

# -----------------------------------------------------------------------------
# 3. Micro-Batch Processing Function (foreachBatch)
# -----------------------------------------------------------------------------
def process_micro_batch(batch_df, batch_id):
    # Separate valid and invalid records to enforce DQ and routes
    valid_records = batch_df.filter("order_id IS NOT NULL AND order_id != ''")
    invalid_records = batch_df.filter("order_id IS NULL OR order_id = ''")
    
    # A. Write invalid records to the Dead Letter Queue (DLQ)
    if invalid_records.count() > 0:
        (
            invalid_records
            .select(
                "record_content",
                "kafka_topic",
                "kafka_partition",
                "_source_kafka_offset",
                "kafka_timestamp",
                "_bronze_ingested_at",
                lit("ERROR: Missing Primary Key (order_id)").alias(
                    "_dq_failure_reason"
                )
            )
            .write
            .format("delta")
            .mode("append")
            .saveAsTable("silver_sales_orders_dlq")
        )
        
    # B. Deduplicate and merge valid records into the Silver table
    if valid_records.count() > 0:
        valid_records.createOrReplaceTempView("ranked_updates")
        
        # SQL Merge executes inside the micro-batch scope
        batch_df.sparkSession.sql("""
            MERGE INTO silver_sales_orders AS target
            USING (
              WITH ranked AS (
                SELECT
                  *,
                  ROW_NUMBER() OVER (
                    PARTITION BY order_id 
                    ORDER BY updated_at DESC, _source_kafka_offset DESC
                  ) as rn
                FROM ranked_updates
              )
              SELECT * EXCEPT (rn, record_content, kafka_topic, 
                               kafka_partition, kafka_timestamp)
              FROM ranked
              WHERE rn = 1
            ) AS source
            ON target.order_id = source.order_id
            WHEN MATCHED AND source.updated_at > target.updated_at THEN
              UPDATE SET *
            WHEN NOT MATCHED THEN
              INSERT *
        """)

# -----------------------------------------------------------------------------
# 4. Start the streaming pipeline
# -----------------------------------------------------------------------------
checkpoint_path = "Files/checkpoints/silver_sales_orders"

query = (
    cleansed_df.writeStream
    .format("delta")
    .foreachBatch(process_micro_batch)
    .option("checkpointLocation", checkpoint_path)
    .start()
)
