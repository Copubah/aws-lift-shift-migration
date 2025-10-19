variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
}

variable "private_subnet_ids" {
  description = "IDs of the private subnets"
  type        = list(string)
}

variable "dms_security_group_id" {
  description = "ID of the DMS security group"
  type        = string
}

variable "replication_instance_class" {
  description = "DMS replication instance class"
  type        = string
  default     = "dms.t3.micro"
}

variable "source_db_endpoint" {
  description = "Source database endpoint"
  type        = string
  default     = ""
}

variable "source_db_username" {
  description = "Source database username"
  type        = string
  default     = ""
}

variable "source_db_password" {
  description = "Source database password"
  type        = string
  default     = ""
  sensitive   = true
}

variable "target_db_endpoint" {
  description = "Target database endpoint"
  type        = string
}

variable "target_db_username" {
  description = "Target database username"
  type        = string
}

variable "target_db_password_secret_arn" {
  description = "ARN of the Secrets Manager secret containing target database password"
  type        = string
}