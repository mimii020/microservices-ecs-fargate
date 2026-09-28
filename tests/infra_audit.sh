#!/usr/bin/env bash
# infra-audit.sh — Inventory of AWS infrastructure provisioned for this project.
#
# Usage:   ./scripts/infra-audit.sh
# Output:  <repo-root>/docs/infra-report.md
# Requires: aws-cli, jq (terraform optional)

set -uo pipefail

# --- Resolve repo root (no chained || && — explicit if) -------------------
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
if [ -z "$REPO_ROOT" ]; then
  REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi
cd "$REPO_ROOT"

# Make sure terraform from tfenv is reachable in non-interactive shells
export PATH="$HOME/.tfenv/bin:$HOME/bin:$PATH"

PROJECT="microservices-ecs-fargate"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"
OUT="docs/infra-report.md"
mkdir -p "$(dirname "$OUT")"

# --- Helpers --------------------------------------------------------------
section() { printf '\n## %s\n\n' "$1" >> "$OUT"; }
kv()      { printf -- '- **%s**: %s\n' "$1" "$2" >> "$OUT"; }
num()     { printf '%s' "${1:-0}" | head -1 | tr -dc '0-9'; }

code() {
  local out
  out=$("$@" 2>&1) || true
  if [ -n "$out" ] && [ "$out" != "None" ]; then
    printf '```\n%s\n```\n' "$out" >> "$OUT"
  else
    printf '_No results._\n' >> "$OUT"
  fi
}

# --- Report header --------------------------------------------------------
: > "$OUT"
{
  printf '# Infrastructure Audit\n\n'
  printf 'Generated: %s\n\n' "$(date -u +'%Y-%m-%d %H:%M UTC')"
  printf 'Region: `%s`  \nProject: `%s`\n' "$REGION" "$PROJECT"
} >> "$OUT"

# --- VPC ------------------------------------------------------------------
VPC_ID=$(aws ec2 describe-vpcs \
  --filters "Name=tag:Name,Values=microservices-ecs-vpc" \
  --query 'Vpcs[0].VpcId' --output text 2>/dev/null)

section "VPC & Networking"
kv "VPC ID" "$VPC_ID"
kv "CIDR" "$(aws ec2 describe-vpcs --vpc-ids "$VPC_ID" \
  --query 'Vpcs[0].CidrBlock' --output text 2>/dev/null)"

kv "Subnets" "$(num "$(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query 'length(Subnets)' --output text 2>/dev/null)")"

kv "Security groups" "$(num "$(aws ec2 describe-security-groups \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query 'length(SecurityGroups)' --output text 2>/dev/null)")"

kv "Total SG rules (ingress + egress)" "$(num "$(aws ec2 describe-security-groups \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query 'sum(SecurityGroups[*].[length(IpPermissions[]),length(IpPermissionsEgress[])][])' \
  --output text 2>/dev/null)")"

kv "NAT gateways" "$(num "$(aws ec2 describe-nat-gateways \
  --filter "Name=vpc-id,Values=$VPC_ID" "Name=state,Values=available" \
  --query 'length(NatGateways)' --output text 2>/dev/null)")"

# --- ECS ------------------------------------------------------------------
section "ECS Fargate"
code aws ecs describe-clusters --clusters "$PROJECT" \
  --query 'clusters[0].[clusterName,status,activeServicesCount,runningTasksCount,pendingTasksCount]' \
  --output table

kv "Registered services" "$(num "$(aws ecs list-services --cluster "$PROJECT" \
  --query 'length(serviceArns)' --output text 2>/dev/null)")"

FAMILIES=$(aws ecs list-task-definition-families \
  --query 'families[?contains(@, `auth-service`) || contains(@, `orders-service`) || contains(@, `microservices-ecs-fargate`)]' \
  --output text 2>/dev/null)

FAMILY_COUNT=$(echo "$FAMILIES" | tr '\t' '\n' | grep -c . 2>/dev/null || echo 0)
kv "Task definition families (project)" "$(num "$FAMILY_COUNT")"

if [ -n "$FAMILIES" ] && [ "$FAMILIES" != "None" ]; then
  printf '\n### Task definition families\n\n' >> "$OUT"
  printf '```\n' >> "$OUT"
  echo "$FAMILIES" | tr '\t' '\n' >> "$OUT"
  printf '```\n' >> "$OUT"
fi

# --- ALB ------------------------------------------------------------------
section "Application Load Balancer"
ALB_DNS=$(aws elbv2 describe-load-balancers --names "${PROJECT}-alb" \
  --query 'LoadBalancers[0].DNSName' --output text 2>/dev/null)
kv "ALB DNS" "${ALB_DNS:-N/A}"

kv "State" "$(aws elbv2 describe-load-balancers --names "${PROJECT}-alb" \
  --query 'LoadBalancers[0].State.Code' --output text 2>/dev/null)"

# Only count the primary TGs (exact names, exclude -blue/-green orphans)
TG_FILTER="TargetGroups[?TargetGroupName=='auth-tg' || TargetGroupName=='orders-tg']"
kv "Target groups (project)" "$(num "$(aws elbv2 describe-target-groups \
  --query "length($TG_FILTER)" --output text 2>/dev/null)")"

printf '\n### Target groups\n\n' >> "$OUT"
printf '```\n' >> "$OUT"
aws elbv2 describe-target-groups \
  --query "$TG_FILTER.[TargetGroupName,Port,HealthCheckPath]" \
  --output table >> "$OUT" 2>&1 || true
printf '```\n' >> "$OUT"

# --- RDS ------------------------------------------------------------------
section "RDS PostgreSQL"
code aws rds describe-db-instances --db-instance-identifier auth-orders-db \
  --query 'DBInstances[0].[DBInstanceIdentifier,DBInstanceClass,Engine,EngineVersion,DBInstanceStatus,AllocatedStorage]' \
  --output table

# --- ECR ------------------------------------------------------------------
section "ECR Repositories"
code aws ecr describe-repositories \
  --query 'repositories[*].{Name:repositoryName,URI:repositoryUri,ScanOnPush:imageScanningConfiguration.scanOnPush}' \
  --output table

NO_SCAN=$(aws ecr describe-repositories \
  --query 'repositories[?imageScanningConfiguration.scanOnPush==`false`].repositoryName' \
  --output text 2>/dev/null | tr '\t' ' ')
if [ -n "$NO_SCAN" ] && [ "$NO_SCAN" != "None" ]; then
  printf '\n> ⚠️  **Scan-on-push disabled** for: `%s`. Enable via:\n' "$NO_SCAN" >> "$OUT"
  printf '> ```hcl\n> image_scanning_configuration { scan_on_push = true }\n> ```\n' >> "$OUT"
fi

# --- IAM ------------------------------------------------------------------
section "IAM Roles"
code aws iam list-roles \
  --query "Roles[?contains(RoleName, '${PROJECT}')].RoleName" \
  --output table

# --- Cloud Map ------------------------------------------------------------
section "AWS Cloud Map (Service Discovery)"
code aws servicediscovery list-namespaces \
  --query 'Namespaces[*].[Name,Type,Id,CreateDate]' \
  --output table

DUPES=$(aws servicediscovery list-namespaces \
  --query 'Namespaces[*].Name' --output text 2>/dev/null \
  | tr '\t' '\n' | sort | uniq -d)
if [ -n "$DUPES" ]; then
  printf '\n> ⚠️  **Duplicate Cloud Map namespaces detected**: `%s`\n' "$DUPES" >> "$OUT"
  printf '> Only one should have services registered. Investigate with:\n' >> "$OUT"
  printf '> ```bash\n> aws servicediscovery list-namespaces --query "Namespaces[*].[Id,Name,CreateDate]" --output table\n> ```\n' >> "$OUT"
fi

# --- Secrets --------------------------------------------------------------
section "Secrets Manager"
code aws secretsmanager describe-secret \
  --secret-id "${PROJECT}-db-secret" \
  --query '[Name,ARN,RotationEnabled,LastChangedDate]' \
  --output table

# --- Terraform ------------------------------------------------------------
section "Terraform Managed Resources"
if command -v terraform >/dev/null 2>&1 && [ -d terraform ]; then
  (cd terraform && terraform state list > /tmp/tf-state.txt 2>/dev/null) || true
  if [ -s /tmp/tf-state.txt ]; then
    kv "Total resources in state" "$(num "$(wc -l < /tmp/tf-state.txt)")"
    printf '\n### Resources by type\n\n' >> "$OUT"
    printf '```\n' >> "$OUT"
    sed 's/\..*//' /tmp/tf-state.txt | sort | uniq -c | sort -rn >> "$OUT"
    printf '```\n' >> "$OUT"
  else
    printf '_Terraform state empty or not initialized._\n' >> "$OUT"
  fi
else
  printf '_Terraform not on PATH, or `terraform/` directory missing._\n' >> "$OUT"
fi

echo "✅ Infrastructure report written to $OUT"