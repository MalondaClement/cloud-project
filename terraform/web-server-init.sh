#!/bin/bash

sudo apt update
sudo apt upgrade -y
sudo apt install -y nginx
sudo systemctl start nginx
sudo systemctl enable nginx

echo "nginx install done" > /home/debian/log-nginx-install.txt
