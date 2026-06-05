# ------------------------------------------------------------------------------
# DMS REPLICATION INSTANCE
# ------------------------------------------------------------------------------
resource "aws_dms_replication_subnet_group" "dms_subnet_group" {
  replication_subnet_group_id          = "sap-dms-subnet-group-${var.environment}"
  replication_subnet_group_description = "Subnet group for SAP to MSK DMS replication"
  subnet_ids                           = var.private_subnet_ids
}

resource "aws_dms_replication_instance" "sap_cdc_instance" {
  replication_instance_id     = "sap-cdc-instance-${var.environment}"
  replication_instance_class  = "dms.c5.large"
  allocated_storage           = 100
  multi_az                    = true
  replication_subnet_group_id = aws_dms_replication_subnet_group.dms_subnet_group.id
  vpc_security_group_ids      = [aws_security_group.msk_connect_sg.id] # Reusing the compute SG
  
  tags = {
    Environment = var.environment
    Component   = "CDCIngestion"
  }
}

# ------------------------------------------------------------------------------
# DMS ENDPOINTS
# ------------------------------------------------------------------------------
resource "aws_dms_endpoint" "sap_source" {
  endpoint_id                 = "sap-hana-source-${var.environment}"
  endpoint_type               = "source"
  engine_name                 = "sap" # Native SAP HANA engine support
  server_name                 = "sap-hana.internal"
  port                        = 30015
  secrets_manager_access_role_arn = aws_iam_role.msk_connect_role.arn
  secrets_manager_arn         = aws_secretsmanager_secret.sap_credentials.arn
}

resource "aws_dms_endpoint" "msk_target" {
  endpoint_id   = "msk-kafka-target-${var.environment}"
  endpoint_type = "target"
  engine_name   = "kafka"

  kafka_settings {
    broker                         = aws_msk_cluster.central_bus.bootstrap_brokers_tls
    topic                          = "sap.sales_orders.v1"
    message_format                 = "json" # Note: DMS supports JSON natively; for Avro, additional schema registry logic is needed
    include_control_details        = true
    include_null_and_empty         = true
    include_partition_value        = true
    include_table_alter_operations = true
    include_transaction_details    = true
    
    # Rule 10 Compliance: Security
    security_protocol = "sasl_ssl"
    sasl_mechanism    = "scram-sha-512"
  }
}

# ------------------------------------------------------------------------------
# DMS REPLICATION TASK
# ------------------------------------------------------------------------------
resource "aws_dms_replication_task" "sap_to_msk_task" {
  replication_task_id      = "sap-to-msk-cdc-${var.environment}"
  migration_type           = "full-and-cdc" # Initial load followed by continuous replication
  replication_instance_arn = aws_dms_replication_instance.sap_cdc_instance.replication_instance_arn
  source_endpoint_arn      = aws_dms_endpoint.sap_source.endpoint_arn
  target_endpoint_arn      = aws_dms_endpoint.msk_target.endpoint_arn

  table_mappings = <<EOF
{
  "rules": [
    {
      "rule-type": "selection",
      "rule-id": "1",
      "rule-name": "1",
      "object-locator": {
        "schema-name": "SAP_SCHEMA",
        "table-name": "SALES_ORDERS"
      },
      "rule-action": "include"
    }
  ]
}
EOF

  replication_task_settings = <<EOF
{
  "Logging": {
    "EnableLogging": true
  },
  "ErrorBehavior": {
    "DataErrorPolicy": "LOG_ERROR",
    "DataTruncationErrorPolicy": "LOG_ERROR",
    "DataErrorEscalationPolicy": "SUSPEND_TABLE",
    "DataErrorEscalationCount": 0
  }
}
EOF
}
