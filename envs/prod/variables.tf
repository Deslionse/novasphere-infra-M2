variable "aws_region" {
  type        = string
  description = "Region AWS du deploiement"
  default     = "us-east-1"
}

variable "owner" {
  type        = string
  description = "Trigramme du proprietaire des ressources"
  default     = "enz"
}

variable "environment" {
  type        = string
  description = "Environnement cible dev ou prod"
  default     = "dev"
}

variable "instance_type" {
  type        = string
  description = "Type d instance EC2"
  default     = "t3.micro"
}

variable "ssh_public_key_path" {
  type        = string
  description = "Chemin vers la cle publique SSH"
  default     = "~/.ssh/id_ed25519.pub"
}
