#!/usr/bin/env bash
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "[>>] Starting Vigilo API..."
source "$ROOT/api/venv/bin/activate"
export $(grep -v '^#' "$ROOT/.env" | xargs)
python3 "$ROOT/api/app.py" &
echo "[>>] Starting Vigilo Monitor..."
sudo "$ROOT/monitor/venv/bin/python3" "$ROOT/monitor/monitor.py" \
  --interface eth0 --gateway 192.168.1.1 --api http://localhost:5000 &
echo "[OK] Vigilo running — dashboard at http://localhost:5000"
