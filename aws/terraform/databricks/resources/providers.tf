terraform {
  required_providers {
    databricks = {
      source  = "databricks/databricks"
      version = "~> 1.30"
    }
  }
}

# Provider configured for the newly deployed workspace
provider "databricks" {
  host  = var.databricks_workspace_url
  token = var.databricks_token
}
