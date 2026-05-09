#!/usr/bin/env bash
# ============================================================
# Vigilo — Start Network Monitor (Linux)
# Must be run as root for raw socket access.
#
# Usage:
#   sudo bash monitor-start.sh
#   sudo bash monitor-start.sh --interface wlan0 --gateway 192.168.1.1
#
# Find your interface : ip a
# Find your gateway   : ip route | grep default
# ============================================================
 
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
 
CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
 
# ── Default values ────────────────────────────────────────────
INTERFACE=""
GATEWAY=""
API_URL="http://localhost:5000"
 
# ── Parse arguments ───────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --interface|-i) INTERFACE="$2"; shift 2 ;;
    --gateway|-g)   GATEWAY="$2";   shift 2 ;;
    --api|-a)       API_URL="$2";   shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done
 
# ── Check root ────────────────────────────────────────────────
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}[XX] Monitor requires root for raw socket access.${NC}"
  echo -e "     Run: sudo bash monitor-start.sh"
  exit 1
fi
 
# ── Auto-detect interface and gateway if not provided ─────────
if [ -z "$INTERFACE" ]; then
  INTERFACE=$(ip route | grep default | awk '{print $5}' | head -1)
  echo -e "${YELLOW}[!!] No interface specified — using detected: $INTERFACE${NC}"
fi
 
if [ -z "$GATEWAY" ]; then
  GATEWAY=$(ip route | grep default | awk '{print $3}' | head -1)
  echo -e "${YELLOW}[!!] No gateway specified — using detected: $GATEWAY${NC}"
fi
 
# ── Validate ──────────────────────────────────────────────────
if [ -z "$INTERFACE" ] || [ -z "$GATEWAY" ]; then
  echo -e "${RED}[XX] Could not detect interface or gateway.${NC}"
  echo -e "     Run: ip a          (to see interfaces)"
  echo -e "     Run: ip route      (to see gateway)"
  echo -e "     Then: sudo bash monitor-start.sh --interface eth0 --gateway 192.168.1.1"
  exit 1
fi
 
echo -e "${CYAN}
[>>] Starting Vigilo Network Monitor
     Interface : $INTERFACE
     Gateway   : $GATEWAY
     API       : $API_URL
     Press Ctrl+C to stop
${NC}"
 
# ── Start monitor ─────────────────────────────────────────────
"$ROOT/monitor/venv/bin/python3" "$ROOT/monitor/monitor.py" \
  --interface "$INTERFACE" \
  --gateway   "$GATEWAY"   \
  --api       "$API_URL"
 