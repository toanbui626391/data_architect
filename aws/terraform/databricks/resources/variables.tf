variable "databricks_workspace_url" {
  type        = string
  description = "The URL of the Databricks Workspace (e.g. from workspace output)."
}

variable "databricks_token" {
  type        = string
  sensitive   = true
  description = "The personal access token or service principal token to authenticate against the workspace."
}

variable "unity_catalog_bucket_arn" {
  type        = string
  description = "The S3 bucket ARN for Unity Catalog storage (e.g. from workspace output)."
}

variable "unity_catalog_role_arn" {
  type        = string
  description = "The IAM role ARN for Unity Catalog access (e.g. from workspace output)."
}

variable "catalog_name" {
  type        = string
  default     = "catalog"
  description = "The name of the Unity Catalog catalog to create."
}
