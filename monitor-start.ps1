# ============================================================
# Vigilo — Start Network Monitor (Windows)
# Run as Administrator
#
# Usage:
#   .\monitor-start.ps1
#   .\monitor-start.ps1 -Interface "Wi-Fi" -Gateway "192.168.1.1"
#
# Find your interface : Get-NetAdapter
# Find your gateway   : Get-NetRoute -DestinationPrefix 0.0.0.0/0
# ============================================================
 
param (
  [string]$Interface = "",
  [string]$Gateway   = "",
  [string]$ApiUrl    = "http://localhost:5000"
)
 
$ErrorActionPreference = "Stop"
$ROOT = Split-Path -Parent $MyInvocation.MyCommand.Path
 
$CYAN   = "Cyan"
$GREEN  = "Green"
$YELLOW = "Yellow"
$RED    = "Red"
 
Write-Host ""
Write-Host "  VIGILO — Network Monitor" -ForegroundColor $CYAN
Write-Host "  Starting with automatic network detection..." -ForegroundColor $CYAN
Write-Host ""
 
# ── Check Administrator ───────────────────────────────────────
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")
if (-not $isAdmin) {
  Write-Host "[XX] Monitor requires Administrator privileges." -ForegroundColor $RED
  Write-Host "     Right-click PowerShell and select 'Run as Administrator'." -ForegroundColor $YELLOW
  exit 1
}
 
# ── Helper: detect active network ────────────────────────────
function Get-ActiveNetwork {
  try {
    $route = Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue |
             Where-Object { $_.RouteMetric -ge 0 -and $_.NextHop -ne "0.0.0.0" } |
             Sort-Object -Property RouteMetric |
             Select-Object -First 1
 
    if (-not $route) { return $null }
 
    $gw        = $route.NextHop
    $ifIndex   = $route.ifIndex
    $ifAlias   = (Get-NetAdapter -InterfaceIndex $ifIndex -ErrorAction SilentlyContinue).Name
 
    if (-not $gw -or -not $ifAlias) { return $null }
 
    return @{ Gateway = $gw; Interface = $ifAlias; IfIndex = $ifIndex }
  } catch {
    return $null
  }
}
 
# ── Helper: check interface still has IP ──────────────────────
function Test-NetworkAlive {
  param([string]$InterfaceName)
  try {
    $addr = Get-NetIPAddress -InterfaceAlias $InterfaceName `
              -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.IPAddress -ne "127.0.0.1" } |
            Select-Object -First 1
    return ($null -ne $addr)
  } catch {
    return $false
  }
}
 
# ── Helper: wait for network ──────────────────────────────────
function Wait-ForNetwork {
  $maxWait = 60
  Write-Host "[!!] No network detected — waiting for connection..." -ForegroundColor $YELLOW
  Write-Host "     Connect to a Wi-Fi network or plug in an ethernet cable." -ForegroundColor $YELLOW
  Write-Host "     Vigilo will start automatically once connected." -ForegroundColor $YELLOW
  Write-Host "     (Press Ctrl+C to cancel)" -ForegroundColor $YELLOW
  Write-Host ""
 
  for ($i = 0; $i -lt $maxWait; $i++) {
    $net = Get-ActiveNetwork
    if ($net) {
      Write-Host "[OK] Network detected — gateway: $($net.Gateway) interface: $($net.Interface)" -ForegroundColor $GREEN
      return $net
    }
    if ($i % 5 -eq 0) {
      Write-Host "     Waiting..." -ForegroundColor $YELLOW
    }
    Start-Sleep -Seconds 1
  }
 
  return $null
}
 
# ── Main restart loop ─────────────────────────────────────────
$pythonExe   = "$ROOT\monitor\venv\Scripts\python.exe"
$monitorScript = "$ROOT\monitor\monitor.py"
$restartCount  = 0
$manualOverride = ($Interface -ne "" -or $Gateway -ne "")
 
# Verify files exist
if (-not (Test-Path $pythonExe)) {
  Write-Host "[XX] Python venv not found at $pythonExe" -ForegroundColor $RED
  Write-Host "     Run install.ps1 first." -ForegroundColor $YELLOW
  exit 1
}
if (-not (Test-Path $monitorScript)) {
  Write-Host "[XX] monitor.py not found at $monitorScript" -ForegroundColor $RED
  exit 1
}
 
while ($true) {
 
  # ── Detect or wait for network ──────────────────────────────
  if (-not $manualOverride) {
    $net = Get-ActiveNetwork
 
    if (-not $net) {
      $net = Wait-ForNetwork
      if (-not $net) {
        Write-Host "[XX] Timed out waiting for network." -ForegroundColor $RED
        Write-Host "     Connect to a network and re-run: .\monitor-start.ps1" -ForegroundColor $YELLOW
        exit 1
      }
    }
 
    $Interface = $net.Interface
    $Gateway   = $net.Gateway
  }
 
  # ── Start monitor ───────────────────────────────────────────
  if ($restartCount -gt 0) {
    Write-Host "[!!] Network change detected — restarting monitor..." -ForegroundColor $YELLOW
  }
 
  Write-Host "[>>] Starting Vigilo Network Monitor" -ForegroundColor $CYAN
  Write-Host "     Interface : $Interface" -ForegroundColor $GREEN
  Write-Host "     Gateway   : $Gateway"   -ForegroundColor $GREEN
  Write-Host "     API       : $ApiUrl"
  Write-Host "     Press Ctrl+C to stop"
  Write-Host ""
 
  # Run monitor and wait for it to exit
  $process = Start-Process `
    -FilePath $pythonExe `
    -ArgumentList "$monitorScript --interface `"$Interface`" --gateway `"$Gateway`" --api `"$ApiUrl`"" `
    -PassThru `
    -NoNewWindow
 
  # Watch for network changes while monitor is running
  while (-not $process.HasExited) {
    Start-Sleep -Seconds 2
 
    # Check if network is still alive
    if (-not (Test-NetworkAlive -InterfaceName $Interface)) {
      Write-Host ""
      Write-Host "[!!] Network connection lost on $Interface" -ForegroundColor $YELLOW
      Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
      break
    }
 
    # Check if gateway/interface changed
    if (-not $manualOverride) {
      $currentNet = Get-ActiveNetwork
      if ($currentNet -and
          ($currentNet.Gateway   -ne $Gateway -or
           $currentNet.Interface -ne $Interface)) {
        Write-Host ""
        Write-Host "[!!] Network changed:" -ForegroundColor $YELLOW
        Write-Host "     Old: $Interface / $Gateway" -ForegroundColor $YELLOW
        Write-Host "     New: $($currentNet.Interface) / $($currentNet.Gateway)" -ForegroundColor $GREEN
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        $Interface = $currentNet.Interface
        $Gateway   = $currentNet.Gateway
        break
      }
    }
  }
 
  $restartCount++
 
  # Brief pause before restarting
  Write-Host "[>>] Restarting monitor in 3 seconds..." -ForegroundColor $CYAN
  Start-Sleep -Seconds 3
}
 