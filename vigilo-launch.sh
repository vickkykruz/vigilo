#!/usr/bin/env bash
# Vigilo - Single Launcher (Linux)
# Starts the API and monitor together, opens the dashboard.
# Run with: sudo bash vigilo-launch.sh

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'

# Need root for the monitor
if [ "$EUID" -ne 0 ]; then
  echo -e "${YELLOW}[!!] Vigilo needs administrator access to monitor your network.${NC}"
  echo -e "     Restarting with sudo..."
  exec sudo bash "$0" "$@"
fi

echo ""
echo -e "${CYAN}  VIGILO - Autonomous Network Protection${NC}"
echo -e "${CYAN}  Starting protection...${NC}"
echo ""

# Load .env
if [ -f "$ROOT/.env" ]; then
  set -a; source "$ROOT/.env"; set +a
fi
PORT=${PORT:-5000}

API_PYTHON="$ROOT/api/venv/bin/python3"
MON_PYTHON="$ROOT/monitor/venv/bin/python3"

if [ ! -f "$API_PYTHON" ]; then
  echo -e "${RED}[XX] Vigilo is not installed correctly. Run the installer again.${NC}"
  exit 1
fi

# Free the port if in use
if lsof -i ":$PORT" &>/dev/null 2>&1; then
  echo -e "${YELLOW}[!!] Vigilo may already be running. Restarting...${NC}"
  fuser -k "${PORT}/tcp" 2>/dev/null
  sleep 2
fi

# Detect network
GATEWAY=$(ip route 2>/dev/null | grep default | awk '{print $3}' | head -1)
IFACE=$(ip route 2>/dev/null | grep default | awk '{print $5}' | head -1)

# Start API in background
echo -e "${CYAN}[>>] Starting protection engine...${NC}"
"$API_PYTHON" "$ROOT/api/app.py" > "$ROOT/.api.log" 2>&1 &
API_PID=$!

# Wait for API
READY=false
for i in $(seq 1 15); do
  sleep 1
  if ! kill -0 $API_PID 2>/dev/null; then
    echo -e "${RED}[XX] Protection engine failed. Check .api.log${NC}"
    exit 1
  fi
  if curl -s "http://localhost:$PORT/api/health" &>/dev/null; then
    READY=true; break
  fi
done

echo -e "${GREEN}[OK] Protection engine running${NC}"

# Start monitor in background
if [ -n "$GATEWAY" ] && [ -n "$IFACE" ]; then
  echo -e "${CYAN}[>>] Starting network monitor...${NC}"
  "$MON_PYTHON" "$ROOT/monitor/monitor.py" --interface "$IFACE" --gateway "$GATEWAY" --api "http://localhost:$PORT" > "$ROOT/.monitor.log" 2>&1 &
  MON_PID=$!
  echo -e "${GREEN}[OK] Network monitor running on $IFACE${NC}"
else
  echo -e "${YELLOW}[!!] No network detected. Connect to start monitoring.${NC}"
  MON_PID=""
fi

# Save PIDs
echo "$API_PID,$MON_PID" > "$ROOT/.vigilo-pids"

# Open dashboard
echo -e "${CYAN}[>>] Opening dashboard...${NC}"
if command -v xdg-open &>/dev/null; then
  sudo -u "${SUDO_USER:-$USER}" xdg-open "http://localhost:$PORT" 2>/dev/null &
fi

echo ""
echo -e "${GREEN}  ============================================================${NC}"
echo -e "${GREEN}   Vigilo is now protecting your network${NC}"
echo -e "${GREEN}  ============================================================${NC}"
echo ""
echo -e "   Dashboard : http://localhost:$PORT"
echo -e "   Stop with : sudo bash vigilo-stop.sh"
echo ""
