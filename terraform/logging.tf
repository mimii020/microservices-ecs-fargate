resource "aws_cloudwatch_log_group" "auth_orders_log_group" {
  for_each = var.services
  name = "/ecs/${var.project}/${each.key}-service"
  retention_in_days = 7

  tags = {
    Environment = "dev"
    Application = each.key
  }
}