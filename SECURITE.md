# Rapport d'Audit Sécurité - Séance S05 (Secrets & IAM)

## 1. Constat initial : Les lieux de fuite de secrets
Dans une chaîne d'automatisation Terraform / Ansible / Cloud classique, les secrets ont 4 vecteurs de fuite majeurs :

### A. Le Code source (Git)
- **Constat** : L'utilisation de variables Terraform avec des valeurs par défaut (`default = "secret123"`), des fichiers `*.tfvars` commités par erreur, ou des mots de passe en clair dans des playbooks Ansible permet de retrouver un secret instantanément via une simple commande `git grep` ou dans l'historique Git (`git log -p`).
- **Preuve** : `git grep -i -E 'password|secret'` montre actuellement que seuls les noms des secrets GitHub Actions sont référencés dans les workflows CI, mais aucune clé en dur ne doit être ajoutée.

### B. Le fichier d'état Terraform (State S3)
- **Constat** : Déclarer une variable avec `sensitive = true` masque uniquement la valeur dans la sortie de console du terminal (`<sensitive>`). En revanche, **la valeur reste stockée 100% en clair dans le fichier `.tfstate`** sur S3 ! Quiconque a accès au bucket de state (ou aux backups) peut lire le mot de passe en clair (`terraform state pull | grep ...`).

### C. Le User Data EC2
- **Constat** : Passer un mot de passe ou une clé d'API directement dans le script d'initialisation `user_data` (ou `bootstrap.sh`) le rend lisible par toute personne ou rôle IAM ayant le droit de lecture `ec2:DescribeInstanceAttribute` :
  ```bash
  aws ec2 describe-instance-attribute --instance-id <ID> --attribute userData --query UserData.Value --output text | base64 -d
  ```
  De plus, ces données sont souvent journalisées en clair dans `/var/log/cloud-init-output.log` sur la machine.

---

## 2. Décisions d'Architecture S05
Pour remédier à ces vulnérabilités :
1. **Stockage centralisé chiffré** : Utilisation d'**AWS Systems Manager (SSM) Parameter Store** de type `SecureString` (chiffré par clé AWS KMS).
2. **Arguments en écriture seule (`value_wo`) & variables éphémères (`ephemeral = true`)** :
   - Pourquoi `value_wo_version` est obligatoire avec `value_wo` : Terraform n'enregistrant pas la valeur du secret dans le state pour des raisons de sécurité, il a besoin d'un numéro de version entier (`value_wo_version = 1`) pour détecter quand la valeur doit être mise à jour ou pivotée (rotation du secret).
3. **Moindre Privilège IAM (Least Privilege)** :
   - L'instance EC2 reçoit un profil d'instance avec un rôle IAM autorisant `ssm:GetParameter` **uniquement sur son propre environnement** : `arn:aws:ssm:*:*:parameter/novasphere/${var.environment}/*`.
   - Tout accès vers `/novasphere/prod/*` depuis dev sera rejeté avec `AccessDeniedException`.
