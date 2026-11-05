#!/bin/bash
apt-get update -y
apt-get install -y nginx
echo "<h1>NovaSphere Web - Host: $(hostname)</h1>" > /var/www/html/index.html
systemctl restart nginx
