# RDS Module for AWS Lift and Shift Migration

# DB Subnet Group
resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-${var.environment}-db-subnet-group"
  subnet_ids = var.private_subnet_ids

  tags = {
    Name = "${var.project_name}-${var.environment}-db-subnet-group"
  }
}

# DB Parameter Group
resource "aws_db_parameter_group" "main" {
  family = "mysql8.0"
  name   = "${var.project_name}-${var.environment}-db-params"

  parameter {
    name  = "innodb_buffer_pool_size"
    value = "{DBInstanceClassMemory*3/4}"
  }

  parameter {
    name  = "slow_query_log"
    value = "1"
  }

  parameter {
    name  = "long_query_time"
    value = "2"
  }

  parameter {
    name  = "general_log"
    value = "0"
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-db-params"
  }
}

# DB Option Group
resource "aws_db_option_group" "main" {
  name                 = "${var.project_name}-${var.environment}-db-options"
  option_group_description = "Option group for ${var.project_name} ${var.environment}"
  engine_name          = "mysql"
  major_engine_version = "8.0"

  tags = {
    Name = "${var.project_name}-${var.environment}-db-options"
  }
}

# Get DB password from Secrets Manager
data "aws_secretsmanager_secret_version" "db_password" {
  secret_id = var.db_password_secret_arn
}

locals {
  db_credentials = jsondecode(data.aws_secretsmanager_secret_version.db_password.secret_string)
}

# RDS Instance
resource "aws_db_instance" "main" {
  identifier = "${var.project_name}-${var.environment}-mysql"

  # Engine configuration
  engine         = "mysql"
  engine_version = "8.0.35"
  instance_class = var.db_instance_class

  # Storage configuration
  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.allocated_storage * 2
  storage_type          = "gp3"
  storage_encrypted     = true

  # Database configuration
  db_name  = replace("${var.project_name}_${var.environment}", "-", "_")
  username = local.db_credentials.username
  password = local.db_credentials.password

  # Network configuration
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [var.db_security_group_id]
  publicly_accessible    = false
  port                   = 3306

  # Parameter and option groups
  parameter_group_name = aws_db_parameter_group.main.name
  option_group_name    = aws_db_option_group.main.name

  # Backup configuration
  backup_retention_period = var.backup_retention_period
  backup_window          = var.backup_window
  maintenance_window     = var.maintenance_window
  copy_tags_to_snapshot  = true
  delete_automated_backups = false

  # Monitoring and logging
  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.rds_monitoring.arn
  
  enabled_cloudwatch_logs_exports = [
    "error",
    "general",
    "slow-query"
  ]

  performance_insights_enabled = true
  performance_insights_retention_period = 7

  # High availability
  multi_az = var.environment == "prod" ? true : false

  # Deletion protection
  deletion_protection = var.environment == "prod" ? true : false
  skip_final_snapshot = var.environment == "prod" ? false : true
  final_snapshot_identifier = var.environment == "prod" ? "${var.project_name}-${var.environment}-final-snapshot-${formatdate("YYYY-MM-DD-hhmm", timestamp())}" : null

  tags = {
    Name = "${var.project_name}-${var.environment}-mysql"
  }

  lifecycle {
    ignore_changes = [password]
  }
}

# IAM Role for RDS Enhanced Monitoring
resource "aws_iam_role" "rds_monitoring" {
  name = "${var.project_name}-${var.environment}-rds-monitoring-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "monitoring.rds.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-rds-monitoring-role"
  }
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# Read Replica (for production)
resource "aws_db_instance" "read_replica" {
  count = var.environment == "prod" ? 1 : 0

  identifier = "${var.project_name}-${var.environment}-mysql-replica"

  # Replica configuration
  replicate_source_db = aws_db_instance.main.identifier
  instance_class      = var.db_instance_class

  # Network configuration
  publicly_accessible = false

  # Monitoring
  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.rds_monitoring.arn

  performance_insights_enabled = true
  performance_insights_retention_period = 7

  tags = {
    Name = "${var.project_name}-${var.environment}-mysql-replica"
  }
}