set -uo pipefail

PROJECT="microservices-ecs-fargate"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"
OUT="docs/infra-report.md"
mkdir -p "$(dirname "$OUT")"

section() { printf '\n## %s\n\n' "$1" >> "$OUT"; }
code()    { printf '```\n' >> "$OUT"; "$@" >> "$OUT" 2>&1 || true; printf '```\n' >> "$OUT"; }
kv()      { printf '- **%s**: %s\n' "$1" "$2" >> "$OUT"; }

: > "$OUT"
{
  printf '# Infrastructure Audit\n\n'
  printf 'Generated: %s\n\n' "$(date -u +'%Y-%m-%d %H:%M UTC')"
  printf 'Region: `%s`  \nProject: `%s`\n' "$REGION" "$PROJECT"
} >> "$OUT"

# --- VPC & Networking -----------------------------------------------------
VPC_ID=$(aws ec2 describe-vpcs \
  --filters "Name=tag:Name,Values=microservices-ecs-vpc" \
  --query 'Vpcs[0].VpcId' --output text 2>/dev/null)

section "VPC & Networking"
kv "VPC ID" "$VPC_ID"
kv "CIDR" "$(aws ec2 describe-vpcs --vpc-ids "$VPC_ID" \
  --query 'Vpcs[0].CidrBlock' --output text 2>/dev/null)"

SUBNET_COUNT=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" \
  --query 'length(Subnets)' --output text 2>/dev/null)
kv "Subnets" "$SUBNET_COUNT"

SG_COUNT=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" \
  --query 'length(SecurityGroups)' --output text 2>/dev/null)
kv "Security groups" "$SG_COUNT"

SG_RULE_COUNT=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" \
  --query 'sum(SecurityGroups[*].[length(IpPermissions[]),length(IpPermissionsEgress[])][])' \
  --output text 2>/dev/null)
kv "Total SG rules (ingress + egress)" "$SG_RULE_COUNT"

NAT_COUNT=$(aws ec2 describe-nat-gateways \
  --filter "Name=vpc-id,Values=$VPC_ID" "Name=state,Values=available" \
  --query 'length(NatGateways)' --output text 2>/dev/null)
kv "NAT gateways" "$NAT_COUNT"

# --- ECS Fargate ----------------------------------------------------------
section "ECS Fargate"
code aws ecs describe-clusters --clusters "$PROJECT" \
  --query 'clusters[0].[clusterName,status,activeServicesCount,runningTasksCount,pendingTasksCount]' \
  --output table

kv "Registered services" "$(aws ecs list-services --cluster "$PROJECT" \
  --query 'length(serviceArns)' --output text 2>/dev/null)"

kv "Task definition families" "$(aws ecs list-task-definition-families \
  --family-prefix auth-service --query 'length(families)' --output text 2>/dev/null)"

# --- Load Balancer --------------------------------------------------------
section "Application Load Balancer"
ALB_DNS=$(aws elbv2 describe-load-balancers --names "${PROJECT}-alb" \
  --query 'LoadBalancers[0].DNSName' --output text 2>/dev/null)
kv "ALB DNS" "$ALB_DNS"
kv "State" "$(aws elbv2 describe-load-balancers --names "${PROJECT}-alb" \
  --query 'LoadBalancers[0].State.Code' --output text 2>/dev/null)"

kv "Target groups" "$(aws elbv2 describe-target-groups \
  --query 'length(TargetGroups[?contains(TargetGroupName,`auth`)||contains(TargetGroupName,`orders`||contains(TargetGroupName,`tg`)])' \
  --output text 2>/dev/null)"

# --- RDS ------------------------------------------------------------------
section "RDS PostgreSQL"
code aws rds describe-db-instances --db-instance-identifier auth-orders-db \
  --query 'DBInstances[0].[DBInstanceIdentifier,DBInstanceClass,Engine,EngineVersion,DBInstanceStatus,AllocatedStorage]' \
  --output table

# --- ECR ------------------------------------------------------------------
section "ECR Repositories"
code aws ecr describe-repositories \
  --query 'repositories[?starts_with(repositoryName,`auth`)||starts_with(repositoryName,`orders`)].{Name:repositoryName,URI:repositoryUri,ScanOnPush:imageScanningConfiguration.scanOnPush}' \
  --output table

# --- IAM ------------------------------------------------------------------
section "IAM Roles"
code aws iam list-roles \
  --query "Roles[?contains(RoleName, '${PROJECT}')].RoleName" \
  --output table

# --- Cloud Map ------------------------------------------------------------
section "AWS Cloud Map (Service Discovery)"
code aws servicediscovery list-namespaces \
  --query 'Namespaces[*].[Name,Type,Id]' --output table

# --- Secrets --------------------------------------------------------------
section "Secrets Manager"
code aws secretsmanager describe-secret \
  --secret-id "${PROJECT}-db-secret" \
  --query '[Name,ARN,RotationEnabled,LastChangedDate]' \
  --output table

# --- Terraform state ------------------------------------------------------
section "Terraform Managed Resources"
if command -v terraform >/dev/null && [ -d terraform ]; then
  (cd terraform && terraform state list > /tmp/tf-state.txt 2>/dev/null) || true
  if [ -s /tmp/tf-state.txt ]; then
    kv "Total resources in state" "$(wc -l < /tmp/tf-state.txt)"
    printf '\n### Resources by type\n\n' >> "$OUT"
    printf '```\n' >> "$OUT"
    sed 's/\..*//' /tmp/tf-state.txt | sort | uniq -c | sort -rn >> "$OUT"
    printf '```\n' >> "$OUT"
  fi
fi

echo "✅ Infrastructure report written to $OUT"