variable "db_password" {
  description = "Mot de passe applicatif fourni par variable d environnement TF_VAR_db_password"
  type        = string
  ephemeral   = true
}

resource "aws_ssm_parameter" "db_password" {
  name             = "/novasphere/${var.environment}/db_password"
  description      = "Mot de passe base de donnees NovaSphere"
  type             = "SecureString"
  value_wo         = var.db_password
  value_wo_version = 1

  tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}
