# DMS Module for AWS Lift and Shift Migration

# DMS Subnet Group
resource "aws_dms_replication_subnet_group" "main" {
  replication_subnet_group_description = "DMS subnet group for ${var.project_name} ${var.environment}"
  replication_subnet_group_id          = "${var.project_name}-${var.environment}-dms-subnet-group"
  subnet_ids                          = var.private_subnet_ids

  tags = {
    Name = "${var.project_name}-${var.environment}-dms-subnet-group"
  }
}

# Data source for availability zones
data "aws_availability_zones" "available" {
  state = "available"
}

# Get target DB password from Secrets Manager
data "aws_secretsmanager_secret_version" "target_db_password" {
  secret_id = var.target_db_password_secret_arn
}

locals {
  target_db_credentials = jsondecode(data.aws_secretsmanager_secret_version.target_db_password.secret_string)
}

# DMS Replication Instance
resource "aws_dms_replication_instance" "main" {
  allocated_storage            = 20
  apply_immediately           = true
  auto_minor_version_upgrade  = true
  availability_zone          = data.aws_availability_zones.available.names[0]
  engine_version             = "3.5.2"
  multi_az                   = false
  publicly_accessible        = false
  replication_instance_class = var.replication_instance_class
  replication_instance_id    = "${var.project_name}-${var.environment}-dms-instance"
  replication_subnet_group_id = aws_dms_replication_subnet_group.main.id

  tags = {
    Name = "${var.project_name}-${var.environment}-dms-instance"
  }

  vpc_security_group_ids = [var.dms_security_group_id]

  depends_on = [
    aws_dms_replication_subnet_group.main
  ]
}

# Source Endpoint (On-premises MySQL)
resource "aws_dms_endpoint" "source" {
  count = var.source_db_endpoint != "" ? 1 : 0

  endpoint_id   = "${var.project_name}-${var.environment}-source-endpoint"
  endpoint_type = "source"
  engine_name   = "mysql"
  server_name   = var.source_db_endpoint
  port          = 3306
  username      = var.source_db_username
  password      = var.source_db_password

  tags = {
    Name = "${var.project_name}-${var.environment}-source-endpoint"
  }
}

# Target Endpoint (RDS MySQL)
resource "aws_dms_endpoint" "target" {
  endpoint_id   = "${var.project_name}-${var.environment}-target-endpoint"
  endpoint_type = "target"
  engine_name   = "mysql"
  server_name   = var.target_db_endpoint
  port          = 3306
  username      = local.target_db_credentials.username
  password      = local.target_db_credentials.password

  tags = {
    Name = "${var.project_name}-${var.environment}-target-endpoint"
  }
}

# DMS Replication Task
resource "aws_dms_replication_task" "main" {
  count = var.source_db_endpoint != "" ? 1 : 0

  migration_type           = "full-load-and-cdc"
  replication_instance_arn = aws_dms_replication_instance.main.replication_instance_arn
  replication_task_id      = "${var.project_name}-${var.environment}-migration-task"
  source_endpoint_arn      = aws_dms_endpoint.source[0].endpoint_arn
  target_endpoint_arn      = aws_dms_endpoint.target.endpoint_arn

  replication_task_settings = jsonencode({
    TargetMetadata = {
      TargetSchema                 = ""
      SupportLobs                  = true
      FullLobMode                  = false
      LobChunkSize                 = 0
      LimitedSizeLobMode           = true
      LobMaxSize                   = 32
      InlineLobMaxSize            = 0
      LoadMaxFileSize             = 0
      ParallelLoadThreads         = 0
      ParallelLoadBufferSize      = 0
      BatchApplyEnabled           = false
      TaskRecoveryTableEnabled    = false
      ParallelApplyThreads        = 0
      ParallelApplyBufferSize     = 0
      ParallelApplyQueuesPerThread = 0
    }
    FullLoadSettings = {
      TargetTablePrepMode          = "DROP_AND_CREATE"
      CreatePkAfterFullLoad        = false
      StopTaskCachedChangesApplied = false
      StopTaskCachedChangesNotApplied = false
      MaxFullLoadSubTasks          = 8
      TransactionConsistencyTimeout = 600
      CommitRate                   = 10000
    }
    Logging = {
      EnableLogging = true
      LogComponents = [
        {
          Id       = "TRANSFORMATION"
          Severity = "LOGGER_SEVERITY_DEFAULT"
        },
        {
          Id       = "SOURCE_UNLOAD"
          Severity = "LOGGER_SEVERITY_DEFAULT"
        },
        {
          Id       = "TARGET_LOAD"
          Severity = "LOGGER_SEVERITY_DEFAULT"
        }
      ]
    }
    ControlTablesSettings = {
      historyTimeslotInMinutes = 5
      ControlSchema           = ""
      HistoryTimeslotInMinutes = 5
      HistoryTableEnabled     = false
      SuspendedTablesTableEnabled = false
      StatusTableEnabled      = false
    }
    StreamBufferSettings = {
      StreamBufferCount      = 3
      StreamBufferSizeInMB   = 8
      CtrlStreamBufferSizeInMB = 5
    }
    ChangeProcessingDdlHandlingPolicy = {
      HandleSourceTableDropped   = true
      HandleSourceTableTruncated = true
      HandleSourceTableAltered   = true
    }
    ErrorBehavior = {
      DataErrorPolicy      = "LOG_ERROR"
      DataTruncationErrorPolicy = "LOG_ERROR"
      DataErrorEscalationPolicy = "SUSPEND_TABLE"
      DataErrorEscalationCount = 0
      TableErrorPolicy     = "SUSPEND_TABLE"
      TableErrorEscalationPolicy = "STOP_TASK"
      TableErrorEscalationCount = 0
      RecoverableErrorCount = -1
      RecoverableErrorInterval = 5
      RecoverableErrorThrottling = true
      RecoverableErrorThrottlingMax = 1800
      RecoverableErrorStopRetryAfterThrottlingMax = true
      ApplyErrorDeletePolicy = "IGNORE_RECORD"
      ApplyErrorInsertPolicy = "LOG_ERROR"
      ApplyErrorUpdatePolicy = "LOG_ERROR"
      ApplyErrorEscalationPolicy = "LOG_ERROR"
      ApplyErrorEscalationCount = 0
      ApplyErrorFailOnTruncationDdl = false
      FullLoadIgnoreConflicts = true
    }
    ChangeProcessingTuning = {
      BatchApplyPreserveTransaction = true
      BatchApplyTimeoutMin = 1
      BatchApplyTimeoutMax = 30
      BatchApplyMemoryLimit = 500
      BatchSplitSize = 0
      MinTransactionSize = 1000
      CommitTimeout = 1
      MemoryLimitTotal = 1024
      MemoryKeepTime = 60
      StatementCacheSize = 50
    }
  })

  table_mappings = jsonencode({
    rules = [
      {
        rule-type   = "selection"
        rule-id     = "1"
        rule-name   = "include-all-tables"
        object-locator = {
          schema-name = "%"
          table-name  = "%"
        }
        rule-action = "include"
        filters = []
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-migration-task"
  }

  depends_on = [
    aws_dms_endpoint.source,
    aws_dms_endpoint.target
  ]
}

# CloudWatch Log Group for DMS
resource "aws_cloudwatch_log_group" "dms_logs" {
  name              = "/aws/dms/task/${var.project_name}-${var.environment}-migration-task"
  retention_in_days = 14

  tags = {
    Name = "${var.project_name}-${var.environment}-dms-logs"
  }
}