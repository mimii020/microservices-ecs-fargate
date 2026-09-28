set -uo pipefail

PROJECT="microservices-ecs-fargate"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"
OUT="docs/runtime-report.md"
mkdir -p "$(dirname "$OUT")"

section() { printf '\n## %s\n\n' "$1" >> "$OUT"; }
code()    { printf '```\n' >> "$OUT"; "$@" >> "$OUT" 2>&1 || true; printf '```\n' >> "$OUT"; }
kv()      { printf -- '- **%s**: %s\n' "$1" "$2" >> "$OUT"; }

# Resolve ALB DNS
ALB_DNS=$(aws elbv2 describe-load-balancers --names "${PROJECT}-alb" \
  --query 'LoadBalancers[0].DNSName' --output text 2>/dev/null)
BASE="http://${ALB_DNS}"

: > "$OUT"
{
  printf '# Runtime Health Report\n\n'
  printf 'Generated: %s\n\n' "$(date -u +'%Y-%m-%d %H:%M UTC')"
  printf 'Endpoint: `%s`\n' "$BASE"
} >> "$OUT"

if [ -z "$ALB_DNS" ] || [ "$ALB_DNS" = "None" ]; then
  printf '\n> ⚠️  Could not resolve ALB DNS. Is the stack up?\n' >> "$OUT"
  exit 1
fi

# --- Task & Service state -------------------------------------------------
section "ECS Service State"
code aws ecs describe-services --cluster "$PROJECT" --services auth orders \
  --query 'services[*].[serviceName,runningCount,desiredCount,status]' \
  --output table

# --- Target group health --------------------------------------------------
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

# --- Health endpoint latency ---------------------------------------------
section "Health Endpoint Latency (10 requests per service)"
for svc in auth orders; do
  printf '\n### %s\n\n' "$svc" >> "$OUT"
  printf '```\n' >> "$OUT"
  total=0
  for i in $(seq 1 10); do
    t=$(curl -o /dev/null -s -w '%{time_total}' "${BASE}/${svc}/health")
    printf 'req %2d: %ss\n' "$i" "$t" >> "$OUT"
    total=$(awk "BEGIN {print $total + $t}")
  done
  avg=$(awk "BEGIN {printf \"%.3f\", $total/10}")
  printf '```\n' >> "$OUT"
  kv "Average" "${avg}s"
done

# --- End-to-end functional test -------------------------------------------
section "End-to-End Functional Test"
USER="bench_$(date +%s)"
printf 'Test user: `%s`\n\n' "$USER" >> "$OUT"

REGISTER_T=$(curl -o /dev/null -s -w '%{time_total}' \
  -X POST "${BASE}/auth/register" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"$USER\",\"password\":\"benchpass123\"}")
kv "Register latency" "${REGISTER_T}s"

LOGIN_T=$(curl -o /dev/null -s -w '%{time_total}' \
  -X POST "${BASE}/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"$USER\",\"password\":\"benchpass123\"}")
kv "Login latency" "${LOGIN_T}s"

TOKEN=$(curl -s -X POST "${BASE}/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"$USER\",\"password\":\"benchpass123\"}" | jq -r .token)

ORDER_T=$(curl -o /dev/null -s -w '%{time_total}' \
  -X POST "${BASE}/orders/" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"item":"bench-widget","quantity":1}')
kv "Order creation latency" "${ORDER_T}s"

LIST_T=$(curl -o /dev/null -s -w '%{time_total}' \
  "${BASE}/orders/" \
  -H "Authorization: Bearer $TOKEN")
kv "Order list latency" "${LIST_T}s"

# --- Task startup time ----------------------------------------------------
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

# --- Log errors in last hour ---------------------------------------------
section "Log Errors (last 1 hour)"
for svc in auth orders; do
  LG=$(aws logs describe-log-groups \
    --log-group-name-prefix "/ecs/${PROJECT}/${svc}-service" \
    --query 'logGroups[0].logGroupName' --output text 2>/dev/null)
  [ -z "$LG" ] || [ "$LG" = "None" ] && continue
  start_ms=$(( ($(date +%s) - 3600) * 1000 ))
  count=$(aws logs filter-log-events --log-group-name "$LG" \
    --start-time "$start_ms" --filter-pattern "ERROR" \
    --query 'length(events)' --output text 2>/dev/null)
  kv "$svc ERROR events" "$count"
done

echo "✅ Runtime report written to $OUT"