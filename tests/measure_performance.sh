#!/usr/bin/env bash
# app-health.sh — Runtime health, latency, and availability measurements.
# Concept: What does the deployed system look like from a user's perspective.
#
# Usage:   ./scripts/app-health.sh      (from anywhere inside the repo)
# Output:  <repo-root>/docs/runtime-report.md
#
# Requires: aws-cli, curl, jq

set -uo pipefail

# --- Resolve repo root so relative paths work from any CWD ----------------
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null \
  || cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

PROJECT="microservices-ecs-fargate"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"
OUT="docs/runtime-report.md"
mkdir -p "$(dirname "$OUT")"

# --- Output helpers -------------------------------------------------------
section() { printf '\n## %s\n\n' "$1" >> "$OUT"; }
kv()      { printf -- '- **%s**: %s\n' "$1" "$2" >> "$OUT"; }

code() {
  local out
  out=$("$@" 2>&1) || true
  if [ -n "$out" ] && [ "$out" != "None" ]; then
    printf '```\n%s\n```\n' "$out" >> "$OUT"
  else
    printf '_No results._\n' >> "$OUT"
  fi
}

# Wrapper that returns "HTTP_CODE|TIME_TOTAL" for a curl call.
timed_curl() {
  curl -o /dev/null -s -w '%{http_code}|%{time_total}' "$@"
}

# ==========================================================================
# Resolve ALB DNS
# ==========================================================================
ALB_DNS=$(aws elbv2 describe-load-balancers --names "${PROJECT}-alb" \
  --query 'LoadBalancers[0].DNSName' --output text 2>/dev/null)
BASE="http://${ALB_DNS}"

: > "$OUT"
{
  printf '# Runtime Health Report\n\n'
  printf 'Generated: %s\n\n' "$(date -u +'%Y-%m-%d %H:%M UTC')"
  printf 'Endpoint: `%s`\n\n' "$BASE"
  printf '> Measured from AWS CloudShell (same region as the stack, `%s`).\n' "$REGION"
  printf '> Latency includes intra-region network hops only.\n'
} >> "$OUT"

if [ -z "$ALB_DNS" ] || [ "$ALB_DNS" = "None" ]; then
  printf '\n> ⚠️  Could not resolve ALB DNS. Is the stack up?\n' >> "$OUT"
  exit 1
fi

# ==========================================================================
# ECS Service State
# ==========================================================================
section "ECS Service State"
code aws ecs describe-services --cluster "$PROJECT" --services auth orders \
  --query 'services[*].[serviceName,runningCount,desiredCount,status]' \
  --output table

# ==========================================================================
# ALB Target Group Health
# ==========================================================================
section "ALB Target Group Health"
for svc in auth orders; do
  TG_ARN=$(aws elbv2 describe-target-groups --names "${svc}-tg" \
    --query 'TargetGroups[0].TargetGroupArn' --output text 2>/dev/null)
  [ -z "$TG_ARN" ] || [ "$TG_ARN" = "None" ] && continue
  printf '\n### %s\n\n' "$svc" >> "$OUT"
  code aws elbv2 describe-target-health --target-group-arn "$TG_ARN" \
    --query 'TargetHealthDescriptions[*].[Target.Id,TargetHealth.State,TargetHealth.Reason]' \
    --output table
done

# ==========================================================================
# Health Endpoint Latency (10 requests per service)
# ==========================================================================
section "Health Endpoint Latency (10 requests per service)"
for svc in auth orders; do
  printf '\n### %s\n\n' "$svc" >> "$OUT"
  printf '```\n' >> "$OUT"
  total=0
  success=0
  for i in $(seq 1 10); do
    result=$(timed_curl "${BASE}/${svc}/health")
    code_http="${result%|*}"
    t="${result#*|}"
    printf 'req %2d: HTTP %s  %ss\n' "$i" "$code_http" "$t" >> "$OUT"
    if [ "$code_http" = "200" ]; then
      total=$(awk "BEGIN {print $total + $t}")
      success=$((success + 1))
    fi
  done
  if [ "$success" -gt 0 ]; then
    avg=$(awk "BEGIN {printf \"%.3f\", $total/$success}")
    printf '```\n' >> "$OUT"
    kv "Average (successful requests)" "${avg}s"
    kv "Successful / total" "${success} / 10"
  else
    printf '```\n' >> "$OUT"
    kv "Average" "N/A — all requests failed"
  fi
done

# ==========================================================================
# End-to-End Functional Test
# ==========================================================================
section "End-to-End Functional Test"
USER="bench_$(date +%s)"
printf 'Test user: `%s`\n\n' "$USER" >> "$OUT"

result=$(timed_curl -X POST "${BASE}/auth/register" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"$USER\",\"password\":\"benchpass123\"}")
code_http="${result%|*}"
t="${result#*|}"
kv "Register latency" "${t}s (HTTP ${code_http})"

result=$(timed_curl -X POST "${BASE}/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"$USER\",\"password\":\"benchpass123\"}")
code_http="${result%|*}"
t="${result#*|}"
kv "Login latency" "${t}s (HTTP ${code_http})"

TOKEN=$(curl -s -X POST "${BASE}/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"$USER\",\"password\":\"benchpass123\"}" | jq -r .token)

if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
  kv "Order tests" "SKIPPED — could not obtain auth token"
else
  result=$(timed_curl -X POST "${BASE}/orders/" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $TOKEN" \
    -d '{"item":"bench-widget","quantity":1}')
  code_http="${result%|*}"
  t="${result#*|}"
  kv "Order creation latency" "${t}s (HTTP ${code_http})"

  result=$(timed_curl "${BASE}/orders/" \
    -H "Authorization: Bearer $TOKEN")
  code_http="${result%|*}"
  t="${result#*|}"
  kv "Order list latency" "${t}s (HTTP ${code_http})"
fi

# ==========================================================================
# ECS Task Startup Time
# ==========================================================================
section "ECS Task Startup Time"
for svc in auth orders; do
  TASK_ARN=$(aws ecs list-tasks --cluster "$PROJECT" \
    --service-name "$svc" --desired-status RUNNING \
    --query 'taskArns[0]' --output text 2>/dev/null)
  [ -z "$TASK_ARN" ] || [ "$TASK_ARN" = "None" ] && continue
  printf '\n### %s\n\n' "$svc" >> "$OUT"
  code aws ecs describe-tasks --cluster "$PROJECT" --tasks "$TASK_ARN" \
    --query 'tasks[0].[createdAt,startedAt,lastStatus,healthStatus]' --output table
done

# ==========================================================================
# Log Errors (last 1 hour)
# ==========================================================================
section "Log Errors (last 1 hour)"
for svc in auth orders; do
  LG=$(aws logs describe-log-groups \
    --log-group-name-prefix "/ecs/${PROJECT}/${svc}-service" \
    --query 'logGroups[0].logGroupName' --output text 2>/dev/null)
  [ -z "$LG" ] || [ "$LG" = "None" ] && continue
  start_ms=$(( ($(date +%s) - 3600) * 1000 ))
  count=$(aws logs filter-log-events --log-group-name "$LG" \
    --start-time "$start_ms" --filter-pattern "ERROR" \
    --query 'length(events)' --output text 2>/dev/null \
    | head -1 | tr -dc '0-9')
  kv "$svc ERROR events" "${count:-0}"
done

echo "✅ Runtime report written to $OUT"