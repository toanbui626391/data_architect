variable "aws_region" {
  type        = string
  description = "AWS region for deployment"
  default     = "us-east-1"
}

variable "environment" {
  type        = string
  description = "Environment name (e.g., dev, prod)"
  default     = "prod"
}

variable "vpc_id" {
  type        = string
  description = "ID of the target VPC"
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "List of private subnet IDs for MSK and MSK Connect"
}

variable "msk_kafka_version" {
  type        = string
  description = "Kafka version for MSK"
  default     = "3.5.1"
}

variable "msk_instance_type" {
  type        = string
  description = "Broker instance type"
  default     = "kafka.m5.large"
}

variable "sap_db_username" {
  type        = string
  description = "SAP HANA Database Username"
  sensitive   = true
}

variable "sap_db_password" {
  type        = string
  description = "SAP HANA Database Password"
  sensitive   = true
}
