# =============================================================================
# bronze_sales.py
# Databricks Lakehouse: Real-Time Kafka Ingestion (PySpark)
#
# Pattern: Kafka -> Spark Structured Streaming -> Bronze Delta Table
#
# Target Table: catalog.bronze.sales_orders (Managed Unity Catalog Table)
# Design Rules: .agents/rules/13_clean_code_principles.md
# =============================================================================

import os
import sys
import time

# Ensure Python can load modules from current script's directory
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from pyspark.sql import SparkSession, DataFrame
from pyspark.sql.functions import col, from_json, current_timestamp, to_date, lit
from databricks_utils import get_spark_session, log_metrics, CATALOG

# -----------------------------------------------------------------------------
# CONSTANTS & CONFIGURATION
# -----------------------------------------------------------------------------
TARGET_TABLE = f"{CATALOG}.bronze.sales_orders"
CHECKPOINT_PATH = f"dbfs:/pipelines/checkpoints/{CATALOG}/bronze_sales_orders"

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

def get_kafka_credentials(spark: SparkSession):
    """
    Fetches Kafka connection details from Spark configuration or Databricks secrets.
    
    Parameters:
        spark (SparkSession): Current active SparkSession.
        
    Returns:
        tuple: (bootstrap_servers, username, password)
    """
    # Attempt reading from Spark Configuration parameters
    bootstrap_servers = spark.conf.get("spark.kafka.bootstrap.servers", None)
    username = spark.conf.get("spark.kafka.sasl.username", None)
    password = spark.conf.get("spark.kafka.sasl.password", None)
    
    # Fallback to Databricks Secret Scope if not configured in SparkSession
    if not (bootstrap_servers and username and password):
        try:
            # We import DBUtils dynamically to ensure local testing doesn't fail
            from pyspark.dbutils import DBUtils
            dbutils = DBUtils(spark)
            bootstrap_servers = bootstrap_servers or dbutils.secrets.get(scope="kafka-credentials", key="bootstrap-servers")
            username = username or dbutils.secrets.get(scope="kafka-credentials", key="sasl-username")
            password = password or dbutils.secrets.get(scope="kafka-credentials", key="sasl-password")
        except Exception as err:
            # Local or testing fallbacks
            print(f"Warning: Failed to fetch secrets from Databricks Secrets: {str(err)}. Using default configurations.")
            bootstrap_servers = bootstrap_servers or "localhost:9092"
            username = username or "default_user"
            password = password or "default_password"
            
    return bootstrap_servers, username, password


def read_kafka(spark: SparkSession) -> DataFrame:
    """
    Connects to Kafka broker and reads real-time stream.

    Parameters:
        spark (SparkSession): Current active SparkSession.

    Returns:
        DataFrame: Stream DataFrame reading from Kafka.
    """
    bootstrap_servers, username, password = get_kafka_credentials(spark)
    
    jaas_config = (
        "org.apache.kafka.common.security.scram.ScramLoginModule required "
        f"username=\"{username}\" password=\"{password}\";"
    )
    
    return (
        spark.readStream
        .format("kafka")
        .option("kafka.bootstrap.servers", bootstrap_servers)
        .option("subscribe", "src-sales-orders")
        .option("startingOffsets", "earliest")
        .option("failOnDataLoss", "false")
        
        # Security protocol: SASL SCRAM-SHA-512
        .option("kafka.security.protocol", "SASL_SSL")
        .option("kafka.sasl.mechanism", "SCRAM-SHA-512")
        .option("kafka.sasl.jaas.config", jaas_config)
        
        # Performance/Throughput Tuning
        .option("maxOffsetsPerTrigger", "50000")
        .load()
    )


def transform_bronze(stream_df: DataFrame) -> DataFrame:
    """
    Parses Kafka JSON payload and adds audit metadata fields.

    Parameters:
        stream_df (DataFrame): Raw Kafka stream DataFrame.

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
            from_json(col("record_content"), PAYLOAD_SCHEMA).alias("parsed"),
            "*"
        )
        .select(
            "parsed.*",
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
    Pre-creates target Unity Catalog Bronze Delta Table if not exists, 
    applying Liquid Clustering and metadata tags as table properties.

    Parameters:
        spark (SparkSession): Current active SparkSession.
    """
    spark.sql(f"CREATE SCHEMA IF NOT EXISTS {CATALOG}.bronze")
    
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
        "cost_center" = "finance",
        "environment" = "prod",
        "project" = "revenue_reporting",
        "team" = "data-engineering",
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
    start_time = time.time()
    allocated_cus = 1.0  # Estimated DBU rate for streaming ingestion node
    
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
            job_name="databricks_bronze_sales_ingestion",
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
            job_name="databricks_bronze_sales_ingestion",
            batch_id=batch_id,
            input_rows=0,
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
    spark_session = get_spark_session("databricks_bronze_sales", max_executors=3)
    
    # Establish target DDL and metadata properties
    create_target_table(spark_session)
    
    # Run structured stream using modular pipeline steps
    raw_stream = read_kafka(spark_session)
    transformed_df = transform_bronze(raw_stream)
    
    query = (
        transformed_df.writeStream
        .format("delta")
        .foreachBatch(process_bronze_batch)
        .option("checkpointLocation", CHECKPOINT_PATH)
        .start()
    )
    
    query.awaitTermination()
