# Infrastructure Audit

Generated: 2026-09-28 23:11 UTC

Region: `us-east-1`  
Project: `microservices-ecs-fargate`

## VPC & Networking

- **VPC ID**: vpc-06c9b69e99ba84857
- **CIDR**: 10.0.0.0/16
- **Subnets**: 4
- **Security groups**: 5
- **Total SG rules (ingress + egress)**: 13
- **NAT gateways**: 1

## ECS Fargate
| DescribeClusters |
+-----------------------------+
| microservices-ecs-fargate |
| ACTIVE |
| 2 |
| 2 |
| 0 |
+-----------------------------+

- **Registered services**: 2
- **Task definition families**: 2 -> auth and orders tasks


## Application Load Balancer

- **ALB DNS**: microservices-ecs-fargate-alb-510987396.us-east-1.elb.amazonaws.com
- **State**: active
- **Target groups (project)**: 2

### Target groups
| DescribeTargetGroups |
+------------+-------+------------------+
| auth-tg | 5000 | /auth/health |
| orders-tg | 5001 | /orders/health |
+------------+-------+------------------+


## RDS PostgreSQL

|DescribeDBInstances|
+-------------------+
| auth-orders-db |
| db.t3.micro |
| postgres |
| 18.3 |
| available |
| 20 |
+-------------------+


## ECR Repositories
| DescribeRepositories |
+----------------+-------------+----------------------------------------------------------------+
| Name | ScanOnPush | URI |
+----------------+-------------+----------------------------------------------------------------+
| auth-service | False | 730335639260.dkr.ecr.us-east-1.amazonaws.com/auth-service |
| orders-service| False | 730335639260.dkr.ecr.us-east-1.amazonaws.com/orders-service |
+----------------+-------------+----------------------------------------------------------------+


> ⚠️  **Scan-on-push disabled** for: `auth-service orders-service`. Enable via:
> ```hcl
> image_scanning_configuration { scan_on_push = true }
> ```

## IAM Roles

| ListRoles |
+-----------------------------------------------------+
| microservices-ecs-fargate-codebuild-role |
| microservices-ecs-fargate-codedeploy-role |
| microservices-ecs-fargate-codepipeline-role |
| microservices-ecs-fargate-ecs-task-execution-role |
+-----------------------------------------------------+

## AWS Cloud Map (Service Discovery)

| ListNamespaces |
+-------------------------------------------+--------------+----------------------+------------------------------------+
| internal.microservices-ecs-fargate.local | DNS_PRIVATE | ns-zrvdkbwc76wikokj | 2026-09-28T21:45:29.159000+00:00 |
+-------------------------------------------+--------------+----------------------+------------------------------------+


## Secrets Manager

| DescribeSecret |
+---------------------------------------------------------------------------------------------------+
| microservices-ecs-fargate-db-secret |
| arn:aws:secretsmanager:us-east-1:730335639260:secret:microservices-ecs-fargate-db-secret-G4GZJS |
| None |
| 2026-09-28T22:26:36.180000+00:00 |
+---------------------------------------------------------------------------------------------------+


## Terraform Managed Resources

- **Total resources in state**: 70

### Resources by type

 aws_vpc_security_group_egress_rule
6 aws_vpc_security_group_ingress_rule
6 aws_lb_target_group
4 aws_subnet
4 aws_security_group
4 aws_route_table_association
4 aws_iam_role
3 data
3 aws_iam_role_policy_attachment
2 aws_service_discovery_service
2 aws_route_table
2 aws_lb_listener_rule
2 aws_ecs_task_definition
2 aws_ecs_service
2 aws_cloudwatch_log_group
1 random_password
1 random_id
1 aws_vpc
1 aws_service_discovery_private_dns_namespace
1 aws_secretsmanager_secret_version
1 aws_secretsmanager_secret
1 aws_s3_bucket
1 aws_nat_gateway
1 aws_lb_listener
1 aws_lb
1 aws_internet_gateway
1 aws_iam_policy
1 aws_eip
1 aws_ecs_cluster
1 aws_db_subnet_group
1 aws_db_instance
1 aws_codedeploy_app


