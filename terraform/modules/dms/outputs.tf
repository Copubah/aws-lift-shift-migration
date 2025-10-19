output "replication_instance_arn" {
  description = "ARN of the DMS replication instance"
  value       = aws_dms_replication_instance.main.replication_instance_arn
}

output "replication_instance_id" {
  description = "ID of the DMS replication instance"
  value       = aws_dms_replication_instance.main.replication_instance_id
}

output "source_endpoint_arn" {
  description = "ARN of the source endpoint"
  value       = var.source_db_endpoint != "" ? aws_dms_endpoint.source[0].endpoint_arn : null
}

output "target_endpoint_arn" {
  description = "ARN of the target endpoint"
  value       = aws_dms_endpoint.target.endpoint_arn
}

output "replication_task_arn" {
  description = "ARN of the replication task"
  value       = var.source_db_endpoint != "" ? aws_dms_replication_task.main[0].replication_task_arn : null
}