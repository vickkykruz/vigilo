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
 
CYAN='\033[0;36m'; GREEN='\033[0;32m'
YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
 
# ── Parse arguments ───────────────────────────────────────────
INTERFACE=""
GATEWAY=""
API_URL="http://localhost:5000"
 
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
 
# ── Wait for network function ─────────────────────────────────
wait_for_network() {
  local attempt=0
  local max_wait=60  # Wait up to 60 seconds
 
  echo -e "${YELLOW}[!!] No network detected — waiting for connection...${NC}"
  echo -e "     Connect to a Wi-Fi network or plug in an ethernet cable."
  echo -e "     Vigilo will start automatically once connected."
  echo -e "     (Press Ctrl+C to cancel)"
  echo ""
 
  while [ $attempt -lt $max_wait ]; do
    DETECTED_GW=$(ip route 2>/dev/null | grep default | awk '{print $3}' | head -1)
    DETECTED_IF=$(ip route 2>/dev/null | grep default | awk '{print $5}' | head -1)
 
    if [ -n "$DETECTED_GW" ] && [ -n "$DETECTED_IF" ]; then
      echo -e "${GREEN}[OK] Network detected — gateway: $DETECTED_GW interface: $DETECTED_IF${NC}"
      return 0
    fi
 
    # Show waiting dots every 5 seconds
    if (( attempt % 5 == 0 )); then
      echo -ne "     Waiting${NC}..."
    fi
 
    sleep 1
    ((attempt++))
  done
 
  return 1  # Timed out
}
 
# ── Detect network with retry loop ────────────────────────────
detect_network() {
  local DETECTED_GW DETECTED_IF
 
  DETECTED_GW=$(ip route 2>/dev/null | grep default | awk '{print $3}' | head -1)
  DETECTED_IF=$(ip route 2>/dev/null | grep default | awk '{print $5}' | head -1)
 
  if [ -z "$DETECTED_GW" ] || [ -z "$DETECTED_IF" ]; then
    wait_for_network || return 1
    DETECTED_GW=$(ip route 2>/dev/null | grep default | awk '{print $3}' | head -1)
    DETECTED_IF=$(ip route 2>/dev/null | grep default | awk '{print $5}' | head -1)
  fi
 
  # Use detected values only if not manually overridden
  [ -z "$GATEWAY"   ] && GATEWAY="$DETECTED_GW"
  [ -z "$INTERFACE" ] && IFACE="$DETECTED_IF"
  [ -z "$INTERFACE" ] && INTERFACE="$IFACE"
 
  return 0
}
 
# ── Main loop — restart monitor if network changes ────────────
echo -e "${CYAN}
  VIGILO — Network Monitor
  Starting with automatic network detection...
${NC}"
 
RESTART_COUNT=0
 
while true; do
  # Detect or wait for network
  if ! detect_network; then
    echo -e "${RED}[XX] Timed out waiting for network.${NC}"
    echo -e "     Connect to a network and re-run: sudo bash monitor-start.sh"
    exit 1
  fi
 
  # Validate
  if [ -z "$INTERFACE" ] || [ -z "$GATEWAY" ]; then
    echo -e "${RED}[XX] Could not determine interface or gateway.${NC}"
    exit 1
  fi
 
  if [ $RESTART_COUNT -gt 0 ]; then
    echo -e "${YELLOW}[!!] Network change detected — restarting monitor...${NC}"
  fi
 
  echo -e "${CYAN}[>>] Starting Vigilo Network Monitor${NC}"
  echo -e "     Interface : ${GREEN}$INTERFACE${NC}"
  echo -e "     Gateway   : ${GREEN}$GATEWAY${NC}"
  echo -e "     API       : $API_URL"
  echo -e "     Press Ctrl+C to stop"
  echo ""
 
  # Run the monitor — it exits if network drops
  "$ROOT/monitor/venv/bin/python3" "$ROOT/monitor/monitor.py" \
    --interface "$INTERFACE" \
    --gateway   "$GATEWAY"   \
    --api       "$API_URL"
 
  EXIT_CODE=$?
  ((RESTART_COUNT++))
 
  # Check if network is still up
  CURRENT_GW=$(ip route 2>/dev/null | grep default | awk '{print $3}' | head -1)
  CURRENT_IF=$(ip route 2>/dev/null | grep default | awk '{print $5}' | head -1)
 
  if [ -z "$CURRENT_GW" ] || [ -z "$CURRENT_IF" ]; then
    echo -e "${YELLOW}[!!] Network connection lost.${NC}"
    # Reset to allow re-detection unless manually overridden
    [ -z "$1" ] && GATEWAY=""
    [ -z "$1" ] && INTERFACE=""
  elif [ "$CURRENT_GW" != "$GATEWAY" ] || [ "$CURRENT_IF" != "$INTERFACE" ]; then
    echo -e "${YELLOW}[!!] Network changed:${NC}"
    echo -e "     Old: $INTERFACE / $GATEWAY"
    echo -e "     New: $CURRENT_IF / $CURRENT_GW"
    # Update to new network (only if not manually specified)
    if [ -z "$1" ]; then
      GATEWAY="$CURRENT_GW"
      INTERFACE="$CURRENT_IF"
    fi
  fi
 
  # Brief pause before restarting
  echo -e "${CYAN}[>>] Restarting monitor in 3 seconds...${NC}"
  sleep 3
done
 