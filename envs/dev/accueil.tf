resource "aws_ssm_parameter" "message_accueil" {
  name  = "/novasphere/${var.environment}/message_accueil"
  type  = "String"
  value = "Bienvenue sur NovaSphere"
}
