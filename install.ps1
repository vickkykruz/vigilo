# Vigilo Windows Installer
# Run as Administrator:
#   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
#   .\install.ps1
 
param (
  [string]$OwnerEmail = ""
)
 
$ErrorActionPreference = "Stop"
 
function Write-Step { param($msg) Write-Host "`n[>>] $msg" -ForegroundColor Cyan }
function Write-Ok   { param($msg) Write-Host "[OK] $msg"   -ForegroundColor Green }
function Write-Warn { param($msg) Write-Host "[!!] $msg"   -ForegroundColor Yellow }
function Write-Fail { param($msg) Write-Host "[XX] $msg"   -ForegroundColor Red; exit 1 }
 
Clear-Host
Write-Host "  VIGILO - Autonomous Network Protection" -ForegroundColor Cyan
Write-Host "  Windows Installer" -ForegroundColor Cyan
Write-Host "  ----------------------------------------`n" -ForegroundColor Cyan
 
# Step 0: Check Administrator
Write-Step "Checking administrator privileges"
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")
if (-not $isAdmin) {
  Write-Fail "Must be run as Administrator. Right-click PowerShell and select Run as Administrator."
}
Write-Ok "Running as Administrator"
 
$ROOT = $PSScriptRoot
 
# Step 1: Check Python
Write-Step "Checking Python installation"
$python = Get-Command python -ErrorAction SilentlyContinue
if (-not $python) { $python = Get-Command python3 -ErrorAction SilentlyContinue }
if (-not $python) {
  Write-Warn "Python not found. Opening download page..."
  Start-Process "https://www.python.org/downloads/"
  Write-Fail "Install Python 3.10+ then re-run. Check Add Python to PATH during install."
}
$pyVersion = & $python.Source --version 2>&1
Write-Ok "Found $pyVersion"
$pythonExe = $python.Source
 
# Step 2: Check Node.js
Write-Step "Checking Node.js version requirements"
$requiredNode = 20
$pkgPath = "$ROOT\dashboard\package.json"
 
if (Test-Path $pkgPath) {
  try {
    $pkg = Get-Content $pkgPath -Raw | ConvertFrom-Json
    if ($pkg.devDependencies -and $pkg.devDependencies.vite) {
      $viteVer   = ($pkg.devDependencies.vite -replace '[^\d.].*$','') -replace '[\^~]',''
      $viteMajor = [int]($viteVer -split '\.')[0]
      if ($viteMajor -ge 6) { $requiredNode = 20 }
      elseif ($viteMajor -eq 5) { $requiredNode = 18 }
    }
  } catch {
    Write-Warn "Could not read package.json - defaulting to Node $requiredNode"
  }
}
 
Write-Warn "Required Node.js : $requiredNode+"
 
$currentNode = 0
$nodeCmd = Get-Command node -ErrorAction SilentlyContinue
if ($nodeCmd) {
  $nodeVer     = & node --version 2>&1
  $currentNode = [int]($nodeVer -replace 'v(\d+)\..*','$1')
  Write-Warn "Installed Node.js : $currentNode ($nodeVer)"
} else {
  Write-Warn "Installed Node.js : not found"
}
 
if ($currentNode -lt $requiredNode) {
  Write-Warn "Node.js $currentNode is below required $requiredNode - installing..."
  $installed = $false
 
  $winget = Get-Command winget -ErrorAction SilentlyContinue
  if ($winget) {
    try {
      Write-Warn "Trying winget..."
      $pkgId = if ($requiredNode -ge 20) { "OpenJS.NodeJS.LTS" } else { "OpenJS.NodeJS" }
      & winget install $pkgId --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
      $installed = $true
      Write-Ok "Node.js installed via winget"
    } catch {
      Write-Warn "winget failed - trying MSI download..."
    }
  }
 
  if (-not $installed) {
    try {
      Write-Warn "Fetching Node.js $requiredNode release info..."
      $releases = Invoke-WebRequest "https://nodejs.org/dist/index.json" -UseBasicParsing | ConvertFrom-Json
      $latest   = $releases | Where-Object { $_.version -match "^v$requiredNode\." -and $_.lts } | Select-Object -First 1
      if (-not $latest) {
        $latest = $releases | Where-Object { $_.version -match "^v$requiredNode\." } | Select-Object -First 1
      }
      $msiUrl  = "https://nodejs.org/dist/$($latest.version)/node-$($latest.version)-x64.msi"
      $msiPath = "$env:TEMP\node-installer.msi"
      Write-Warn "Downloading Node.js $($latest.version)..."
      Invoke-WebRequest -Uri $msiUrl -OutFile $msiPath -UseBasicParsing
      Start-Process msiexec.exe -Wait -ArgumentList "/i `"$msiPath`" /qn ADDLOCAL=ALL"
      Remove-Item $msiPath -ErrorAction SilentlyContinue
      $installed = $true
      Write-Ok "Node.js $($latest.version) installed via MSI"
    } catch {
      Start-Process "https://nodejs.org/en/download/"
      Write-Fail "Install Node.js $requiredNode+ manually then re-run."
    }
  }
 
  # Refresh PATH so new node is visible
  $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
 
  $nodeCmd = Get-Command node -ErrorAction SilentlyContinue
  if ($nodeCmd) {
    Write-Ok "Node.js $(& node --version) is now installed"
  } else {
    Write-Fail "Node.js install could not be verified. Restart PowerShell and re-run."
  }
} else {
  Write-Ok "Node.js $currentNode meets requirement ($requiredNode+) - skipping"
}
 
# Step 3: Check Npcap
Write-Step "Checking Npcap installation"
$npcapService = Get-Service -Name "npcap" -ErrorAction SilentlyContinue
if ($npcapService) {
  Write-Ok "Npcap already installed - skipping"
} else {
  Write-Warn "Npcap not found. Downloading..."
  $npcapUrl  = "https://npcap.com/dist/npcap-1.82.exe"
  $npcapPath = "$env:TEMP\npcap-installer.exe"
  try {
    Invoke-WebRequest -Uri $npcapUrl -OutFile $npcapPath -UseBasicParsing
    Write-Ok "Npcap downloaded"
  } catch {
    Write-Fail "Could not download Npcap. Check internet connection."
  }
  Write-Host ""
  Write-Warn "The Npcap installer will now open."
  Write-Warn "Accept defaults. Check WinPcap API-compatible Mode."
  Read-Host "  Press Enter to launch Npcap installer" | Out-Null
  Start-Process -FilePath $npcapPath -Wait -Verb RunAs
  $npcapCheck = Get-Service -Name "npcap" -ErrorAction SilentlyContinue
  if (-not $npcapCheck) {
    Write-Fail "Npcap not verified. Install manually from https://npcap.com"
  }
  Write-Ok "Npcap installed and verified"
  Remove-Item $npcapPath -ErrorAction SilentlyContinue
}
 
# Step 4: Monitor virtual environment
Write-Step "Setting up Monitor Python environment"
$monitorVenv = "$ROOT\monitor\venv"
if (-not (Test-Path $monitorVenv)) { & $pythonExe -m venv $monitorVenv }
& "$monitorVenv\Scripts\pip.exe" install --upgrade pip --quiet
& "$monitorVenv\Scripts\pip.exe" install -r "$ROOT\monitor\requirements.txt" --quiet
Write-Ok "Monitor dependencies installed"
 
# Step 5: API virtual environment
Write-Step "Setting up API Python environment"
$apiVenv = "$ROOT\api\venv"
if (-not (Test-Path $apiVenv)) { & $pythonExe -m venv $apiVenv }
& "$apiVenv\Scripts\pip.exe" install --upgrade pip --quiet
& "$apiVenv\Scripts\pip.exe" install -r "$ROOT\api\requirements.txt" --quiet
Write-Ok "API dependencies installed"
 
# Step 6: Configure environment
Write-Step "Configuring environment"
$envFile = "$ROOT\.env"
if (-not (Test-Path $envFile)) {
  Copy-Item "$ROOT\.env.example" $envFile
  Write-Host ""
  Write-Host "  Vigilo sends an automatic alert when a threat is detected." -ForegroundColor Cyan
  Write-Host ""
  if (-not $OwnerEmail) {
    $OwnerEmail = Read-Host "  Your email address (where alerts will be sent)"
  }
  (Get-Content $envFile) -replace [regex]::Escape("owner@yourbusiness.com"), $OwnerEmail | Set-Content $envFile
  Write-Ok "Email configured - alerts will be sent to: $OwnerEmail"
} else {
  Write-Ok "Environment file exists - skipping"
}
 
# Step 7: Build dashboard
Write-Step "Building React dashboard"
"VITE_API_URL=http://localhost:5000" | Set-Content "$ROOT\dashboard\.env.local"
Push-Location "$ROOT\dashboard"
& npm install
& npm run build
Pop-Location
Write-Ok "Dashboard built"
 
# Done
Write-Host ""
Write-Host "  ============================================================" -ForegroundColor Green
Write-Host "   Vigilo installed successfully!" -ForegroundColor Green
Write-Host "  ============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "   Start Vigilo  : .\start.ps1  (as Administrator)" -ForegroundColor White
Write-Host "   Start monitor : .\monitor-start.ps1 (as Administrator)" -ForegroundColor White
Write-Host "   Dashboard     : http://localhost:5000" -ForegroundColor White
Write-Host ""
Write-Host "   Useful commands:" -ForegroundColor Yellow
Write-Host "   Find interface : Get-NetAdapter" -ForegroundColor White
Write-Host "   Find gateway   : Get-NetRoute -DestinationPrefix 0.0.0.0/0" -ForegroundColor White
Write-Host ""
 