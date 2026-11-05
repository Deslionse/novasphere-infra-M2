# Rapport d'Audit et Sécurisation - Séance S05 (Secrets & IAM)

## 1. Preuves de fuite constatées
Dans une chaîne d'automatisation Terraform / Ansible / Cloud classique, les secrets ont 3 vecteurs de fuite majeurs :

### A. Le Code source (Git)
- **Constat** : L'utilisation de variables Terraform avec des valeurs par défaut (`default = "..."`), des fichiers `*.tfvars` commités par inadvertance, ou des secrets en clair dans des playbooks Ansible permet de retrouver un secret instantanément via `git grep` ou dans l'historique (`git log -p`).
- **Preuve / Vérification** :
  ```bash
  git grep -i -E 'password|secret'
  ```
  Sur notre dépôt, aucun secret en dur n'est présent dans le code source. Les variables sensibles sont injectées dynamiquement via l'environnement local (`TF_VAR_db_password`).

### B. Le fichier d'état Terraform (State S3)
- **Constat** : Déclarer une variable avec `sensitive = true` masque uniquement la valeur dans la sortie console du terminal (`<sensitive>`). En revanche, **la valeur reste stockée 100% en clair dans le fichier `.tfstate`** sur S3 ! Quiconque dispose des droits de lecture sur le bucket S3 de state peut extraire le secret en clair.
- **Preuve / Vérification avec variable classique** :
  ```bash
  terraform state pull | grep -c "Enzo2105"
  # Retourne 1 si l'attribut standard 'value' est utilisé -> Fuite avérée dans le state !
  ```
- **Remédiation avec `value_wo`** :
  En utilisant `value_wo` (Write-Only) et `variable "db_password" { ephemeral = true }`, le résultat est garanti à zéro fuite :
  ```bash
  terraform state pull | grep -c "Enzo2105"
  # Retourne 0 -> Le secret n'est jamais écrit dans le tfstate S3 !
  ```

### C. Le User Data EC2
- **Constat** : Passer un mot de passe ou une clé d'API directement dans le script d'initialisation `user_data` (ou `bootstrap.sh`) le rend lisible par toute personne ou rôle IAM ayant le droit de lecture `ec2:DescribeInstanceAttribute` :
  ```bash
  aws ec2 describe-instance-attribute --instance-id <ID> --attribute userData --query UserData.Value --output text | base64 -d
  ```
  De plus, ces données sont souvent journalisées en clair dans `/var/log/cloud-init-output.log` sur la machine.
- **Remédiation** : `user_data` ne contient aucun secret. L'instance s'authentifie via son rôle IAM (Instance Profile) auprès d'AWS SSM Parameter Store au démarrage pour récupérer la valeur de manière sécurisée et l'écrire dans un fichier protégé (`chmod 0640 /etc/novasphere/app.conf`).

---

## 2. Écriture seule (`value_wo` et `ephemeral`)

### Pourquoi `ephemeral = true` ?
Terraform 1.10+ introduit les variables éphémères (`ephemeral = true`). Cela garantit que la variable ne peut être utilisée que dans des contextes temporaires (arguments `value_wo`) et interdit formellement à Terraform d'évaluer ou d'écrire cette variable dans les attributs persistés du state.

### Pourquoi `value_wo_version` est-il obligatoire avec `value_wo` ?
Puisque Terraform n'enregistre **pas** la valeur du secret dans le fichier d'état pour empêcher toute fuite, le moteur de Terraform est par nature aveugle au changement de valeur lors d'un `terraform plan`.
Pour savoir quand il doit mettre à jour le paramètre SSM lors d'une rotation de mot de passe, Terraform s'appuie obligatoirement sur un entier versionné : `value_wo_version = 1`. Incrémenter ce numéro (`value_wo_version = 2`) indique explicitement à Terraform de repousser la nouvelle valeur du secret dans AWS SSM.

---

## 3. La valeur qui a fui a-t-elle disparu d'AWS ?

**Non.** Retirer un secret du code Terraform ou modifier la valeur dans SSM Parameter Store ne supprime pas automatiquement les traces :
1. **SSM Parameter Store Versioning** : AWS SSM conserve l'historique complet des versions précédentes d'un paramètre. L'ancienne valeur reste lisible via `aws ssm get-parameter-history`.
2. **Git History** : Tout commit Git historique conserve la valeur tant que le dépôt n'est pas purgé avec un outil tel que `git-filter-repo` ou BFG.
3. **Logs EC2 / Snapshots EBS** : Les instances démarrées avant la rotation ont toujours la valeur dans leurs journaux ou dans leur fichier local `/etc/novasphere/app.conf`, ainsi que dans d'éventuels snapshots EBS non chiffrés.

### Procédure de remédiation complète en cas de fuite :
1. Révoquer et renouveler immédiatement le secret à la source (ex. rotation du mot de passe en base de données).
2. Pousser la nouvelle version dans SSM Parameter Store (`value_wo_version = N+1`).
3. Supprimer explicitement les anciennes versions du paramètre SSM via l'AWS CLI.
4. Recréer/recycler les instances EC2 compromises (via Auto Scaling Group / Instance Refresh).

---

## 4. Limite assumée : AWS Learner Lab

Dans le cadre des comptes **AWS Academy Learner Lab**, des Service Control Policies (SCP) strictes interdisent toute création ou modification de rôle et politique IAM :
```
iam:CreateRole, iam:CreatePolicy -> Denied by SCP
```

### Notre approche :
1. **Code pédagogique conforme aux règles de l'art** : Nous avons créé et documenté le fichier `envs/dev/iam_compte_classique.tf.exemple` démontrant la mise en œuvre du principe du moindre privilège (*Least Privilege*), restreignant l'accès au paramètre de l'environnement uniquement :
   ```hcl
   Resource = "arn:aws:ssm:*:*:parameter/novasphere/${var.environment}/*"
   ```
2. **Déploiement effectif sous contrainte Lab** : L'Auto Scaling Group et le Launch Template utilisent le profil d'instance préexistant `LabInstanceProfile`, disposant des permissions nécessaires pour s'authentifier auprès de SSM.

---

## 5. Résultats Checkov

Un audit statique de sécurité a été réalisé avec **Checkov 3.4** sur le dossier `envs/dev`.

### Règles corrigées :
- **`CKV_AWS_79` (IMDSv2)** : Activation obligatoire du service de métadonnées v2 (`http_tokens = "required"`, `http_put_response_hop_limit = 1`) sur `aws_launch_template.web` pour protéger les instances contre les attaques SSRF (Server-Side Request Forgery).
- **`CKV_AWS_8` (Chiffrement EBS)** : Activation du chiffrement systématique des volumes EBS racine (`encrypted = true`, type `gp3`) sur `aws_launch_template.web`.

### Règles justifiées et ignorées (Checkov Skips) :
- **`CKV2_AWS_20` (Redirection HTTP vers HTTPS sur l'ALB)** :
  - *Annotation* : `#checkov:skip=CKV2_AWS_20:Environnement de lab etudiant sans nom de domaine ni certificat ACM`
  - *Justification* : Le lab étudiant ne dispose pas d'un nom de domaine public déposé sur Route53 ni d'un certificat TLS public AWS Certificate Manager (ACM). Le listener 80 reste en HTTP brut pour les besoins des tests de charge et d'équilibrage.
- **`CKV2_AWS_28` (Activation AWS WAF sur ALB)** :
  - *Annotation* : `#checkov:skip=CKV2_AWS_28:WAF non active en lab pour maitrise des couts`
  - *Justification* : L'activation d'AWS WAF v2 entraîne une facturation fixe par WebACL ($5/mois + règles), proscrite pour éviter l'épuisement prématuré des crédits étudiants du Learner Lab.


---

## 6. Dérives traitées (Séance S06 - Étape 3)

### Règle : Ouverture non autorisée du port 8080 sur le Security Group `novasphere-dev-web`
- **Dérive constatée** : Ajout manuel hors-Terraform via l'AWS CLI / Console d'une règle d'entrée autorisant le trafic `TCP/8080` depuis `0.0.0.0/0` sur le Security Group `novasphere-dev-web` (`sg-0a9b0e1dac2516c0b`).
- **Décision retenue** : **Le code a raison** (remédiation par réalignement automatique via `terraform apply`).
- **Justification** : Cette ouverture non versionnée expose directement les serveurs d'application à Internet sans filtrage, contournant l'Application Load Balancer et détruisant le principe de défense en profondeur (*Defense in Depth*). Le code Terraform constitue la source unique de vérité (*Single Source of Truth*) : la règle sauvage est donc supprimée par Terraform pour rétablir la conformité de l'infrastructure.


---

## 7. Fédération OIDC vs Secrets de Lab & Journaux Publics (Séance S07)

### A. Rôle de la condition `sub` en OIDC
La condition `StringLike = { "token.actions.githubusercontent.com:sub" = "repo:Deslionse/novasphere-infra-M2:*" }` restreint l'échange de jeton Web Identity strictement aux pipelines exécutés depuis notre dépôt GitHub. Même si un tiers configure une action GitHub avec le même client ID AWS, la requête sera rejetée s'il ne provient pas de notre dépôt.

### B. Comparatif OIDC vs Credentials de Lab
En production standard avec OIDC, aucun secret ou identifiant statique n'est stocké dans GitHub : un jeton court (1h) est émis dynamiquement par AWS pour chaque exécution. Dans le cadre du Learner Lab (IAM bloqué par SCP), les identifiants temporaires de session (valables 4h) sont stockés dans les GitHub Actions Secrets et synchronisés à chaque lancement de session via `scripts/ci-secrets.sh`.

### C. Analyse des journaux publics de CI
Les logs publics de GitHub Actions affichent les ARN (contenant l'ID de compte AWS), le `ADMIN_CIDR` et les noms DNS de l'ALB : ces informations d'adressage et de topologie ne sont pas des secrets car elles ne confèrent aucun droit d'authentification ni d'élévation de privilège, l'accès restant scellé par les Security Groups et les mécanismes IAM.
