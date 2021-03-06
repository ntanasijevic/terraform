provider "aws" {
  region = "us-east-1"
}

variable "server_port" {
  description   = "The port the server will use for HTTP requests"
  type          = number
  default       = 8080
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnet_ids" "default" {
  vpc_id = data.aws_vpc.default.id
}

resource "aws_key_pair" "terraform_key" {
  key_name = "terraform-key"
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDjWlJJQU3a67GSFJ25CmbbYhpXUZpr3a7ZeiQyu0E6+A0nOmlqA65HvFkmEqMW9tSIU+o7TpsI2drmzXMAuvZZKjm6FkJ8Tp68b5yXvSpeVXYpwFz7lo5peYYSrMWZs2q7nz4IB7QHJFz9etwEUUCKLBAk8s7qKUAFU6GtC3eJ3FrBMIvLpQQ1k37vCav1KUN8cPHv4gSw2HrB+0Dm7zSapU0JDueYue68suJPlHgLuqGc31RZ9hx57LN6jeaoIWOlhiUjy62RJQxDoxhrFzP1gg4zYSa0/OEDLiRI6ztuX3j8gjER8QftcTIV8nu5J9+LQOtbr+HjPhJ2bLhLu3x9 root@nta-centos7-primary"
}

resource "aws_lb" "example" {
  name                  = "terraform-asg-example"
  load_balancer_type    = "application"
  subnets               = data.aws_subnet_ids.default.ids
  security_groups       = [aws_security_group.alb.id]
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.example.arn
  port              = 80
  protocol          = "HTTP"

  # By default, return a simple 404 page
  default_action {
    type = "fixed-response"
  
    fixed_response {
      content_type = "text/plain"
      message_body = "404: page not found"
      status_code  = 404
    }
  }
}

resource "aws_security_group" "alb" {
  name = "terraform-example-alb"

  # Allow inbound HTTP requests
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound requests
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_lb_target_group" "asg" {
  name      = "terraform-asg-example"
  port      = var.server_port
  protocol  = "HTTP"
  vpc_id    = data.aws_vpc.default.id

  health_check {
    path        = "/"
    protocol    = "HTTP"
    matcher     = "200"
    interval    = 15
    timeout     = 3
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_launch_configuration" "example" {
  # Created private image with Ubuntu and Hello, World index file
  image_id      = "ami-07ebfd5b3428b6f4d"
  instance_type = "t2.micro"
  security_groups    = [aws_security_group.instance-www.id, aws_security_group.instance-ssh.id]
  key_name           = "terraform-key"

  user_data = <<-EOF
            #!/bin/bash
            echo "Hello, World!" > index.html
            nohup busybox httpd -f -p ${var.server_port} &
            EOF

  lifecycle {
    create_before_destroy   = true
  }
}

resource "aws_autoscaling_group" "example" {
  launch_configuration  = aws_launch_configuration.example.name
  vpc_zone_identifier   = data.aws_subnet_ids.default.ids

  target_group_arns = [aws_lb_target_group.asg.arn]
  health_check_type = "ELB"

  min_size  = 2
  max_size  = 2

  tag {
    key                 = "Name"
    value               = "terraform-asg-example"
    propagate_at_launch = true
  }
}

resource "aws_security_group" "instance-www" {
  name = "terraform-example-instance-www"

  ingress {
    from_port   = var.server_port
    to_port     = var.server_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "instance-ssh" {
  name = "terraform-example-instance-ssh"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


resource "aws_lb_listener_rule" "asg" {
  listener_arn  = aws_lb_listener.http.arn
  priority      = 100

  condition {
    field   = "path-pattern"
    values  = ["*"]
  }
  action {
    type                = "forward"
    target_group_arn    = aws_lb_target_group.asg.arn
  }
}

output "alb_dns_name" {
  value         = aws_lb.example.dns_name
  description   = "The domain name of the load balancer"
}


