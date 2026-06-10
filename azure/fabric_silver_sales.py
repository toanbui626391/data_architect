# =============================================================================
# fabric_silver_sales.py
# Microsoft Fabric Lakehouse: Cleansed & Deduplicated Entity (PySpark)
#
# Pattern: Bronze Delta -> Spark Streaming -> Silver Delta (SCD Type 1)
#
# Target Table: Files/Tables/silver_sales_orders (Managed OneLake Table)
# Design Rules: .agents/rules/13_clean_code_principles.md
# =============================================================================

import sys
# Ensure Python can load modules from current workspace directory
sys.path.append(".")

from pyspark.sql import SparkSession, DataFrame
from pyspark.sql.functions import col, current_timestamp, to_date, upper, trim, array, lit, when
from fabric_observability import get_spark_session, log_metrics

# -----------------------------------------------------------------------------
# CONSTANTS & CONFIGURATION
# -----------------------------------------------------------------------------
SOURCE_TABLE = "bronze_sales_orders"
TARGET_TABLE = "silver_sales_orders"
DLQ_TABLE = "silver_sales_orders_dlq"
CHECKPOINT_PATH = "Files/checkpoints/silver_sales_orders"

# -----------------------------------------------------------------------------
# MODULAR FUNCTIONS
# -----------------------------------------------------------------------------

def create_silver_tables(spark: SparkSession) -> None:
    """
    Ensures conformed target silver tables and dead letter queues are pre-created.

    Parameters:
        spark (SparkSession): Current active SparkSession.
    """
    # Create the conformed Silver table with Row Tracking/CDF enabled
    spark.sql(f"""
      CREATE TABLE IF NOT EXISTS {TARGET_TABLE} (
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

    # Create the dead letter table to track invalid orders
    spark.sql(f"""
      CREATE TABLE IF NOT EXISTS {DLQ_TABLE} (
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

def read_bronze_stream(spark: SparkSession) -> DataFrame:
    """
    Reads the append-only stream from the Bronze OneLake Delta table.

    Parameters:
        spark (SparkSession): Current active SparkSession.

    Returns:
        DataFrame: Stream DataFrame reading from Bronze.
    """
    return (
        spark.readStream
        .format("delta")
        .table(SOURCE_TABLE)
    )

def transform_silver(bronze_df: DataFrame) -> DataFrame:
    """
    Applies standard cleaning, casting, schema mapping, and runs optional
    data quality checks to label anomalies.

    Parameters:
        bronze_df (DataFrame): Incoming raw Bronze stream DataFrame.

    Returns:
        DataFrame: Transformed and conformed Silver schema DataFrame.
    """
    return (
        bronze_df
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

def process_micro_batch(batch_df: DataFrame, batch_id: int) -> None:
    """
    Processes a streaming micro-batch: routes invalid records to DLQ, and
    executes an idempotent MERGE (SCD Type 1) for valid records.

    Parameters:
        batch_df (DataFrame): Incoming micro-batch DataFrame from Bronze.
        batch_id (int): Incremental micro-batch run ID.
    """
    import time
    start_time = time.time()
    allocated_cus = 0.5  # Streaming autoscale rate
    
    try:
        input_rows = batch_df.count()
        if input_rows == 0:
            return
            
        # Separate valid and invalid records to enforce DQ and routes
        valid_records = batch_df.filter("order_id IS NOT NULL AND order_id != ''")
        invalid_records = batch_df.filter("order_id IS NULL OR order_id = ''")
        
        invalid_count = invalid_records.count()
        valid_count = valid_records.count()
        
        # A. Write invalid records to the Dead Letter Queue (DLQ)
        if invalid_count > 0:
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
                .saveAsTable(DLQ_TABLE)
            )
            
        inserted_rows = 0
        updated_rows = 0
        
        # B. Deduplicate and merge valid records into the Silver table
        if valid_count > 0:
            valid_records.createOrReplaceTempView("ranked_updates")
            
            # SQL Merge executes inside the micro-batch scope
            batch_df.sparkSession.sql(f"""
                MERGE INTO {TARGET_TABLE} AS target
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
            
            # Retrieve merge metrics from the history of silver_sales_orders
            try:
                history_df = batch_df.sparkSession.sql(f"DESCRIBE HISTORY {TARGET_TABLE} LIMIT 1")
                metrics = history_df.select("operationMetrics").collect()[0]["operationMetrics"]
                inserted_rows = int(metrics.get("numTargetRowsInserted", 0))
                updated_rows = int(metrics.get("numTargetRowsUpdated", 0))
            except Exception as history_err:
                print(f"Warning: Failed to fetch merge metrics: {str(history_err)}")
                
        duration_ms = int((time.time() - start_time) * 1000)
        
        # Log success metrics (including the DLQ count as invalid count)
        log_metrics(
            spark=batch_df.sparkSession,
            job_name="sjd_silver_sales_cleansing",
            batch_id=batch_id,
            input_rows=input_rows,
            inserted_rows=inserted_rows,
            updated_rows=updated_rows,
            deleted_rows=invalid_count,
            duration_ms=duration_ms,
            status="Succeeded",
            allocated_cus=allocated_cus
        )
    except Exception as err:
        duration_ms = int((time.time() - start_time) * 1000)
        log_metrics(
            spark=batch_df.sparkSession,
            job_name="sjd_silver_sales_cleansing",
            batch_id=batch_id,
            input_rows=batch_df.count(),
            inserted_rows=0,
            updated_rows=0,
            deleted_rows=0,
            duration_ms=duration_ms,
            status="Failed",
            allocated_cus=allocated_cus,
            error_message=str(err)
        )
        raise err

# -----------------------------------------------------------------------------
# MAIN EXECUTION ENTRYPOINT
# -----------------------------------------------------------------------------
if __name__ == "__main__":
    # Initialize session from shared utility
    spark_session = get_spark_session("fabric_silver_sales", max_executors=3)
    
    # Establish conformed schemas
    create_silver_tables(spark_session)
    
    # Run structured stream using modular pipeline steps
    bronze_stream = read_bronze_stream(spark_session)
    cleansed_df = transform_silver(bronze_stream)
    
    query = (
        cleansed_df.writeStream
        .format("delta")
        .foreachBatch(process_micro_batch)
        .option("checkpointLocation", CHECKPOINT_PATH)
        .start()
    )
    
    query.awaitTermination()
