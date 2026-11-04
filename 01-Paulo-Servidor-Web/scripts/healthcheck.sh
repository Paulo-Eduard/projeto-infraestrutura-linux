#!/usr/bin/env bash
HTTP_STATUS="000""000"

if [ "" -eq 200 ]; then
    echo "[HEALTHCHECK OK] API operational (HTTP 200)"
    exit 0
else
    echo "[HEALTHCHECK FAIL] API unresponsive or returning HTTP "
    exit 1
fi
