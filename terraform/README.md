# AWS Lift and Shift Migration - Terraform Infrastructure

This Terraform configuration automates the deployment of a complete AWS infrastructure for migrating a 2-tier web application from on-premises to AWS cloud.

## Architecture Overview

The infrastructure includes:
- VPC with public/private subnets across 2 AZs
- Application Load Balancer for traffic distribution
- EC2 instances for web servers (with Auto Scaling capability)
- RDS MySQL for database with automated backups
- S3 buckets for file storage and backups
- DMS for database migration
- CloudWatch for monitoring and alerting
- IAM roles with least privilege access
- Security Groups with proper network segmentation

## Prerequisites

1. AWS CLI configured with appropriate credentials
2. Terraform >= 1.0 installed
3. SSH Key Pair created in AWS (for EC2 access)
4. Domain/SSL Certificate (optional, for HTTPS)

## Quick Start

1. Clone and navigate to terraform directory:
   ```bash
   cd terraform
   ```

2. Copy and customize variables:
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your specific values
   ```

3. Initialize Terraform:
   ```bash
   terraform init
   ```

4. Plan the deployment:
   ```bash
   terraform plan
   ```

5. Deploy the infrastructure:
   ```bash
   terraform apply
   ```

## Configuration

### Required Variables

Edit `terraform.tfvars` with your specific values:

```hcl
# Project Configuration
project_name = "your-project-name"
environment  = "dev"  # or "staging", "prod"
owner        = "your-team"

# AWS Configuration
aws_region = "us-east-1"
key_pair_name = "your-key-pair"

# Source Database (for migration)
source_db_endpoint = "192.168.1.100"
source_db_username = "root"
source_db_password = "your-source-password"
```

### Optional Customizations

```hcl
# Instance sizing
instance_type = "t3.medium"
db_instance_class = "db.t3.small"

# Network configuration
vpc_cidr = "10.0.0.0/16"

# Monitoring
alert_email = "alerts@yourcompany.com"
log_retention_days = 30
```

## Module Structure

```
terraform/
├── main.tf                 # Main configuration
├── variables.tf            # Variable definitions
├── outputs.tf             # Output values
├── user_data.sh           # EC2 initialization script
└── modules/
    ├── vpc/               # VPC and networking
    ├── security/          # Security groups
    ├── rds/              # Database configuration
    ├── s3/               # Storage buckets
    ├── alb/              # Load balancer
    ├── iam/              # IAM roles and policies
    ├── cloudwatch/       # Monitoring and alerting
    └── dms/              # Database migration service
```

## Best Practices Implemented

### Security
- Least Privilege IAM: Minimal required permissions
- Network Segmentation: Private subnets for databases
- Encryption: At-rest and in-transit encryption
- Secrets Management: AWS Secrets Manager for passwords
- Security Groups: Restrictive inbound/outbound rules
- VPC Flow Logs: Network traffic monitoring

### High Availability
- Multi-AZ Deployment: Resources across availability zones
- Auto Scaling: Automatic capacity management (configurable)
- Load Balancing: Traffic distribution and health checks
- Database Backups: Automated RDS backups
- Read Replicas: For production environments

### Monitoring & Observability
- CloudWatch Dashboards: Centralized monitoring
- Custom Metrics: Application-specific monitoring
- Log Aggregation: Centralized logging
- Alerting: SNS notifications for critical events
- Performance Insights: Database performance monitoring

### Cost Optimization
- Right-sizing: Appropriate instance types for workload
- S3 Lifecycle Policies: Automatic storage class transitions
- Reserved Capacity: For predictable workloads (manual)
- Resource Tagging: Cost allocation and tracking

### Operational Excellence
- Infrastructure as Code: Version-controlled infrastructure
- Modular Design: Reusable components
- Environment Separation: Dev/staging/prod isolation
- Automated Deployment: Consistent deployments
- Documentation: Comprehensive documentation

## Post-Deployment Steps

### 1. Verify Infrastructure
```bash
# Check outputs
terraform output

# Test ALB endpoint
curl http://$(terraform output -raw alb_dns_name)
```

### 2. Configure DNS (Optional)
```bash
# Create Route 53 record pointing to ALB
aws route53 change-resource-record-sets --hosted-zone-id Z123456789 \
  --change-batch file://dns-change.json
```

### 3. Start Database Migration
```bash
# Start DMS replication task
aws dms start-replication-task \
  --replication-task-arn $(terraform output -raw dms_replication_task_arn) \
  --start-replication-task-type start-replication
```

### 4. Deploy Application Code
```bash
# Use Systems Manager or SSH to deploy application
aws ssm send-command \
  --document-name "AWS-RunShellScript" \
  --targets "Key=tag:Name,Values=lift-shift-migration-dev-web-server" \
  --parameters 'commands=["cd /var/www/html && git pull origin main"]'
```

## Monitoring and Maintenance

### CloudWatch Dashboard
Access the monitoring dashboard:
```bash
echo "Dashboard URL: $(terraform output cloudwatch_dashboard_url)"
```

### Log Analysis
```bash
# View application logs
aws logs tail /aws/ec2/lift-shift-migration-dev/application --follow

# Query logs with CloudWatch Insights
aws logs start-query \
  --log-group-name "/aws/ec2/lift-shift-migration-dev/application" \
  --start-time $(date -d '1 hour ago' +%s) \
  --end-time $(date +%s) \
  --query-string 'fields @timestamp, @message | filter @message like /ERROR/'
```

### Database Monitoring
```bash
# Check RDS performance
aws rds describe-db-instances \
  --db-instance-identifier $(terraform output -raw rds_instance_id)

# View Performance Insights
aws pi get-resource-metrics \
  --service-type RDS \
  --identifier $(terraform output -raw rds_instance_id)
```

## Scaling Operations

### Auto Scaling Group (Manual Setup)
```bash
# Create Auto Scaling Group using the launch template
aws autoscaling create-auto-scaling-group \
  --auto-scaling-group-name "lift-shift-migration-dev-asg" \
  --launch-template LaunchTemplateId=$(terraform output -raw launch_template_id),Version='$Latest' \
  --min-size 2 \
  --max-size 6 \
  --desired-capacity 2 \
  --target-group-arns $(terraform output -raw target_group_arn) \
  --vpc-zone-identifier "$(terraform output -raw private_subnet_ids | tr -d '[]" ' | tr ',' ' ')"
```

### Database Scaling
```bash
# Modify RDS instance class
aws rds modify-db-instance \
  --db-instance-identifier $(terraform output -raw rds_instance_id) \
  --db-instance-class db.t3.medium \
  --apply-immediately
```

## Disaster Recovery

### Backup Verification
```bash
# List RDS snapshots
aws rds describe-db-snapshots \
  --db-instance-identifier $(terraform output -raw rds_instance_id)

# List S3 backup objects
aws s3 ls s3://$(terraform output -raw backup_bucket_name)/
```

### Cross-Region Replication (Manual)
```bash
# Create cross-region RDS replica
aws rds create-db-instance-read-replica \
  --db-instance-identifier lift-shift-migration-dev-replica-us-west-2 \
  --source-db-instance-identifier $(terraform output -raw rds_instance_id) \
  --db-instance-class db.t3.micro
```

## Troubleshooting

### Common Issues

1. DMS Task Fails
   ```bash
   # Check DMS task status
   aws dms describe-replication-tasks \
     --filters Name=replication-task-id,Values=$(terraform output -raw dms_replication_task_arn | cut -d: -f6)
   ```

2. Health Check Failures
   ```bash
   # Check target group health
   aws elbv2 describe-target-health \
     --target-group-arn $(terraform output -raw target_group_arn)
   ```

3. Database Connection Issues
   ```bash
   # Test database connectivity from EC2
   aws ssm start-session --target i-1234567890abcdef0
   mysql -h $(terraform output -raw rds_endpoint) -u admin -p
   ```

### Logs and Debugging
```bash
# CloudFormation events (if using)
aws cloudformation describe-stack-events --stack-name terraform-stack

# EC2 instance logs
aws ssm get-command-invocation \
  --command-id "command-id" \
  --instance-id "i-1234567890abcdef0"
```

## Cleanup

To destroy the infrastructure:
```bash
# Destroy all resources
terraform destroy

# Confirm destruction
terraform show
```

Note: Some resources like S3 buckets with objects may need manual cleanup before destruction.

## Security Considerations

### Production Deployment
- Enable deletion protection on critical resources
- Use AWS Config for compliance monitoring
- Implement AWS GuardDuty for threat detection
- Enable AWS CloudTrail for API logging
- Use AWS Systems Manager for patch management
- Implement backup and disaster recovery procedures

### Network Security
- Restrict security group rules to minimum required access
- Use VPC endpoints for AWS services
- Implement network ACLs for additional security
- Enable VPC Flow Logs for network monitoring

### Data Protection
- Enable S3 bucket versioning and MFA delete
- Use AWS KMS for encryption key management
- Implement data classification and retention policies
- Regular security assessments and penetration testing

## Support and Maintenance

### Regular Tasks
- Monitor CloudWatch alarms and dashboards
- Review and rotate access keys and passwords
- Apply security patches and updates
- Review and optimize costs
- Test backup and recovery procedures
- Update documentation and runbooks

### Automation Opportunities
- Automated patching with Systems Manager
- Automated backup verification
- Cost optimization recommendations
- Security compliance scanning
- Performance optimization suggestions