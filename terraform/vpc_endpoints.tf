resource "aws_security_group" "vpc_endpoints_sg" {
  vpc_id = aws_vpc.microservices-ecs-vpc.id
  name   = "${var.project}-vpce-sg"

  tags = {
    Name = "${var.project}-vpce-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "allow_tasks_to_vpce" {
  for_each                      = var.services
  security_group_id             = aws_security_group.vpc_endpoints_sg.id
  referenced_security_group_id  = aws_security_group.auth_orders_task_sgs[each.key].id
  from_port                     = 443
  ip_protocol                   = "tcp"
  to_port                       = 443
}

resource "aws_vpc_security_group_egress_rule" "allow_tasks_to_vpce" {
  for_each                      = var.services
  security_group_id             = aws_security_group.auth_orders_task_sgs[each.key].id
  referenced_security_group_id  = aws_security_group.vpc_endpoints_sg.id
  from_port                     = 443
  ip_protocol                   = "tcp"
  to_port                       = 443
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.microservices-ecs-vpc.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private-route-table.id]

  tags = {
    Name = "${var.project}-s3-endpoint"
  }
}



resource "aws_vpc_endpoint" "interface" {
  for_each            = local.interface_endpoints
  vpc_id              = aws_vpc.microservices-ecs-vpc.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.${each.value}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [for subnet in values(aws_subnet.microservices-ecs-private-subnets) : subnet.id]
  security_group_ids  = [aws_security_group.vpc_endpoints_sg.id]
  private_dns_enabled = true

  tags = {
    Name = "${var.project}-${each.key}-endpoint"
  }
}