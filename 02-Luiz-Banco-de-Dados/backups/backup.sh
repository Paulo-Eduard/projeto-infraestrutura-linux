```bash
#!/usr/bin/env bash
set -Eeuo pipefail

# ==========================================
# CONFIGURAÇÕES
# ==========================================

DB_NAME="infralab_db"

BACKUP_DIR="/var/backups/infralab/postgresql"
RETENTION_DAYS=7

SAMBA_SERVER="192.168.20.10"
SAMBA_SHARE="dados"
SAMBA_CREDENTIALS="/etc/infralab/samba-credentials"

INSTALLED_SCRIPT="/usr/local/sbin/infralab-backup.sh"

TIMESTAMP="$(date +'%Y%m%d_%H%M%S')"
BACKUP_FILE="${BACKUP_DIR}/${DB_NAME}_${TIMESTAMP}_$$.dump"

# ==========================================
# EXECUÇÃO COMO POSTGRES
# ==========================================

# Se executado como root, delega o backup ao postgres.
if [[ "$(id -un)" == "root" ]]; then

    if [[ ! -x "$INSTALLED_SCRIPT" ]]; then
        echo "Erro: script instalado não encontrado: ${INSTALLED_SCRIPT}" >&2
        echo "Execute primeiro o instalar.sh." >&2
        exit 1
    fi

    exec runuser -u postgres -- "$INSTALLED_SCRIPT" "$@"
fi

if [[ "$(id -un)" != "postgres" ]]; then
    echo "Execute como root (sudo) ou como usuário postgres." >&2
    exit 1
fi

# ==========================================
# PREPARAÇÃO
# ==========================================

install -d -o postgres -g postgres -m 0750 "$BACKUP_DIR"
umask 077

if ! command -v pg_dump >/dev/null 2>&1 ||
   ! command -v pg_restore >/dev/null 2>&1; then
    echo "Erro: ferramentas PostgreSQL não encontradas." >&2
    exit 1
fi

if ! command -v smbclient >/dev/null 2>&1; then
    echo "Erro: smbclient não está instalado." >&2
    exit 1
fi

if [[ ! -r "$SAMBA_CREDENTIALS" ]]; then
    echo "Erro: arquivo de credenciais Samba não encontrado ou sem permissão." >&2
    exit 1
fi

# ==========================================
# GERA E VALIDA O BACKUP
# ==========================================

TEMP_FILE="$(mktemp "${BACKUP_DIR}/.backup.XXXXXX")"

trap 'rm -f "$TEMP_FILE"' EXIT

echo "Gerando backup do banco ${DB_NAME}..."

pg_dump \
    --format=custom \
    --no-owner \
    --file="$TEMP_FILE" \
    "$DB_NAME"

echo "Validando integridade do backup..."

pg_restore --list "$TEMP_FILE" >/dev/null

# Publica o backup somente após a validação.
mv -- "$TEMP_FILE" "$BACKUP_FILE"

trap - EXIT

echo "Backup local concluído: ${BACKUP_FILE}"

# ==========================================
# ENVIA PARA O SERVIDOR SAMBA
# ==========================================

echo "Enviando backup para o Samba..."

REMOTE_FILE="$(basename "$BACKUP_FILE")"

if smbclient "//${SAMBA_SERVER}/${SAMBA_SHARE}" \
    -A "$SAMBA_CREDENTIALS" \
    -c "put ${BACKUP_FILE} ${REMOTE_FILE}"; then

    echo "Backup enviado ao Samba com sucesso."

else
    echo "ERRO: não foi possível enviar o backup ao Samba." >&2
    echo "O backup local foi preservado em: ${BACKUP_FILE}" >&2
    exit 1
fi

# ==========================================
# LIMPEZA DE BACKUPS LOCAIS ANTIGOS
# ==========================================

echo "Removendo backups locais com mais de ${RETENTION_DAYS} dias..."

find "$BACKUP_DIR" \
    -maxdepth 1 \
    -type f \
    -name "${DB_NAME}_*.dump" \
    -mtime "+${RETENTION_DAYS}" \
    -delete

echo
echo "=========================================="
echo "BACKUP CONCLUÍDO!"
echo "=========================================="
echo "Arquivo local: ${BACKUP_FILE}"
echo "Destino Samba: //${SAMBA_SERVER}/${SAMBA_SHARE}"
```