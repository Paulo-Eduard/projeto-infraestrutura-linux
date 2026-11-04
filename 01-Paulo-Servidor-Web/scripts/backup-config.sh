#!/usr/bin/env bash
BACKUP_DIR="/tmp/infralab_backups"
TIMESTAMP="20261104_004909"
ARCHIVE_NAME="infralab_web_config_.tar.gz"

mkdir -p ""

echo "[+] Gerando cópia de segurança..."
tar -czf "/"     -C "./.."     nginx/site.conf     systemd/infralab-api.service     fastapi/app/config.py

echo "[✓] Backup concluído em: /"
