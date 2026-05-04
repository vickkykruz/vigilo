# Contributing to Vigilo
 
Thank you for your interest in Vigilo. This document covers how to set
up your development environment and contribute effectively.
 
---
 
## Development setup
 
### Prerequisites
 
- Ubuntu 20.04+ (for the monitor — requires raw socket access)
- Python 3.10+
- Node.js 18+
- Two devices on the same local network (for testing)
### Clone and install
 
```bash
git clone https://github.com/YOUR_USERNAME/vigilo.git
cd vigilo
 
# Monitor
cd monitor && pip install -r requirements.txt --break-system-packages && cd ..
 
# API
cd api && pip install -r requirements.txt --break-system-packages && cd ..
 
# Dashboard
cd dashboard && npm install && cd ..
```
 
### Environment setup
 
```bash
cp .env.example .env
# Edit .env with your values
```
 
---
 
## Branch strategy
 
| Branch | Purpose |
|--------|---------|
| `main` | Stable, demo-ready code only |
| `develop` | Active development |
| `feature/xxx` | Individual features |
 
---
 
## Commit style
 
Use clear, descriptive commits:
 
```
feat: add corrective ARP broadcast on spoof detection
fix: handle gateway MAC resolution timeout
docs: update README with Phase 2 roadmap
```
 
---
 
## Reporting issues
 
Open a GitHub issue with the following:
- What you were doing
- What you expected
- What actually happened
- Your OS and Python/Node versions
 