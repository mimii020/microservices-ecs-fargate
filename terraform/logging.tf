resource "random_id" "log_suffix" {
  byte_length = 4
}

resource "aws_cloudwatch_log_group" "auth_orders_log_group" {
  for_each = var.services
  name     = "/ecs/${var.project}/${each.key}-service-${random_id.log_suffix.hex}"

  tags = {
    Environment = "dev"
    Application = each.key
  }
}