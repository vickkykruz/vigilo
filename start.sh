#!/usr/bin/env bash
# ============================================================
# Vigilo — Start API and Dashboard (Linux)
# Usage: bash start.sh
# ============================================================
 
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
 
CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
 
# ── Load .env ────────────────────────────────────────────────
if [ -f "$ROOT/.env" ]; then
  set -a
  source "$ROOT/.env"
  set +a
fi
 
PORT=${PORT:-5000}
 
# ── Check port is free ────────────────────────────────────────
if lsof -i ":$PORT" &>/dev/null 2>&1; then
  echo -e "${RED}[XX] Port $PORT is already in use.${NC}"
  echo -e "     Find the process  : sudo lsof -i :$PORT"
  echo -e "     Kill it           : sudo fuser -k ${PORT}/tcp"
  echo -e "     Then run          : bash start.sh"
  exit 1
fi
 
echo -e "${CYAN}[>>] Starting Vigilo API on port $PORT...${NC}"
"$ROOT/api/venv/bin/python3" "$ROOT/api/app.py" &
API_PID=$!
 
# ── Wait and verify API is actually serving ───────────────────
echo -e "     Waiting for API to be ready..."
READY=false
for i in 1 2 3 4 5; do
  sleep 1
  # Check process is still alive
  if ! kill -0 $API_PID 2>/dev/null; then
    echo -e "${RED}[XX] API process died during startup.${NC}"
    echo -e "     Run manually to see error:"
    echo -e "     $ROOT/api/venv/bin/python3 $ROOT/api/app.py"
    exit 1
  fi
  # Check if it is actually responding
  if curl -s "http://localhost:$PORT/api/health" &>/dev/null; then
    READY=true
    break
  fi
done
 
if [ "$READY" = false ]; then
  echo -e "${RED}[XX] API started but is not responding after 5 seconds.${NC}"
  echo -e "     Check the output above for errors."
  kill $API_PID 2>/dev/null
  exit 1
fi
 
echo -e "${GREEN}[OK] Vigilo API running and responding (PID $API_PID)${NC}"
echo -e ""
echo -e "     Dashboard     : http://localhost:$PORT"
echo -e "     Stop API      : kill $API_PID"
echo -e ""
echo -e "${YELLOW}     To start the network monitor (in a separate terminal):${NC}"
echo -e "${YELLOW}     sudo bash monitor-start.sh${NC}"
echo -e ""
echo -e "     Press Ctrl+C to stop the API"
 
wait $API_PID
 