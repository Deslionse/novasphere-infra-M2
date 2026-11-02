# novasphere-infra

Depot de depart du module Bac+5 « Terraform et Automatisation du deploiement d'infrastructures dans le cloud ».
Il represente l'infrastructure NovaSphere en etat de fin de module Bac+4 : une instance EC2 Debian
provisionnee par Terraform, configuree par Ansible, avec un inventaire genere automatiquement.

## Prerequis

- Terraform >= 1.14, AWS CLI v2 configure (`aws sts get-caller-identity` repond), ansible-core 2.21 (Python 3.12+), Git
- Une paire de cles SSH : `ssh-keygen -t ed25519 -f ~/.ssh/novasphere -N ""`

## Demarrage

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # renseigner votre trigramme
terraform init
terraform apply
cd ../ansible
ansible-playbook site.yml
curl http://$(cd ../terraform && terraform output -raw web_public_ip)
```

## Fin de journee

```bash
./scripts/stop-evening.sh     # le lendemain : ./scripts/start-morning.sh
```

En fin de module : `terraform destroy` depuis `terraform/`.

## Structure

```
terraform/   versions.tf, variables.tf, main.tf, outputs.tf, inventory.tftpl
ansible/     site.yml, ansible.cfg, roles/web (tasks, handlers, templates, defaults)
scripts/     stop-evening.sh, start-morning.sh
```

Le fichier `ansible/inventory.ini` n'est pas versionne : il est produit par `terraform apply`.
