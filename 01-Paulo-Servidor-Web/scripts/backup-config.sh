#!/usr/bin/env bash
set -euo pipefail

# Backup dos arquivos de configuração (NÃO inclui o .env real, pois contém senhas).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

BACKUP_DIR="${BACKUP_DIR:-/tmp/infralab_backups}"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
ARCHIVE_NAME="infralab_web_config_${TIMESTAMP}.tar.gz"

mkdir -p "${BACKUP_DIR}"

echo "[+] Gerando cópia de segurança..."
tar -czf "${BACKUP_DIR}/${ARCHIVE_NAME}" \
    -C "${PROJECT_DIR}" \
    nginx/site.conf \
    systemd/infralab-api.service \
    fastapi/app/config.py \
    fastapi/.env.example

echo "[✓] Backup concluído em: ${BACKUP_DIR}/${ARCHIVE_NAME}"
