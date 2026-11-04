#!/usr/bin/env bash
echo "[-] Encerrando serviços..."
sudo systemctl stop infralab-api || true
sudo systemctl stop nginx || true
echo "[✓] Serviços encerrados."
