#!/usr/bin/env bash
# ============================================================
# Vigilo — Start API and Dashboard (Linux)
# Usage: bash start.sh
#
# This starts the Flask API which serves the dashboard.
# To start the network monitor separately (requires root):
#   sudo bash monitor-start.sh
# ============================================================
 
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
 
CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
 
# Load .env into environment
if [ -f "$ROOT/.env" ]; then
  set -a
  source "$ROOT/.env"
  set +a
fi
 
echo -e "${CYAN}[>>] Starting Vigilo API...${NC}"
"$ROOT/api/venv/bin/python3" "$ROOT/api/app.py" &
API_PID=$!
 
sleep 2
 
# Confirm API is actually running
if ! kill -0 $API_PID 2>/dev/null; then
  echo -e "\033[0;31m[XX] API failed to start. Check the output above for errors.${NC}"
  exit 1
fi
 
echo -e "${GREEN}[OK] Vigilo API running (PID $API_PID)${NC}"
echo -e ""
echo -e "     Dashboard     : http://localhost:5000"
echo -e "     Stop API      : kill $API_PID"
echo -e ""
echo -e "${YELLOW}     To start the network monitor (in a separate terminal):${NC}"
echo -e "${YELLOW}     sudo bash monitor-start.sh${NC}"
echo -e ""
echo -e "     Press Ctrl+C to stop the API"
 
# Keep running — Ctrl+C cleanly stops the API
wait $API_PID
 