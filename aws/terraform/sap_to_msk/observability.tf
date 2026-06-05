resource "aws_sns_topic" "alerts_topic" {
  name = "sap-ingestion-alerts-${var.environment}"
}

# P1 Alert: DMS Task Failure
resource "aws_cloudwatch_metric_alarm" "dms_task_failure" {
  alarm_name          = "DMSTaskFailed-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "ReplicationTaskStatus"
  namespace           = "AWS/DMS"
  period              = "60"
  statistic           = "Minimum"
  threshold           = "0" # Status 0 or below indicates a stopped/failed state
  alarm_description   = "[P1] DMS CDC task has failed or stopped."
  alarm_actions       = [aws_sns_topic.alerts_topic.arn]
  
  dimensions = {
    ReplicationTaskIdentifier = aws_dms_replication_task.sap_to_msk_task.replication_task_id
  }
}

# P2 Alert: CDC Target Latency
resource "aws_cloudwatch_metric_alarm" "dms_cdc_latency" {
  alarm_name          = "DMSCDCTargetLatency-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "3"
  metric_name         = "CDCLatencyTarget"
  namespace           = "AWS/DMS"
  period              = "300"
  statistic           = "Average"
  threshold           = "300" # 5 minutes of latency
  alarm_description   = "[P2] SAP CDC latency to MSK exceeds 5 minutes."
  alarm_actions       = [aws_sns_topic.alerts_topic.arn]

  dimensions = {
    ReplicationInstanceIdentifier = aws_dms_replication_instance.sap_cdc_instance.replication_instance_id
  }
}

# P2 Alert: MSK Throughput Drop
resource "aws_cloudwatch_metric_alarm" "msk_throughput_drop" {
  alarm_name          = "MSKThroughputDrop-${var.environment}"
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
