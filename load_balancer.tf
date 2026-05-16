resource "aws_lb" "this" {
  name               = substr("${local.name_prefix}-alb", 0, 32)
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  tags = {
    Name = "${local.name_prefix}-alb"
  }
}

resource "aws_lb_target_group" "web" {
  name_prefix = "web-"
  port        = local.backend_port
  protocol    = local.backend_proto
  vpc_id      = aws_vpc.this.id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200-399"
    path                = var.health_check_path
    protocol            = local.backend_proto
    timeout             = 5
    unhealthy_threshold = 2
  }

  tags = {
    Name = "${local.name_prefix}-tg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = local.create_https ? "redirect" : "forward"

    dynamic "redirect" {
      for_each = local.create_https ? [1] : []

      content {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }

    dynamic "forward" {
      for_each = local.create_https ? [] : [1]

      content {
        target_group {
          arn = aws_lb_target_group.web.arn
        }
      }
    }
  }
}

resource "aws_lb_listener" "https" {
  count = local.create_https ? 1 : 0

  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate_validation.web[0].certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}
