#!/bin/bash
set -e

echo "=== Inisialisasi server Fruit POS ==="
echo

# 1. Update sistem
sudo apt update && sudo apt upgrade -y

# 2. Install Docker & Docker Compose
if ! command -v docker &> /dev/null; then
    echo "Menginstall Docker..."
    curl -fsSL https://get.docker.com | sudo sh
    sudo usermod -aG docker $USER
fi

if ! command -v docker compose &> /dev/null; then
    echo "Menginstall Docker Compose plugin..."
    sudo apt install -y docker-compose-plugin
fi

# 3. Install Certbot untuk HTTPS
if ! command -v certbot &> /dev/null; then
    echo "Menginstall Certbot..."
    sudo apt install -y certbot
fi

echo
echo "Docker version: $(docker --version)"
echo "Compose version: $(docker compose version)"
echo
echo "Setup selesai. Langkah berikutnya:"
echo "1. Buat file .env berdasarkan deploy/.env.example"
echo "2. Jalankan: docker compose up -d --build"
echo "3. Setup HTTPS dengan certbot"