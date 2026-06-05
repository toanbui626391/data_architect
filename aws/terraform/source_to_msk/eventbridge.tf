# ------------------------------------------------------------------------------
# SQS BUFFER QUEUE
# ------------------------------------------------------------------------------
resource "aws_sqs_queue" "webhook_buffer" {
  name                        = "webhook-buffer-queue-${var.environment}"
  message_retention_seconds   = 86400 # 24 hours
  visibility_timeout_seconds  = 30
  
  # DLQ for events that Pipes cannot deliver to MSK
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.webhook_dlq.arn
    maxReceiveCount     = 5
  })
}

resource "aws_sqs_queue" "webhook_dlq" {
  name = "webhook-dlq-${var.environment}"
}

# ------------------------------------------------------------------------------
# EVENTBRIDGE PIPES (Zero-Code SQS to MSK)
# ------------------------------------------------------------------------------
resource "aws_pipes_pipe" "sqs_to_msk" {
  name     = "webhook-to-msk-pipe-${var.environment}"
  role_arn = aws_iam_role.eventbridge_pipes_role.arn

  # Source: SQS Queue
  source = aws_sqs_queue.webhook_buffer.arn
  source_parameters {
    sqs_queue_parameters {
      batch_size = 10
      maximum_batching_window_in_seconds = 1
    }
  }

  # Target: MSK Cluster (Private Network routing handled via Role and ENIs)
  target = aws_msk_cluster.central_bus.arn
  target_parameters {
    kafka_cluster_parameters {
      topic = "sfdc.account.v1"
    }
  }
}
