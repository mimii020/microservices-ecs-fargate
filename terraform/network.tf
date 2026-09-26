#vpc
resource "aws_vpc" "microservices-ecs-vpc" {
  cidr_block       = var.vpc_cidr
  instance_tenancy = "default"
  enable_dns_hostnames = true
  enable_dns_support = true

  tags = {
    Name = "microservices-ecs-vpc"
  }
}

resource "aws_subnet" "microservices-ecs-public-subnets" {
  vpc_id     = aws_vpc.microservices-ecs-vpc.id
  for_each = local.azs
  availability_zone = each.key
  cidr_block = cidrsubnet(var.vpc_cidr, 8, each.value * 2)
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project}-public-${each.key}"
  }
}

resource "aws_subnet" "microservices-ecs-private-subnets" {
  vpc_id     = aws_vpc.microservices-ecs-vpc.id
  for_each   = local.azs
  availability_zone = each.key
  cidr_block = cidrsubnet(var.vpc_cidr, 8, each.value * 2 + 1)

  tags = {
    Name = "${var.project}-private-${each.key}"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.microservices-ecs-vpc.id
  tags = {
    Name = "igw"
  }
}

resource "aws_route_table" "public-route-table" {
  vpc_id = aws_vpc.microservices-ecs-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "${var.project}-public-route-table"
  }
}

resource "aws_route_table" "private-route-table" {
  vpc_id = aws_vpc.microservices-ecs-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gateway.id
  }

  tags = {
    Name = "${var.project}-private-route-table"
  }
}

resource "aws_route_table_association" "public-route-table-association" {
  route_table_id = aws_route_table.public-route-table.id
  for_each = aws_subnet.microservices-ecs-public-subnets

  subnet_id = each.value.id
}

resource "aws_eip" "eip-nat" {
  domain = "vpc"

  tags = {
    Name = "${var.project}-nat-eip"
  }
}

resource "aws_nat_gateway" "nat_gateway" {
  allocation_id = aws_eip.eip-nat.id
  subnet_id = aws_subnet.microservices-ecs-public-subnets[local.az_names[0]].id

  tags = {
    Name = "gw NAT"
  }

  depends_on = [aws_internet_gateway.igw]
}

resource "aws_route_table_association" "private_route_table_association" {
  route_table_id = aws_route_table.private-route-table.id
  for_each = aws_subnet.microservices-ecs-private-subnets

  subnet_id = each.value.id
}

resource "aws_security_group" "alb_sg" {
  vpc_id = aws_vpc.microservices-ecs-vpc.id
  name        = "${var.project}-alb-sg"
  description = "Allow HTTP/HTTPS from the internet to the ALB and from the ALB to the ECS tasks"
  tags = {
    Name = "${var.project}-alb-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "allow_http" {
  security_group_id = aws_security_group.alb_sg.id
  cidr_ipv4 = "0.0.0.0/0"
  from_port = 80
  ip_protocol = "tcp"
  to_port = 80
}

resource "aws_vpc_security_group_egress_rule" "allow_auth_task" {
  security_group_id = aws_security_group.alb_sg.id
  referenced_security_group_id = aws_security_group.auth_orders_task_sgs["auth"].id
  from_port = 5000
  ip_protocol = "tcp"
  to_port = 5000
}

resource "aws_vpc_security_group_egress_rule" "allow_orders_task" {
  security_group_id = aws_security_group.alb_sg.id
  referenced_security_group_id = aws_security_group.auth_orders_task_sgs["orders"].id
  from_port = 5001
  ip_protocol = "tcp"
  to_port = 5001
}

resource "aws_vpc_security_group_ingress_rule" "allow_alb_sg_to_auth" {
  security_group_id = aws_security_group.auth_orders_task_sgs["auth"].id
  referenced_security_group_id = aws_security_group.alb_sg.id
  ip_protocol = "tcp"
  from_port = 5000
  to_port = 5000
}

resource "aws_vpc_security_group_ingress_rule" "allow_orders_to_auth" {
  security_group_id = aws_security_group.auth_orders_task_sgs["auth"].id
  referenced_security_group_id = aws_security_group.auth_orders_task_sgs["orders"].id
  ip_protocol = "tcp"
  from_port = 5000
  to_port = 5000
}

resource "aws_security_group" "auth_orders_task_sgs" {
  vpc_id = aws_vpc.microservices-ecs-vpc.id
  for_each = var.services
  name = "${var.project}-${each.key}-task-sg"
  description = "Allow inbound traffic from ALB sg"
  tags = {
    Name = "${var.project}-${each.key}-task-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "allow_alb_sg_to_orders" {
  security_group_id = aws_security_group.auth_orders_task_sgs["orders"].id
  referenced_security_group_id = aws_security_group.alb_sg.id
  ip_protocol = "tcp"
  from_port = 5001
  to_port = 5001
}

resource "aws_vpc_security_group_egress_rule" "allow_orders_to_auth" {
  security_group_id = aws_security_group.auth_orders_task_sgs["orders"].id
  referenced_security_group_id = aws_security_group.auth_orders_task_sgs["auth"].id
  ip_protocol = "tcp"
  from_port = 5000
  to_port = 5000
}

resource "aws_vpc_security_group_egress_rule" "tasks_to_db" {
  for_each = var.services
  security_group_id            = aws_security_group.auth_orders_task_sgs[each.key].id
  referenced_security_group_id = aws_security_group.rds-sg.id
  from_port                    = 5432
  ip_protocol                  = "tcp"
  to_port                      = 5432
}