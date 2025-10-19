# S3 Module for AWS Lift and Shift Migration

# Random suffix for bucket name
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# S3 Bucket for application files
resource "aws_s3_bucket" "app_files" {
  bucket = "${var.project_name}-${var.environment}-files-${random_id.bucket_suffix.hex}"

  tags = {
    Name        = "${var.project_name}-${var.environment}-files"
    Environment = var.environment
  }
}

# S3 Bucket Versioning
resource "aws_s3_bucket_versioning" "app_files" {
  bucket = aws_s3_bucket.app_files.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 Bucket Server-side Encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "app_files" {
  bucket = aws_s3_bucket.app_files.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# S3 Bucket Public Access Block
resource "aws_s3_bucket_public_access_block" "app_files" {
  bucket = aws_s3_bucket.app_files.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 Bucket Lifecycle Configuration
resource "aws_s3_bucket_lifecycle_configuration" "app_files" {
  bucket = aws_s3_bucket.app_files.id

  rule {
    id     = "transition_to_ia"
    status = "Enabled"

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    transition {
      days          = 365
      storage_class = "DEEP_ARCHIVE"
    }
  }

  rule {
    id     = "delete_incomplete_multipart_uploads"
    status = "Enabled"

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  rule {
    id     = "delete_old_versions"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

# S3 Bucket Notification (optional - for Lambda triggers)
resource "aws_s3_bucket_notification" "app_files" {
  bucket = aws_s3_bucket.app_files.id

  # Example: Trigger Lambda function on object creation
  # lambda_function {
  #   lambda_function_arn = aws_lambda_function.processor.arn
  #   events              = ["s3:ObjectCreated:*"]
  #   filter_prefix       = "uploads/"
  # }
}

# S3 Bucket Policy for web application access
resource "aws_s3_bucket_policy" "app_files" {
  bucket = aws_s3_bucket.app_files.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowWebAppAccess"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.account_id}:role/${var.project_name}-${var.environment}-ec2-role"
        }
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.app_files.arn,
          "${aws_s3_bucket.app_files.arn}/*"
        ]
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.app_files]
}

# S3 Bucket for backups
resource "aws_s3_bucket" "backups" {
  bucket = "${var.project_name}-${var.environment}-backups-${random_id.bucket_suffix.hex}"

  tags = {
    Name        = "${var.project_name}-${var.environment}-backups"
    Environment = var.environment
  }
}

# S3 Bucket Versioning for backups
resource "aws_s3_bucket_versioning" "backups" {
  bucket = aws_s3_bucket.backups.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 Bucket Server-side Encryption for backups
resource "aws_s3_bucket_server_side_encryption_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# S3 Bucket Public Access Block for backups
resource "aws_s3_bucket_public_access_block" "backups" {
  bucket = aws_s3_bucket.backups.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 Bucket Lifecycle Configuration for backups
resource "aws_s3_bucket_lifecycle_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id

  rule {
    id     = "backup_lifecycle"
    status = "Enabled"

    transition {
      days          = 7
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 30
      storage_class = "GLACIER"
    }

    transition {
      days          = 90
      storage_class = "DEEP_ARCHIVE"
    }

    expiration {
      days = 2555  # 7 years
    }
  }
}

# CloudTrail for S3 API logging (optional)
resource "aws_cloudtrail" "s3_api_logging" {
  count = var.environment == "prod" ? 1 : 0

  name           = "${var.project_name}-${var.environment}-s3-trail"
  s3_bucket_name = aws_s3_bucket.backups.bucket
  s3_key_prefix  = "cloudtrail-logs"

  event_selector {
    read_write_type                 = "All"
    include_management_events       = false
    exclude_management_event_sources = []

    data_resource {
      type   = "AWS::S3::Object"
      values = ["${aws_s3_bucket.app_files.arn}/*"]
    }
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-s3-trail"
  }
}