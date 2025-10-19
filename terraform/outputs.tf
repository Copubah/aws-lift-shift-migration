# Outputs for AWS Lift and Shift Migration Project

output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = module.vpc.private_subnet_ids
}

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = module.alb.alb_dns_name
}

output "alb_zone_id" {
  description = "Zone ID of the Application Load Balancer"
  value       = module.alb.alb_zone_id
}

output "rds_endpoint" {
  description = "RDS instance endpoint"
  value       = module.rds.db_endpoint
  sensitive   = true
}

output "rds_port" {
  description = "RDS instance port"
  value       = module.rds.db_port
}

output "s3_bucket_name" {
  description = "Name of the S3 bucket for file storage"
  value       = module.s3.bucket_name
}

output "s3_bucket_domain_name" {
  description = "Domain name of the S3 bucket"
  value       = module.s3.bucket_domain_name
}

output "cloudwatch_dashboard_url" {
  description = "URL to the CloudWatch dashboard"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${module.cloudwatch.dashboard_name}"
}

output "secrets_manager_secret_arn" {
  description = "ARN of the Secrets Manager secret containing DB credentials"
  value       = aws_secretsmanager_secret.db_password.arn
  sensitive   = true
}

output "ec2_instance_profile_name" {
  description = "Name of the EC2 instance profile"
  value       = module.iam.ec2_instance_profile_name
}

output "launch_template_id" {
  description = "ID of the launch template for web servers"
  value       = aws_launch_template.web_server.id
}

output "dms_replication_instance_arn" {
  description = "ARN of the DMS replication instance"
  value       = module.dms.replication_instance_arn
}

output "security_group_ids" {
  description = "Security group IDs"
  value = {
    alb = module.security_groups.alb_security_group_id
    web = module.security_groups.web_security_group_id
    db  = module.security_groups.db_security_group_id
    dms = module.security_groups.dms_security_group_id
  }
}

# Connection strings and configuration for applications
output "application_config" {
  description = "Application configuration values"
  value = {
    db_host     = module.rds.db_endpoint
    db_port     = module.rds.db_port
    s3_bucket   = module.s3.bucket_name
    region      = var.aws_region
    alb_dns     = module.alb.alb_dns_name
  }
  sensitive = true
}