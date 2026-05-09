#!/usr/bin/env bash
# ============================================================
# Vigilo — Start All Services (Linux)
# Usage: bash start.sh
#
# For systems using systemd (auto-installed):
#   systemctl start vigilo-api vigilo-monitor
#
# For WSL or manual start — use this script.
# ============================================================
 
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
 
CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
 
echo -e "${CYAN}[>>] Starting Vigilo API...${NC}"
 
# Load .env into environment
if [ -f "$ROOT/.env" ]; then
  export $(grep -v '^#' "$ROOT/.env" | grep '=' | xargs)
fi
 
# Start Flask API in background
"$ROOT/api/venv/bin/python3" "$ROOT/api/app.py" &
API_PID=$!
echo -e "${GREEN}[OK] API started (PID $API_PID)${NC}"
 
# Wait for API to be ready
sleep 2
 
echo -e "${CYAN}[>>] Vigilo is running${NC}"
echo -e "     Dashboard      : http://localhost:5000"
echo -e "     Stop API        : kill $API_PID"
echo -e "${YELLOW}     Start monitor  : sudo bash monitor-start.sh${NC}"
echo -e "${YELLOW}     (in a separate terminal, as root)${NC}"
 
# Keep script alive so Ctrl+C stops the API
wait $API_PID
 