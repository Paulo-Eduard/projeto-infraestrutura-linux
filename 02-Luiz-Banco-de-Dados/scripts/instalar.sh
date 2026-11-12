#!/usr/bin/env bash
set -Eeuo pipefail

# ==========================================
# CONFIGURAÇÕES DO INFRALAB
# ==========================================

DB_NAME="infralab_db"
DB_USER="infralab_user"

DB_SERVER_IP="192.168.30.10"
WEB_SERVER_IP="192.168.10.10"

SAMBA_SERVER="192.168.20.10"
SAMBA_SHARE="dados"

SAMBA_CREDENTIALS="/etc/infralab/samba-credentials"
BACKUP_SCRIPT="/usr/local/sbin/infralab-backup.sh"
BACKUP_DIR="/var/backups/infralab/configuracoes"

CRON_FILE="/etc/cron.d/infralab-backup"

# Localiza o backup.sh dentro do projeto.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f "${SCRIPT_DIR}/../backups/backup.sh" ]]; then
    SOURCE_BACKUP="${SCRIPT_DIR}/../backups/backup.sh"
else
    echo "Erro: backup.sh não encontrado." >&2
    exit 1
fi

# ==========================================
# VERIFICAÇÕES INICIAIS
# ==========================================

if [[ "${EUID}" -ne 0 ]]; then
    echo "Execute com sudo: sudo bash instalar.sh" >&2
    exit 1
fi

export DEBIAN_FRONTEND=noninteractive

echo "Atualizando pacotes..."
apt-get update

echo "Instalando dependências..."
apt-get install -y \
    postgresql \
    postgresql-contrib \
    iproute2 \
    smbclient \
    cron

echo "Iniciando PostgreSQL..."
systemctl enable --now postgresql

if ! systemctl is-active --quiet postgresql; then
    echo "Erro: PostgreSQL não iniciou corretamente." >&2
    exit 1
fi

systemctl enable --now cron

# ==========================================
# LOCALIZA CONFIGURAÇÕES DO POSTGRESQL
# ==========================================

CONFIG_FILE="$(runuser -u postgres -- psql -tAc "SHOW config_file;" | xargs)"
HBA_FILE="$(runuser -u postgres -- psql -tAc "SHOW hba_file;" | xargs)"

if [[ ! -f "$CONFIG_FILE" || ! -f "$HBA_FILE" ]]; then
    echo "Erro: arquivos de configuração não encontrados." >&2
    exit 1
fi

install -d -o root -g root -m 0700 "$BACKUP_DIR"

TIMESTAMP="$(date +'%Y%m%d_%H%M%S')"
NEEDS_RESTART=false
NEEDS_RELOAD=false

# ==========================================
# CONFIGURA LISTEN_ADDRESSES
# ==========================================

if ip -o -4 addr show |
    awk '{split($4,a,"/"); print a[1]}' |
    grep -Fxq "$DB_SERVER_IP"; then

    echo "IP PostgreSQL ${DB_SERVER_IP} encontrado."

    CURRENT_LISTEN="$(runuser -u postgres -- psql -tAc "SHOW listen_addresses;" | xargs)"

    if [[ "$CURRENT_LISTEN" != "localhost,${DB_SERVER_IP}" ]]; then

        cp -a "$CONFIG_FILE" \
            "${BACKUP_DIR}/postgresql.conf.${TIMESTAMP}.bak"

        runuser -u postgres -- psql -v ON_ERROR_STOP=1 \
            -c "ALTER SYSTEM SET listen_addresses = 'localhost,${DB_SERVER_IP}';"

        NEEDS_RESTART=true
        echo "listen_addresses configurado."
    else
        echo "listen_addresses já está correto."
    fi

else
    echo "AVISO: IP ${DB_SERVER_IP} ainda não está atribuído à VM."
    echo "A configuração de escuta será aplicada quando o IP estiver disponível."
fi

# ==========================================
# CONFIGURA ACESSO DO SERVIDOR WEB
# ==========================================

PG_HBA_RULE="host    ${DB_NAME}    ${DB_USER}    ${WEB_SERVER_IP}/32    scram-sha-256"

if grep -Eq "^[[:space:]]*host[[:space:]]+${DB_NAME}[[:space:]]+${DB_USER}[[:space:]]+${WEB_SERVER_IP}/32[[:space:]]+scram-sha-256([[:space:]]*(#.*)?)?$" "$HBA_FILE"; then

    echo "Regra de acesso do servidor Web já existe."

else
    cp -a "$HBA_FILE" \
        "${BACKUP_DIR}/pg_hba.conf.${TIMESTAMP}.bak"

    sed -i "1i\\${PG_HBA_RULE}" "$HBA_FILE"

    NEEDS_RELOAD=true
    echo "Regra de acesso do servidor Web adicionada."
fi

# ==========================================
# VALIDA CONFIGURAÇÕES
# ==========================================

CONFIG_ERRORS="$(runuser -u postgres -- psql -X -tAc \
    "SELECT sourcefile || ':' || sourceline || ': ' || error
     FROM pg_file_settings
     WHERE error IS NOT NULL;")"

HBA_ERRORS="$(runuser -u postgres -- psql -X -tAc \
    "SELECT format('linha %s: %s', line_number, error)
     FROM pg_hba_file_rules
     WHERE error IS NOT NULL;")"

if [[ -n "$CONFIG_ERRORS" || -n "$HBA_ERRORS" ]]; then
    echo "Erro: configuração inválida do PostgreSQL." >&2
    [[ -n "$CONFIG_ERRORS" ]] && echo "$CONFIG_ERRORS" >&2
    [[ -n "$HBA_ERRORS" ]] && echo "$HBA_ERRORS" >&2
    exit 1
fi

# ==========================================
# APLICA CONFIGURAÇÕES
# ==========================================

if [[ "$NEEDS_RESTART" == true ]]; then
    echo "Reiniciando PostgreSQL..."
    systemctl restart postgresql
elif [[ "$NEEDS_RELOAD" == true ]]; then
    echo "Recarregando PostgreSQL..."
    systemctl reload postgresql
fi

if ! systemctl is-active --quiet postgresql; then
    echo "Erro: PostgreSQL não está ativo." >&2
    exit 1
fi

if ! pg_isready >/dev/null 2>&1; then
    echo "Erro: PostgreSQL não está aceitando conexões." >&2
    exit 1
fi

# ==========================================
# CONFIGURA CREDENCIAIS SAMBA
# ==========================================

install -d -o root -g postgres -m 0750 /etc/infralab

if [[ ! -f "$SAMBA_CREDENTIALS" ]]; then

    echo
    echo "Configuração das credenciais Samba"
    echo "Informe o usuário autorizado no compartilhamento ${SAMBA_SHARE}."

    read -r -p "Usuário Samba: " SAMBA_USER

    if [[ -z "$SAMBA_USER" || "$SAMBA_USER" == *$'\n'* ]]; then
        echo "Usuário Samba inválido." >&2
        exit 1
    fi

    read -r -s -p "Senha Samba: " SAMBA_PASSWORD
    echo

    if [[ -z "$SAMBA_PASSWORD" || "$SAMBA_PASSWORD" == *$'\n'* ]]; then
        echo "Senha Samba inválida." >&2
        exit 1
    fi

    umask 077

    {
        printf 'username = %s\n' "$SAMBA_USER"
        printf 'password = %s\n' "$SAMBA_PASSWORD"
    } > "$SAMBA_CREDENTIALS"

    unset SAMBA_PASSWORD

    chown root:postgres "$SAMBA_CREDENTIALS"
    chmod 0640 "$SAMBA_CREDENTIALS"

    echo "Credenciais Samba configuradas."
else
    echo "Arquivo de credenciais Samba já existe. Mantendo as credenciais atuais."
    chown root:postgres "$SAMBA_CREDENTIALS"
    chmod 0640 "$SAMBA_CREDENTIALS"
fi

# ==========================================
# INSTALA SCRIPT DE BACKUP
# ==========================================

install -o root -g postgres -m 0750 \
    "$SOURCE_BACKUP" "$BACKUP_SCRIPT"

echo "Script de backup instalado em ${BACKUP_SCRIPT}."

# ==========================================
# CONFIGURA CRON
# ==========================================

cat > "$CRON_FILE" <<EOF
# Backup diário do PostgreSQL InfraLab às 02:00.
0 2 * * * postgres $BACKUP_SCRIPT
EOF

chown root:root "$CRON_FILE"
chmod 0644 "$CRON_FILE"

systemctl enable --now cron

echo "Agendamento diário configurado."

# ==========================================
# RESULTADO
# ==========================================

echo
echo "=========================================="
echo "INSTALAÇÃO CONCLUÍDA!"
echo "=========================================="

echo "PostgreSQL: ativo"
echo "Banco esperado: ${DB_NAME}"
echo "Usuário esperado: ${DB_USER}"
echo "Servidor Samba: ${SAMBA_SERVER}"
echo "Compartilhamento: ${SAMBA_SHARE}"
echo "Backup: ${BACKUP_SCRIPT}"
echo "Agendamento: diariamente às 02:00"

echo

if ip -o -4 addr show |
    awk '{split($4,a,"/"); print a[1]}' |
    grep -Fxq "$DB_SERVER_IP"; then

    echo "Endereço de escuta:"
    ss -ltn | grep ':5432' || true
else
    echo "AVISO: listen_addresses depende da atribuição do IP definitivo."
fi

echo
echo "Próximo passo: sudo bash scripts/configurar-banco.sh"
