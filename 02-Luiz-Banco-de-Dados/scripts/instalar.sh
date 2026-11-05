#!/usr/bin/env bash
set -Eeuo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Execute com sudo: sudo $0" >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y postgresql postgresql-contrib
systemctl enable --now postgresql

if ! systemctl is-active --quiet postgresql; then
  echo "Erro: o serviço PostgreSQL não iniciou corretamente." >&2
  systemctl --no-pager --full status postgresql || true
  exit 1
fi

psql --version
echo "PostgreSQL instalado e serviço ativo."
echo "Próximo passo: sudo bash scripts/configurar-banco.sh"
