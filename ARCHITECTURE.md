# AWS Lift and Shift Migration Architecture

## High-Level Architecture

```mermaid
graph TB
    subgraph "Internet"
        Users[Users/Clients]
    end
    
    subgraph "AWS Cloud"
        subgraph "VPC (10.0.0.0/16)"
            subgraph "Public Subnets"
                IGW[Internet Gateway]
                ALB[Application Load Balancer]
                NAT1[NAT Gateway AZ-1a]
                NAT2[NAT Gateway AZ-1b]
            end
            
            subgraph "Private Subnets"
                subgraph "AZ us-east-1a"
                    EC2_1[Web Server 1<br/>EC2 Instance]
                    RDS_PRIMARY[RDS MySQL<br/>Primary Instance]
                end
                
                subgraph "AZ us-east-1b"
                    EC2_2[Web Server 2<br/>EC2 Instance]
                    RDS_REPLICA[RDS MySQL<br/>Read Replica]
                end
            end
        end
        
        subgraph "AWS Services"
            S3[S3 Bucket<br/>File Storage]
            SECRETS[Secrets Manager<br/>DB Credentials]
            CW[CloudWatch<br/>Monitoring & Logs]
            DMS[Database Migration Service]
        end
    end
    
    subgraph "On-Premises"
        ON_PREM_DB[(Source MySQL Database)]
        ON_PREM_WEB[Source Web Servers]
    end
    
    Users --> IGW
    IGW --> ALB
    ALB --> EC2_1
    ALB --> EC2_2
    EC2_1 --> RDS_PRIMARY
    EC2_2 --> RDS_PRIMARY
    EC2_2 --> RDS_REPLICA
    EC2_1 --> S3
    EC2_2 --> S3
    EC2_1 --> SECRETS
    EC2_2 --> SECRETS
    EC2_1 --> CW
    EC2_2 --> CW
    RDS_PRIMARY --> CW
    DMS --> ON_PREM_DB
    DMS --> RDS_PRIMARY
    
    classDef aws fill:#FF9900,stroke:#232F3E,stroke-width:2px,color:#fff
    classDef compute fill:#EC7211,stroke:#232F3E,stroke-width:2px,color:#fff
    classDef database fill:#3F48CC,stroke:#232F3E,stroke-width:2px,color:#fff
    classDef storage fill:#569A31,stroke:#232F3E,stroke-width:2px,color:#fff
    classDef network fill:#8C4FFF,stroke:#232F3E,stroke-width:2px,color:#fff
    classDef onprem fill:#666,stroke:#333,stroke-width:2px,color:#fff
    
    class ALB,IGW,NAT1,NAT2 network
    class EC2_1,EC2_2 compute
    class RDS_PRIMARY,RDS_REPLICA database
    class S3 storage
    class SECRETS,CW,DMS aws
    class ON_PREM_DB,ON_PREM_WEB onprem
```

## Detailed Network Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                                AWS VPC (10.0.0.0/16)                           │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                 │
│  ┌─────────────────────────┐              ┌─────────────────────────┐          │
│  │    Public Subnet 1      │              │    Public Subnet 2      │          │
│  │    (10.0.1.0/24)        │              │    (10.0.2.0/24)        │          │
│  │    AZ: us-east-1a       │              │    AZ: us-east-1b       │          │
│  │                         │              │                         │          │
│  │  ┌─────────────────┐    │              │  ┌─────────────────┐    │          │
│  │  │       ALB       │    │              │  │   NAT Gateway   │    │          │
│  │  │   (Primary)     │    │              │  │                 │    │          │
│  │  └─────────────────┘    │              │  └─────────────────┘    │          │
│  │                         │              │                         │          │
│  │  ┌─────────────────┐    │              │                         │          │
│  │  │   NAT Gateway   │    │              │                         │          │
│  │  │                 │    │              │                         │          │
│  │  └─────────────────┘    │              │                         │          │
│  └─────────────────────────┘              └─────────────────────────┘          │
│                                                                                 │
│  ┌─────────────────────────┐              ┌─────────────────────────┐          │
│  │   Private Subnet 1      │              │   Private Subnet 2      │          │
│  │    (10.0.3.0/24)        │              │    (10.0.4.0/24)        │          │
│  │    AZ: us-east-1a       │              │    AZ: us-east-1b       │          │
│  │                         │              │                         │          │
│  │  ┌─────────────────┐    │              │  ┌─────────────────┐    │          │
│  │  │   Web Server 1  │    │              │  │   Web Server 2  │    │          │
│  │  │   EC2 Instance  │    │              │  │   EC2 Instance  │    │          │
│  │  └─────────────────┘    │              │  └─────────────────┘    │          │
│  │                         │              │                         │          │
│  │  ┌─────────────────┐    │              │  ┌─────────────────┐    │          │
│  │  │  RDS Primary    │    │              │  │  RDS Replica    │    │          │
│  │  │  MySQL 8.0      │    │              │  │  MySQL 8.0      │    │          │
│  │  └─────────────────┘    │              │  └─────────────────┘    │          │
│  └─────────────────────────┘              └─────────────────────────┘          │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────┐
│                              AWS Managed Services                               │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                 │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐           │
│  │     S3      │  │  Secrets    │  │ CloudWatch  │  │     DMS     │           │
│  │   Bucket    │  │  Manager    │  │ Monitoring  │  │ Migration   │           │
│  │             │  │             │  │             │  │   Service   │           │
│  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘           │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘
```

## Migration Flow

```
┌─────────────────┐    Migration    ┌─────────────────┐
│  On-Premises    │    Services     │   AWS Cloud     │
│                 │                 │                 │
│  ┌───────────┐  │                 │  ┌───────────┐  │
│  │MySQL DB   │  │ ──── DMS ────► │  │RDS MySQL  │  │
│  │           │  │                 │  │           │  │
│  └───────────┘  │                 │  └───────────┘  │
│                 │                 │                 │
│  ┌───────────┐  │                 │  ┌───────────┐  │
│  │Web Servers│  │ ──── MGN ────► │  │EC2 Instances│ │
│  │           │  │                 │  │           │  │
│  └───────────┘  │                 │  └───────────┘  │
│                 │                 │                 │
│  ┌───────────┐  │                 │  ┌───────────┐  │
│  │File Storage│  │ ── Manual ───► │  │S3 Bucket  │  │
│  │           │  │                 │  │           │  │
│  └───────────┘  │                 │  └───────────┘  │
└─────────────────┘                 └─────────────────┘
```

## Security Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                              Security Layers                                    │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                 │
│  Internet ──► WAF ──► ALB ──► Security Groups ──► EC2 Instances                │
│                │       │                                                       │
│                │       └──► SSL/TLS Termination                               │
│                │                                                               │
│                └──► DDoS Protection                                            │
│                                                                                 │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │                        Network Security                                 │   │
│  │                                                                         │   │
│  │  • VPC with private subnets for databases                             │   │
│  │  • Security Groups (stateful firewall)                                │   │
│  │  • NACLs (network-level access control)                               │   │
│  │  • VPC Flow Logs for monitoring                                       │   │
│  │  • Private connectivity to AWS services                               │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│                                                                                 │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │                        Data Security                                    │   │
│  │                                                                         │   │
│  │  • RDS encryption at rest (AES-256)                                   │   │
│  │  • S3 encryption at rest                                              │   │
│  │  • SSL/TLS encryption in transit                                      │   │
│  │  • Secrets Manager for credentials                                    │   │
│  │  • IAM roles with least privilege                                     │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘
```

## Component Details

### Compute Layer
- **EC2 Instances**: t3.medium instances running Amazon Linux 2023
- **Auto Scaling**: Configurable ASG for high availability
- **Load Balancer**: Application Load Balancer with health checks

### Database Layer
- **RDS MySQL**: Multi-AZ deployment for high availability
- **Read Replicas**: For read scaling and disaster recovery
- **Automated Backups**: 7-day retention with point-in-time recovery

### Storage Layer
- **S3 Bucket**: Object storage for application files
- **Lifecycle Policies**: Automatic transition to cheaper storage classes
- **Versioning**: Enabled for data protection

### Network Layer
- **VPC**: Isolated network environment
- **Subnets**: Public for load balancers, private for applications
- **NAT Gateways**: Outbound internet access for private subnets
- **Security Groups**: Application-level firewall rules

### Monitoring Layer
- **CloudWatch**: Metrics, logs, and alarms
- **Custom Dashboards**: Application performance monitoring
- **SNS Notifications**: Alert notifications via email/SMS

### Migration Services
- **DMS**: Database migration with minimal downtime
- **MGN**: Server migration service
- **Secrets Manager**: Secure credential storage

## Scalability Features

### Horizontal Scaling
- Auto Scaling Groups for EC2 instances
- Application Load Balancer for traffic distribution
- RDS Read Replicas for database read scaling

### Vertical Scaling
- Easy instance type changes
- RDS instance class modifications
- Storage auto-scaling

### Geographic Scaling
- Multi-AZ deployment for high availability
- Cross-region replication capabilities
- CloudFront CDN integration ready

## Disaster Recovery

### Backup Strategy
- RDS automated backups with 7-day retention
- S3 versioning and cross-region replication
- Infrastructure as Code for rapid rebuilding

### Recovery Objectives
- **RTO (Recovery Time Objective)**: < 4 hours
- **RPO (Recovery Point Objective)**: < 15 minutes
- **Availability Target**: 99.9% uptime

This architecture provides a robust, scalable, and secure foundation for migrating traditional web applications to AWS cloud infrastructure.