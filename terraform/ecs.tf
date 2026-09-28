resource "aws_ecs_task_definition" "auth-orders-tasks" {
  for_each = var.services
  family = "${each.key}-service"
  network_mode = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu = 256
  memory = 512
  execution_role_arn = aws_iam_role.ecs_task_execution.arn
  depends_on = [aws_secretsmanager_secret_version.db_secret_version]
  tags = {
    Name = "${var.project}-${each.key}-task"
  }
  container_definitions = jsonencode([
    {
      name      = "${each.key}-service"
      image     = "${local.ecr_registry_path}/${each.key}-service:latest"
      essential = true
      secrets = [
        { name = "DB_USERNAME", valueFrom = "${aws_secretsmanager_secret.db_secret.arn}:username::" },
        { name = "DB_PASSWORD", valueFrom = "${aws_secretsmanager_secret.db_secret.arn}:password::" },
        { name = "DB_HOST",     valueFrom = "${aws_secretsmanager_secret.db_secret.arn}:host::" },
        { name = "DB_PORT",     valueFrom = "${aws_secretsmanager_secret.db_secret.arn}:port::" },
        { name = "DB_NAME",     valueFrom = "${aws_secretsmanager_secret.db_secret.arn}:db_name::" },
      ]
      portMappings = [
        {
          containerPort = each.value.port
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.auth_orders_log_group[each.key].name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" =  "${var.project}/${each.key}-service"
        }
      }
    }
  ])
}

resource "aws_ecs_cluster" "ecs-cluster" {
  name = var.project
}

resource "aws_ecs_service" "auth-orders-services" {
  for_each = var.services
  name = each.key
  cluster = aws_ecs_cluster.ecs-cluster.id
  task_definition = aws_ecs_task_definition.auth-orders-tasks[each.key].arn
  desired_count = 1
  launch_type = "FARGATE"

  service_registries {
    registry_arn = aws_service_discovery_service.services[each.key].arn
  }

  depends_on = [
    aws_lb_listener_rule.services_rules,
    aws_secretsmanager_secret_version.db_secret_version,
  ]

  deployment_controller {
    type = "CODE_DEPLOY"
  }

  lifecycle {
    ignore_changes = [task_definition, load_balancer, desired_count]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.tgs[each.key].arn
    container_name   = "${each.key}-service"
    container_port   = each.value.port
  }

  network_configuration {
    assign_public_ip = false
    security_groups = [aws_security_group.auth_orders_task_sgs[each.key].id]
    subnets = [for subnet in values(aws_subnet.microservices-ecs-private-subnets) : subnet.id]
  }
}