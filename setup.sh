#!/bin/bash
# setup.sh - Instalasi otomatis Habitica (Docker + Caddy) pada Ubuntu 24.04
# Pemakaian: ./setup.sh <domain>
set -e

DOMAIN="${1:?Pemakaian: ./setup.sh <domain>}"

echo "==> Update sistem"
sudo apt update && sudo apt upgrade -y

echo "==> Menambah swap 2 GB"
if ! swapon --show | grep -q /swapfile; then
  sudo fallocate -l 2G /swapfile
  sudo chmod 600 /swapfile
  sudo mkswap /swapfile
  sudo swapon /swapfile
  echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
fi

echo "==> Memasang Docker"
if ! command -v docker >/dev/null 2>&1; then
  curl -fsSL https://get.docker.com | sudo sh
fi
sudo usermod -aG docker "$USER"

echo "==> Membuat file konfigurasi"
mkdir -p ~/habitica && cd ~/habitica

cat > docker-compose.yml << EOF
version: "3"

services:
  mongo:
    image: docker.io/mongo:6
    restart: unless-stopped
    command: ["--replSet", "rs", "--bind_ip_all"]
    volumes:
      - mongo-data:/data/db
    networks:
      - habitica
    healthcheck:
      test: >
        mongosh --quiet --eval
        "try { rs.status().ok } catch (e) { rs.initiate({_id:'rs',members:[{_id:0,host:'mongo:27017'}]}).ok }"
      interval: 10s
      timeout: 10s
      retries: 10

  server:
    image: docker.io/awinterstein/habitica-server:latest
    restart: unless-stopped
    depends_on:
      mongo:
        condition: service_healthy
    networks:
      - habitica
    environment:
      - NODE_DB_URI=mongodb://mongo/habitica?replicaSet=rs
      - BASE_URL=https://${DOMAIN}
      - INVITE_ONLY=false

  caddy:
    image: docker.io/caddy:2
    restart: unless-stopped
    depends_on:
      - server
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile
      - caddy-data:/data
      - caddy-config:/config
    networks:
      - habitica

networks:
  habitica:

volumes:
  mongo-data:
  caddy-data:
  caddy-config:
EOF

cat > Caddyfile << EOF
${DOMAIN} {
    reverse_proxy server:3000
}
EOF

echo "==> Menjalankan layanan"
sudo docker compose up -d
sudo docker compose ps

echo "Selesai. Buka https://${DOMAIN} (tunggu 1-3 menit)."
