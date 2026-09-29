# Runtime Health Report

Generated: 2026-09-28 23:12 UTC

Endpoint: `http://microservices-ecs-fargate-alb-510987396.us-east-1.elb.amazonaws.com`

> Measured from AWS CloudShell (same region as the stack, `us-east-1`).
> Latency includes intra-region network hops only.

## ECS Service State

| DescribeServices |
+---------+----+----+----------+
| auth | 1 | 1 | ACTIVE |
| orders | 1 | 1 | ACTIVE |
+---------+----+----+----------+


## ALB Target Group Health


### auth

| DescribeTargetHealth |
+-------------+-----------+-------+
| 10.0.1.165 | healthy | None |
+-------------+-----------+-------+


### orders

| DescribeTargetHealth |
+-------------+-----------+-------+
| 10.0.3.196 | healthy | None |
+-------------+-----------+-------+


## Health Endpoint Latency (10 requests per service)


### auth

req 1: HTTP 200 0.011168s
req 2: HTTP 200 0.007990s
req 3: HTTP 200 0.006848s
req 4: HTTP 200 0.008608s
req 5: HTTP 200 0.006833s
req 6: HTTP 200 0.007475s
req 7: HTTP 200 0.005603s
req 8: HTTP 200 0.007508s
req 9: HTTP 200 0.004906s
req 10: HTTP 200 0.008488s

- **Average (successful requests)**: 0.008s
- **Successful / total**: 10 / 10

### orders

req 1: HTTP 200 0.007053s
req 2: HTTP 200 0.007736s
req 3: HTTP 200 0.006478s
req 4: HTTP 200 0.005838s
req 5: HTTP 200 0.007190s
req 6: HTTP 200 0.005991s
req 7: HTTP 200 0.005994s
req 8: HTTP 200 0.005667s
req 9: HTTP 200 0.006196s
req 10: HTTP 200 0.005384s

- **Average (successful requests)**: 0.006s
- **Successful / total**: 10 / 10

## End-to-End Functional Test

Test user: `bench_1790637151`

- **Register latency**: 0.021765s (HTTP 201)
- **Login latency**: 0.014311s (HTTP 200)
- **Order creation latency**: 0.039007s (HTTP 201)
- **Order list latency**: 0.015492s (HTTP 200)

## ECS Task Startup Time


### auth

| DescribeTasks |
+------------------------------------+
| 2026-09-28T23:10:20.761000+00:00 |
| 2026-09-28T23:11:09.611000+00:00 |
| RUNNING |
| UNKNOWN |
+------------------------------------+


### orders

| DescribeTasks |
+------------------------------------+
| 2026-09-28T23:08:51.968000+00:00 |
| 2026-09-28T23:10:44.935000+00:00 |
| RUNNING |
| UNKNOWN |
+------------------------------------+


## Log Errors (last 1 hour)

- **auth ERROR events**: 0
- **orders ERROR events**: 0