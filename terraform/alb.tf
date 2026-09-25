resource "aws_lb" "alb" {
  name               = "${var.project}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [for subnet in values(aws_subnet.microservices-ecs-public-subnets) : subnet.id]

  tags = {
    Name        = "${var.project}-alb"
  }
}

resource "aws_lb_target_group" "tgs" {
  for_each = var.services
  name     = "alb-${each.key}-tg"
  target_type = "ip"
  port     = each.value.port
  protocol = "HTTP"
  vpc_id   = aws_vpc.microservices-ecs-vpc.id
  deregistration_delay = 30

  health_check {
    path = "/health"
  }

  tags = {
    Name = "${var.project}-${each.key}-tg"
  }
}

resource "aws_lb_listener" "alb-listener" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "404: Not Found"
      status_code  = "404"
    }
  }
}

resource "aws_lb_listener_rule" "service" {
  for_each     = var.services
  listener_arn = aws_lb_listener.http.arn

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tgs[each.key].arn
  }

  condition {
    path_pattern {
      values = ["/${each.key}/*"]
    }
  }
}