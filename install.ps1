Copy

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
Write-Step "Checking Node.js version requirements"
 
# Read required Node version from dashboard/package.json
# Check engines.node field first, then infer from Vite version
$requiredNode = 20  # safe default
$pkgPath = "$ROOT\dashboard\package.json"
 
if (Test-Path $pkgPath) {
  try {
    $pkg = Get-Content $pkgPath | ConvertFrom-Json
 
    # Check engines.node field
    if ($pkg.engines -and $pkg.engines.node) {
      $enginesMatch = [regex]::Match($pkg.engines.node, '\d+')
      if ($enginesMatch.Success) {
        $requiredNode = [int]$enginesMatch.Value
      }
    } else {
      # Infer from Vite version in devDependencies
      $viteVer = ($pkg.devDependencies.vite -replace '[^\d.].*$','') -replace '[\^~]',''
      if ($viteVer) {
        $viteMajor = [int]($viteVer -split '\.')[0]
        if ($viteMajor -ge 6) { $requiredNode = 20 }
        elseif ($viteMajor -eq 5) { $requiredNode = 18 }
      }
    }
  } catch {
    Write-Warn "Could not read package.json — defaulting to Node $requiredNode"
  }
}
 
Write-Warn "Required Node.js version  : $requiredNode+"
 
# Check currently installed Node version
$currentNode = 0
$nodeCmd = Get-Command node -ErrorAction SilentlyContinue
if ($nodeCmd) {
  $nodeVer = & node --version 2>&1
  $currentNode = [int]($nodeVer -replace 'v(\d+)\..*','$1')
  Write-Warn "Installed Node.js version : $currentNode ($nodeVer)"
} else {
  Write-Warn "Installed Node.js version : not found"
}
 
if ($currentNode -lt $requiredNode) {
  Write-Warn "Node.js $currentNode is below required $requiredNode — installing automatically..."
 
  $installed = $false
 
  # Method 1: Try winget (available on Windows 11 and modern Windows 10)
  $winget = Get-Command winget -ErrorAction SilentlyContinue
  if ($winget) {
    Write-Warn "Attempting install via winget..."
    try {
      $pkgId = if ($requiredNode -ge 20) { "OpenJS.NodeJS.LTS" } else { "OpenJS.NodeJS" }
      & winget install $pkgId --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
      $installed = $true
      Write-Ok "Node.js installed via winget"
    } catch {
      Write-Warn "winget install failed — trying MSI download..."
    }
  }
 
  # Method 2: Download MSI directly from Node.js release index
  if (-not $installed) {
    Write-Warn "Fetching latest Node.js $requiredNode release info..."
    try {
      $releases  = Invoke-WebRequest "https://nodejs.org/dist/index.json" -UseBasicParsing |
                   ConvertFrom-Json
      $latest    = $releases |
                   Where-Object { $_.version -match "^v$requiredNode\." -and $_.lts } |
                   Select-Object -First 1
      if (-not $latest) {
        $latest = $releases |
                  Where-Object { $_.version -match "^v$requiredNode\." } |
                  Select-Object -First 1
      }
      $msiUrl    = "https://nodejs.org/dist/$($latest.version)/node-$($latest.version)-x64.msi"
      $msiPath   = "$env:TEMP
ode-installer.msi"
 
      Write-Warn "Downloading Node.js $($latest.version)..."
      Invoke-WebRequest -Uri $msiUrl -OutFile $msiPath -UseBasicParsing
 
      Write-Warn "Running Node.js installer silently..."
      Start-Process msiexec.exe -Wait -ArgumentList "/i `"$msiPath`" /qn ADDLOCAL=ALL"
      Remove-Item $msiPath -ErrorAction SilentlyContinue
      $installed = $true
      Write-Ok "Node.js $($latest.version) installed via MSI"
    } catch {
      Write-Warn "Automatic install failed."
      Write-Warn "Please install Node.js $requiredNode+ manually from https://nodejs.org"
      Start-Process "https://nodejs.org/en/download/"
      Write-Fail "Re-run this installer after installing Node.js $requiredNode+."
    }
  }
 
  # Refresh PATH so new node is visible in this session
  $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
              [System.Environment]::GetEnvironmentVariable("Path","User")
 
  # Verify installation
  $nodeCmd = Get-Command node -ErrorAction SilentlyContinue
  if ($nodeCmd) {
    $newVer = & node --version 2>&1
    Write-Ok "Node.js $newVer is now installed"
  } else {
    Write-Fail "Node.js installation could not be verified. Please restart PowerShell and re-run."
  }
 
} else {
  Write-Ok "Node.js $currentNode meets requirement ($requiredNode+) — skipping"
}
 
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
 
  Write-Host ""
  Write-Host "  Vigilo will send you an automatic security alert whenever" -ForegroundColor Cyan
  Write-Host "  a threat is detected on your network." -ForegroundColor Cyan
  Write-Host ""
 
  if (-not $OwnerEmail) {
    $OwnerEmail = Read-Host "  Your email address (where alerts will be sent)"
  }
 
  # Escape special regex chars before using -replace
  $escapedEmail  = [regex]::Escape("owner@yourhostel.com")
  $escapedSmtp   = [regex]::Escape("your@gmail.com")
  $escapedPass   = [regex]::Escape("your-app-password")
  $escapedHost   = [regex]::Escape("smtp.gmail.com")
 
  $envContent = (Get-Content $envFile) `
    -replace $escapedEmail, $OwnerEmail `
    -replace $escapedSmtp,  $SmtpUser  `
    -replace $escapedPass,  $SmtpPass
 
  # Update SMTP host if user provided one
  if ($SmtpHostInput -and $SmtpHostInput -ne "") {
    $envContent = $envContent -replace $escapedHost, $SmtpHostInput
  }
 
  $envContent | Set-Content $envFile
 
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
 