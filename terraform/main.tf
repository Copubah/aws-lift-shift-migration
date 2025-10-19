# AWS Lift and Shift Migration - Main Terraform Configuration
terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }

  # Remote state backend - uncomment and configure for production
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "migration/terraform.tfstate"
  #   region         = "us-east-1"
  #   encrypt        = true
  #   dynamodb_table = "terraform-state-lock"
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Owner       = var.owner
      CostCenter  = var.cost_center
    }
  }
}

# Data sources
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

# Random password for RDS
resource "random_password" "db_password" {
  length  = 16
  special = true
}

# Store RDS password in AWS Secrets Manager
resource "aws_secretsmanager_secret" "db_password" {
  name                    = "${var.project_name}-${var.environment}-db-password"
  description             = "RDS MySQL password for migration project"
  recovery_window_in_days = 7

  tags = {
    Name = "${var.project_name}-${var.environment}-db-password"
  }
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id     = aws_secretsmanager_secret.db_password.id
  secret_string = jsonencode({
    username = var.db_username
    password = random_password.db_password.result
  })
}

# VPC Module
module "vpc" {
  source = "./modules/vpc"

  project_name = var.project_name
  environment  = var.environment
  vpc_cidr     = var.vpc_cidr
  azs          = slice(data.aws_availability_zones.available.names, 0, 2)
}

# Security Groups Module
module "security_groups" {
  source = "./modules/security"

  project_name = var.project_name
  environment  = var.environment
  vpc_id       = module.vpc.vpc_id
  vpc_cidr     = var.vpc_cidr
}

# RDS Module
module "rds" {
  source = "./modules/rds"

  project_name           = var.project_name
  environment           = var.environment
  vpc_id                = module.vpc.vpc_id
  private_subnet_ids    = module.vpc.private_subnet_ids
  db_security_group_id  = module.security_groups.db_security_group_id
  db_username           = var.db_username
  db_password_secret_arn = aws_secretsmanager_secret.db_password.arn
  db_instance_class     = var.db_instance_class
  allocated_storage     = var.db_allocated_storage
}

# S3 Module
module "s3" {
  source = "./modules/s3"

  project_name = var.project_name
  environment  = var.environment
  account_id   = data.aws_caller_identity.current.account_id
}

# Load Balancer Module
module "alb" {
  source = "./modules/alb"

  project_name          = var.project_name
  environment          = var.environment
  vpc_id               = module.vpc.vpc_id
  public_subnet_ids    = module.vpc.public_subnet_ids
  alb_security_group_id = module.security_groups.alb_security_group_id
}

# IAM Module
module "iam" {
  source = "./modules/iam"

  project_name = var.project_name
  environment  = var.environment
  s3_bucket_arn = module.s3.bucket_arn
}

# CloudWatch Module
module "cloudwatch" {
  source = "./modules/cloudwatch"

  project_name = var.project_name
  environment  = var.environment
  alb_arn_suffix = module.alb.alb_arn_suffix
  target_group_arn_suffix = module.alb.target_group_arn_suffix
  rds_instance_id = module.rds.db_instance_id
}

# DMS Module (for database migration)
module "dms" {
  source = "./modules/dms"

  project_name              = var.project_name
  environment              = var.environment
  vpc_id                   = module.vpc.vpc_id
  private_subnet_ids       = module.vpc.private_subnet_ids
  dms_security_group_id    = module.security_groups.dms_security_group_id
  source_db_endpoint       = var.source_db_endpoint
  source_db_username       = var.source_db_username
  source_db_password       = var.source_db_password
  target_db_endpoint       = module.rds.db_endpoint
  target_db_username       = var.db_username
  target_db_password_secret_arn = aws_secretsmanager_secret.db_password.arn
}

# Launch Template for MGN
resource "aws_launch_template" "web_server" {
  name_prefix   = "${var.project_name}-${var.environment}-web-"
  image_id      = var.ami_id
  instance_type = var.instance_type
  key_name      = var.key_pair_name

  vpc_security_group_ids = [module.security_groups.web_security_group_id]

  iam_instance_profile {
    name = module.iam.ec2_instance_profile_name
  }

  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    db_endpoint = module.rds.db_endpoint
    s3_bucket   = module.s3.bucket_name
    region      = var.aws_region
  }))

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.project_name}-${var.environment}-web-server"
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}