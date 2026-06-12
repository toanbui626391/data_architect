# -----------------------------------------------------------------------------
# 1. Databricks Cross-Account IAM Role
# -----------------------------------------------------------------------------
# Allows Databricks to provision compute resources (EC2 instances, network interfaces)
# in your AWS account.

data "aws_iam_policy_document" "cross_account_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::414351767826:root"] # Databricks service account
    }
    condition {
      test     = "StringEquals"
      variable = "sts:ExternalId"
      values   = [var.databricks_account_id]
    }
  }
}

resource "aws_iam_role" "cross_account_role" {
  name               = "${var.project_name}-databricks-cross-account-role"
  assume_role_policy = data.aws_iam_policy_document.cross_account_assume_role.json

  tags = {
    Name        = "${var.project_name}-cross-account-role"
    Environment = var.environment
  }
}

# The policy required by Databricks for cross-account compute management
resource "aws_iam_policy" "cross_account_policy" {
  name        = "${var.project_name}-databricks-cross-account-policy"
  description = "IAM Policy for Databricks compute provisioning on AWS"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EC2Policy"
        Effect = "Allow"
        Action = [
          "ec2:AssociateRouteTable",
          "ec2:AttachVolume",
          "ec2:AuthorizeSecurityGroupEgress",
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:CancelSpotInstanceRequests",
          "ec2:CreateKeyPair",
          "ec2:CreateRoute",
          "ec2:CreateSecurityGroup",
          "ec2:CreateTags",
          "ec2:CreateVolume",
          "ec2:DeleteKeyPair",
          "ec2:DeleteRoute",
          "ec2:DeleteRouteTable",
          "ec2:DeleteSecurityGroup",
          "ec2:DeleteTags",
          "ec2:DeleteVolume",
          "ec2:DetachVolume",
          "ec2:DisassociateRouteTable",
          "ec2:DisassociateSubnetCidrBlock",
          "ec2:ModifyVpcAttribute",
          "ec2:ReplaceRoute",
          "ec2:ReplaceRouteTableAssociation",
          "ec2:RequestSpotInstances",
          "ec2:RevokeSecurityGroupEgress",
          "ec2:RevokeSecurityGroupIngress",
          "ec2:RunInstances",
          "ec2:TerminateInstances"
        ]
        Resource = "*"
      },
      {
        Sid    = "IAMPassRole"
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = "*"
      },
      {
        Sid    = "VPCReadOnly"
        Effect = "Allow"
        Action = [
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeElasticGpus",
          "ec2:DescribeInstanceStatus",
          "ec2:DescribeInstances",
          "ec2:DescribeInternetGateways",
          "ec2:DescribeKeyPairs",
          "ec2:DescribeNatGateways",
          "ec2:DescribeNetworkAcls",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribePrefixLists",
          "ec2:DescribeRegions",
          "ec2:DescribeRouteTables",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSpotInstanceRequests",
          "ec2:DescribeSpotPriceHistory",
          "ec2:DescribeSubnets",
          "ec2:DescribeTags",
          "ec2:DescribeVpcAttribute",
          "ec2:DescribeVpcs"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "cross_account" {
  role       = aws_iam_role.cross_account_role.name
  policy_arn = aws_iam_policy.cross_account_policy.arn
}

# -----------------------------------------------------------------------------
# 2. Unity Catalog Metastore Access IAM Role
# -----------------------------------------------------------------------------
# Allows the Unity Catalog engine to read/write to the metastore storage bucket.

data "aws_iam_policy_document" "unity_catalog_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::414351767826:root"] # Databricks AWS account for STS trust
    }
    condition {
      test     = "StringEquals"
      variable = "sts:ExternalId"
      values   = [var.databricks_account_id]
    }
  }
}

resource "aws_iam_role" "unity_catalog_role" {
  name               = "${var.project_name}-unity-catalog-role"
  assume_role_policy = data.aws_iam_policy_document.unity_catalog_assume_role.json

  tags = {
    Name        = "${var.project_name}-unity-catalog-role"
    Environment = var.environment
  }
}

resource "aws_iam_policy" "unity_catalog_policy" {
  name        = "${var.project_name}-unity-catalog-policy"
  description = "IAM Policy allowing Unity Catalog access to S3 storage bucket"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3Access"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketLocation",
          "s3:GetLifecycleConfiguration",
          "s3:PutLifecycleConfiguration"
        ]
        Resource = [
          aws_s3_bucket.unity_catalog_storage.arn,
          "${aws_s3_bucket.unity_catalog_storage.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "unity_catalog" {
  role       = aws_iam_role.unity_catalog_role.name
  policy_arn = aws_iam_policy.unity_catalog_policy.arn
}
