#!/usr/bin/env bash
# Vigilo - Stop (Linux)
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'

if [ "$EUID" -ne 0 ]; then
  exec sudo bash "$0" "$@"
fi

echo -e "${CYAN}  Stopping Vigilo...${NC}"

if [ -f "$ROOT/.vigilo-pids" ]; then
  IFS=',' read -ra PIDS < "$ROOT/.vigilo-pids"
  for p in "${PIDS[@]}"; do
    [ -n "$p" ] && kill "$p" 2>/dev/null
  done
  rm -f "$ROOT/.vigilo-pids"
fi

fuser -k 5000/tcp 2>/dev/null

echo -e "${GREEN}[OK] Vigilo stopped.${NC}"
