resource "aws_glue_registry" "sap_schema_registry" {
  registry_name = "sap-registry-${var.environment}"
  description   = "Schema Registry for SAP Data Contracts"
}

resource "aws_glue_schema" "sap_sales_orders" {
  schema_name       = "sap.sales_orders.v1"
  registry_arn      = aws_glue_registry.sap_schema_registry.arn
  data_format       = "AVRO"
  compatibility     = "BACKWARD"
  schema_definition = <<EOF
{
  "type": "record",
  "name": "SalesOrder",
  "namespace": "com.sap.erp",
  "fields": [
    {"name": "order_id", "type": "string"},
    {"name": "customer_id", "type": "string"},
    {"name": "total_amount", "type": "double"},
    {"name": "created_at", "type": "long", "logicalType": "timestamp-millis"}
  ]
}
EOF
}
