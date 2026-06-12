# -----------------------------------------------------------------------------
# Upload PySpark Scripts to Databricks Workspace Shared Folder
# -----------------------------------------------------------------------------

resource "databricks_workspace_file" "databricks_utils" {
  source = "${path.module}/../../../../databricks/databricks_utils.py"
  path   = "/Shared/sales_pipeline/databricks_utils.py"
}

resource "databricks_workspace_file" "bronze_sales" {
  source = "${path.module}/../../../../databricks/bronze_sales.py"
  path   = "/Shared/sales_pipeline/bronze_sales.py"
}

resource "databricks_workspace_file" "silver_sales" {
  source = "${path.module}/../../../../databricks/silver_sales.py"
  path   = "/Shared/sales_pipeline/silver_sales.py"
}

resource "databricks_workspace_file" "gold_sales" {
  source = "${path.module}/../../../../databricks/gold_sales.py"
  path   = "/Shared/sales_pipeline/gold_sales.py"
}
