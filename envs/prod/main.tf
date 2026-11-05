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

locals {
  my_cidr = var.admin_cidr != "" ? var.admin_cidr : "${chomp(data.http.my_ip.response_body)}/32"
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

moved {
  from = aws_instance.web
  to   = module.web.aws_instance.this
}

moved {
  from = aws_security_group.web
  to   = module.web.aws_security_group.this
}

resource "local_file" "inventory" {
  count           = var.generate_inventory ? 1 : 0
  filename        = "${path.module}/../../ansible/inventory-${var.environment}.ini"
  file_permission = "0644"

  content = templatefile("${path.module}/inventory.tftpl", {
    web_ip        = module.web.public_ip
    monitoring_ip = module.monitoring.public_ip
  })
}

moved {
  from = local_file.inventory
  to   = local_file.inventory[0]
}
