#!/usr/bin/env bash
# Verifica a API (/health) e a conexão com o banco (/health/ready).
# Use INFRALAB_URL para apontar para outro endereço (padrão: backend local).
BASE_URL="${INFRALAB_URL:-http://127.0.0.1:8000}"

http_code() {
    local code
    code="$(curl -s -o /dev/null -m 5 -w '%{http_code}' "$1" 2>/dev/null || true)"
    echo "${code:-000}"
}

HTTP_STATUS="$(http_code "${BASE_URL}/health")"
if [ "${HTTP_STATUS}" -ne 200 ]; then
    echo "[HEALTHCHECK FAIL] API unresponsive or returning HTTP ${HTTP_STATUS}"
    exit 1
fi
echo "[HEALTHCHECK OK] API operational (HTTP 200)"

READY_STATUS="$(http_code "${BASE_URL}/health/ready")"
if [ "${READY_STATUS}" -ne 200 ]; then
    echo "[HEALTHCHECK FAIL] Database not ready (HTTP ${READY_STATUS}) - verifique DATABASE_URL no .env"
    exit 1
fi
echo "[HEALTHCHECK OK] Database connected (HTTP 200)"
exit 0
