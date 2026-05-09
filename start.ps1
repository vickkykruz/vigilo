# Vigilo — Start All Services (Windows)
# Run as Administrator
 
$ROOT = Split-Path -Parent $MyInvocation.MyCommand.Path
 
# Load .env
Get-Content "$ROOT\.env" | ForEach-Object {
  if ($_ -match '^([^#][^=]+)=(.+)$') {
    [System.Environment]::SetEnvironmentVariable($matches[1].Trim(), $matches[2].Trim(), 'Process')
  }
}
 
Write-Host "`n[>>] Starting Vigilo Flask API..." -ForegroundColor Cyan
Start-Process -FilePath "$ROOT\api\venv\Scripts\python.exe" `
  -ArgumentList "$ROOT\api\app.py" `
  -WindowStyle Minimized
 
Start-Sleep -Seconds 2
 
Write-Host "[>>] Opening Vigilo dashboard..." -ForegroundColor Cyan
Start-Process "http://localhost:5000"
 
Write-Host "`n[OK] Vigilo is running." -ForegroundColor Green
Write-Host "     Dashboard      : http://localhost:5000" -ForegroundColor White
Write-Host "     Start monitor  : .\monitor-start.ps1" -ForegroundColor Yellow
Write-Host "     Find interface : Get-NetAdapter" -ForegroundColor Yellow
Write-Host "     Find gateway   : Get-NetRoute -DestinationPrefix 0.0.0.0/0" -ForegroundColor Yellow
 