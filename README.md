# AWS Lift and Shift Migration Project

A comprehensive Terraform-based solution for migrating 2-tier web applications from on-premises to AWS cloud infrastructure using industry best practices.

## Overview

This project automates the migration of traditional web applications to AWS using a lift-and-shift approach. It includes complete infrastructure provisioning, database migration, and monitoring setup using Infrastructure as Code principles.

## Architecture

View the detailed [Architecture Documentation](./ARCHITECTURE.md) for comprehensive diagrams and technical specifications.

### Key Components
- VPC: Multi-AZ networking with public/private subnets
- Application Load Balancer: Traffic distribution with health checks
- EC2 Instances: Auto-scalable web servers
- RDS MySQL: Managed database with automated backups
- S3: Object storage for application files
- CloudWatch: Comprehensive monitoring and alerting
- DMS: Database migration service
- Secrets Manager: Secure credential storage

## Features

### Production-Ready Infrastructure
- Multi-AZ high availability deployment
- Auto Scaling Groups for dynamic capacity
- Automated backups and disaster recovery
- SSL/TLS encryption and security best practices
- Cost-optimized resource allocation

### Migration Tools
- Database Migration Service (DMS) for MySQL migration
- Application Migration Service (MGN) launch templates
- Automated file migration to S3
- Zero-downtime migration capabilities

### Monitoring & Observability
- CloudWatch dashboards and custom metrics
- Automated alerting via SNS
- Log aggregation and analysis
- Performance monitoring and optimization

## Quick Start

### Prerequisites
- AWS CLI configured with appropriate permissions
- Terraform >= 1.0 installed
- SSH key pair created in AWS

### Deployment

1. Clone the repository
   ```bash
   git clone https://github.com/Copubah/aws-lift-shift-migration.git
   cd aws-lift-shift-migration
   ```

2. Configure variables
   ```bash
   cp terraform/terraform.tfvars.example terraform/terraform.tfvars
   # Edit terraform.tfvars with your specific values
   ```

3. Deploy infrastructure
   ```bash
   ./scripts/deploy.sh
   ```

4. Monitor deployment
   ```bash
   ./scripts/monitoring.sh health
   ```

## Configuration

### Required Variables
```hcl
project_name = "your-project-name"
environment  = "dev"
aws_region   = "us-east-1"
key_pair_name = "your-key-pair"

# Source database for migration
source_db_endpoint = "192.168.1.100"
source_db_username = "root"
source_db_password = "your-password"
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
```

## Project Structure

```
├── README.md                    # This file
├── ARCHITECTURE.md              # Architecture diagrams and details
├── PROJECT_STRUCTURE.md         # Detailed project structure
├── scripts/                     # Automation scripts
│   ├── deploy.sh               # Main deployment script
│   └── monitoring.sh           # Health monitoring script
└── terraform/                  # Infrastructure as Code
    ├── main.tf                 # Main configuration
    ├── variables.tf            # Variable definitions
    ├── outputs.tf              # Output values
    ├── terraform.tfvars.example # Example configuration
    ├── user_data.sh            # EC2 initialization script
    └── modules/                # Terraform modules
        ├── vpc/                # VPC and networking
        ├── security/           # Security groups
        ├── rds/               # Database configuration
        ├── s3/                # Storage buckets
        ├── alb/               # Load balancer
        ├── iam/               # IAM roles and policies
        ├── cloudwatch/        # Monitoring and alerting
        └── dms/               # Database migration service
```

## Operations

### Deployment Commands
```bash
# Full deployment
./scripts/deploy.sh

# Plan only (no changes)
./scripts/deploy.sh plan

# Destroy infrastructure
./scripts/deploy.sh destroy
```

### Monitoring Commands
```bash
# Check all components
./scripts/monitoring.sh health

# Check specific components
./scripts/monitoring.sh alb
./scripts/monitoring.sh rds
./scripts/monitoring.sh ec2

# Generate health report
./scripts/monitoring.sh report
```

## Security

### Implemented Security Features
- Network segmentation with private subnets
- Security groups with least privilege access
- Encryption at rest and in transit
- AWS Secrets Manager for credential storage
- VPC Flow Logs for network monitoring
- Automated security patching

### Security Best Practices
- Enable AWS Config for compliance monitoring
- Implement AWS GuardDuty for threat detection
- Use AWS Systems Manager for patch management
- Enable CloudTrail for API logging
- Regular security assessments

## Cost Optimization

- Right-sized instances by environment
- S3 lifecycle policies for storage optimization
- Automated resource tagging for cost allocation
- Reserved Instance recommendations
- CloudWatch billing alarms

## Migration Process

### Database Migration
1. Create DMS replication instance
2. Configure source and target endpoints
3. Start full load and CDC replication
4. Monitor migration progress and validate data

### Server Migration
1. Install MGN agent on source servers
2. Configure launch templates
3. Test and cutover instances
4. Validate application functionality

### File Migration
1. Sync existing files to S3
2. Update application configuration
3. Implement S3 SDK integration
4. Test file upload/download functionality

## Monitoring

Access the CloudWatch dashboard after deployment:
```bash
terraform output cloudwatch_dashboard_url
```

### Key Metrics Monitored
- Application response times
- Database performance and connections
- Infrastructure utilization
- Error rates and availability
- Cost and resource usage

## Support

### Troubleshooting
- Check CloudWatch logs for application errors
- Verify security group configurations
- Monitor DMS task status for database migration
- Review target group health for load balancer issues

### Documentation
- [Terraform Documentation](./terraform/README.md)
- [Project Structure](./PROJECT_STRUCTURE.md)
- [Architecture Details](./ARCHITECTURE.md)

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Portfolio Value

This project demonstrates:
- Cloud architecture and migration expertise
- Infrastructure as Code best practices
- DevOps automation and monitoring
- AWS security implementation
- Real-world migration scenarios
- Operational excellence principles

Perfect for showcasing cloud engineering skills in technical interviews and portfolio presentations.