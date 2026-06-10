# -----------------------------------------------------------------------------
# 1. Local JSON Metadata Generation for Spark Job Definitions
# -----------------------------------------------------------------------------

resource "local_file" "bronze_sales_metadata" {
  filename = "${path.module}/.tmp/sjd_bronze_sales.json"
  content  = jsonencode({
    executableFile             = "Main/fabric_bronze_sales.py"
    defaultLakehouseArtifactId = fabric_lakehouse.sales_lakehouse.id
    language                   = "Python"
    environmentArtifactId      = fabric_environment.streaming_env.id
    retryPolicy = {
      policyType = "SimpleRetry"
      policyProperties = {
        retryCount                      = -1
        intervalBetweenRetriesInSeconds = 60
      }
    }
  })
}

resource "local_file" "silver_sales_metadata" {
  filename = "${path.module}/.tmp/sjd_silver_sales.json"
  content  = jsonencode({
    executableFile             = "Main/fabric_silver_sales.py"
    defaultLakehouseArtifactId = fabric_lakehouse.sales_lakehouse.id
    language                   = "Python"
    environmentArtifactId      = fabric_environment.streaming_env.id
    retryPolicy = {
      policyType = "SimpleRetry"
      policyProperties = {
        retryCount                      = -1
        intervalBetweenRetriesInSeconds = 60
      }
    }
  })
}

resource "local_file" "gold_sales_metadata" {
  filename = "${path.module}/.tmp/sjd_gold_sales.json"
  content  = jsonencode({
    executableFile             = "Main/fabric_gold_sales.py"
    defaultLakehouseArtifactId = fabric_lakehouse.sales_lakehouse.id
    language                   = "Python"
    environmentArtifactId      = null
    retryPolicy                = null
  })
}

# -----------------------------------------------------------------------------
# 2. Spark Job Definitions (SJDs) using SparkJobDefinitionV2 format
# -----------------------------------------------------------------------------

resource "fabric_spark_job_definition" "bronze_sales" {
  workspace_id = fabric_workspace.main.id
  display_name = "sjd_bronze_sales_ingestion"
  format       = "SparkJobDefinitionV2"

  definition = {
    "SparkJobDefinitionV1.json" = {
      source = local_file.bronze_sales_metadata.filename
    }
    "Main/fabric_bronze_sales.py" = {
      source = "${path.module}/../../fabric_bronze_sales.py"
    }
  }
}

resource "fabric_spark_job_definition" "silver_sales" {
  workspace_id = fabric_workspace.main.id
  display_name = "sjd_silver_sales_cleansing"
  format       = "SparkJobDefinitionV2"

  definition = {
    "SparkJobDefinitionV1.json" = {
      source = local_file.silver_sales_metadata.filename
    }
    "Main/fabric_silver_sales.py" = {
      source = "${path.module}/../../fabric_silver_sales.py"
    }
  }
}

resource "fabric_spark_job_definition" "gold_sales" {
  workspace_id = fabric_workspace.main.id
  display_name = "sjd_gold_sales_aggregation"
  format       = "SparkJobDefinitionV2"

  definition = {
    "SparkJobDefinitionV1.json" = {
      source = local_file.gold_sales_metadata.filename
    }
    "Main/fabric_gold_sales.py" = {
      source = "${path.module}/../../fabric_gold_sales.py"
    }
  }
}
