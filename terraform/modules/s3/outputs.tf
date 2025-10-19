output "bucket_name" {
  description = "Name of the S3 bucket for application files"
  value       = aws_s3_bucket.app_files.bucket
}

output "bucket_arn" {
  description = "ARN of the S3 bucket for application files"
  value       = aws_s3_bucket.app_files.arn
}

output "bucket_domain_name" {
  description = "Domain name of the S3 bucket"
  value       = aws_s3_bucket.app_files.bucket_domain_name
}

output "backup_bucket_name" {
  description = "Name of the S3 bucket for backups"
  value       = aws_s3_bucket.backups.bucket
}

output "backup_bucket_arn" {
  description = "ARN of the S3 bucket for backups"
  value       = aws_s3_bucket.backups.arn
}