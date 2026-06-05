resource "aws_sns_topic" "alerts_topic" {
  name = "sap-ingestion-alerts-${var.environment}"
}

# ------------------------------------------------------------------------------
# SAP HANA ALARMS (MSK Connect)
# ------------------------------------------------------------------------------

# P1 Alert: MSK Connect Task Failure (SAP)
resource "aws_cloudwatch_metric_alarm" "sap_connect_task_failure" {
  alarm_name          = "SAPConnectTaskFailed-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "FailedTaskCount"
  namespace           = "AWS/MSKConnect"
  period              = "60"
  statistic           = "Maximum"
  threshold           = "0"
  alarm_description   = "[P1] MSK Connect SAP ingestion task has failed."
  alarm_actions       = [aws_sns_topic.alerts_topic.arn]
  
  dimensions = {
    ConnectorName = aws_mskconnect_connector.sap_sales_orders.name
  }
}

# P2 Alert: MSK Throughput Drop (SAP)
resource "aws_cloudwatch_metric_alarm" "sap_throughput_drop" {
  alarm_name          = "SAPThroughputDrop-${var.environment}"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "3"
  metric_name         = "MessagesInPerSec"
  namespace           = "AWS/Kafka"
  period              = "300"
  statistic           = "Average"
  threshold           = "1"
  alarm_description   = "[P2] SAP Topic throughput dropped to 0 for 15 minutes."
  alarm_actions       = [aws_sns_topic.alerts_topic.arn]

  dimensions = {
    ClusterName = aws_msk_cluster.central_bus.cluster_name
    Topic       = "sap.sales_orders.v1"
  }
}

# ------------------------------------------------------------------------------
# SALESFORCE ALARMS (MSK Connect)
# ------------------------------------------------------------------------------

# P1 Alert: MSK Connect Task Failure (Salesforce)
resource "aws_cloudwatch_metric_alarm" "sfdc_connect_task_failure" {
  alarm_name          = "SFDCConnectTaskFailed-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "FailedTaskCount"
  namespace           = "AWS/MSKConnect"
  period              = "60"
  statistic           = "Maximum"
  threshold           = "0"
  alarm_description   = "[P1] MSK Connect Salesforce ingestion task has failed."
  alarm_actions       = [aws_sns_topic.alerts_topic.arn]
  
  dimensions = {
    ConnectorName = aws_mskconnect_connector.salesforce_cdc.name
  }
}

# P1 Alert: DLQ Contains Messages (Salesforce)
resource "aws_cloudwatch_metric_alarm" "sfdc_dlq_messages" {
  alarm_name          = "SFDCDeadLetterQueueSpike-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "MessagesInPerSec"
  namespace           = "AWS/Kafka"
  period              = "60"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "[P1] Salesforce MSK Connect failed to serialize payload. Check DLQ Topic."
  alarm_actions       = [aws_sns_topic.alerts_topic.arn]

  dimensions = {
    ClusterName = aws_msk_cluster.central_bus.cluster_name
    Topic       = "sfdc.account.dlq"
  }
}

# ------------------------------------------------------------------------------
# API GATEWAY ALARMS (Webhook Push Ingestion)
# ------------------------------------------------------------------------------

# P1 Alert: Edge Validation Errors (Schema changed at source)
resource "aws_cloudwatch_metric_alarm" "apigw_4xx_errors" {
  alarm_name          = "APIGatewayClientErrors-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "4XXError"
  namespace           = "AWS/ApiGateway"
  period              = "60"
  statistic           = "Sum"
  threshold           = "5" # 5 rejected payloads in 1 minute
  alarm_description   = "[P1] API Gateway rejected 5+ Salesforce webhooks (4XX Error). The source system likely changed the JSON schema."
  alarm_actions       = [aws_sns_topic.alerts_topic.arn]

  dimensions = {
    ApiName = aws_api_gateway_rest_api.webhook_api.name
    Stage   = var.environment
  }
}

# P1 Alert: Gateway Integration Errors
resource "aws_cloudwatch_metric_alarm" "apigw_5xx_errors" {
  alarm_name          = "APIGatewayServerErrors-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "5XXError"
  namespace           = "AWS/ApiGateway"
  period              = "60"
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "[P1] API Gateway 5XX Error. SQS Integration or EventBridge Pipe is likely failing."
  alarm_actions       = [aws_sns_topic.alerts_topic.arn]

  dimensions = {
    ApiName = aws_api_gateway_rest_api.webhook_api.name
    Stage   = var.environment
  }
}
