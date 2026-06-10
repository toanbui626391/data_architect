# =============================================================================
# fabric_bronze_sales.py
# Microsoft Fabric Lakehouse: Real-Time Event Hubs Ingestion (PySpark)
#
# Pattern: Event Hubs -> Spark Structured Streaming -> Bronze Delta Table
#
# Target Table: Files/Tables/bronze_sales_orders (Managed OneLake Table)
# Design Rules: .agents/rules/12_elt_pipeline_quality_observability.md
# =============================================================================

from pyspark.sql import SparkSession
from pyspark.sql.functions import col, from_json, current_timestamp, to_date

# Initialize Spark Session
spark = SparkSession.builder.getOrCreate()

# -----------------------------------------------------------------------------
# 1. Connection Configurations
# -----------------------------------------------------------------------------
EH_NAMESPACE = "evh-central-prod.servicebus.windows.net:9093"
TOPIC_NAME = "src-sales-orders"

# Credentials should be fetched securely from Key Vault in production
connection_string = (
    "Endpoint=sb://evh-central-prod.servicebus.windows.net/;"
    "SharedAccessKeyName=RootManageSharedAccessKey;SharedAccessKey=SECRET_KEY"
)

jaas_config = (
    "org.apache.kafka.common.security.plain.PlainLoginModule required "
    f"username=\"$ConnectionString\" password=\"{connection_string}\";"
)

# -----------------------------------------------------------------------------
# 2. Configure Read Stream from Event Hubs Kafka Compatibility Endpoint
# -----------------------------------------------------------------------------
eventhubs_stream = (
    spark.readStream
    .format("kafka")
    .option("kafka.bootstrap.servers", EH_NAMESPACE)
    .option("subscribe", TOPIC_NAME)
    .option("startingOffsets", "earliest")
    .option("failOnDataLoss", "false")
    .option("kafka.security.protocol", "SASL_SSL")
    .option("kafka.sasl.mechanism", "PLAIN")
    .option("kafka.sasl.jaas.config", jaas_config)
    .option("kafka.request.timeout.ms", "60000")
    .option("kafka.session.timeout.ms", "60000")
    .option("maxOffsetsPerTrigger", "50000")
    .load()
)

# -----------------------------------------------------------------------------
# 3. Parse Payload with Schema Evolution Rescue Support
# -----------------------------------------------------------------------------
payload_schema = """
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

# Apply schema and capture any unmapped fields in the rescued column
bronze_df = (
    eventhubs_stream
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
            payload_schema, 
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

# -----------------------------------------------------------------------------
# 4. Stream Write to OneLake Delta Table
# -----------------------------------------------------------------------------
# V-Order write optimization is natively applied by the Fabric Spark engine.
checkpoint_path = "Files/checkpoints/bronze_sales_orders"
target_table = "bronze_sales_orders"

# Ensure target table properties and clustering are pre-configured
spark.sql(f"""
  CREATE TABLE IF NOT EXISTS {target_table} (
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

query = (
    bronze_df.writeStream
    .format("delta")
    .outputMode("append")
    .option("checkpointLocation", checkpoint_path)
    .toTable(target_table)
)
