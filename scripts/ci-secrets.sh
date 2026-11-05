#!/usr/bin/env bash
# Recopie les identifiants de session du lab dans les secrets du depot (a chaque Start Lab).
set -euo pipefail

cd "$(dirname "$0")/.."

# Verifie que les identifiants locaux sont valides
aws sts get-caller-identity --query Arn --output text

GH_BIN="gh"
if [ -f "$HOME/.local/bin/gh" ]; then
  GH_BIN="$HOME/.local/bin/gh"
fi

for k in aws_access_key_id aws_secret_access_key aws_session_token; do
  aws configure get "$k" | $GH_BIN secret set "$(echo "$k" | tr 'a-z' 'A-Z')" -R Deslionse/novasphere-infra-M2
done

echo "trois secrets AWS mis a jour"
