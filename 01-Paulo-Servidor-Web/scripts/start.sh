#!/usr/bin/env bash
echo "[+] Iniciando serviços..."
sudo systemctl start infralab-api || echo "[!] Systemd não ativo. Use Uvicorn em dev."
sudo systemctl restart nginx
echo "[✓] Serviços iniciados."
