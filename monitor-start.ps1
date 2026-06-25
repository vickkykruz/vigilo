# Vigilo - Start Network Monitor (Windows)
# Run as Administrator
#
# Usage:
#   .\monitor-start.ps1
#   .\monitor-start.ps1 -Interface "Wi-Fi" -Gateway "192.168.1.1"
 
param (
  [string]$Interface = "",
  [string]$Gateway   = "",
  [string]$ApiUrl    = "http://localhost:5000"
)
 
$ErrorActionPreference = "Stop"
$ROOT = Split-Path -Parent $MyInvocation.MyCommand.Path
 
Write-Host ""
Write-Host "  VIGILO - Network Monitor" -ForegroundColor Cyan
Write-Host "  Starting with automatic network detection..." -ForegroundColor Cyan
Write-Host ""
 
# Check Administrator
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")
if (-not $isAdmin) {
  Write-Host "[XX] Monitor requires Administrator privileges." -ForegroundColor Red
  Write-Host "     Right-click PowerShell and select Run as Administrator." -ForegroundColor Yellow
  exit 1
}
 
function Get-ActiveNetwork {
  try {
    $route = Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue |
             Where-Object { $_.NextHop -ne "0.0.0.0" } |
             Sort-Object -Property RouteMetric |
             Select-Object -First 1
    if (-not $route) { return $null }
    $gw      = $route.NextHop
    $ifIndex = $route.ifIndex
    $ifAlias = (Get-NetAdapter -InterfaceIndex $ifIndex -ErrorAction SilentlyContinue).Name
    if (-not $gw -or -not $ifAlias) { return $null }
    return @{ Gateway = $gw; Interface = $ifAlias }
  } catch {
    return $null
  }
}
 
function Test-NetworkAlive {
  param([string]$InterfaceName)
  try {
    $addr = Get-NetIPAddress -InterfaceAlias $InterfaceName -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.IPAddress -ne "127.0.0.1" } |
            Select-Object -First 1
    return ($null -ne $addr)
  } catch {
    return $false
  }
}
 
function Wait-ForNetwork {
  $maxWait = 60
  Write-Host "[!!] No network detected - waiting for connection..." -ForegroundColor Yellow
  Write-Host "     Connect to Wi-Fi or plug in ethernet." -ForegroundColor Yellow
  Write-Host "     Vigilo will start automatically once connected." -ForegroundColor Yellow
  Write-Host "     (Press Ctrl+C to cancel)" -ForegroundColor Yellow
  Write-Host ""
  for ($i = 0; $i -lt $maxWait; $i++) {
    $net = Get-ActiveNetwork
    if ($net) {
      Write-Host "[OK] Network detected - gateway: $($net.Gateway) interface: $($net.Interface)" -ForegroundColor Green
      return $net
    }
    if ($i % 5 -eq 0) { Write-Host "     Waiting..." -ForegroundColor Yellow }
    Start-Sleep -Seconds 1
  }
  return $null
}
 
$pythonExe     = "$ROOT\monitor\venv\Scripts\python.exe"
$monitorScript = "$ROOT\monitor\monitor.py"
$restartCount  = 0
$manualOverride = ($Interface -ne "" -or $Gateway -ne "")
 
if (-not (Test-Path $pythonExe)) {
  Write-Host "[XX] Python venv not found. Run install.ps1 first." -ForegroundColor Red
  exit 1
}
if (-not (Test-Path $monitorScript)) {
  Write-Host "[XX] monitor.py not found at $monitorScript" -ForegroundColor Red
  exit 1
}
 
while ($true) {
 
  if (-not $manualOverride) {
    $net = Get-ActiveNetwork
    if (-not $net) {
      $net = Wait-ForNetwork
      if (-not $net) {
        Write-Host "[XX] Timed out waiting for network." -ForegroundColor Red
        exit 1
      }
    }
    $Interface = $net.Interface
    $Gateway   = $net.Gateway
  }
 
  if ($restartCount -gt 0) {
    Write-Host "[!!] Network change detected - restarting monitor..." -ForegroundColor Yellow
  }
 
  Write-Host "[>>] Starting Vigilo Network Monitor" -ForegroundColor Cyan
  Write-Host "     Interface : $Interface" -ForegroundColor Green
  Write-Host "     Gateway   : $Gateway"   -ForegroundColor Green
  Write-Host "     API       : $ApiUrl"
  Write-Host "     Press Ctrl+C to stop"
  Write-Host ""
 
  $process = Start-Process -FilePath $pythonExe `
    -ArgumentList "`"$monitorScript`" --interface `"$Interface`" --gateway `"$Gateway`" --api `"$ApiUrl`"" `
    -PassThru -NoNewWindow
 
  while (-not $process.HasExited) {
    Start-Sleep -Seconds 2
    if (-not (Test-NetworkAlive -InterfaceName $Interface)) {
      Write-Host ""
      Write-Host "[!!] Network connection lost on $Interface" -ForegroundColor Yellow
      Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
      break
    }
    if (-not $manualOverride) {
      $currentNet = Get-ActiveNetwork
      if ($currentNet -and ($currentNet.Gateway -ne $Gateway -or $currentNet.Interface -ne $Interface)) {
        Write-Host ""
        Write-Host "[!!] Network changed:" -ForegroundColor Yellow
        Write-Host "     Old: $Interface / $Gateway" -ForegroundColor Yellow
        Write-Host "     New: $($currentNet.Interface) / $($currentNet.Gateway)" -ForegroundColor Green
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        $Interface = $currentNet.Interface
        $Gateway   = $currentNet.Gateway
        break
      }
    }
  }
 
  $restartCount++
  Write-Host "[>>] Restarting monitor in 3 seconds..." -ForegroundColor Cyan
  Start-Sleep -Seconds 3
}
 