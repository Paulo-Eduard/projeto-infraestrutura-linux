#!/usr/bin/env bash
set -Eeuo pipefail

DB_NAME="infralab_db"
BACKUP_DIR="/var/backups/infralab/postgresql"
RETENTION_DAYS=7
TIMESTAMP="$(date +'%Y%m%d_%H%M%S')"
BACKUP_FILE="${BACKUP_DIR}/${DB_NAME}_${TIMESTAMP}.dump"

# O cron executa este script como postgres. Para execução manual, aceite root
# e delegue somente a operação do backup ao usuário de sistema postgres.
if [[ "$(id -un)" == "root" ]]; then
  install -d -o postgres -g postgres -m 0750 "$BACKUP_DIR"
  exec runuser -u postgres -- /usr/local/sbin/infralab-backup.sh "$@"
fi

if [[ "$(id -un)" != "postgres" ]]; then
  echo "Execute como root (sudo) ou como usuário postgres." >&2
  exit 1
fi

install -d -o postgres -g postgres -m 0750 "$BACKUP_DIR"
umask 077

# Gera um arquivo temporário e só publica o .dump após validar sua integridade.
TEMP_FILE="${BACKUP_FILE}.tmp"
trap 'rm -f "$TEMP_FILE"' EXIT
pg_dump --format=custom --no-owner --file="$TEMP_FILE" "$DB_NAME"
pg_restore --list "$TEMP_FILE" >/dev/null
mv -- "$TEMP_FILE" "$BACKUP_FILE"
trap - EXIT

# Remove backups com mais de sete dias.
find "$BACKUP_DIR" -maxdepth 1 -type f -name "${DB_NAME}_*.dump" -mtime "+${RETENTION_DAYS}" -delete

echo "Backup concluído: ${BACKUP_FILE}"
