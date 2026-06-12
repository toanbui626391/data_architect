# -----------------------------------------------------------------------------
# 1. BRONZE & SILVER STREAMING WORKFLOW
# -----------------------------------------------------------------------------
# Runs always-on (continuous) to ingest Kafka streams to Bronze and clean to Silver.

resource "databricks_job" "streaming_pipeline" {
  name = "Sales Real-Time Streaming (Bronze & Silver)"

  # Continuous block ensures the streaming job runs always-on and restarts on failure
  continuous {
    status = "PAUSED" # Initial state paused, can be activated via UI/CLI
  }

  # Job Cluster: shared between the Bronze and Silver tasks to minimize spin-up costs
  job_cluster {
    job_cluster_key = "streaming_cluster"
    new_cluster {
      spark_version = "13.3.x-scala2.12"
      node_type_id  = "m5.xlarge" # AWS general purpose instance
      
      # Driver node runs on-demand (no interruption), workers run on Spot instances
      aws_attributes {
        first_on_demand = 1
        availability    = "SPOT_WITH_FALLBACK"
      }

      # Bounded Auto-scaling (1-3 Workers)
      autoscale {
        min_workers = 1
        max_workers = 3
      }

      # Optimizations aligned with Azure Fabric environment configuration
      spark_conf = {
        "spark.dynamicAllocation.enabled"                                     = "true"
        "spark.dynamicAllocation.minExecutors"                                 = "1"
        "spark.dynamicAllocation.maxExecutors"                                 = "3"
        "spark.sql.streaming.stateStore.providerClass"                         = "org.apache.spark.sql.execution.streaming.state.RocksDBStateStoreProvider"
        "spark.sql.streaming.stateStore.rocksdb.changelogCheckpointing.enabled" = "true"
        "spark.sql.adaptive.enabled"                                           = "true"
        "spark.sql.adaptive.coalescePartitions.enabled"                        = "true"
        "spark.sql.adaptive.coalescePartitions.initialPartitionNum"            = "128"
        "spark.sql.shuffle.partitions"                                         = "128"
      }

      # Metadata Tagging propagated down to AWS resources (FinOps)
      custom_tags = {
        quality     = "silver"
        cost_center = "finance"
        environment = "prod"
        project     = "revenue_reporting"
        team        = "data-engineering"
      }
    }
  }

  # Task 1.1: Bronze Ingestion
  task {
    task_key        = "bronze_sales_ingestion"
    job_cluster_key = "streaming_cluster"

    spark_python_task {
      python_file = databricks_workspace_file.bronze_sales.path
    }
  }

  # Task 1.2: Silver Cleansing & Deduplication (depends on Bronze)
  task {
    task_key        = "silver_sales_cleansing"
    job_cluster_key = "streaming_cluster"
    
    depends_on {
      task_key = "bronze_sales_ingestion"
    }

    spark_python_task {
      python_file = databricks_workspace_file.silver_sales.path
    }
  }
}

# -----------------------------------------------------------------------------
# 2. GOLD BATCH AGGREGATION WORKFLOW (Scheduled)
# -----------------------------------------------------------------------------
# Runs every 15 minutes to compute incremental aggregates via Change Data Feed (CDF).

resource "databricks_job" "gold_aggregation" {
  name = "Sales Daily Aggregation (Gold Batch)"

  schedule {
    quartz_cron_expression = "0 */15 * * * ?" # Run every 15 minutes
    timezone_id            = "UTC"
  }

  # Independent cluster for short-lived batch aggregation
  new_cluster {
    spark_version = "13.3.x-scala2.12"
    node_type_id  = "r5.xlarge" # AWS memory-optimized instance for aggregations
    num_workers   = 1           # Small scale, single worker
    
    aws_attributes {
      first_on_demand = 1
      availability    = "SPOT" # 100% Spot workers for short batch runs (cost savings)
    }

    spark_conf = {
      "spark.sql.adaptive.enabled"                                = "true"
      "spark.sql.adaptive.coalescePartitions.enabled"             = "true"
      "spark.sql.adaptive.coalescePartitions.initialPartitionNum" = "128"
      "spark.sql.shuffle.partitions"                              = "128"
    }

    custom_tags = {
      quality     = "gold"
      cost_center = "finance"
      environment = "prod"
      project     = "revenue_reporting"
      team        = "data-engineering"
    }
  }

  task {
    task_key = "gold_sales_aggregation"

    spark_python_task {
      python_file = databricks_workspace_file.gold_sales.path
    }
  }
}
