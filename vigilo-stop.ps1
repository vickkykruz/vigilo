# Vigilo - Stop (Windows)
# Stops the API and monitor running in the background.

$ErrorActionPreference = "SilentlyContinue"

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")
if (-not $isAdmin) {
  Start-Process powershell.exe -Verb RunAs -ArgumentList "-ExecutionPolicy Bypass -File `"$PSCommandPath`""
  exit
}

$ROOT = Split-Path -Parent $MyInvocation.MyCommand.Path
$pidFile = "$ROOT\.vigilo-pids"

Write-Host ""
Write-Host "  Stopping Vigilo..." -ForegroundColor Cyan

if (Test-Path $pidFile) {
  $pids = (Get-Content $pidFile) -split ","
  foreach ($processId in $pids) {
    Stop-Process -Id $processId -Force -ErrorAction SilentlyContinue
  }
  Remove-Item $pidFile -ErrorAction SilentlyContinue
}

# Also clean up any stray vigilo python processes on port 5000
$portInUse = Get-NetTCPConnection -LocalPort 5000 -ErrorAction SilentlyContinue
if ($portInUse) {
  $pidUsing = $portInUse.OwningProcess | Select-Object -First 1
  Stop-Process -Id $pidUsing -Force -ErrorAction SilentlyContinue
}

Write-Host "[OK] Vigilo stopped." -ForegroundColor Green
Start-Sleep -Seconds 2
