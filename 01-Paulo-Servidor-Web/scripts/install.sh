#!/usr/bin/env bash
set -euo pipefail

echo "[InfraLab] Instalação do Servidor Web Linux - Componente Paulo"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_SRC="$(cd "${SCRIPT_DIR}/.." && pwd)"

APP_USER="infralab"
INSTALL_ROOT="/opt/infralab"
APP_DIR="${INSTALL_ROOT}/01-Paulo-Servidor-Web"
VENV_PATH="${INSTALL_ROOT}/venv"
ENV_FILE="${APP_DIR}/fastapi/.env"

SUDO=""
if [ "${EUID}" -ne 0 ]; then
    SUDO="sudo"
fi

if [ -f /etc/os-release ]; then
    . /etc/os-release
    echo "[+] OS detectado: ${NAME:-desconhecido} (${VERSION_ID:-?})"
fi

echo "[+] Atualizando pacotes e instalando dependências..."
${SUDO} apt-get update -y
${SUDO} apt-get install -y python3 python3-venv python3-pip nginx curl tar

echo "[+] Preparando usuário de serviço '${APP_USER}'..."
if ! id -u "${APP_USER}" >/dev/null 2>&1; then
    ${SUDO} useradd --system --home-dir "${INSTALL_ROOT}" --shell /usr/sbin/nologin "${APP_USER}"
fi

echo "[+] Implantando projeto em ${APP_DIR}..."
${SUDO} mkdir -p "${APP_DIR}"
if [ "$(realpath "${PROJECT_SRC}")" != "$(realpath "${APP_DIR}")" ]; then
    # Não copia caches nem um .env local; o .env de produção em ${APP_DIR} é preservado.
    tar -C "${PROJECT_SRC}" --exclude='__pycache__' --exclude='*.pyc' --exclude='.env' -cf - . \
        | ${SUDO} tar -C "${APP_DIR}" --no-same-owner -xf -
fi

if [ ! -d "${VENV_PATH}" ]; then
    echo "[+] Criando ambiente virtual em ${VENV_PATH}..."
    ${SUDO} python3 -m venv "${VENV_PATH}"
fi

echo "[+] Instalando dependências Python..."
${SUDO} "${VENV_PATH}/bin/pip" install --upgrade pip
${SUDO} "${VENV_PATH}/bin/pip" install -r "${APP_DIR}/fastapi/requirements.txt"

echo "[+] Configurando arquivo .env..."
if [ ! -f "${ENV_FILE}" ]; then
    ${SUDO} cp "${APP_DIR}/fastapi/.env.example" "${ENV_FILE}"
    echo "[!] ${ENV_FILE} criado a partir do .env.example."
fi
# Legível pelo systemd (root) e pelo serviço (grupo), e por mais ninguém.
${SUDO} chown root:"${APP_USER}" "${ENV_FILE}"
${SUDO} chmod 640 "${ENV_FILE}"

echo "[+] Configurando Nginx..."
${SUDO} cp "${APP_DIR}/nginx/site.conf" /etc/nginx/sites-available/infralab.conf
${SUDO} ln -sf /etc/nginx/sites-available/infralab.conf /etc/nginx/sites-enabled/infralab.conf
${SUDO} rm -f /etc/nginx/sites-enabled/default
${SUDO} nginx -t

echo "[+] Configurando Systemd..."
${SUDO} cp "${APP_DIR}/systemd/infralab-api.service" /etc/systemd/system/infralab-api.service
${SUDO} systemctl daemon-reload
${SUDO} systemctl enable infralab-api

echo "[✓] Instalação concluída com sucesso!"
echo ""
if ${SUDO} grep -q 'SENHA' "${ENV_FILE}"; then
    echo "[!] ATENÇÃO: ${ENV_FILE} ainda contém a senha de exemplo (SENHA)."
    echo "    Edite o DATABASE_URL antes de iniciar (senhas com @ # ! devem ser codificadas: @ -> %40)."
fi
echo "Próximos passos:"
echo "  1. sudoedit ${ENV_FILE}"
echo "  2. bash scripts/start.sh"
echo "  3. bash scripts/healthcheck.sh"
