#!/bin/bash

# User Data Script for Web Servers
# This script runs when EC2 instances are launched

# Update system
yum update -y

# Install required packages
yum install -y httpd php php-mysqlnd mysql wget unzip

# Install AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# Install CloudWatch Agent
wget https://s3.amazonaws.com/amazoncloudwatch-agent/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm
rpm -U ./amazon-cloudwatch-agent.rpm

# Configure CloudWatch Agent
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << EOF
{
    "agent": {
        "metrics_collection_interval": 60,
        "run_as_user": "cwagent"
    },
    "logs": {
        "logs_collected": {
            "files": {
                "collect_list": [
                    {
                        "file_path": "/var/log/httpd/access_log",
                        "log_group_name": "/aws/ec2/lift-shift-migration-dev/web-server",
                        "log_stream_name": "{instance_id}/httpd/access_log"
                    },
                    {
                        "file_path": "/var/log/httpd/error_log",
                        "log_group_name": "/aws/ec2/lift-shift-migration-dev/web-server",
                        "log_stream_name": "{instance_id}/httpd/error_log"
                    },
                    {
                        "file_path": "/var/www/html/logs/application.log",
                        "log_group_name": "/aws/ec2/lift-shift-migration-dev/application",
                        "log_stream_name": "{instance_id}/application.log"
                    }
                ]
            }
        }
    },
    "metrics": {
        "namespace": "CWAgent",
        "metrics_collected": {
            "cpu": {
                "measurement": ["cpu_usage_idle", "cpu_usage_user", "cpu_usage_system"],
                "metrics_collection_interval": 60
            },
            "disk": {
                "measurement": ["used_percent"],
                "metrics_collection_interval": 60,
                "resources": ["*"]
            },
            "mem": {
                "measurement": ["mem_used_percent"],
                "metrics_collection_interval": 60
            }
        }
    }
}
EOF

# Start CloudWatch Agent
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json -s

# Create application directory structure
mkdir -p /var/www/html/logs
mkdir -p /var/www/html/config
mkdir -p /var/www/html/uploads

# Set permissions
chown -R apache:apache /var/www/html
chmod -R 755 /var/www/html

# Create a simple health check endpoint
cat > /var/www/html/health.php << 'EOF'
<?php
header('Content-Type: application/json');

$health = [
    'status' => 'healthy',
    'timestamp' => date('c'),
    'server' => gethostname(),
    'checks' => []
];

// Database connectivity check
try {
    $db_host = '${db_endpoint}';
    $db_name = 'lift_shift_migration_dev';
    $db_user = 'admin';
    
    // Get password from AWS Secrets Manager
    $secret_name = "lift-shift-migration-dev-db-password";
    $region = "${region}";
    
    $cmd = "aws secretsmanager get-secret-value --secret-id $secret_name --region $region --query SecretString --output text";
    $secret_json = shell_exec($cmd);
    $secret = json_decode($secret_json, true);
    $db_pass = $secret['password'];
    
    $pdo = new PDO("mysql:host=$db_host;dbname=$db_name", $db_user, $db_pass);
    $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    
    $health['checks']['database'] = 'connected';
} catch (Exception $e) {
    $health['checks']['database'] = 'failed: ' . $e->getMessage();
    $health['status'] = 'unhealthy';
}

// S3 connectivity check
try {
    $bucket = '${s3_bucket}';
    $cmd = "aws s3 ls s3://$bucket --region ${region}";
    $result = shell_exec($cmd);
    
    if ($result !== null) {
        $health['checks']['s3'] = 'accessible';
    } else {
        $health['checks']['s3'] = 'failed';
        $health['status'] = 'unhealthy';
    }
} catch (Exception $e) {
    $health['checks']['s3'] = 'failed: ' . $e->getMessage();
    $health['status'] = 'unhealthy';
}

// Disk space check
$disk_free = disk_free_space('/');
$disk_total = disk_total_space('/');
$disk_usage = (($disk_total - $disk_free) / $disk_total) * 100;

if ($disk_usage > 90) {
    $health['checks']['disk'] = 'critical: ' . round($disk_usage, 2) . '% used';
    $health['status'] = 'unhealthy';
} else {
    $health['checks']['disk'] = 'ok: ' . round($disk_usage, 2) . '% used';
}

echo json_encode($health, JSON_PRETTY_PRINT);
?>
EOF

# Create application configuration file
cat > /var/www/html/config/database.php << 'EOF'
<?php
// Database configuration
$db_config = [
    'host' => '${db_endpoint}',
    'database' => 'lift_shift_migration_dev',
    'username' => 'admin',
    'charset' => 'utf8mb4'
];

// Get password from AWS Secrets Manager
function getDbPassword() {
    $secret_name = "lift-shift-migration-dev-db-password";
    $region = "${region}";
    
    $cmd = "aws secretsmanager get-secret-value --secret-id $secret_name --region $region --query SecretString --output text";
    $secret_json = shell_exec($cmd);
    $secret = json_decode($secret_json, true);
    
    return $secret['password'];
}

$db_config['password'] = getDbPassword();

// S3 configuration
$s3_config = [
    'bucket' => '${s3_bucket}',
    'region' => '${region}'
];
?>
EOF

# Create a simple index page
cat > /var/www/html/index.php << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>AWS Lift and Shift Migration - Web Application</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        .container { max-width: 800px; margin: 0 auto; }
        .status { padding: 10px; margin: 10px 0; border-radius: 5px; }
        .healthy { background-color: #d4edda; color: #155724; }
        .unhealthy { background-color: #f8d7da; color: #721c24; }
        .info { background-color: #d1ecf1; color: #0c5460; }
    </style>
</head>
<body>
    <div class="container">
        <h1>AWS Lift and Shift Migration</h1>
        <h2>Web Application Status</h2>
        
        <?php
        require_once 'config/database.php';
        
        echo '<div class="info">';
        echo '<h3>Server Information</h3>';
        echo '<p><strong>Server:</strong> ' . gethostname() . '</p>';
        echo '<p><strong>PHP Version:</strong> ' . phpversion() . '</p>';
        echo '<p><strong>Timestamp:</strong> ' . date('Y-m-d H:i:s T') . '</p>';
        echo '</div>';
        
        // Test database connection
        try {
            $pdo = new PDO(
                "mysql:host={$db_config['host']};dbname={$db_config['database']};charset={$db_config['charset']}", 
                $db_config['username'], 
                $db_config['password']
            );
            $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
            
            echo '<div class="status healthy">';
            echo '<h3>✓ Database Connection</h3>';
            echo '<p>Successfully connected to MySQL database</p>';
            echo '</div>';
            
        } catch (Exception $e) {
            echo '<div class="status unhealthy">';
            echo '<h3>✗ Database Connection</h3>';
            echo '<p>Failed to connect: ' . htmlspecialchars($e->getMessage()) . '</p>';
            echo '</div>';
        }
        
        // Test S3 connection
        $bucket = $s3_config['bucket'];
        $region = $s3_config['region'];
        $cmd = "aws s3 ls s3://$bucket --region $region 2>&1";
        $result = shell_exec($cmd);
        
        if (strpos($result, 'error') === false && !empty(trim($result))) {
            echo '<div class="status healthy">';
            echo '<h3>✓ S3 Storage</h3>';
            echo '<p>Successfully connected to S3 bucket: ' . htmlspecialchars($bucket) . '</p>';
            echo '</div>';
        } else {
            echo '<div class="status unhealthy">';
            echo '<h3>✗ S3 Storage</h3>';
            echo '<p>Failed to access S3 bucket: ' . htmlspecialchars($bucket) . '</p>';
            echo '</div>';
        }
        ?>
        
        <div class="info">
            <h3>Migration Project Features</h3>
            <ul>
                <li>✓ VPC with public/private subnets</li>
                <li>✓ Application Load Balancer</li>
                <li>✓ RDS MySQL database</li>
                <li>✓ S3 file storage</li>
                <li>✓ CloudWatch monitoring</li>
                <li>✓ Auto Scaling (when configured)</li>
                <li>✓ Security groups and IAM roles</li>
            </ul>
        </div>
    </div>
</body>
</html>
EOF

# Configure Apache
systemctl enable httpd
systemctl start httpd

# Configure PHP error logging
echo "log_errors = On" >> /etc/php.ini
echo "error_log = /var/www/html/logs/php_errors.log" >> /etc/php.ini

# Restart Apache to apply PHP changes
systemctl restart httpd

# Create log rotation for application logs
cat > /etc/logrotate.d/webapp << 'EOF'
/var/www/html/logs/*.log {
    daily
    missingok
    rotate 7
    compress
    notifempty
    create 644 apache apache
    postrotate
        systemctl reload httpd
    endscript
}
EOF

# Install and configure fail2ban for security
yum install -y epel-release
yum install -y fail2ban

cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3

[sshd]
enabled = true
port = ssh
logpath = /var/log/secure
maxretry = 3

[httpd-auth]
enabled = true
port = http,https
logpath = /var/log/httpd/error_log
maxretry = 3
EOF

systemctl enable fail2ban
systemctl start fail2ban

# Set up automatic security updates
yum install -y yum-cron
systemctl enable yum-cron
systemctl start yum-cron

echo "Web server setup completed successfully!"