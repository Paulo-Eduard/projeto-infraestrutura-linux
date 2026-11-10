#!/usr/bin/env bash
echo "[=== STATUS DO SERVIDOR WEB INFRALAB ===]"
echo ""
echo "--- Nginx ---"
sudo systemctl status nginx --no-pager || true
echo ""
echo "--- API FastAPI (Systemd) ---"
sudo systemctl status infralab-api --no-pager || true
echo ""
echo "--- Banco de dados em uso (log de inicialização) ---"
sudo journalctl -u infralab-api --no-pager -n 200 2>/dev/null | grep "Banco de dados em uso" | tail -1 || true
echo ""
echo "--- Teste de Conectividade HTTP (/health e /health/ready) ---"
curl -s -w '\nHTTP Code: %{http_code}\n' http://127.0.0.1:8000/health || echo "[!] API indisponível."
curl -s -w '\nHTTP Code: %{http_code}\n' http://127.0.0.1:8000/health/ready || echo "[!] API indisponível."
