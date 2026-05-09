# ============================================================
# Vigilo — Windows Installer
# Run as Administrator in PowerShell:
#   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
#   .\install.ps1
# ============================================================
 
# Fix 1: Stop on any error
$ErrorActionPreference = "Stop"
 
param (
  [string]$OwnerEmail = "",
  [string]$SmtpUser   = "",
  [string]$SmtpPass   = ""
)
 
function Write-Step { param($msg) Write-Host "`n[>>] $msg" -ForegroundColor Cyan }
function Write-Ok   { param($msg) Write-Host "[OK] $msg"   -ForegroundColor Green }
function Write-Warn { param($msg) Write-Host "[!!] $msg"   -ForegroundColor Yellow }
function Write-Fail { param($msg) Write-Host "[XX] $msg"   -ForegroundColor Red; exit 1 }
 
Clear-Host
Write-Host @"
 
  VIGILO — Autonomous Network Protection
  Windows Installer
  ----------------------------------------
"@ -ForegroundColor Cyan
 
# ── Step 0: Administrator check ──────────────────────────────
Write-Step "Checking administrator privileges"
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")
if (-not $isAdmin) {
  Write-Fail "Must be run as Administrator. Right-click PowerShell and select 'Run as Administrator'."
}
Write-Ok "Running as Administrator"
 
$ROOT = $PSScriptRoot
 
# ── Step 1: Check Python ──────────────────────────────────────
Write-Step "Checking Python installation"
# Fix 2: Use Get-Command — reliable cross-version detection
$python = Get-Command python -ErrorAction SilentlyContinue
if (-not $python) {
  $python = Get-Command python3 -ErrorAction SilentlyContinue
}
if (-not $python) {
  Write-Warn "Python not found. Opening download page..."
  Start-Process "https://www.python.org/downloads/"
  Write-Fail "Install Python 3.10+ then re-run this installer. Ensure 'Add Python to PATH' is checked."
}
$pyVersion = & $python.Source --version 2>&1
Write-Ok "Found $pyVersion"
$pythonExe = $python.Source
 
# ── Step 2: Check Node.js ─────────────────────────────────────
Write-Step "Checking Node.js installation"
$node = Get-Command node -ErrorAction SilentlyContinue
if (-not $node) {
  Write-Warn "Node.js not found. Opening download page..."
  Start-Process "https://nodejs.org/en/download/"
  Write-Fail "Install Node.js 18+ then re-run this installer."
}
$nodeVersion = & node --version 2>&1
# Check version is 18+
$nodeMajor = [int]($nodeVersion -replace 'v(\d+)\..*','$1')
if ($nodeMajor -lt 18) {
  Write-Warn "Node.js $nodeVersion found but version 18+ is required."
  Start-Process "https://nodejs.org/en/download/"
  Write-Fail "Please upgrade Node.js to version 18 or higher."
}
Write-Ok "Found Node.js $nodeVersion"
 
# ── Step 3: Install Npcap ─────────────────────────────────────
Write-Step "Checking Npcap installation"
$npcapService = Get-Service -Name "npcap" -ErrorAction SilentlyContinue
if ($npcapService) {
  Write-Ok "Npcap already installed — skipping"
} else {
  Write-Warn "Npcap not found. Downloading..."
  $npcapUrl  = "https://npcap.com/dist/npcap-1.82.exe"
  $npcapPath = "$env:TEMP\npcap-installer.exe"
 
  try {
    Invoke-WebRequest -Uri $npcapUrl -OutFile $npcapPath -UseBasicParsing
    Write-Ok "Npcap downloaded"
  } catch {
    Write-Fail "Could not download Npcap. Check internet connection and try again."
  }
 
  Write-Host ""
  Write-Warn "The Npcap installer will now open."
  Write-Warn "Accept the defaults. Recommended: check 'WinPcap API-compatible Mode'."
  Write-Host "  Press Enter when ready to launch the Npcap installer..." -ForegroundColor Yellow
  Read-Host | Out-Null
 
  # Use Start-Process -Wait to ensure we wait for installer to finish
  Start-Process -FilePath $npcapPath -Wait -Verb RunAs
 
  # Verify
  $npcapCheck = Get-Service -Name "npcap" -ErrorAction SilentlyContinue
  if (-not $npcapCheck) {
    Write-Fail "Npcap installation could not be verified. Please install manually from https://npcap.com and re-run."
  }
  Write-Ok "Npcap installed and verified"
  Remove-Item $npcapPath -ErrorAction SilentlyContinue
}
 
# ── Step 4: Monitor virtual environment ───────────────────────
Write-Step "Setting up Monitor Python environment"
$monitorDir  = "$ROOT\monitor"
$monitorVenv = "$monitorDir\venv"
 
if (-not (Test-Path $monitorVenv)) {
  & $pythonExe -m venv $monitorVenv
}
& "$monitorVenv\Scripts\pip.exe" install --upgrade pip --quiet
& "$monitorVenv\Scripts\pip.exe" install -r "$monitorDir\requirements.txt" --quiet
Write-Ok "Monitor dependencies installed"
 
# ── Step 5: API virtual environment ──────────────────────────
Write-Step "Setting up API Python environment"
$apiDir  = "$ROOT\api"
$apiVenv = "$apiDir\venv"
 
if (-not (Test-Path $apiVenv)) {
  & $pythonExe -m venv $apiVenv
}
& "$apiVenv\Scripts\pip.exe" install --upgrade pip --quiet
& "$apiVenv\Scripts\pip.exe" install -r "$apiDir\requirements.txt" --quiet
Write-Ok "API dependencies installed"
 
# ── Step 6: Configure environment ────────────────────────────
Write-Step "Configuring environment"
$envFile = "$ROOT\.env"
 
if (-not (Test-Path $envFile)) {
  Copy-Item "$ROOT\.env.example" $envFile
 
  if (-not $OwnerEmail) {
    $OwnerEmail = Read-Host "`n  Owner email address for alerts"
  }
  if (-not $SmtpUser) {
    $SmtpUser = Read-Host "  Gmail address (for sending alerts)"
  }
  if (-not $SmtpPass) {
    $securePass = Read-Host "  Gmail App Password" -AsSecureString
    $SmtpPass = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
      [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePass)
    )
  }
 
  # Fix 4: Escape special regex chars before using -replace
  $escapedEmail  = [regex]::Escape("owner@yourhostel.com")
  $escapedSmtp   = [regex]::Escape("your@gmail.com")
  $escapedPass   = [regex]::Escape("your-app-password")
 
  (Get-Content $envFile) `
    -replace $escapedEmail, $OwnerEmail `
    -replace $escapedSmtp,  $SmtpUser  `
    -replace $escapedPass,  $SmtpPass  |
  Set-Content $envFile
 
  Write-Ok "Environment configured"
} else {
  Write-Ok "Environment file exists — skipping"
}
 
# ── Step 7: Set VITE_API_URL then build dashboard ─────────────
# Fix 11: Must set env var before npm run build so Vite bakes it in
Write-Step "Building React dashboard"
$dashDir = "$ROOT\dashboard"
 
# Write .env.local for the Vite build
"VITE_API_URL=http://localhost:5000" | Set-Content "$dashDir\.env.local"
 
Push-Location $dashDir
& npm install
& npm run build
Pop-Location
Write-Ok "Dashboard built"
 
# ── Done ─────────────────────────────────────────────────────
Write-Host @"
 
  ============================================================
   Vigilo installed successfully!
  ============================================================
 
   Start Vigilo  : .\start.ps1  (as Administrator)
 
   Start monitor : .\monitor-start.ps1 -Interface "Wi-Fi" -Gateway "192.168.1.1"
                   (as Administrator, after start.ps1)
 
   Dashboard     : http://localhost:5000
 
   Useful commands:
     Find interface name : Get-NetAdapter
     Find gateway IP     : Get-NetRoute -DestinationPrefix 0.0.0.0/0
  ============================================================
"@ -ForegroundColor Green
 