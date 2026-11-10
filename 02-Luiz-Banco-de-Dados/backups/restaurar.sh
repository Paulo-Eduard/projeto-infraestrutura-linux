#!/usr/bin/env bash
set -Eeuo pipefail

DB_NAME="infralab_db"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Por segurança, execute com sudo: sudo $0 /caminho/backup.dump" >&2
  exit 1
fi

if [[ $# -ne 1 ]]; then
  echo "Uso: sudo $0 /caminho/arquivo.dump" >&2
  exit 1
fi

BACKUP_FILE="$1"
if [[ ! -f "$BACKUP_FILE" ]]; then
  echo "Arquivo de backup não encontrado: $BACKUP_FILE" >&2
  exit 1
fi

if ! runuser -u postgres -- test -r "$BACKUP_FILE"; then
  echo "O usuário postgres não consegue ler o arquivo. Coloque-o no diretório de backups ou ajuste permissões." >&2
  exit 1
fi

if ! runuser -u postgres -- pg_restore --list "$BACKUP_FILE" >/dev/null; then
  echo "O arquivo não parece ser um backup válido do pg_dump em formato custom." >&2
  exit 1
fi

cat <<WARN
ATENÇÃO: a restauração substituirá objetos existentes no banco ${DB_NAME}.
Faça um backup atual antes de continuar.
WARN
read -r -p "Digite RESTAURAR para confirmar: " CONFIRM
if [[ "$CONFIRM" != "RESTAURAR" ]]; then
  echo "Operação cancelada."
  exit 0
fi

runuser -u postgres -- pg_restore \
  --clean --if-exists --no-owner \
  --role=infralab_user \
  --dbname="$DB_NAME" "$BACKUP_FILE"

echo "Restauração concluída no banco ${DB_NAME}."
