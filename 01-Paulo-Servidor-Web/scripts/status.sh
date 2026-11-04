#!/usr/bin/env bash
echo "[=== STATUS DO SERVIDOR WEB INFRALAB ===]"
echo ""
echo "--- Nginx ---"
sudo systemctl status nginx --no-pager || true
echo ""
echo "--- API FastAPI (Systemd) ---"
sudo systemctl status infralab-api --no-pager || true
echo ""
echo "--- Teste de Conectividade HTTP (/health) ---"
curl -s -w "
HTTP Code: %{http_code}
" http://127.0.0.1:8000/health || echo "[!] API indisponível."
