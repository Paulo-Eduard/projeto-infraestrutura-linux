#!/usr/bin/env bash
set -Eeuo pipefail

DB_NAME="infralab_db"
DB_USER="infralab_user"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Execute com sudo: sudo $0" >&2
  exit 1
fi

if ! systemctl is-active --quiet postgresql; then
  systemctl start postgresql
fi

read -r -s -p "Defina a senha do usuário ${DB_USER}: " DB_PASSWORD
echo
if [[ ${#DB_PASSWORD} -lt 12 ]]; then
  echo "Use uma senha com pelo menos 12 caracteres." >&2
  exit 1
fi

# Cria o usuário caso ainda não exista; se existir, atualiza sua senha.
runuser -u postgres -- psql -v ON_ERROR_STOP=1 -v db_password="$DB_PASSWORD" <<'SQL'
SELECT format('CREATE ROLE infralab_user LOGIN PASSWORD %L', :'db_password')
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'infralab_user')\gexec
SELECT format('ALTER ROLE infralab_user WITH LOGIN PASSWORD %L', :'db_password')\gexec
SQL

# CREATE DATABASE não pode ser executado dentro de um bloco transacional.
if ! runuser -u postgres -- psql -tAc "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'" | grep -q 1; then
  runuser -u postgres -- createdb --owner="$DB_USER" "$DB_NAME"
else
  runuser -u postgres -- psql -v ON_ERROR_STOP=1 -c "ALTER DATABASE ${DB_NAME} OWNER TO ${DB_USER};"
fi

runuser -u postgres -- psql -v ON_ERROR_STOP=1 -d "$DB_NAME" <<'SQL'
GRANT CONNECT, TEMPORARY ON DATABASE infralab_db TO infralab_user;
ALTER SCHEMA public OWNER TO infralab_user;
GRANT USAGE, CREATE ON SCHEMA public TO infralab_user;
SQL

unset DB_PASSWORD
echo "Banco ${DB_NAME} e usuário ${DB_USER} configurados."
echo "A senha não foi gravada neste script. Guarde-a em local seguro para configurar o .env do FastAPI."
