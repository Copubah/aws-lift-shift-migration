#!/bin/bash

# AWS Lift and Shift Migration - Deployment Script
# This script automates the deployment of the Terraform infrastructure

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
TERRAFORM_DIR="terraform"
BACKUP_DIR="backups"
LOG_FILE="deployment.log"

# Functions
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
    exit 1
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Terraform is installed
    if ! command -v terraform &> /dev/null; then
        error "Terraform is not installed. Please install Terraform first."
    fi
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI first."
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure' first."
    fi
    
    # Check if terraform.tfvars exists
    if [ ! -f "$TERRAFORM_DIR/terraform.tfvars" ]; then
        warning "terraform.tfvars not found. Please copy terraform.tfvars.example and customize it."
        echo "Run: cp $TERRAFORM_DIR/terraform.tfvars.example $TERRAFORM_DIR/terraform.tfvars"
        exit 1
    fi
    
    success "Prerequisites check passed"
}

# Backup existing state
backup_state() {
    if [ -f "$TERRAFORM_DIR/terraform.tfstate" ]; then
        log "Backing up existing Terraform state..."
        mkdir -p "$BACKUP_DIR"
        cp "$TERRAFORM_DIR/terraform.tfstate" "$BACKUP_DIR/terraform.tfstate.$(date +%Y%m%d_%H%M%S)"
        success "State backed up"
    fi
}

# Initialize Terraform
init_terraform() {
    log "Initializing Terraform..."
    cd "$TERRAFORM_DIR"
    
    terraform init
    
    if [ $? -eq 0 ]; then
        success "Terraform initialized successfully"
    else
        error "Terraform initialization failed"
    fi
    
    cd ..
}

# Validate Terraform configuration
validate_terraform() {
    log "Validating Terraform configuration..."
    cd "$TERRAFORM_DIR"
    
    terraform validate
    
    if [ $? -eq 0 ]; then
        success "Terraform configuration is valid"
    else
        error "Terraform configuration validation failed"
    fi
    
    cd ..
}

# Plan Terraform deployment
plan_terraform() {
    log "Planning Terraform deployment..."
    cd "$TERRAFORM_DIR"
    
    terraform plan -out=tfplan
    
    if [ $? -eq 0 ]; then
        success "Terraform plan completed successfully"
    else
        error "Terraform planning failed"
    fi
    
    cd ..
}

# Apply Terraform configuration
apply_terraform() {
    log "Applying Terraform configuration..."
    cd "$TERRAFORM_DIR"
    
    # Prompt for confirmation
    echo -e "${YELLOW}This will create AWS resources that may incur costs.${NC}"
    read -p "Do you want to continue? (y/N): " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        warning "Deployment cancelled by user"
        exit 0
    fi
    
    terraform apply tfplan
    
    if [ $? -eq 0 ]; then
        success "Terraform applied successfully"
    else
        error "Terraform apply failed"
    fi
    
    cd ..
}

# Display outputs
show_outputs() {
    log "Displaying Terraform outputs..."
    cd "$TERRAFORM_DIR"
    
    echo -e "\n${GREEN}=== Deployment Outputs ===${NC}"
    terraform output
    
    # Save outputs to file
    terraform output -json > ../outputs.json
    
    cd ..
    success "Outputs saved to outputs.json"
}

# Post-deployment verification
verify_deployment() {
    log "Verifying deployment..."
    
    cd "$TERRAFORM_DIR"
    
    # Get ALB DNS name
    ALB_DNS=$(terraform output -raw alb_dns_name 2>/dev/null)
    
    if [ -n "$ALB_DNS" ]; then
        log "Testing ALB endpoint: http://$ALB_DNS"
        
        # Wait for ALB to be ready
        sleep 30
        
        # Test health endpoint
        if curl -f -s "http://$ALB_DNS/health.php" > /dev/null; then
            success "ALB health check passed"
        else
            warning "ALB health check failed - this is normal if instances are still initializing"
        fi
    fi
    
    cd ..
}

# Generate post-deployment instructions
generate_instructions() {
    log "Generating post-deployment instructions..."
    
    cd "$TERRAFORM_DIR"
    
    ALB_DNS=$(terraform output -raw alb_dns_name 2>/dev/null)
    DASHBOARD_URL=$(terraform output -raw cloudwatch_dashboard_url 2>/dev/null)
    
    cat > ../POST_DEPLOYMENT.md << EOF
# Post-Deployment Instructions

## Access Information

### Web Application
- **URL**: http://$ALB_DNS
- **Health Check**: http://$ALB_DNS/health.php

### Monitoring
- **CloudWatch Dashboard**: $DASHBOARD_URL

## Next Steps

### 1. Configure DNS (Optional)
If you have a domain, create a CNAME record pointing to: \`$ALB_DNS\`

### 2. SSL Certificate (Recommended for Production)
1. Request an SSL certificate in AWS Certificate Manager
2. Update the ALB listener to use HTTPS
3. Update the terraform.tfvars with the certificate ARN

### 3. Start Database Migration
\`\`\`bash
# Check DMS replication task status
aws dms describe-replication-tasks --filters Name=replication-task-id,Values=<task-id>

# Start the migration task
aws dms start-replication-task \\
  --replication-task-arn <task-arn> \\
  --start-replication-task-type start-replication
\`\`\`

### 4. Deploy Application Code
\`\`\`bash
# Use Systems Manager to deploy code
aws ssm send-command \\
  --document-name "AWS-RunShellScript" \\
  --targets "Key=tag:Name,Values=lift-shift-migration-dev-web-server" \\
  --parameters 'commands=["cd /var/www/html && git pull origin main"]'
\`\`\`

### 5. Set Up Auto Scaling (Optional)
\`\`\`bash
# Create Auto Scaling Group
aws autoscaling create-auto-scaling-group \\
  --auto-scaling-group-name "lift-shift-migration-dev-asg" \\
  --launch-template LaunchTemplateId=<template-id>,Version='\$Latest' \\
  --min-size 2 \\
  --max-size 6 \\
  --desired-capacity 2 \\
  --target-group-arns <target-group-arn> \\
  --vpc-zone-identifier "<subnet-ids>"
\`\`\`

## Monitoring and Maintenance

### CloudWatch Alarms
Monitor the following alarms:
- High CPU utilization
- High database connections
- ALB response time
- Application errors

### Regular Tasks
- Review CloudWatch dashboards daily
- Check backup status weekly
- Apply security patches monthly
- Review costs monthly

## Troubleshooting

### Common Issues
1. **Health checks failing**: Check EC2 instance logs in CloudWatch
2. **Database connection issues**: Verify security groups and credentials
3. **High response times**: Check CloudWatch metrics and consider scaling

### Support Commands
\`\`\`bash
# Check EC2 instance status
aws ec2 describe-instances --filters "Name=tag:Name,Values=*web-server*"

# View CloudWatch logs
aws logs tail /aws/ec2/lift-shift-migration-dev/application --follow

# Check RDS status
aws rds describe-db-instances --db-instance-identifier <db-id>
\`\`\`

## Security Recommendations

1. **Restrict Security Groups**: Limit access to known IP ranges
2. **Enable MFA**: For all AWS accounts with access
3. **Regular Updates**: Keep EC2 instances updated
4. **Backup Verification**: Test restore procedures regularly
5. **Access Logging**: Enable CloudTrail for API logging

For more detailed information, see the README.md file.
EOF
    
    cd ..
    success "Post-deployment instructions generated: POST_DEPLOYMENT.md"
}

# Cleanup function
cleanup() {
    log "Cleaning up temporary files..."
    rm -f "$TERRAFORM_DIR/tfplan"
}

# Main deployment function
main() {
    log "Starting AWS Lift and Shift Migration deployment..."
    
    # Create log file
    touch "$LOG_FILE"
    
    # Run deployment steps
    check_prerequisites
    backup_state
    init_terraform
    validate_terraform
    plan_terraform
    apply_terraform
    show_outputs
    verify_deployment
    generate_instructions
    cleanup
    
    success "Deployment completed successfully!"
    echo -e "\n${GREEN}=== Next Steps ===${NC}"
    echo "1. Review the outputs above"
    echo "2. Check POST_DEPLOYMENT.md for detailed instructions"
    echo "3. Access your application at: http://$(cd terraform && terraform output -raw alb_dns_name 2>/dev/null)"
    echo "4. Monitor the deployment in CloudWatch"
}

# Handle script arguments
case "${1:-deploy}" in
    "deploy")
        main
        ;;
    "plan")
        check_prerequisites
        init_terraform
        validate_terraform
        plan_terraform
        ;;
    "destroy")
        log "Destroying infrastructure..."
        cd "$TERRAFORM_DIR"
        terraform destroy
        cd ..
        success "Infrastructure destroyed"
        ;;
    "validate")
        check_prerequisites
        validate_terraform
        ;;
    "outputs")
        cd "$TERRAFORM_DIR"
        terraform output
        cd ..
        ;;
    *)
        echo "Usage: $0 [deploy|plan|destroy|validate|outputs]"
        echo "  deploy   - Full deployment (default)"
        echo "  plan     - Plan only, no changes"
        echo "  destroy  - Destroy infrastructure"
        echo "  validate - Validate configuration"
        echo "  outputs  - Show outputs"
        exit 1
        ;;
esac