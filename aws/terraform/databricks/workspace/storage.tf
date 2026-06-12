# -----------------------------------------------------------------------------
# 1. DBFS Root Storage Bucket
# -----------------------------------------------------------------------------
resource "aws_s3_bucket" "root_storage" {
  bucket        = "${var.project_name}-dbfs-root-${var.environment}"
  force_destroy = true

  tags = {
    Name        = "${var.project_name}-dbfs-root"
    Environment = var.environment
  }
}

resource "aws_s3_bucket_public_access_block" "root_storage_pab" {
  bucket                  = aws_s3_bucket.root_storage.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "root_storage_versioning" {
  bucket = aws_s3_bucket.root_storage.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "root_storage_sse" {
  bucket = aws_s3_bucket.root_storage.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 Bucket policy for DBFS root
resource "aws_s3_bucket_policy" "root_storage_policy" {
  bucket = aws_s3_bucket.root_storage.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "GrantDatabricksAccess"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::414351767826:root" # Databricks AWS Account
        }
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [
          aws_s3_bucket.root_storage.arn,
          "${aws_s3_bucket.root_storage.arn}/*"
        ]
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# 2. Unity Catalog Metastore Storage Bucket
# -----------------------------------------------------------------------------
resource "aws_s3_bucket" "unity_catalog_storage" {
  bucket        = "${var.project_name}-uc-metastore-${var.environment}"
  force_destroy = true

  tags = {
    Name        = "${var.project_name}-uc-metastore"
    Environment = var.environment
  }
}

resource "aws_s3_bucket_public_access_block" "unity_catalog_pab" {
  bucket                  = aws_s3_bucket.unity_catalog_storage.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "unity_catalog_versioning" {
  bucket = aws_s3_bucket.unity_catalog_storage.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "unity_catalog_sse" {
  bucket = aws_s3_bucket.unity_catalog_storage.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
