# Vigilo - Single Launcher (Windows)
# Starts the API, monitor, and opens the dashboard - all in one.
# This is the only thing the user needs to run.
#
# It self-elevates to Administrator automatically if needed.

$ErrorActionPreference = "Stop"

# Self-elevate to Administrator if not already
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")
if (-not $isAdmin) {
  # Relaunch this script as Administrator
  Start-Process powershell.exe -Verb RunAs -ArgumentList "-ExecutionPolicy Bypass -File `"$PSCommandPath`""
  exit
}

$ROOT = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host ""
Write-Host "  VIGILO - Autonomous Network Protection" -ForegroundColor Cyan
Write-Host "  Starting protection..." -ForegroundColor Cyan
Write-Host ""

# Load .env
$envFile = "$ROOT\.env"
if (Test-Path $envFile) {
  Get-Content $envFile | ForEach-Object {
    if ($_ -match '^([^#][^=]+)=(.+)$') {
      [System.Environment]::SetEnvironmentVariable($matches[1].Trim(), $matches[2].Trim(), 'Process')
    }
  }
}

$PORT = if ($env:PORT) { $env:PORT } else { "5000" }

# Verify install
$apiPython = "$ROOT\api\venv\Scripts\python.exe"
$monPython = "$ROOT\monitor\venv\Scripts\python.exe"
$appScript = "$ROOT\api\app.py"
$monScript = "$ROOT\monitor\monitor.py"

if (-not (Test-Path $apiPython)) {
  Write-Host "[XX] Vigilo is not installed correctly. Please run the installer again." -ForegroundColor Red
  Read-Host "Press Enter to close"
  exit 1
}

# -- Detect network --------------------------------------------
function Get-ActiveNetwork {
  try {
    $route = Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue |
             Where-Object { $_.NextHop -ne "0.0.0.0" } |
             Sort-Object -Property RouteMetric | Select-Object -First 1
    if (-not $route) { return $null }
    $ifAlias = (Get-NetAdapter -InterfaceIndex $route.ifIndex -ErrorAction SilentlyContinue).Name
    if (-not $route.NextHop -or -not $ifAlias) { return $null }
    return @{ Gateway = $route.NextHop; Interface = $ifAlias }
  } catch { return $null }
}

# -- Free the port if already in use ---------------------------
$portInUse = Get-NetTCPConnection -LocalPort $PORT -ErrorAction SilentlyContinue
if ($portInUse) {
  $pidUsing = $portInUse.OwningProcess | Select-Object -First 1
  Write-Host "[!!] Vigilo may already be running. Restarting..." -ForegroundColor Yellow
  Stop-Process -Id $pidUsing -Force -ErrorAction SilentlyContinue
  Start-Sleep -Seconds 2
}

# -- Start API (hidden window) ---------------------------------
Write-Host "[>>] Starting protection engine..." -ForegroundColor Cyan
$apiProcess = Start-Process -FilePath $apiPython `
  -ArgumentList "`"$appScript`"" `
  -PassThru -WindowStyle Hidden

# Wait for API to respond
$ready = $false
for ($i = 1; $i -le 15; $i++) {
  Start-Sleep -Seconds 1
  if ($apiProcess.HasExited) {
    Write-Host "[XX] Protection engine failed to start." -ForegroundColor Red
    Read-Host "Press Enter to close"
    exit 1
  }
  try {
    $r = Invoke-WebRequest -Uri "http://127.0.0.1:$PORT/api/health" -UseBasicParsing -TimeoutSec 2 -ErrorAction SilentlyContinue
    if ($r.StatusCode -eq 200) { $ready = $true; break }
  } catch { }
}

if (-not $ready -and $apiProcess.HasExited) {
  Write-Host "[XX] Protection engine did not respond." -ForegroundColor Red
  Read-Host "Press Enter to close"
  exit 1
}

Write-Host "[OK] Protection engine running" -ForegroundColor Green

# -- Start monitor (hidden window) -----------------------------
$net = Get-ActiveNetwork
if ($net) {
  Write-Host "[>>] Starting network monitor..." -ForegroundColor Cyan
  $monProcess = Start-Process -FilePath $monPython `
    -ArgumentList "`"$monScript`" --interface `"$($net.Interface)`" --gateway `"$($net.Gateway)`" --api `"http://localhost:$PORT`"" `
    -PassThru -WindowStyle Hidden
  Write-Host "[OK] Network monitor running on $($net.Interface)" -ForegroundColor Green
} else {
  Write-Host "[!!] No network detected. Monitor will start when you connect." -ForegroundColor Yellow
  $monProcess = $null
}

# -- Open dashboard --------------------------------------------
Write-Host "[>>] Opening Vigilo dashboard..." -ForegroundColor Cyan
Start-Process "http://localhost:$PORT"

# Save PIDs so we can stop them later
$pidFile = "$ROOT\.vigilo-pids"
$pids = @($apiProcess.Id)
if ($monProcess) { $pids += $monProcess.Id }
$pids -join "," | Set-Content $pidFile

Write-Host ""
Write-Host "  ============================================================" -ForegroundColor Green
Write-Host "   Vigilo is now protecting your network" -ForegroundColor Green
Write-Host "  ============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "   Dashboard : http://localhost:$PORT" -ForegroundColor White
Write-Host ""
Write-Host "   Vigilo is running in the background." -ForegroundColor White
Write-Host "   You can close this window - protection continues." -ForegroundColor White
Write-Host "   To stop Vigilo, run: vigilo-stop.ps1" -ForegroundColor Yellow
Write-Host ""
Write-Host "   This window closes automatically in 10 seconds..." -ForegroundColor Yellow

Start-Sleep -Seconds 10
