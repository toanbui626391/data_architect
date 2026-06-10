# =============================================================================
# fabric_observability.py
# Microsoft Fabric Lakehouse Shared Observability Module
#
# Contains reusable utilities for configuring Spark Sessions and logging
# execution metrics for Bronze, Silver, and Gold pipelines.
# =============================================================================

import datetime
from typing import Optional
from pyspark.sql import SparkSession
from pyspark.sql.types import StructType, StructField, StringType, LongType, TimestampType, DoubleType

def get_spark_session(
    app_name: str, 
    max_executors: int = 3, 
    shuffle_partitions: int = 16
) -> SparkSession:
    """
    Initializes and configures a SparkSession with cost optimization, 
    state store, and file format optimization settings.

    Parameters:
        app_name (str): Name of the Spark Application.
        max_executors (int): Bounded maximum number of executors.
        shuffle_partitions (int): Number of shuffle partitions.

    Returns:
        SparkSession: The configured SparkSession instance.
    """
    return (
        SparkSession.builder.appName(app_name)
        # 1. Flexible Cost Control (Bounded Dynamic Allocation)
        .config("spark.dynamicAllocation.enabled", "true")
        .config("spark.dynamicAllocation.minExecutors", "1")
        .config("spark.dynamicAllocation.maxExecutors", str(max_executors))
        
        # 2. Streaming State Optimization (RocksDB + Changelog Checkpointing)
        .config("spark.sql.streaming.stateStore.providerClass", 
                "org.apache.spark.sql.execution.streaming.state.RocksDBStateStoreProvider")
        .config("spark.sql.streaming.stateStore.rocksdb.changelogCheckpointing.enabled", "true")
        
        # 3. Small File Management (Fabric V-Order)
        .config("spark.sql.parquet.vorder.enabled", "true")
        .config("spark.microsoft.delta.optimizeWrite.enabled", "true")
        
        # 4. Compute Efficiency (Adaptive Query Execution & Shuffle Tuning)
        .config("spark.sql.adaptive.enabled", "true")
        .config("spark.sql.shuffle.partitions", str(shuffle_partitions))
        .getOrCreate()
    )

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
    pipeline_execution_metrics Delta table in OneLake.

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
        allocated_cus (float): Capacity Units associated with the compute node.
        error_message (str, optional): Stack trace description if status is 'Failed'.
    """
    # Cost calculation: PAYG rate is $0.18 per CU-hour
    cu_rate_usd = 0.18
    estimated_cost_usd = (duration_ms / 3600000.0) * allocated_cus * cu_rate_usd
    
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
    
    # Ensure metrics table exists in OneLake
    spark.sql("""
      CREATE TABLE IF NOT EXISTS pipeline_execution_metrics (
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
        "delta.autoOptimize.optimizeWrite" = "true"
      )
      CLUSTER BY (job_name, timestamp)
    """)
    
    # Append metrics using mergeSchema to adapt to future extensions
    (
        metrics_df.write
        .format("delta")
        .mode("append")
        .option("mergeSchema", "true")
        .saveAsTable("pipeline_execution_metrics")
    )
