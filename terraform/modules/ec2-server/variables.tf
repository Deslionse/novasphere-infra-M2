variable "name" {
  description = "Nom logique du serveur"
  type        = string
}

variable "name_prefix" {
  description = "Prefixe du nom des ressources"
  type        = string
  default     = "novasphere"
}

variable "security_group_description" {
  description = "Description du Security Group"
  type        = string
  default     = "Regles du serveur"
}

variable "ami_id" {
  type = string
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "key_name" {
  type = string
}

variable "admin_cidr" {
  description = "CIDR autorise en SSH"
  type        = string

  validation {
    condition     = var.admin_cidr != "0.0.0.0/0" && can(cidrhost(var.admin_cidr, 0))
    error_message = "admin_cidr doit etre un CIDR valide et ne peut pas etre 0.0.0.0/0."
  }
}

variable "open_ports" {
  description = "Ports TCP ouverts a tout Internet"
  type        = list(number)
  default     = []
}

variable "enable_monitoring_port" {
  description = "Ouvre le port 9100 (Node Exporter) uniquement pour le CIDR admin"
  type        = bool
  default     = false
}

variable "tags" {
  type    = map(string)
  default = {}
}
