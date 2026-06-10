# =============================================================================
# fabric_gold_sales.py
# Microsoft Fabric Lakehouse: Gold Aggregation (PySpark)
#
# Pattern: Silver Delta (CDF) -> Spark Streaming (AvailableNow) -> Gold Star Schema
#
# Target Table: Files/Tables/gold_daily_sales (Managed OneLake Table)
# Orchestration: Scheduled via Data Factory Pipeline (e.g., every 15 mins)
# Design Rules: .agents/rules/13_clean_code_principles.md
# =============================================================================

import sys
# Ensure Python can load modules from current workspace directory
sys.path.append(".")

from pyspark.sql import SparkSession, DataFrame
from fabric_observability import get_spark_session, log_metrics

# -----------------------------------------------------------------------------
# CONSTANTS & CONFIGURATION
# -----------------------------------------------------------------------------
SOURCE_TABLE = "silver_sales_orders"
TARGET_TABLE = "gold_daily_sales"
CHECKPOINT_PATH = "Files/checkpoints/gold_daily_sales"

# -----------------------------------------------------------------------------
# MODULAR FUNCTIONS
# -----------------------------------------------------------------------------

def create_gold_table(spark: SparkSession) -> None:
    """
    Pre-creates target Gold Aggregation table if not exists.

    Parameters:
        spark (SparkSession): Current active SparkSession.
    """
    spark.sql(f"""
      CREATE TABLE IF NOT EXISTS {TARGET_TABLE} (
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

def read_silver_cdf_stream(spark: SparkSession) -> DataFrame:
    """
    Reads incremental changes from the Silver table using Delta Change Data Feed.

    Parameters:
        spark (SparkSession): Current active SparkSession.

    Returns:
        DataFrame: Stream DataFrame reading from Silver CDF.
    """
    return (
        spark.readStream
        .format("delta")
        .option("readChangeFeed", "true")
        .option("startingVersion", 0) # Ignored if checkpoint exists
        .table(SOURCE_TABLE)
    )

def merge_into_gold(batch_df: DataFrame, batch_id: int) -> None:
    """
    Performs incremental running aggregation: calculates net changes from CDF 
    (positive for inserts/post-images, negative for deletes/pre-images) 
    and applies a MERGE into the Gold daily aggregation table.

    Parameters:
        batch_df (DataFrame): Incoming batch DataFrame from Silver CDF.
        batch_id (int): Incremental micro-batch run ID.
    """
    import time
    start_time = time.time()
    
    # Gold batch job runs on Workspace Starter Pool Small cluster (1 driver + 1 executor = 4 CUs)
    allocated_cus = 4.0
    
    try:
        input_rows = batch_df.count()
        if input_rows == 0:
            return
            
        # Register the micro-batch as a temporary view
        batch_df.createOrReplaceTempView("silver_changes")
        
        # Perform incremental aggregation by calculating net changes from CDF:
        # - insert / update_postimage: positive contribution (+total_amount, +1 order)
        # - delete / update_preimage: negative contribution (-total_amount, -1 order)
        spark = batch_df.sparkSession
        spark.sql(f"""
            MERGE INTO {TARGET_TABLE} AS target
            USING (
                SELECT
                    order_date,
                    store_id,
                    SUM(
                        CASE 
                            WHEN _change_type IN ('insert', 'update_postimage') THEN total_amount
                            WHEN _change_type IN ('delete', 'update_preimage') THEN -total_amount
                            ELSE 0
                        END
                    ) AS net_revenue,
                    SUM(
                        CASE 
                            WHEN _change_type IN ('insert', 'update_postimage') THEN 1
                            WHEN _change_type IN ('delete', 'update_preimage') THEN -1
                            ELSE 0
                        END
                    ) AS net_orders,
                    current_timestamp() AS _gold_updated_at
                FROM silver_changes
                GROUP BY order_date, store_id
            ) AS source
            ON  target.order_date = source.order_date
            AND target.store_id   = source.store_id
            WHEN MATCHED THEN 
                UPDATE SET 
                    target.total_revenue = target.total_revenue + source.net_revenue,
                    target.total_orders  = target.total_orders + source.net_orders,
                    target._gold_updated_at = source._gold_updated_at
            WHEN NOT MATCHED THEN 
                INSERT (order_date, store_id, total_revenue, total_orders, _gold_updated_at)
                VALUES (source.order_date, source.store_id, source.net_revenue, source.net_orders, source._gold_updated_at)
        """)
        
        inserted_rows = 0
        updated_rows = 0
        deleted_rows = 0
        
        # Retrieve merge metrics from target table history
        try:
            history_df = spark.sql(f"DESCRIBE HISTORY {TARGET_TABLE} LIMIT 1")
            metrics = history_df.select("operationMetrics").collect()[0]["operationMetrics"]
            inserted_rows = int(metrics.get("numTargetRowsInserted", 0))
            updated_rows = int(metrics.get("numTargetRowsUpdated", 0))
            deleted_rows = int(metrics.get("numTargetRowsDeleted", 0))
        except Exception as history_err:
            print(f"Warning: Failed to fetch merge metrics: {str(history_err)}")
            
        duration_ms = int((time.time() - start_time) * 1000)
        
        log_metrics(
            spark=spark,
            job_name="sjd_gold_sales_aggregation",
            batch_id=batch_id,
            input_rows=input_rows,
            inserted_rows=inserted_rows,
            updated_rows=updated_rows,
            deleted_rows=deleted_rows,
            duration_ms=duration_ms,
            status="Succeeded",
            allocated_cus=allocated_cus
        )
    except Exception as err:
        duration_ms = int((time.time() - start_time) * 1000)
        log_metrics(
            spark=batch_df.sparkSession,
            job_name="sjd_gold_sales_aggregation",
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
    # Initialize session from shared utility (max executors 4 for Gold batch)
    spark_session = get_spark_session("fabric_gold_sales", max_executors=4)
    
    # Establish conformed target DDL
    create_gold_table(spark_session)
    
    # Run structured stream using modular pipeline steps
    silver_cdf_stream = read_silver_cdf_stream(spark_session)
    
    query = (
        silver_cdf_stream.writeStream
        .foreachBatch(merge_into_gold)
        .option("checkpointLocation", CHECKPOINT_PATH)
        # AvailableNow trigger runs the stream as an incremental scheduled batch
        .trigger(availableNow=True)
        .start()
    )
    
    # Block execution until the batch completes
    query.awaitTermination()
