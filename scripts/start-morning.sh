#!/usr/bin/env bash
# Redemarre l'instance web et regenere l'inventaire (l'IP publique change au redemarrage).
set -euo pipefail
cd "$(dirname "$0")/../terraform"
ID=$(terraform output -raw web_instance_id)
aws ec2 start-instances --instance-ids "$ID" > /dev/null
aws ec2 wait instance-running --instance-ids "$ID"
terraform apply -refresh-only -auto-approve > /dev/null
terraform apply -auto-approve -target=local_file.inventory > /dev/null
echo "Instance $ID demarree. Nouvelle IP : $(terraform output -raw web_public_ip)"
