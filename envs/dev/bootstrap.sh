#!/bin/bash
apt-get update -y && apt-get install -y nginx awscli curl

# Agent SSM officiel pour Debian 12 (us-east-1)
curl -fsSL -o /tmp/amazon-ssm-agent.deb https://s3.us-east-1.amazonaws.com/amazon-ssm-us-east-1/latest/debian_amd64/amazon-ssm-agent.deb
dpkg -i /tmp/amazon-ssm-agent.deb
systemctl enable --now amazon-ssm-agent

# Recuperation du secret depuis Parameter Store vers app.conf
mkdir -p /etc/novasphere
aws ssm get-parameter --region us-east-1 --name /novasphere/dev/db_password --with-decryption --query Parameter.Value --output text > /etc/novasphere/app.conf
chmod 0640 /etc/novasphere/app.conf

echo "<h1>NovaSphere</h1><p>$(hostname)</p>" > /var/www/html/index.html
systemctl enable --now nginx
