resource "aws_service_discovery_private_dns_namespace" "internal" {
  name        = "internal.${var.project}.local"
  description = "Private DNS namespace for service-to-service discovery"
  vpc         = aws_vpc.microservices-ecs-vpc.id
}

resource "aws_service_discovery_service" "services" {
  for_each = var.services
  name     = each.key

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.internal.id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 1
  }
}