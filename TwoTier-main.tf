#Version 
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = "us-west-2"
}

# Create a VPC
resource "aws_vpc" "golden_vpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "golden_vpc"
  }
}

# Create Public Subnet 1
resource "aws_subnet" "pub_sub_1" {
  vpc_id            = "aws_vpc.golden_vpc.id"
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-west-2a"

  tags = {
    Name = "Public_Subnet_1"
  }
}

# Create Public Subnet 2
resource "aws_subnet" "pub_sub_2" {
  vpc_id            = "aws_vpc.golden_vpc.id"
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-west-2b"

  tags = {
    Name = "Public_Subnet_2"
  }
}

# Create Private Subnets
resource "aws_subnet" "priv_sub_1" {
  vpc_id            = "aws_vpc.golden_vpc.id"
  cidr_block        = "10.0.3.0/24"
  availability_zone = "us-west-2a"

  tags = {
    Name = "Private_Subnet_1"
  }
}

resource "aws_subnet" "priv_sub_2" {
  vpc_id            = "aws_vpc.golden_vpc.id"
  cidr_block        = "10.0.4.0/24"
  availability_zone = "us-west-2b"

  tags = {
    Name = "Private_Subnet_2"
  }
}

# Create Internet Gateway
resource "aws_internet_gateway" "IGW" {
  vpc_id = "aws_vpc.golden_vpc.id"

  tags = {
    name = "IGW"
  }
}

#Create Route Table for Public Subnets
resource "aws_route_table" "main_rt" {
  vpc_id = "aws_vpc.golden_vpc.id"
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "aws_internet_gateway.IGW.id"
  }

  tags = {
    name = "main_rt"
  }
}

#Route Table Associations for public Subnets
resource "aws_route_table_association" "pub_rt_1" {
  subnet_id      = "aws_subnet.pub_sub_1.id"
  route_table_id = "aws_route_table.main_rt.id"
}

resource "aws_route_table_association" "pub_rt_2" {
  subnet_id      = "aws_subnet.pub_sub_2.id"
  route_table_id = "aws_route_table.main_rt.id"
}

# Create security groups
resource "aws_security_group" "pub_sg" {
  name        = "pub_sg"
  description = "Allow web and ssh traffic"
  vpc_id      = "aws_vpc.golden_vpc.id"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
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
  tags = {
    Name = "pub_sg"
  }
}

resource "aws_security_group" "priv_sg" {
  name        = "priv_sg"
  description = "Allow web tier and ssh traffic"
  vpc_id      = "aws_vpc.golden_vpc.id"

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    cidr_blocks     = ["10.0.0.0/16"]
    security_groups = [aws_security_group.pub_sg.id]
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
  tags = {
    Name = "priv_sg"
  }
}

# Security group for Application Load Balancer
resource "aws_security_group" "alb_sg" {
  name        = "alb_sg"
  description = "security group for alb"
  vpc_id      = "aws_vpc.golden_vpc.id"

  ingress {
    from_port   = "0"
    to_port     = "0"
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = "0"
    to_port     = "0"
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Create Application Load Balancer
resource "aws_lb" "project_alb" {
  name               = "alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [aws_subnet.pub_sub_1.id, aws_subnet.pub_sub_2.id]
}

# Create Application Load Balancer target group
resource "aws_lb_target_group" "golden_tg" {
  name     = "golden-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = "aws_vpc.golden_vpc.id"

  health_check {
    interval            = 70
    path                = "/"
    port                = 80
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 60
    protocol            = "HTTP"
    matcher             = "200,202"
  }
}


#Create Application Load Balancer Target Group Attachments
resource "aws_lb_target_group_attachment" "tg_attach1" {
  target_group_arn = aws_lb_target_group.golden_tg.arn
  target_id        = aws_instance.web_1.id
  port             = 80

  depends_on = [aws_instance.web_1]
}

resource "aws_lb_target_group_attachment" "tg_attach2" {
  target_group_arn = aws_lb_target_group.golden_tg.arn
  target_id        = aws_instance.web_2.id
  port             = 80

  depends_on = [aws_instance.web_2]
}

#Create EC2 Instances for Public Subnets
resource "aws_instance" "web_1" {
  ami                         = "ami-094125af156557ca2"
  instance_type               = "t2.micro"
  key_name                    = "nginx-server"
  availability_zone           = "us-west-2a"
  vpc_security_group_ids      = [aws_security_group.pub_sg.id]
  subnet_id                   = aws_subnet.pub_sub_1.id
  associate_public_ip_address = true
  user_data                   = <<-EOF
        #!/bin/bash
        yum update -y
        yum install httpd -y
        systemctl start 
        systemctl enable
        echo '<h1>Welcome to Week 20. Level up Gold Team.</h1>' > /usr/share/nginx/html/index.html
        EOF

  tags = {
    Name = "web_1"
  }
}

resource "aws_instance" "web_2" {
  ami                         = "ami-094125af156557ca2"
  instance_type               = "t2.micro"
  key_name                    = "nginx-server"
  availability_zone           = "us-west-2b"
  vpc_security_group_ids      = [aws_security_group.pub_sg.id]
  subnet_id                   = aws_subnet.pub_sub_2.id
  associate_public_ip_address = true
  user_data                   = <<-EOF
        #!/bin/bash
        yum update -y
        yum install httpd -y
        systemctl start 
        systemctl enable
        echo '<h1>Welcome to Week 20. Level up Gold Team.</h1>' > /usr/share/nginx/html/index.html
        EOF

  tags = {
    Name = "web_2"
  }
}

#Create Database subnet group
resource "aws_db_subnet_group" "default" {
  name       = "db_subnetgroup"
  subnet_ids = [aws_subnet.priv_sub_1.id, aws_subnet.priv_sub_2.id]
}

#Create database instance 
resource "aws_db_instance" "golden_db" {
  allocated_storage           = 5
  storage_type                = "gp2"
  engine                      = "mysql"
  engine_version              = "5.7"
  instance_class              = "db.t2.micro"
  identifier                  = "db-instance"
  db_name                     = "golden_db"
  username                    = "admin"
  password                    = "P4$$w0rd"
  db_subnet_group_name        = "db_subnetgroup"
  allow_major_version_upgrade = true
  auto_minor_version_upgrade  = true
  backup_retention_period     = 35
  backup_window               = "22:00-23:00"
  maintenance_window          = "Sat:00:00-Sat:03:00"
  multi_az                    = true
  vpc_security_group_ids      = [aws_security_group.priv_sg.id]
  publicly_accessible         = false
  skip_final_snapshot         = true
}