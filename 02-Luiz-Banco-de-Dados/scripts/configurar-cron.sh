#!/usr/bin/env bash
set -Eeuo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Execute com sudo: sudo $0" >&2
  exit 1
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_BACKUP="${SCRIPT_DIR}/../backups/backup.sh"
INSTALL_BACKUP="/usr/local/sbin/infralab-backup.sh"
CRON_LINE="0 2 * * * ${INSTALL_BACKUP} >> /var/log/infralab-backup.log 2>&1"

if [[ ! -f "$SOURCE_BACKUP" ]]; then
  echo "Não encontrei ${SOURCE_BACKUP}" >&2
  exit 1
fi

install -o root -g postgres -m 0750 "$SOURCE_BACKUP" "$INSTALL_BACKUP"
install -d -o postgres -g postgres -m 0750 /var/backups/infralab/postgresql
install -o postgres -g postgres -m 0640 /dev/null /var/log/infralab-backup.log

tmp_cron="$(mktemp)"
trap 'rm -f "$tmp_cron"' EXIT
crontab -u postgres -l 2>/dev/null | grep -Fv "$INSTALL_BACKUP" > "$tmp_cron" || true
echo "$CRON_LINE" >> "$tmp_cron"
crontab -u postgres "$tmp_cron"

systemctl enable --now cron
echo "Backup diário agendado para 02:00, executado como usuário postgres."
echo "Confira com: sudo crontab -u postgres -l"
