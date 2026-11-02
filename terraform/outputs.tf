output "web_public_ip" {
  description = "IP publique de l'instance web"
  value       = aws_instance.web.public_ip
}

output "web_instance_id" {
  description = "Identifiant de l'instance (utilise par les scripts stop/start)"
  value       = aws_instance.web.id
}

output "ssh_command" {
  description = "Commande de connexion"
  value       = "ssh -i ~/.ssh/novasphere admin@${aws_instance.web.public_ip}"
}
