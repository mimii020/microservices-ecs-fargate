resource "aws_db_subnet_group" "db_subnet_group" {
  name       = "db-subnet-group"
  subnet_ids = [for subnet in values(aws_subnet.microservices-ecs-private-subnets) : subnet.id]

  tags = {
    Name = "${var.project}-db-group"
  }
}

resource "aws_security_group" "rds_sg" {
    vpc_id = aws_vpc.microservices-ecs-vpc.id
    name = "${var.project}-rds-sg"
}

resource "aws_vpc_security_group_ingress_rule" "allow_auth_orders_to_rds" {
  security_group_id = aws_security_group.rds_sg.id
  for_each = var.services
  referenced_security_group_id = aws_security_group.auth_orders_task_sgs[each.key].id  
  from_port = 5432
  ip_protocol = "tcp"
  to_port = 5432
}

resource "random_password" "password" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_secretsmanager_secret" "db_secret" {
  name = "${var.project}-db-secret"
}

resource "aws_db_instance" "auth_orders_db" {
  allocated_storage    = 20
  engine               = "postgres"
  instance_class       = "db.t3.micro" 
  identifier           = "auth-orders-db"
  db_name              = "auth_orders_db"
  username             = local.db_username
  password = random_password.password.result  
  db_subnet_group_name = aws_db_subnet_group.db_subnet_group.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]

  tags = {
    Name = "auth-orders-db"
  }
}

resource "aws_secretsmanager_secret_version" "db_secret_version" {
  secret_id = aws_secretsmanager_secret.db_secret.id
  secret_string = jsonencode({
    username = local.db_username
    password = random_password.password.result
    db_name = "auth_orders_db"
    host = aws_db_instance.auth_orders_db.address
    port = 5432
  })
}

resource "aws_elasticache_subnet_group" "redis_cache" {
  name       = "redis-cache-subnet"
  subnet_ids = [for subnet in values(aws_subnet.microservices-ecs-private-subnets) : subnet.id]
}

resource "aws_security_group" "redis_sg" {
    vpc_id = aws_vpc.microservices-ecs-vpc.id
    name = "${var.project}-redis-sg"
}

resource "aws_vpc_security_group_ingress_rule" "allow_auth_to_redis" {
  security_group_id = aws_security_group.redis_sg.id
  referenced_security_group_id = aws_security_group.auth_orders_task_sgs["auth"].id  
  from_port = 6379
  ip_protocol = "tcp"
  to_port = 6379
}

resource "aws_elasticache_cluster" "elasticcache_cluster" {
  cluster_id           = "elasticcache-cluster"
  engine               = "redis"
  node_type            = "cache.t4g.micro"
  num_cache_nodes      = 1
  parameter_group_name = "default.redis7.1"
  engine_version       = "7.1"
  port                 = 6379
  subnet_group_name = aws_elasticache_subnet_group.redis_cache.name
  security_group_ids = [aws_security_group.redis_sg.id]
}