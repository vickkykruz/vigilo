#!/usr/bin/env bash
# ============================================================
# Vigilo — Linux Installer
# Usage: sudo bash install.sh
# ============================================================
 
# Fix 1: Stop on error
set -euo pipefail
 
CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
step() { echo -e "\n${CYAN}[>>] $1${NC}"; }
ok()   { echo -e "${GREEN}[OK] $1${NC}"; }
warn() { echo -e "${YELLOW}[!!] $1${NC}"; }
fail() { echo -e "${RED}[XX] $1${NC}"; exit 1; }
 
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
 
clear
echo -e "${CYAN}
  VIGILO — Autonomous Network Protection
  Linux Installer
${NC}"
 
# ── Step 0: Check root ───────────────────────────────────────
step "Checking permissions"
[ "$EUID" -ne 0 ] && fail "Run as root: sudo bash install.sh"
ok "Running as root"
 
# ── Step 1: System dependencies ──────────────────────────────
step "Installing system dependencies"
apt-get update -qq
apt-get install -y -qq \
  python3 \
  python3-pip \
  python3-venv \
  python3-full \
  git \
  curl \
  net-tools \
  libpcap-dev
 
# Detect required Node version from dashboard/package.json engines field.
# Falls back to 20 if not specified.
# Then checks if the installed Node meets that requirement.
# If not — installs the correct version via NodeSource automatically.
 
REQUIRED_NODE=20
 
# Read engines.node from package.json if it exists
PKG_JSON="$ROOT/dashboard/package.json"
if [ -f "$PKG_JSON" ] && command -v node &>/dev/null; then
  ENGINES_NODE=$(node -e "
    try {
      const p = require('$PKG_JSON');
      const v = (p.engines && p.engines.node) || '';
      const m = v.match(/\d+/);
      if (m) process.stdout.write(m[0]);
    } catch(e) {}
  " 2>/dev/null || echo "")
  [ -n "$ENGINES_NODE" ] && REQUIRED_NODE="$ENGINES_NODE"
fi
 
# If no engines field, infer from Vite version in devDependencies
# Vite 5.x requires Node 18+, Vite 6+/7+/8+ requires Node 20+
if command -v node &>/dev/null; then
  VITE_VER=$(node -e "
    try {
      const p = require('$PKG_JSON');
      const v = ((p.devDependencies || {}).vite || '').replace(/[^0-9.].*$/,'').replace(/\^|~/,'');
      const m = v.match(/^(\d+)/);
      if (m) process.stdout.write(m[1]);
    } catch(e) {}
  " 2>/dev/null || echo "")
  if [ -n "$VITE_VER" ] && [ "$VITE_VER" -ge 6 ] 2>/dev/null; then
    REQUIRED_NODE=20
  elif [ -n "$VITE_VER" ] && [ "$VITE_VER" -eq 5 ] 2>/dev/null; then
    REQUIRED_NODE=18
  fi
fi
 
warn "Required Node.js version : $REQUIRED_NODE+"
 
# Check currently installed Node version
CURRENT_NODE=0
if command -v node &>/dev/null; then
  CURRENT_NODE=$(node --version 2>/dev/null | grep -oP 'v\K[0-9]+' || echo '0')
fi
warn "Installed Node.js version: $CURRENT_NODE"
 
if [ "$CURRENT_NODE" -lt "$REQUIRED_NODE" ] 2>/dev/null; then
  warn "Node.js $CURRENT_NODE is below required $REQUIRED_NODE — upgrading via NodeSource..."
  curl -fsSL "https://deb.nodesource.com/setup_${REQUIRED_NODE}.x" | bash - >/dev/null 2>&1
  apt-get install -y -qq nodejs
  INSTALLED=$(node --version)
  ok "Node.js upgraded to $INSTALLED"
else
  ok "Node.js $CURRENT_NODE meets requirement ($REQUIRED_NODE+) — skipping"
fi
ok "System dependencies installed — Node $(node --version), Python $(python3 --version)"
 
# ── Step 2: Monitor virtual environment ──────────────────────
step "Setting up Monitor Python environment"
cd "$ROOT/monitor"
 
# Fix 6: Use if/then instead of &&  to avoid set -e false positive
if [ ! -d "venv" ]; then
  python3 -m venv venv
fi
 
source venv/bin/activate
pip install --upgrade pip --quiet
pip install -r requirements.txt --quiet
deactivate
ok "Monitor environment ready"
 
# ── Step 3: API virtual environment ──────────────────────────
step "Setting up API Python environment"
cd "$ROOT/api"
 
if [ ! -d "venv" ]; then
  python3 -m venv venv
fi
 
source venv/bin/activate
pip install --upgrade pip --quiet
pip install -r requirements.txt --quiet
deactivate
ok "API environment ready"
 
# ── Step 4: Configure environment ────────────────────────────
step "Configuring environment"
cd "$ROOT"
 
if [ ! -f ".env" ]; then
  cp .env.example .env
  echo ""
  echo "  Vigilo will send you an automatic security alert whenever"
  echo "  a threat is detected on your network."
  echo ""
  read -rp "  Your email address (where alerts will be sent): " OWNER_EMAIL
  echo ""
 
  sed -i "s|owner@yourhostel.com|$OWNER_EMAIL|" .env
  ok "Email configured — alerts will be sent to: $OWNER_EMAIL"
else
  ok "Environment file exists — skipping"
fi
 
# ── Step 5: Detect network configuration ─────────────────────
step "Detecting network configuration"
GATEWAY=$(ip route | grep default | awk '{print $3}' | head -1)
IFACE=$(ip route | grep default | awk '{print $5}' | head -1)
ok "Detected gateway  : $GATEWAY"
ok "Detected interface: $IFACE"
echo ""
echo "  If these values look correct, just press Enter to continue."
echo "  If you need to override (e.g. multiple network cards or VPN),"
echo "  type the correct value and press Enter."
echo ""
read -rp "  Gateway IP (Enter to confirm): " CONFIRM_GW || true
[ -n "${CONFIRM_GW:-}" ] && GATEWAY="$CONFIRM_GW"
 
read -rp "  Interface name (Enter to confirm): " CONFIRM_IF || true
[ -n "${CONFIRM_IF:-}" ] && IFACE="$CONFIRM_IF"
 
if [ -z "$GATEWAY" ] || [ -z "$IFACE" ]; then
  fail "Could not determine gateway or interface. Run: ip route"
fi
 
ok "Using gateway=$GATEWAY interface=$IFACE"
 
# ── Step 6: Set VITE_API_URL and build dashboard ─────────────
# Fix 11: Set env var before build so Vite bakes it into the bundle
step "Building React dashboard"
cd "$ROOT/dashboard"
echo "VITE_API_URL=http://localhost:5000" > .env.local
npm install --silent
npm run build
ok "Dashboard built"
 
# ── Step 7: Register services ─────────────────────────────────
# Fix 9: Check systemd is available before using it
step "Registering system services"
 
HAS_SYSTEMD=false
if command -v systemctl &>/dev/null && systemctl is-system-running &>/dev/null 2>&1; then
  HAS_SYSTEMD=true
fi
 
if [ "$HAS_SYSTEMD" = true ]; then
  # API service
  cat > /etc/systemd/system/vigilo-api.service << EOF
[Unit]
Description=Vigilo API — Autonomous Network Protection
After=network.target
 
[Service]
Type=simple
User=root
WorkingDirectory=$ROOT/api
ExecStart=$ROOT/api/venv/bin/python3 $ROOT/api/app.py
EnvironmentFile=$ROOT/.env
Restart=always
RestartSec=5
 
[Install]
WantedBy=multi-user.target
EOF
 
  # Monitor service
  cat > /etc/systemd/system/vigilo-monitor.service << EOF
[Unit]
Description=Vigilo Network Monitor
After=network.target vigilo-api.service
 
[Service]
Type=simple
User=root
WorkingDirectory=$ROOT/monitor
ExecStart=$ROOT/monitor/venv/bin/python3 $ROOT/monitor/monitor.py --interface $IFACE --gateway $GATEWAY --api http://localhost:5000
Restart=always
RestartSec=10
 
[Install]
WantedBy=multi-user.target
EOF
 
  systemctl daemon-reload
  systemctl enable vigilo-api vigilo-monitor --quiet
  systemctl start vigilo-api vigilo-monitor
  ok "Services registered and started via systemd"
 
else
  # WSL or no systemd — write a manual start script instead
  warn "systemd not available (WSL detected) — creating manual start script"
  cat > "$ROOT/start.sh" << 'EOF2'
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
EOF2
  chmod +x "$ROOT/start.sh"
  ok "Manual start script created: ./start.sh"
fi
 
# ── Done ─────────────────────────────────────────────────────
echo -e "${GREEN}
  ============================================================
   Vigilo installed successfully!
  ============================================================
 
   Dashboard     : http://localhost:5000
 
   Systemd commands (if applicable):
     API status    : systemctl status vigilo-api
     Monitor logs  : journalctl -u vigilo-monitor -f
     Stop all      : systemctl stop vigilo-api vigilo-monitor
 
   WSL / manual start:
     ./start.sh
 
  ============================================================
${NC}"
 