# =============================================================================
# fabric_bronze_sales.py
# Microsoft Fabric Lakehouse: Real-Time Event Hubs Ingestion (PySpark)
#
# Pattern: Event Hubs -> Spark Structured Streaming -> Bronze Delta Table
#
# Target Table: Files/Tables/bronze_sales_orders (Managed OneLake Table)
# Design Rules: .agents/rules/13_clean_code_principles.md
# =============================================================================

import sys
# Ensure Python can load modules from current workspace directory
sys.path.append(".")

from pyspark.sql import SparkSession, DataFrame
from pyspark.sql.functions import col, from_json, current_timestamp, to_date
from fabric_observability import get_spark_session, log_metrics

# -----------------------------------------------------------------------------
# CONSTANTS & CONFIGURATION
# -----------------------------------------------------------------------------
EH_NAMESPACE = "evh-central-prod.servicebus.windows.net:9093"
TOPIC_NAME = "src-sales-orders"
CHECKPOINT_PATH = "Files/checkpoints/bronze_sales_orders"
TARGET_TABLE = "bronze_sales_orders"

# Credentials should be fetched securely from Key Vault in production
CONNECTION_STRING = (
    "Endpoint=sb://evh-central-prod.servicebus.windows.net/;"
    "SharedAccessKeyName=RootManageSharedAccessKey;SharedAccessKey=SECRET_KEY"
)

JAAS_CONFIG = (
    "org.apache.kafka.common.security.plain.PlainLoginModule required "
    f"username=\"$ConnectionString\" password=\"{CONNECTION_STRING}\";"
)

PAYLOAD_SCHEMA = """
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
    items ARRAY<STRUCT<
      item_id: STRING,
      product_id: STRING,
      quantity: INT,
      unit_price: DOUBLE
    >>,
    created_at TIMESTAMP,
    updated_at TIMESTAMP
"""

# -----------------------------------------------------------------------------
# MODULAR FUNCTIONS
# -----------------------------------------------------------------------------

def read_eventhubs(spark: SparkSession) -> DataFrame:
    """
    Connects to Azure Event Hubs via Kafka-compatible endpoint and reads stream.

    Parameters:
        spark (SparkSession): Current active SparkSession.

    Returns:
        DataFrame: Stream DataFrame reading from Event Hubs.
    """
    return (
        spark.readStream
        .format("kafka")
        .option("kafka.bootstrap.servers", EH_NAMESPACE)
        .option("subscribe", TOPIC_NAME)
        .option("startingOffsets", "earliest")
        .option("failOnDataLoss", "false")
        .option("kafka.security.protocol", "SASL_SSL")
        .option("kafka.sasl.mechanism", "PLAIN")
        .option("kafka.sasl.jaas.config", JAAS_CONFIG)
        .option("kafka.request.timeout.ms", "60000")
        .option("kafka.session.timeout.ms", "60000")
        .option("maxOffsetsPerTrigger", "50000")
        .load()
    )

def transform_bronze(stream_df: DataFrame) -> DataFrame:
    """
    Parses Event Hubs payload, applies schema evolution rescue, and adds audit metadata.

    Parameters:
        stream_df (DataFrame): Raw Event Hubs stream DataFrame.

    Returns:
        DataFrame: Parsed and transformed Bronze schema DataFrame.
    """
    return (
        stream_df
        .select(
            col("value").cast("string").alias("record_content"),
            col("topic").alias("kafka_topic"),
            col("partition").alias("kafka_partition"),
            col("offset").alias("kafka_offset"),
            col("timestamp").alias("kafka_timestamp"),
            current_timestamp().alias("_ingested_at"),
            to_date(current_timestamp()).alias("_ingested_date")
        )
        .select(
            from_json(
                col("record_content"), 
                PAYLOAD_SCHEMA, 
                {"rescuedDataColumn": "_rescued_data_"}
            ).alias("parsed"),
            "*"
        )
        .select(
            "parsed.*",
            "_rescued_data",
            "record_content",
            "kafka_topic",
            "kafka_partition",
            "kafka_offset",
            "kafka_timestamp",
            "_ingested_at",
            "_ingested_date"
        )
    )

def create_target_table(spark: SparkSession) -> None:
    """
    Pre-creates target OneLake Delta Table if not exists.

    Parameters:
        spark (SparkSession): Current active SparkSession.
    """
    spark.sql(f"""
      CREATE TABLE IF NOT EXISTS {TARGET_TABLE} (
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
        items ARRAY<STRUCT<
          item_id: STRING,
          product_id: STRING,
          quantity: INT,
          unit_price: DOUBLE
        >>,
        created_at TIMESTAMP,
        updated_at TIMESTAMP,
        _rescued_data STRING,
        record_content STRING,
        kafka_topic STRING,
        kafka_partition INT,
        kafka_offset LONG,
        kafka_timestamp TIMESTAMP,
        _ingested_at TIMESTAMP,
        _ingested_date DATE
      )
      USING DELTA
      TBLPROPERTIES (
        "quality" = "bronze",
        "delta.autoOptimize.optimizeWrite" = "true"
      )
      CLUSTER BY (_ingested_date)
    """)

def process_bronze_batch(batch_df: DataFrame, batch_id: int) -> None:
    """
    Appends micro-batch to Bronze table and logs performance analytics.

    Parameters:
        batch_df (DataFrame): Incoming batch DataFrame.
        batch_id (int): Incremental micro-batch run ID.
    """
    import time
    start_time = time.time()
    allocated_cus = 0.5  # Streaming autoscale rate
    
    try:
        input_rows = batch_df.count()
        if input_rows == 0:
            return
            
        (
            batch_df.write
            .format("delta")
            .mode("append")
            .saveAsTable(TARGET_TABLE)
        )
        
        duration_ms = int((time.time() - start_time) * 1000)
        
        log_metrics(
            spark=batch_df.sparkSession,
            job_name="sjd_bronze_sales_ingestion",
            batch_id=batch_id,
            input_rows=input_rows,
            inserted_rows=input_rows,
            updated_rows=0,
            deleted_rows=0,
            duration_ms=duration_ms,
            status="Succeeded",
            allocated_cus=allocated_cus
        )
    except Exception as err:
        duration_ms = int((time.time() - start_time) * 1000)
        log_metrics(
            spark=batch_df.sparkSession,
            job_name="sjd_bronze_sales_ingestion",
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
    spark_session = get_spark_session("fabric_bronze_sales", max_executors=3)
    
    # Establish target DDL
    create_target_table(spark_session)
    
    # Run structured stream using modular pipeline steps
    raw_stream = read_eventhubs(spark_session)
    transformed_df = transform_bronze(raw_stream)
    
    query = (
        transformed_df.writeStream
        .format("delta")
        .foreachBatch(process_bronze_batch)
        .option("checkpointLocation", CHECKPOINT_PATH)
        .start()
    )
    
    query.awaitTermination()
