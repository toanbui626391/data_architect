terraform {
  required_providers {
    fabric = {
      source  = "microsoft/fabric"
      version = "~> 0.1" # Use the latest available provider version
    }
  }
}

provider "fabric" {
  # Authentication is typically handled via Azure CLI or Service Principal environment variables
  # ARM_CLIENT_ID, ARM_CLIENT_SECRET, ARM_TENANT_ID
}

variable "workspace_name" {
  type    = string
  default = "sales_realtime_lakehouse_prod"
}

variable "capacity_id" {
  type        = string
  description = "The ID of the Fabric F-SKU Capacity with Autoscale Billing Enabled"
}

# -----------------------------------------------------------------------------
# 1. Fabric Workspace
# -----------------------------------------------------------------------------
resource "fabric_workspace" "main" {
  display_name = var.workspace_name
  description  = "Production Real-Time Sales Lakehouse"
  capacity_id  = var.capacity_id
}

# -----------------------------------------------------------------------------
# 2. Fabric Lakehouse
# -----------------------------------------------------------------------------
resource "fabric_lakehouse" "sales_lakehouse" {
  display_name = "sales_lakehouse"
  description  = "Unified Lakehouse for Bronze, Silver, and Gold"
  workspace_id = fabric_workspace.main.id
}

# -----------------------------------------------------------------------------
# 3. Custom Spark Pool (Cost-Optimized Streaming)
# -----------------------------------------------------------------------------
resource "fabric_spark_custom_pool" "streaming_pool" {
  workspace_id = fabric_workspace.main.id
  name         = "StreamingPoolSmall"
  
  # Lock down the node family and size for cost control
  node_family  = "MemoryOptimized"
  node_size    = "Small" # 4 vCores, 32GB RAM per node

  # Strict Autoscaling limits (preventing massive CU drain)
  auto_scale {
    enabled  = true
    min_node = 1
    max_node = 3
  }

  # Disable dynamic executor allocation at the pool level
  dynamic_executor_allocation {
    enabled = false
  }
}

# -----------------------------------------------------------------------------
# 4. Custom Spark Environment (Cost-Optimized Streaming)
# -----------------------------------------------------------------------------
resource "fabric_environment" "streaming_env" {
  workspace_id = fabric_workspace.main.id
  display_name = "env_streaming_sales_orders"
  description  = "Spark Environment for Bronze and Silver Streaming Jobs"
}

resource "fabric_spark_environment_settings" "streaming_env_settings" {
  workspace_id       = fabric_workspace.main.id
  environment_id     = fabric_environment.streaming_env.id
  publication_status = "Published"

  driver_cores    = 4
  driver_memory   = "28g"
  executor_cores  = 4
  executor_memory = "28g"
  runtime_version = "1.2" # Adjust based on your Fabric default runtime version

  dynamic_executor_allocation = {
    enabled       = false
    max_executors = 3
    min_executors = 1
  }

  pool = {
    name = fabric_spark_custom_pool.streaming_pool.name
    type = "Workspace"
  }

  spark_properties = {
    "spark.sql.streaming.stateStore.providerClass"                       = "org.apache.spark.sql.execution.streaming.state.RocksDBStateStoreProvider"
    "spark.sql.streaming.stateStore.rocksdb.changelogCheckpointing.enabled" = "true"
    "spark.sql.shuffle.partitions"                                       = "12"
  }
}
