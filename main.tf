provider "aws" {
  region = "ap-southeast-1" # Adjust to match the region of your availability zones
}

# VPC
resource "aws_vpc" "terravpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "terravpc"
  }
}

# Subnets
resource "aws_subnet" "public_subnet" {
  count                   = length(var.vpc_az)
  vpc_id                  = aws_vpc.terravpc.id
  cidr_block              = cidrsubnet(aws_vpc.terravpc.cidr_block, 8, count.index)
  map_public_ip_on_launch = true
  availability_zone       = element(var.vpc_az, count.index)
}

# Internet Gateway
resource "aws_internet_gateway" "terra_igw" {
  vpc_id = aws_vpc.terravpc.id
}

# Route Table for Public Subnets
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.terravpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.terra_igw.id
  }
}

resource "aws_route_table_association" "public_association" {
  count          = length(var.vpc_az)
  subnet_id      = element(aws_subnet.public_subnet[*].id, count.index)
  route_table_id = aws_route_table.public.id
}

# Security Group for ALB and EC2
resource "aws_security_group" "terra_alb_sg" {
  name   = "terra-alb-sg"
  vpc_id = aws_vpc.terravpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "terra_ec2_sg" {
  name   = "terra-ec2-sg"
  vpc_id = aws_vpc.terravpc.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.terra_alb_sg.id]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Application Load Balancer (ALB)
resource "aws_lb" "terra_alb" {
  name               = "terra-alb"
  load_balancer_type = "application"
  security_groups    = [aws_security_group.terra_alb_sg.id]
  subnets            = aws_subnet.public_subnet[*].id
}

# Target Group
resource "aws_lb_target_group" "terra_tg" {
  name     = "terra-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.terravpc.id

  health_check {
    path                = "/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

# ALB Listener
resource "aws_lb_listener" "http_listener" {
  load_balancer_arn = aws_lb.terra_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.terra_tg.arn
  }
}

# Launch Template
resource "aws_launch_template" "terra_lt" {
  name          = "terra-lt"
  image_id      = "ami-01811d4912b4ccb26" # Ubuntu 20.04 LTS AMI (us-east-1)
  instance_type = "t2.micro"
  key_name      = "llr-keypair"
  user_data     = filebase64("userdata.sh")

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.terra_ec2_sg.id]
  }

  #   tags = {
  #     ScheduleShutdown = "true"
  #   }
}

# Auto Scaling Group (ASG)
resource "aws_autoscaling_group" "terra_asg" {
  name                = "terra-asg"
  max_size            = 3
  desired_capacity    = 2
  min_size            = 2
  vpc_zone_identifier = aws_subnet.public_subnet[*].id
  target_group_arns   = [aws_lb_target_group.terra_tg.arn]
  launch_template {
    id      = aws_launch_template.terra_lt.id
    version = "$Latest"
  }

  health_check_type         = "ELB"
  health_check_grace_period = 300

  tag {
    key                 = "Name"
    value               = "terra-web-server"
    propagate_at_launch = true
  }
}

# Output the ALB DNS name
output "alb_dns_name" {
  value = aws_lb.terra_alb.dns_name
}
