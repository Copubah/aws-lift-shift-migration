#!/bin/bash

# AWS Lift and Shift Migration - Monitoring Script
# This script provides monitoring and health check capabilities

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
TERRAFORM_DIR="terraform"
REGION=$(cd "$TERRAFORM_DIR" && terraform output -raw aws_region 2>/dev/null || echo "us-east-1")

# Functions
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Get Terraform outputs
get_terraform_output() {
    local output_name=$1
    cd "$TERRAFORM_DIR"
    terraform output -raw "$output_name" 2>/dev/null || echo ""
    cd ..
}

# Check ALB health
check_alb_health() {
    log "Checking Application Load Balancer health..."
    
    local alb_dns=$(get_terraform_output "alb_dns_name")
    local target_group_arn=$(get_terraform_output "target_group_arn")
    
    if [ -z "$alb_dns" ]; then
        error "Could not retrieve ALB DNS name"
        return 1
    fi
    
    echo "ALB DNS: $alb_dns"
    
    # Check ALB status
    local alb_arn=$(get_terraform_output "alb_arn")
    if [ -n "$alb_arn" ]; then
        local alb_state=$(aws elbv2 describe-load-balancers --load-balancer-arns "$alb_arn" --query 'LoadBalancers[0].State.Code' --output text --region "$REGION")
        echo "ALB State: $alb_state"
        
        if [ "$alb_state" = "active" ]; then
            success "ALB is active"
        else
            warning "ALB is not active: $alb_state"
        fi
    fi
    
    # Check target group health
    if [ -n "$target_group_arn" ]; then
        echo -e "\nTarget Group Health:"
        aws elbv2 describe-target-health --target-group-arn "$target_group_arn" --region "$REGION" --output table
    fi
    
    # Test HTTP endpoint
    echo -e "\nTesting HTTP endpoint..."
    if curl -f -s -o /dev/null -w "HTTP Status: %{http_code}, Response Time: %{time_total}s\n" "http://$alb_dns/health.php"; then
        success "HTTP health check passed"
    else
        warning "HTTP health check failed"
    fi
}

# Check RDS health
check_rds_health() {
    log "Checking RDS database health..."
    
    local db_instance_id=$(get_terraform_output "rds_instance_id")
    local db_endpoint=$(get_terraform_output "rds_endpoint")
    
    if [ -z "$db_instance_id" ]; then
        error "Could not retrieve RDS instance ID"
        return 1
    fi
    
    echo "RDS Instance: $db_instance_id"
    echo "RDS Endpoint: $db_endpoint"
    
    # Get RDS status
    local db_status=$(aws rds describe-db-instances --db-instance-identifier "$db_instance_id" --query 'DBInstances[0].DBInstanceStatus' --output text --region "$REGION")
    echo "RDS Status: $db_status"
    
    if [ "$db_status" = "available" ]; then
        success "RDS is available"
    else
        warning "RDS is not available: $db_status"
    fi
    
    # Get RDS metrics
    echo -e "\nRDS Metrics (last 5 minutes):"
    local end_time=$(date -u +%Y-%m-%dT%H:%M:%S)
    local start_time=$(date -u -d '5 minutes ago' +%Y-%m-%dT%H:%M:%S)
    
    # CPU Utilization
    local cpu_util=$(aws cloudwatch get-metric-statistics \
        --namespace AWS/RDS \
        --metric-name CPUUtilization \
        --dimensions Name=DBInstanceIdentifier,Value="$db_instance_id" \
        --start-time "$start_time" \
        --end-time "$end_time" \
        --period 300 \
        --statistics Average \
        --region "$REGION" \
        --query 'Datapoints[0].Average' \
        --output text 2>/dev/null || echo "N/A")
    
    echo "CPU Utilization: ${cpu_util}%"
    
    # Database Connections
    local db_connections=$(aws cloudwatch get-metric-statistics \
        --namespace AWS/RDS \
        --metric-name DatabaseConnections \
        --dimensions Name=DBInstanceIdentifier,Value="$db_instance_id" \
        --start-time "$start_time" \
        --end-time "$end_time" \
        --period 300 \
        --statistics Average \
        --region "$REGION" \
        --query 'Datapoints[0].Average' \
        --output text 2>/dev/null || echo "N/A")
    
    echo "Database Connections: $db_connections"
}

# Check EC2 instances
check_ec2_health() {
    log "Checking EC2 instances health..."
    
    # Find instances by tag
    local project_name=$(get_terraform_output "project_name" || echo "lift-shift-migration")
    local environment=$(get_terraform_output "environment" || echo "dev")
    
    echo "Looking for instances with tag: $project_name-$environment-web-server"
    
    # Get instance information
    aws ec2 describe-instances \
        --filters "Name=tag:Name,Values=*$project_name*$environment*web*" "Name=instance-state-name,Values=running,pending,stopping,stopped" \
        --query 'Reservations[].Instances[].[InstanceId,State.Name,PrivateIpAddress,PublicIpAddress,InstanceType]' \
        --output table \
        --region "$REGION"
    
    # Get instance IDs
    local instance_ids=$(aws ec2 describe-instances \
        --filters "Name=tag:Name,Values=*$project_name*$environment*web*" "Name=instance-state-name,Values=running" \
        --query 'Reservations[].Instances[].InstanceId' \
        --output text \
        --region "$REGION")
    
    if [ -n "$instance_ids" ]; then
        echo -e "\nEC2 Metrics (last 5 minutes):"
        local end_time=$(date -u +%Y-%m-%dT%H:%M:%S)
        local start_time=$(date -u -d '5 minutes ago' +%Y-%m-%dT%H:%M:%S)
        
        for instance_id in $instance_ids; do
            echo "Instance: $instance_id"
            
            # CPU Utilization
            local cpu_util=$(aws cloudwatch get-metric-statistics \
                --namespace AWS/EC2 \
                --metric-name CPUUtilization \
                --dimensions Name=InstanceId,Value="$instance_id" \
                --start-time "$start_time" \
                --end-time "$end_time" \
                --period 300 \
                --statistics Average \
                --region "$REGION" \
                --query 'Datapoints[0].Average' \
                --output text 2>/dev/null || echo "N/A")
            
            echo "  CPU Utilization: ${cpu_util}%"
            
            # Status checks
            local status_checks=$(aws ec2 describe-instance-status \
                --instance-ids "$instance_id" \
                --query 'InstanceStatuses[0].[SystemStatus.Status,InstanceStatus.Status]' \
                --output text \
                --region "$REGION" 2>/dev/null || echo "N/A N/A")
            
            echo "  Status Checks: $status_checks"
        done
    else
        warning "No running EC2 instances found"
    fi
}

# Check S3 buckets
check_s3_health() {
    log "Checking S3 buckets..."
    
    local bucket_name=$(get_terraform_output "s3_bucket_name")
    local backup_bucket=$(get_terraform_output "backup_bucket_name")
    
    if [ -n "$bucket_name" ]; then
        echo "Application Bucket: $bucket_name"
        
        # Check bucket exists and is accessible
        if aws s3 ls "s3://$bucket_name" --region "$REGION" > /dev/null 2>&1; then
            success "Application bucket is accessible"
            
            # Get bucket size
            local bucket_size=$(aws s3 ls "s3://$bucket_name" --recursive --summarize --region "$REGION" 2>/dev/null | grep "Total Size" | awk '{print $3, $4}' || echo "N/A")
            echo "Bucket Size: $bucket_size"
        else
            error "Application bucket is not accessible"
        fi
    fi
    
    if [ -n "$backup_bucket" ]; then
        echo "Backup Bucket: $backup_bucket"
        
        if aws s3 ls "s3://$backup_bucket" --region "$REGION" > /dev/null 2>&1; then
            success "Backup bucket is accessible"
        else
            error "Backup bucket is not accessible"
        fi
    fi
}

# Check DMS status
check_dms_health() {
    log "Checking DMS replication status..."
    
    local project_name=$(get_terraform_output "project_name" || echo "lift-shift-migration")
    local environment=$(get_terraform_output "environment" || echo "dev")
    
    # Find DMS replication instance
    local replication_instances=$(aws dms describe-replication-instances \
        --filters "Name=replication-instance-id,Values=$project_name-$environment-dms-instance" \
        --query 'ReplicationInstances[].[ReplicationInstanceIdentifier,ReplicationInstanceStatus,AllocatedStorage,ReplicationInstanceClass]' \
        --output table \
        --region "$REGION" 2>/dev/null)
    
    if [ -n "$replication_instances" ]; then
        echo "DMS Replication Instances:"
        echo "$replication_instances"
        
        # Check replication tasks
        local replication_tasks=$(aws dms describe-replication-tasks \
            --filters "Name=replication-instance-arn,Values=*$project_name-$environment-dms-instance*" \
            --query 'ReplicationTasks[].[ReplicationTaskIdentifier,Status,ReplicationTaskStats.TablesLoaded,ReplicationTaskStats.TablesLoading,ReplicationTaskStats.TablesErrored]' \
            --output table \
            --region "$REGION" 2>/dev/null)
        
        if [ -n "$replication_tasks" ]; then
            echo -e "\nDMS Replication Tasks:"
            echo "$replication_tasks"
        else
            warning "No DMS replication tasks found"
        fi
    else
        warning "No DMS replication instances found"
    fi
}

# Check CloudWatch alarms
check_cloudwatch_alarms() {
    log "Checking CloudWatch alarms..."
    
    local project_name=$(get_terraform_output "project_name" || echo "lift-shift-migration")
    local environment=$(get_terraform_output "environment" || echo "dev")
    
    # Get alarms with project prefix
    aws cloudwatch describe-alarms \
        --alarm-name-prefix "$project_name-$environment" \
        --query 'MetricAlarms[].[AlarmName,StateValue,StateReason]' \
        --output table \
        --region "$REGION"
}

# Generate health report
generate_health_report() {
    log "Generating comprehensive health report..."
    
    local report_file="health_report_$(date +%Y%m%d_%H%M%S).txt"
    
    {
        echo "AWS Lift and Shift Migration - Health Report"
        echo "Generated: $(date)"
        echo "Region: $REGION"
        echo "=========================================="
        echo
        
        echo "ALB Health:"
        check_alb_health 2>&1
        echo
        
        echo "RDS Health:"
        check_rds_health 2>&1
        echo
        
        echo "EC2 Health:"
        check_ec2_health 2>&1
        echo
        
        echo "S3 Health:"
        check_s3_health 2>&1
        echo
        
        echo "DMS Health:"
        check_dms_health 2>&1
        echo
        
        echo "CloudWatch Alarms:"
        check_cloudwatch_alarms 2>&1
        echo
        
    } > "$report_file"
    
    success "Health report generated: $report_file"
}

# Monitor logs in real-time
monitor_logs() {
    log "Starting real-time log monitoring..."
    
    local log_group="/aws/ec2/lift-shift-migration-dev/application"
    
    echo "Monitoring log group: $log_group"
    echo "Press Ctrl+C to stop..."
    
    aws logs tail "$log_group" --follow --region "$REGION"
}

# Show CloudWatch dashboard URL
show_dashboard() {
    local dashboard_url=$(get_terraform_output "cloudwatch_dashboard_url")
    
    if [ -n "$dashboard_url" ]; then
        echo "CloudWatch Dashboard: $dashboard_url"
    else
        warning "Dashboard URL not available"
    fi
}

# Performance metrics
show_performance_metrics() {
    log "Retrieving performance metrics (last hour)..."
    
    local end_time=$(date -u +%Y-%m-%dT%H:%M:%S)
    local start_time=$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S)
    
    # ALB metrics
    local alb_arn_suffix=$(get_terraform_output "alb_arn_suffix")
    if [ -n "$alb_arn_suffix" ]; then
        echo "ALB Request Count (last hour):"
        aws cloudwatch get-metric-statistics \
            --namespace AWS/ApplicationELB \
            --metric-name RequestCount \
            --dimensions Name=LoadBalancer,Value="$alb_arn_suffix" \
            --start-time "$start_time" \
            --end-time "$end_time" \
            --period 3600 \
            --statistics Sum \
            --region "$REGION" \
            --query 'Datapoints[0].Sum' \
            --output text 2>/dev/null || echo "N/A"
        
        echo "ALB Average Response Time (last hour):"
        aws cloudwatch get-metric-statistics \
            --namespace AWS/ApplicationELB \
            --metric-name TargetResponseTime \
            --dimensions Name=LoadBalancer,Value="$alb_arn_suffix" \
            --start-time "$start_time" \
            --end-time "$end_time" \
            --period 3600 \
            --statistics Average \
            --region "$REGION" \
            --query 'Datapoints[0].Average' \
            --output text 2>/dev/null || echo "N/A"
    fi
}

# Main function
main() {
    case "${1:-health}" in
        "health"|"check")
            check_alb_health
            echo
            check_rds_health
            echo
            check_ec2_health
            echo
            check_s3_health
            ;;
        "alb")
            check_alb_health
            ;;
        "rds")
            check_rds_health
            ;;
        "ec2")
            check_ec2_health
            ;;
        "s3")
            check_s3_health
            ;;
        "dms")
            check_dms_health
            ;;
        "alarms")
            check_cloudwatch_alarms
            ;;
        "report")
            generate_health_report
            ;;
        "logs")
            monitor_logs
            ;;
        "dashboard")
            show_dashboard
            ;;
        "performance")
            show_performance_metrics
            ;;
        *)
            echo "Usage: $0 [health|alb|rds|ec2|s3|dms|alarms|report|logs|dashboard|performance]"
            echo "  health      - Check all components (default)"
            echo "  alb         - Check Application Load Balancer"
            echo "  rds         - Check RDS database"
            echo "  ec2         - Check EC2 instances"
            echo "  s3          - Check S3 buckets"
            echo "  dms         - Check DMS replication"
            echo "  alarms      - Check CloudWatch alarms"
            echo "  report      - Generate comprehensive health report"
            echo "  logs        - Monitor application logs in real-time"
            echo "  dashboard   - Show CloudWatch dashboard URL"
            echo "  performance - Show performance metrics"
            exit 1
            ;;
    esac
}

# Check if terraform directory exists
if [ ! -d "$TERRAFORM_DIR" ]; then
    error "Terraform directory not found: $TERRAFORM_DIR"
    exit 1
fi

main "$@"