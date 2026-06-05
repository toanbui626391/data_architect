# ------------------------------------------------------------------------------
# SECURITY GROUPS
# ------------------------------------------------------------------------------
resource "aws_security_group" "msk_sg" {
  name        = "msk-cluster-sg-${var.environment}"
  description = "Security group for Amazon MSK Cluster"
  vpc_id      = var.vpc_id

  # Allow ingress on TLS port 9094 from within the VPC (e.g. MSK Connect, Databricks)
  ingress {
    from_port   = 9094
    to_port     = 9094
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.selected.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "msk_connect_sg" {
  name        = "msk-connect-sg-${var.environment}"
  description = "Security group for MSK Connect tasks"
  vpc_id      = var.vpc_id

  # Connect needs egress to MSK, SAP (Transit GW), and Secrets Manager (VPC Endpoint)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

data "aws_vpc" "selected" {
  id = var.vpc_id
}

# ------------------------------------------------------------------------------
# IAM ROLES
# ------------------------------------------------------------------------------
resource "aws_iam_role" "msk_connect_role" {
  name = "msk-connect-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "kafkaconnect.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "msk_connect_policy" {
  name = "msk-connect-policy-${var.environment}"
  role = aws_iam_role.msk_connect_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = [
          aws_secretsmanager_secret.sap_credentials.arn,
          aws_secretsmanager_secret.salesforce_credentials.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "glue:GetSchemaVersion",
          "glue:RegisterSchemaVersion",
          "glue:GetSchema"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "kafka-cluster:Connect",
          "kafka-cluster:DescribeCluster",
          "kafka-cluster:WriteData",
          "kafka-cluster:ReadData",
          "kafka-cluster:AlterGroup"
        ]
        Resource = aws_msk_cluster.central_bus.arn
      }
    ]
  })
}
