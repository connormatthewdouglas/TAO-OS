#!/usr/bin/env bash
set -euo pipefail

API_URL="http://127.0.0.1:8787/health"
API_DIR="/home/connor/CursiveOS/hub-api"
HUB_HTML="/home/connor/CursiveOS/hub/index.html"
LOG_FILE="/tmp/cursiveos-hub-api.log"

if ! curl -sf "$API_URL" >/dev/null 2>&1; then
  if [ -f "$API_DIR/.env" ]; then
    (cd "$API_DIR" && nohup npm start >"$LOG_FILE" 2>&1 &)
    sleep 1
  else
    echo "Hub API .env not found at $API_DIR/.env"
    echo "Create it (copy .env.example) so one-click startup can launch API."
  fi
fi

xdg-open "$HUB_HTML"
