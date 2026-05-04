# Vigilo — Autonomous Network Protection
 
> *From Latin: to watch, to guard.*
 
Vigilo detects ARP spoofing attacks on shared Wi-Fi networks, automatically
neutralises the attacker before credentials can be stolen, and notifies the
business owner in real time and in plain English, with no technical knowledge required.
 
Built for small hospitality businesses. Designed for non-technical owners.
Acts before a human could read an alert.
 
---
 
## The problem
 
Small hospitality businesses — hostels, B&Bs, guesthouses — run their admin
devices and guest devices on the same Wi-Fi network. A guest with basic hacking
knowledge can perform an ARP spoofing attack to position themselves between the
owner's device and the router, silently intercepting all traffic including login
credentials for platforms like booking.com and myallocator.
 
By the time a human reads an alert and acts — the credentials are already stolen.
 
**Vigilo acts first. Then tells you what it did.**
 
---
 
## How it works
 
```
Attacker (PC 2)                    Shared Wi-Fi Network
    │                                      │
    │── ARP spoof ──────────────────────── │
    │                                      │
                          PC 1 (Ubuntu) ───┘
                          ┌────────────────────────────┐
                          │  Python monitor (Scapy)    │
                          │  Detects ARP anomaly       │
                          │  Fires corrective ARP      │
                          │         │                  │
                          │  Flask + Socket.IO         │
                          │  Logs threat event         │
                          │  Pushes to dashboard       │
                          │  Triggers email alert      │
                          │         │                  │
                          │  React dashboard           │
                          │  Live threat display       │
                          └────────────────────────────┘
                                    │
                              Email → John
                          "Your network is safe.
                           Vigilo handled it."
```
 
---
 
## Project structure
 
```
vigilo/
│
├── monitor/                        # ARP spoof detection engine
│   ├── monitor.py                  # Core monitor — Scapy, detection, corrective ARP
│   └── requirements.txt
│
├── api/                            # Real-time API layer
│   ├── app.py                      # Flask + Socket.IO server
│   ├── mailer.py                   # Plain-English email alert
│   └── requirements.txt
│
├── dashboard/                      # Owner-facing web dashboard
│   ├── public/
│   │   └── index.html
│   ├── src/
│   │   ├── App.jsx                 # Root component + Socket.IO connection
│   │   ├── App.css                 # Dark security-tool aesthetic
│   │   ├── index.js
│   │   └── components/
│   │       ├── StatusBanner.jsx    # Safe / Threat detected banner
│   │       ├── NetworkStats.jsx    # Metrics — threats, neutralised, attackers
│   │       └── ThreatFeed.jsx      # Live scrolling threat event log
│   └── package.json
│
├── .github/
│   └── workflows/
│       └── ci.yml                  # GitHub Actions — lint + build checks
│
├── .env.example                    # Environment variable template
├── .gitignore
├── CONTRIBUTING.md
└── README.md
```
 
---
 
## Tech stack
 
| Layer | Technology | Purpose |
|-------|-----------|---------|
| Detection | Python 3.11 + Scapy 2.5 | ARP packet sniffing and corrective ARP |
| API | Flask 3.0 + Flask-SocketIO 5.3 | Threat event receiver and real-time push |
| Real-time | Socket.IO (WebSocket) | Instant dashboard updates, no polling |
| Dashboard | React 18 | Live threat display for the owner |
| Alerts | SMTP via Python smtplib | Plain-English email to owner |
 
---
 
## Setup — PC 1 (Ubuntu)
 
### Prerequisites
 
```bash
# Confirm Python version
python3 --version  # 3.10+ required
 
# Confirm Node version
node --version     # 18+ required
 
# Find your network interface name
ip a               # usually eth0 or wlan0
 
# Find your gateway IP
ip route           # look for "default via X.X.X.X"
```
 
### 1. Clone the repository
 
```bash
git clone https://github.com/YOUR_USERNAME/vigilo.git
cd vigilo
```
 
### 2. Configure environment variables
 
```bash
cp .env.example .env
nano .env  # fill in OWNER_EMAIL and SMTP credentials
```
 
### 3. Install Python dependencies
 
```bash
# Monitor
cd monitor
pip install -r requirements.txt --break-system-packages
cd ..
 
# API
cd api
pip install -r requirements.txt --break-system-packages
cd ..
```
 
### 4. Install dashboard dependencies
 
```bash
cd dashboard
npm install
cd ..
```
 
### 5. Start all three services
 
Open three separate terminal windows on PC 1:
 
**Terminal 1 — Flask API:**
```bash
cd vigilo/api
python3 app.py
# API running on http://localhost:5000
```
 
**Terminal 2 — React dashboard:**
```bash
cd vigilo/dashboard
npm start
# Dashboard running on http://localhost:3000
```
 
**Terminal 3 — Python monitor (requires root):**
```bash
cd vigilo/monitor
sudo python3 monitor.py --interface eth0 --gateway 192.168.1.1 --api http://localhost:5000
# Replace eth0 and 192.168.1.1 with your actual values
```
 
---
 
## Demo — PC 2 (attacker simulation)
 
### Install ARP spoofing tools
 
```bash
# Ubuntu
sudo apt install dsniff
 
# Or use Scapy directly
pip install scapy
```
 
### Launch the attack
 
```bash
# Enable IP forwarding (makes the attack stealthy — traffic still flows)
sudo sysctl -w net.ipv4.ip_forward=1
 
# Launch ARP spoof — tell PC 1 that you are the gateway
sudo arpspoof -i eth0 -t <PC1_IP> <GATEWAY_IP>
```
 
### Expected demo sequence
 
| Time | Event |
|------|-------|
| 0s | PC 2 launches ARP spoof |
| 2–3s | Vigilo monitor detects MAC anomaly |
| 3s | Corrective ARP broadcast fires automatically |
| 3s | Threat POSTed to Flask API |
| 3s | Socket.IO pushes event to dashboard |
| 3s | Dashboard threat card animates in |
| 3s | Email dispatched to owner |
| 4s | Demo complete — John did nothing |
 
---
 
## API reference
 
| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/api/health` | Health check |
| `POST` | `/api/threat` | Receive threat from monitor |
| `GET` | `/api/threats` | Get all threats this session |
| `POST` | `/api/threats/clear` | Reset threat log for demo |
 
### Threat payload (monitor → API)
 
```json
{
  "attacker_mac": "aa:bb:cc:dd:ee:ff",
  "attacker_ip": "192.168.1.45",
  "spoofed_ip": "192.168.1.1",
  "interface": "eth0",
  "timestamp": "2026-05-19T14:32:01.123456",
  "action": "corrective_arp_broadcast",
  "status": "neutralised"
}
```
 
---
 
## Product roadmap
 
### Phase 1 — Built
- ARP spoof detection via Scapy
- Automatic corrective ARP broadcast
- Flask + Socket.IO real-time API
- React dashboard — live threat feed
- Automatic plain-English email alert
- Fully self-contained — no internet required
### Phase 2 — Router integration
- Direct router API integration
- Ubiquiti UniFi, TP-Link Omada, Cisco Meraki support
- Automatic VLAN creation on threat detection
- Admin devices isolated at hardware level instantly
- Attacker reconnects to find admin traffic completely invisible
### Phase 3 — Platform integration
- booking.com API — forced session logout on threat
- myallocator API — session invalidation
- Direct platform fraud notification
- Stolen session cookies killed before they can be used
- Multi-platform simultaneous logout in one event
---
 
## GitHub setup
 
### First push
 
```bash
cd vigilo
git init
git add .
git commit -m "feat: initial Vigilo build — ARP detection, Flask API, React dashboard"
git branch -M main
git remote add origin https://github.com/YOUR_USERNAME/vigilo.git
git push -u origin main
```
 
### Branch strategy
 
```bash
# All new work goes on develop
git checkout -b develop
git push -u origin develop
 
# Features branch off develop
git checkout -b feature/router-api
```
 
### Recommended GitHub labels
 
| Label | Purpose |
|-------|---------|
| `phase-1` | Current build features |
| `phase-2` | Router integration roadmap |
| `phase-3` | Platform integration roadmap |
| `bug` | Something broken |
| `demo` | Demo setup and flow |
 
---
 
## Security and legal notice
 
The ARP detection and corrective ARP functionality in Vigilo is designed
for use on networks you own or have explicit permission to monitor.
 
Using network monitoring or interference tools on networks you do not own
is illegal under the Computer Misuse Act 1990 (UK) and equivalent legislation
in other jurisdictions.
 
The demo setup described in this README uses two devices on a private
test network controlled by the operator. Do not run this against any
public, shared, or third-party network.
 
---
 
## Acknowledgements
 
Built at the University of Lancashire Hackathon — May 2026.
 
Vigilo addresses a real and largely ignored vulnerability affecting
the 5.5 million SMEs in the UK, with particular focus on the
hospitality sector.
 