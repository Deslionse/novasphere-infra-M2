# Contributing
Une branche est créée pour chaque changement.
Chaque changement passe par une pull request.
L'autre membre du binôme relit la pull request.
Le merge sur `main` intervient après cette relecture.
Un tag est créé par séance.
Le tag de cette séance est `v5.1.0`.
Avec `use_lockfile`, `dynamodb_table` n'est plus nécessaire pour le verrouillage S3.
Un fichier `*.tfstate`, `*.tfvars`, `*.pem` ou `.env` ne doit jamais être commité.
Avant de quitter la salle, exécuter `destroy` ou `stop-evening.sh`.
La pipeline Terraform valide et planifie les changements sur les pull requests.
Le déploiement est manuel depuis `terraform/ansible` via GitHub Actions.
