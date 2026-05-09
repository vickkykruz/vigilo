# Vigilo — Start Network Monitor (Windows)
# Run as Administrator
# Usage: .\monitor-start.ps1 -Interface "Wi-Fi" -Gateway "192.168.1.1"
#
# Find your interface name : Get-NetAdapter
# Find your gateway IP     : Get-NetRoute -DestinationPrefix 0.0.0.0/0
 
param (
  [string]$Interface = "Wi-Fi",
  [string]$Gateway   = "192.168.1.1"
)
 
$ROOT = Split-Path -Parent $MyInvocation.MyCommand.Path
 
Write-Host "`n[>>] Starting Vigilo Network Monitor..." -ForegroundColor Cyan
Write-Host "     Interface : $Interface" -ForegroundColor White
Write-Host "     Gateway   : $Gateway"   -ForegroundColor White
Write-Host "     Press Ctrl+C to stop`n" -ForegroundColor Yellow
 
& "$ROOT\monitor\venv\Scripts\python.exe" "$ROOT\monitor\monitor.py" `
  --interface $Interface `
  --gateway   $Gateway   `
  --api       "http://localhost:5000"
