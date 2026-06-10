# =============================================================================
# fabric_gold_sales.py
# Microsoft Fabric Lakehouse: Gold Aggregation (PySpark)
#
# Pattern: Silver Delta (CDF) -> Spark Streaming (AvailableNow) -> Gold Star Schema
#
# Target Table: Files/Tables/gold_daily_sales (Managed OneLake Table)
# Orchestration: Scheduled via Data Factory Pipeline (e.g., every 15 mins)
# =============================================================================

from pyspark.sql import SparkSession
from pyspark.sql.functions import col, current_timestamp

# Initialize Spark Session with Batch/Incremental Profile
spark = (
    SparkSession.builder.appName("fabric_gold_sales")
    # 1. Flexible Cost Control
    .config("spark.dynamicAllocation.enabled", "true")
    .config("spark.dynamicAllocation.minExecutors", "1")
    .config("spark.dynamicAllocation.maxExecutors", "4")
    
    # 2. State Optimization (Required for CDF streaming state)
    .config("spark.sql.streaming.stateStore.providerClass", 
            "org.apache.spark.sql.execution.streaming.state.RocksDBStateStoreProvider")
    .config("spark.sql.streaming.stateStore.rocksdb.changelogCheckpointing.enabled", "true")
    
    # 3. Small File Management (Fabric V-Order)
    .config("spark.sql.parquet.vorder.enabled", "true")
    .config("spark.microsoft.delta.optimizeWrite.enabled", "true")
    
    # 4. Compute Efficiency (AQE)
    .config("spark.sql.adaptive.enabled", "true")
    .config("spark.sql.shuffle.partitions", "16")
    .getOrCreate()
)

# -----------------------------------------------------------------------------
# 1. Ensure Target Table Exists (DDL)
# -----------------------------------------------------------------------------
spark.sql("""
  CREATE TABLE IF NOT EXISTS gold_daily_sales (
    order_date DATE,
    store_id STRING,
    total_revenue DOUBLE,
    total_orders BIGINT,
    _gold_updated_at TIMESTAMP
  )
  USING DELTA
  TBLPROPERTIES (
    "quality" = "gold",
    "delta.enableChangeDataFeed" = "true",
    "delta.autoOptimize.optimizeWrite" = "true"
  )
  CLUSTER BY (order_date)
""")

# -----------------------------------------------------------------------------
# 2. Read Incremental Changes from Silver (CDF)
# -----------------------------------------------------------------------------
# We read from Silver as a stream to keep track of processed offsets, 
# but we will use Trigger.AvailableNow to run it as a scheduled batch.
silver_cdf_stream = (
    spark.readStream
    .format("delta")
    .option("readChangeFeed", "true")
    .option("startingVersion", 0) # Ignored if checkpoint exists
    .table("silver_sales_orders")
)

# -----------------------------------------------------------------------------
# 3. Process Changes (foreachBatch + MERGE)
# -----------------------------------------------------------------------------
def merge_into_gold(batch_df, batch_id):
    # Register the micro-batch as a temporary view
    batch_df.createOrReplaceTempView("silver_changes")
    
    # Perform the aggregation and MERGE directly in Spark SQL
    # We only process 'insert' and 'update_postimage' from the CDF
    spark.sql("""
        MERGE INTO gold_daily_sales AS target
        USING (
            SELECT
                CAST(updated_at AS DATE) AS order_date,
                store_id,
                SUM(total_amount)        AS total_revenue,
                COUNT(DISTINCT order_id) AS total_orders,
                current_timestamp()      AS _gold_updated_at
            FROM silver_changes
            WHERE _change_type IN ('insert', 'update_postimage')
            GROUP BY CAST(updated_at AS DATE), store_id
        ) AS source
        ON  target.order_date = source.order_date
        AND target.store_id   = source.store_id
        WHEN MATCHED THEN 
            UPDATE SET 
                target.total_revenue = target.total_revenue + source.total_revenue,
                target.total_orders  = target.total_orders + source.total_orders,
                target._gold_updated_at = source._gold_updated_at
        WHEN NOT MATCHED THEN 
            INSERT (order_date, store_id, total_revenue, total_orders, _gold_updated_at)
            VALUES (source.order_date, source.store_id, source.total_revenue, source.total_orders, source._gold_updated_at)
    """)

# -----------------------------------------------------------------------------
# 4. Execute the Incremental Batch
# -----------------------------------------------------------------------------
checkpoint_path = "Files/checkpoints/gold_daily_sales"

query = (
    silver_cdf_stream.writeStream
    .foreachBatch(merge_into_gold)
    .option("checkpointLocation", checkpoint_path)
    # AvailableNow acts as a one-time batch execution. 
    # It processes all new data since the last run and then gracefully shuts down.
    .trigger(availableNow=True)
    .start()
)

# Block until the batch finishes processing
query.awaitTermination()
