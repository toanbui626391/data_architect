# -----------------------------------------------------------------------------
# 1. Register Cross-Account Credentials in Databricks Account
# -----------------------------------------------------------------------------
resource "databricks_mws_credentials" "this" {
  provider         = databricks.mws
  role_arn         = aws_iam_role.cross_account_role.arn
  credentials_name = "${var.project_name}-credentials"
}

# -----------------------------------------------------------------------------
# 2. Register Root Storage Configuration in Databricks Account
# -----------------------------------------------------------------------------
resource "databricks_mws_storage_configurations" "this" {
  provider                   = databricks.mws
  bucket_name                = aws_s3_bucket.root_storage.id
  storage_configuration_name = "${var.project_name}-storage"
}

# -----------------------------------------------------------------------------
# 3. Register Network Configuration in Databricks Account
# -----------------------------------------------------------------------------
resource "databricks_mws_networks" "this" {
  provider             = databricks.mws
  network_name         = "${var.project_name}-network"
  security_group_ids   = [aws_security_group.databricks_sg.id]
  subnet_ids           = aws_subnet.private_subnets[*].id
  vpc_id               = aws_vpc.databricks_vpc.id
}

# -----------------------------------------------------------------------------
# 4. Provision Databricks Workspace
# -----------------------------------------------------------------------------
resource "databricks_mws_workspaces" "this" {
  provider                 = databricks.mws
  workspace_name           = "${var.project_name}-workspace-${var.environment}"
  aws_region               = var.aws_region
  credentials_id           = databricks_mws_credentials.this.credentials_id
  storage_configuration_id = databricks_mws_storage_configurations.this.storage_configuration_id
  network_id               = databricks_mws_networks.this.network_id

  # Enables the workspace to use Unified Catalog
  pricing_tier = "ENTERPRISE"

  tags = {
    Environment = var.environment
  }
}

# -----------------------------------------------------------------------------
# 5. Infrastructure Outputs
# -----------------------------------------------------------------------------
output "databricks_workspace_url" {
  value       = databricks_mws_workspaces.this.workspace_url
  description = "The unique URL to access your Databricks Workspace."
}

output "databricks_workspace_id" {
  value       = databricks_mws_workspaces.this.workspace_id
  description = "The workspace ID."
}

output "unity_catalog_bucket_arn" {
  value       = aws_s3_bucket.unity_catalog_storage.arn
  description = "The ARN of the S3 bucket designated for Unity Catalog metastore."
}

output "unity_catalog_role_arn" {
  value       = aws_iam_role.unity_catalog_role.arn
  description = "The IAM Role ARN for Unity Catalog storage access."
}
