#!/bin/bash
sudo apt update -y
sudo apt install -y nginx
sudo systemctl start nginx
echo "<h1>This webserver IP: $(hostname -i)</h1>" > /var/www/html/index.nginx-debian.html