#!/bin/bash

sudo apt update
sudo apt upgrade -y
sudo apt install -y nginx

echo "nginx install done" > /home/debian/log-nginx-install.txt
