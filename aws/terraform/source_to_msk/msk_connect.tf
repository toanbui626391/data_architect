resource "aws_mskconnect_worker_configuration" "sfdc_worker_config" {
  name        = "sfdc-worker-config-${var.environment}"
  description = "Worker config for Salesforce CDC Connector"
  properties_file_content = <<EOF
key.converter=io.confluent.connect.avro.AvroConverter
value.converter=io.confluent.connect.avro.AvroConverter
key.converter.schema.registry.url=https://glue-schema-registry
value.converter.schema.registry.url=https://glue-schema-registry
EOF
}

# ------------------------------------------------------------------------------
# SAP HANA JDBC CONNECTOR
# ------------------------------------------------------------------------------
resource "aws_mskconnect_custom_plugin" "sap_jdbc" {
  name         = "sap-jdbc-plugin-${var.environment}"
  content_type = "ZIP"

  location {
    s3 {
      bucket_arn = "arn:aws:s3:::sap-connector-plugins-${var.environment}"
      file_key   = "sap-jdbc-connector-1.0.0.zip"
    }
  }
}

resource "aws_mskconnect_connector" "sap_sales_orders" {
  name = "sap-sales-orders-connector-${var.environment}"

  kafkaconnect_version = "2.7.1"

  capacity {
    autoscaling {
      mcu_count        = 1
      min_worker_count = 1
      max_worker_count = 4
      
      scale_in_policy {
        cpu_utilization_percentage = 20
      }
      
      scale_out_policy {
        cpu_utilization_percentage = 80
      }
    }
  }

  connector_configuration = {
    "connector.class" = "io.confluent.connect.jdbc.JdbcSourceConnector"
    "tasks.max"       = "2"
    
    # DB Connection mapped from secrets manager dynamically
    "connection.url"      = "jdbc:sap://${var.sap_db_username}:${var.sap_db_password}@sap-hana.internal:30015"
    "table.whitelist"     = "SALES_ORDERS"
    "mode"                = "timestamp+incrementing"
    "incrementing.column.name" = "id"
    "timestamp.column.name"    = "updated_at"
    
    # Output Topic naming convention
    "topic.prefix" = "sap.sales_orders."
    
    # Rule 10 Compliance: DLQ and Zero Data Loss guarantees
    "errors.tolerance"        = "all"
    "errors.deadletterqueue.topic.name" = "sap.sales_orders.dlq"
    "errors.deadletterqueue.context.headers.enable" = "true"
    "producer.override.acks"               = "all"
    "producer.override.enable.idempotence" = "true"
  }

  kafka_cluster {
    apache_kafka_cluster {
      bootstrap_servers = aws_msk_cluster.central_bus.bootstrap_brokers_tls
      vpc {
        security_groups = [aws_security_group.msk_connect_sg.id]
        subnets         = var.private_subnet_ids
      }
    }
  }

  kafka_cluster_client_authentication {
    authentication_type = "NONE"
  }

  kafka_cluster_encryption_in_transit {
    encryption_type = "TLS"
  }

  plugin {
    custom_plugin {
      arn      = aws_mskconnect_custom_plugin.sap_jdbc.arn
      revision = aws_mskconnect_custom_plugin.sap_jdbc.latest_revision
    }
  }

  service_execution_role_arn = aws_iam_role.msk_connect_role.arn

  worker_configuration {
    arn      = aws_mskconnect_worker_configuration.sfdc_worker_config.arn # Assuming shared worker config
    revision = aws_mskconnect_worker_configuration.sfdc_worker_config.latest_revision
  }
}

# ------------------------------------------------------------------------------
# SALESFORCE SOURCE CONNECTOR
# ------------------------------------------------------------------------------
# The custom plugin requires a pre-existing S3 bucket containing the Salesforce Source Connector zip
resource "aws_mskconnect_custom_plugin" "sfdc_cdc" {
  name         = "sfdc-cdc-plugin-${var.environment}"
  content_type = "ZIP"

  location {
    s3 {
      bucket_arn = "arn:aws:s3:::connector-plugins-${var.environment}"
      file_key   = "salesforce-cdc-connector-1.0.0.zip"
    }
  }
}

resource "aws_mskconnect_connector" "salesforce_cdc" {
  name = "sfdc-cdc-connector-${var.environment}"

  kafkaconnect_version = "2.7.1"

  capacity {
    autoscaling {
      mcu_count        = 1
      min_worker_count = 1
      max_worker_count = 3
      
      scale_in_policy {
        cpu_utilization_percentage = 20
      }
      
      scale_out_policy {
        cpu_utilization_percentage = 80
      }
    }
  }

  connector_configuration = {
    "connector.class" = "io.confluent.salesforce.SalesforceSourceConnector"
    "tasks.max"       = "1"
    
    # Salesforce API configuration mapped dynamically
    "salesforce.client.id"       = var.salesforce_client_id
    "salesforce.jwt.private.key" = var.salesforce_private_key
    "salesforce.login.url"       = var.salesforce_login_url
    
    # Subscribe to CDC Channels via Pub/Sub API
    "salesforce.push.topic.name" = "/data/AccountChangeEvent"
    "kafka.topic"                = "sfdc.account.v1"
    
    # Rule 10 Compliance: DLQ and Zero Data Loss guarantees
    "errors.tolerance"        = "all"
    "errors.deadletterqueue.topic.name" = "sfdc.account.dlq"
    "errors.deadletterqueue.context.headers.enable" = "true"
    "producer.override.acks"               = "all"
    "producer.override.enable.idempotence" = "true"
  }

  kafka_cluster {
    apache_kafka_cluster {
      bootstrap_servers = aws_msk_cluster.central_bus.bootstrap_brokers_tls
      vpc {
        security_groups = [aws_security_group.msk_connect_sg.id]
        subnets         = var.private_subnet_ids
      }
    }
  }

  kafka_cluster_client_authentication {
    authentication_type = "NONE" # Update to IAM/SASL based on exact MSK Auth configured
  }

  kafka_cluster_encryption_in_transit {
    encryption_type = "TLS"
  }

  plugin {
    custom_plugin {
      arn      = aws_mskconnect_custom_plugin.sfdc_cdc.arn
      revision = aws_mskconnect_custom_plugin.sfdc_cdc.latest_revision
    }
  }

  service_execution_role_arn = aws_iam_role.msk_connect_role.arn

  worker_configuration {
    arn      = aws_mskconnect_worker_configuration.sfdc_worker_config.arn
    revision = aws_mskconnect_worker_configuration.sfdc_worker_config.latest_revision
  }
}
