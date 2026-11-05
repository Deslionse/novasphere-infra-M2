# Image Debian 12 officielle la plus recente
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

# IP publique du poste qui execute Terraform (pattern my_ip, acquis Bac+4)
data "http" "my_ip" {
  url = "https://api.ipify.org"
}

locals {
  my_cidr = "${chomp(data.http.my_ip.response_body)}/32"
  name    = "novasphere-${var.owner}"
}

resource "aws_key_pair" "main" {
  key_name   = "${local.name}-key"
  public_key = file(pathexpand(var.ssh_public_key_path))
}

module "web" {
  source                     = "./modules/ec2-server"
  name                       = "web"
  name_prefix                = local.name
  ami_id                     = data.aws_ami.debian.id
  instance_type              = var.instance_type
  key_name                   = aws_key_pair.main.key_name
  admin_cidr                 = local.my_cidr
  open_ports                 = [80]
  security_group_description = "SSH restreint a mon IP, HTTP ouvert"
}

module "monitoring" {
  source                     = "./modules/ec2-server"
  name                       = "monitoring"
  ami_id                     = data.aws_ami.debian.id
  instance_type              = var.instance_type
  key_name                   = aws_key_pair.main.key_name
  admin_cidr                 = local.my_cidr
  open_ports                 = []
  security_group_description = "Regles du serveur monitoring"

  ingress {
    description = "HTTP public"
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

resource "aws_instance" "web" {
  ami                    = data.aws_ami.debian.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.main.key_name
  vpc_security_group_ids = [aws_security_group.web.id]

  tags = {
    Name = "${local.name}-web"
    Role = "web"
  }
}

# Inventaire Ansible genere depuis les outputs : aucune IP recopiee a la main
resource "local_file" "inventory" {
  filename        = "${path.module}/../ansible/inventory.ini"
  file_permission = "0644"
  content = templatefile("${path.module}/inventory.tftpl", {
    web_ip = aws_instance.web.public_ip
  })
}
