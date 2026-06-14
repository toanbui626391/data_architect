# =============================================================================
# databricks_utils.py
# Databricks Lakehouse Shared Utility Module
#
# Contains reusable utilities for configuring Spark Sessions and logging
# execution metrics for Bronze, Silver, and Gold pipelines.
# =============================================================================

import datetime
from typing import Optional
from pyspark.sql import SparkSession
from pyspark.sql.types import StructType, StructField, StringType, LongType, TimestampType, DoubleType

# Default Unity Catalog Name
CATALOG = "catalog"
METRICS_TABLE = f"{CATALOG}.observability.pipeline_execution_metrics"


def get_spark_session(
    app_name: str, 
    max_executors: int = 3
) -> SparkSession:
    """
    Initializes and configures a SparkSession with cost optimization, 
    state store, and file format optimization settings.

    Parameters:
        app_name (str): Name of the Spark Application.
        max_executors (int): Bounded maximum number of executors.

    Returns:
        SparkSession: The configured SparkSession instance.
    """
    spark = SparkSession.builder.appName(app_name).getOrCreate()

    # 1. Flexible Cost Control (Bounded Dynamic Allocation)
    spark.conf.set("spark.dynamicAllocation.enabled", "true")
    spark.conf.set("spark.dynamicAllocation.minExecutors", "1")
    spark.conf.set("spark.dynamicAllocation.maxExecutors", str(max_executors))
    
    # 2. Streaming State Optimization (RocksDB + Changelog Checkpointing)
    spark.conf.set("spark.sql.streaming.stateStore.providerClass", 
                   "org.apache.spark.sql.execution.streaming.state.RocksDBStateStoreProvider")
    spark.conf.set("spark.sql.streaming.stateStore.rocksdb.changelogCheckpointing.enabled", "true")
    
    # 3. Compute Efficiency (Adaptive Query Execution & Shuffle Tuning)
    spark.conf.set("spark.sql.adaptive.enabled", "true")
    spark.conf.set("spark.sql.adaptive.coalescePartitions.enabled", "true")
    spark.conf.set("spark.sql.adaptive.coalescePartitions.initialPartitionNum", "128")
    spark.conf.set("spark.sql.adaptive.coalescePartitions.minPartitionNum", "1")
    spark.conf.set("spark.sql.adaptive.advisoryPartitionSizeInBytes", "67108864") # 64MB target
    spark.conf.set("spark.sql.adaptive.skewJoin.enabled", "true")
    spark.conf.set("spark.sql.adaptive.localShuffleReader.enabled", "true")
    spark.conf.set("spark.sql.shuffle.partitions", "128")
    
    # 4. Delta Lake Small Files & Compaction Tuning (Auto Optimize & Auto Compact)
    spark.conf.set("spark.databricks.delta.properties.defaults.autoOptimize.optimizeWrite", "true")
    spark.conf.set("spark.databricks.delta.properties.defaults.autoOptimize.autoCompact", "true")
    
    return spark


def log_metrics(
    spark: SparkSession,
    job_name: str,
    batch_id: int,
    input_rows: int,
    inserted_rows: int,
    updated_rows: int,
    deleted_rows: int,
    duration_ms: int,
    status: str,
    allocated_cus: float,
    error_message: Optional[str] = None
) -> None:
    """
    Logs run-level execution metrics and cost estimations to a centralized 
    pipeline_execution_metrics Delta table in Unity Catalog.

    Parameters:
        spark (SparkSession): Current active SparkSession.
        job_name (str): Name of the executing Spark Job Definition.
        batch_id (int): Streaming micro-batch ID or unique run ID.
        input_rows (int): Count of incoming records read.
        inserted_rows (int): Count of records successfully created.
        updated_rows (int): Count of records updated.
        deleted_rows (int): Count of records deleted or sent to the DLQ.
        duration_ms (int): Elapsed processing duration in milliseconds.
        status (str): Outcome of the run ('Succeeded' or 'Failed').
        allocated_cus (float): Capacity Units (or DBUs/hr) associated with the compute node.
        error_message (str, optional): Stack trace description if status is 'Failed'.
    """
    # Cost calculation: Job compute estimate is $0.40 per DBU/hr (VM + DBU list price)
    dbu_rate_usd = 0.40
    estimated_cost_usd = (duration_ms / 3600000.0) * allocated_cus * dbu_rate_usd
    
    schema = StructType([
        StructField("job_name", StringType(), True),
        StructField("batch_id", LongType(), True),
        StructField("timestamp", TimestampType(), True),
        StructField("input_rows", LongType(), True),
        StructField("inserted_rows", LongType(), True),
        StructField("updated_rows", LongType(), True),
        StructField("deleted_rows", LongType(), True),
        StructField("execution_duration_ms", LongType(), True),
        StructField("status", StringType(), True),
        StructField("allocated_cus", DoubleType(), True),
        StructField("estimated_cost_usd", DoubleType(), True),
        StructField("error_message", StringType(), True)
    ])
    
    data = [(
        job_name,
        batch_id,
        datetime.datetime.now(),
        input_rows,
        inserted_rows,
        updated_rows,
        deleted_rows,
        duration_ms,
        status,
        float(allocated_cus),
        float(estimated_cost_usd),
        error_message
    )]
    
    metrics_df = spark.createDataFrame(data, schema)
    
    # Pre-create schemas if they don't exist
    spark.sql(f"CREATE SCHEMA IF NOT EXISTS {CATALOG}.observability")
    
    # Ensure metrics table exists in Unity Catalog
    spark.sql(f"""
      CREATE TABLE IF NOT EXISTS {METRICS_TABLE} (
        job_name STRING,
        batch_id LONG,
        timestamp TIMESTAMP,
        input_rows LONG,
        inserted_rows LONG,
        updated_rows LONG,
        deleted_rows LONG,
        execution_duration_ms LONG,
        status STRING,
        allocated_cus DOUBLE,
        estimated_cost_usd DOUBLE,
        error_message STRING
      )
      USING DELTA
      TBLPROPERTIES (
        "quality" = "observability",
        "cost_center" = "finance",
        "environment" = "prod",
        "project" = "revenue_reporting",
        "team" = "data-engineering",
        "delta.autoOptimize.optimizeWrite" = "true",
        "delta.autoOptimize.autoCompact" = "true"
      )
      CLUSTER BY (job_name, timestamp)
    """)
    
    # Append metrics using mergeSchema to adapt to future extensions
    (
        metrics_df.write
        .format("delta")
        .mode("append")
        .option("mergeSchema", "true")
        .saveAsTable(METRICS_TABLE)
    )
