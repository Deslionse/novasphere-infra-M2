data "aws_ami" "debian" {
  most_recent = true
  owners      = ["136693071363"]

  filter {
    name   = "name"
    values = ["debian-12-amd64-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "http" "my_ip" {
  url = "https://api.ipify.org"
}


module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "novasphere-${var.environment}"
  cidr = "10.0.0.0/16"

  azs            = ["us-east-1a", "us-east-1b"]
  public_subnets = ["10.0.1.0/24", "10.0.2.0/24"]

  enable_nat_gateway      = false
  map_public_ip_on_launch = true
}

locals {
  my_cidr = "${chomp(data.http.my_ip.response_body)}/32"
  name    = "novasphere-${var.environment}-${var.owner}"
}

resource "aws_key_pair" "main" {
  key_name   = "${local.name}-key"
  public_key = file(pathexpand(var.ssh_public_key_path))
}

module "web" {
  source                     = "../../terraform/modules/ec2-server"
  name                       = "web"
  name_prefix                = local.name
  ami_id                     = data.aws_ami.debian.id
  instance_type              = var.instance_type
  key_name                   = aws_key_pair.main.key_name
  admin_cidr                 = local.my_cidr
  open_ports                 = [80]
  security_group_description = "SSH restreint a mon IP, HTTP ouvert dev"
}

module "monitoring" {
  source                     = "../../terraform/modules/ec2-server"
  name                       = "monitoring"
  name_prefix                = local.name
  ami_id                     = data.aws_ami.debian.id
  instance_type              = var.instance_type
  key_name                   = aws_key_pair.main.key_name
  admin_cidr                 = local.my_cidr
  open_ports                 = []
  enable_monitoring_port     = true
  security_group_description = "Regles du serveur monitoring dev"

  tags = {
    Role = "monitoring"
  }
}





resource "local_file" "inventory" {
  filename        = "${path.module}/../../ansible/inventory.ini"
  file_permission = "0644"

  content = templatefile("${path.module}/inventory.tftpl", {
    web_ip        = module.web.public_ip
    monitoring_ip = module.monitoring.public_ip
  })
}

# === S04 : SECURITE & LAUNCH TEMPLATE ===

resource "aws_security_group" "lb" {
  name        = "novasphere-${var.environment}-alb"
  description = "Autorise le trafic HTTP public vers l ALB"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "HTTP public"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Tout trafic sortant autorise"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "novasphere-${var.environment}-alb"
  }
}

resource "aws_security_group" "web" {
  name        = "novasphere-${var.environment}-web"
  description = "Autorise le port 80 depuis l ALB uniquement"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description     = "HTTP depuis l ALB uniquement"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.lb.id]
  }

  egress {
    description = "Tout trafic sortant autorise"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "novasphere-${var.environment}-web"
  }
}

resource "aws_launch_template" "web" {
  name_prefix   = "novasphere-${var.environment}-"
  image_id      = data.aws_ami.debian.id
  instance_type = var.instance_type
  key_name      = aws_key_pair.main.key_name

  vpc_security_group_ids = [aws_security_group.web.id]

  iam_instance_profile {
    name = var.instance_profile_name
  }
  user_data = base64encode(file("${path.module}/bootstrap.sh"))

  metadata_options {
    http_tokens                 = "required"
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 1
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      encrypted   = true
      volume_size = 20
      volume_type = "gp3"
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "novasphere-${var.environment}-web"
    }
  }
}

# === S04 ETAPE 3 : ALB, TARGET GROUP, LISTENER & ASG ===

resource "aws_lb" "web" {
  #checkov:skip=CKV2_AWS_20:Environnement de lab etudiant sans nom de domaine ni certificat ACM
  #checkov:skip=CKV2_AWS_28:WAF non active en lab pour maitrise des couts
  name               = "novasphere-${var.environment}"
  internal           = false
  load_balancer_type = "application"
  subnets            = module.vpc.public_subnets
  security_groups    = [aws_security_group.lb.id]
  idle_timeout       = 120

  tags = {
    Name = "novasphere-${var.environment}-alb"
  }
}

resource "aws_lb_target_group" "web" {
  name     = "novasphere-${var.environment}-web"
  port     = 80
  protocol = "HTTP"
  vpc_id   = module.vpc.vpc_id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = {
    Name = "novasphere-${var.environment}-tg"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.web.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}

resource "aws_autoscaling_group" "web" {
  depends_on          = [aws_ssm_parameter.db_password]
  name                = "novasphere-${var.environment}-web"
  min_size            = 2
  max_size            = 4
  desired_capacity    = 2
  vpc_zone_identifier = module.vpc.public_subnets
  target_group_arns   = [aws_lb_target_group.web.arn]
  health_check_type   = "ELB"

  launch_template {
    id      = aws_launch_template.web.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "novasphere-${var.environment}-asg-web"
    propagate_at_launch = true
  }

  tag {
    key                 = "Environment"
    value               = var.environment
    propagate_at_launch = true
  }
}

output "alb_dns_name" {
  description = "DNS public de l Application Load Balancer"
  value       = aws_lb.web.dns_name
}
