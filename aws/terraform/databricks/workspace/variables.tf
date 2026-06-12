variable "aws_region" {
  type        = string
  default     = "us-east-1"
  description = "AWS Region to deploy resources."
}

variable "databricks_account_id" {
  type        = string
  sensitive   = true
  description = "Databricks Account ID (found in Accounts Console)."
}

variable "databricks_client_id" {
  type        = string
  sensitive   = true
  description = "Client ID of the Service Principal with Databricks Account Admin role."
}

variable "databricks_client_secret" {
  type        = string
  sensitive   = true
  description = "Client Secret of the Service Principal with Databricks Account Admin role."
}

variable "vpc_cidr" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR range for the dedicated Databricks VPC."
}

variable "environment" {
  type        = string
  default     = "prod"
  description = "Deployment environment (e.g. prod, staging, dev)."
}

variable "project_name" {
  type        = string
  default     = "sales-intelligence"
  description = "Project name to tag resources."
}
