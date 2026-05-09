# ============================================================
# Vigilo — Start API and Dashboard (Windows)
# Run as Administrator
# ============================================================
 
$ErrorActionPreference = "Stop"
$ROOT = Split-Path -Parent $MyInvocation.MyCommand.Path
 
Write-Host ""
Write-Host "  VIGILO — Starting..." -ForegroundColor Cyan
Write-Host ""
 
# ── Load .env ────────────────────────────────────────────────
$envFile = "$ROOT\.env"
if (Test-Path $envFile) {
  Get-Content $envFile | ForEach-Object {
    if ($_ -match '^([^#][^=]+)=(.+)$') {
      [System.Environment]::SetEnvironmentVariable(
        $matches[1].Trim(),
        $matches[2].Trim(),
        'Process'
      )
    }
  }
} else {
  Write-Host "[!!] .env file not found — run install.ps1 first." -ForegroundColor Yellow
}
 
# ── Start Flask API ───────────────────────────────────────────
Write-Host "[>>] Starting Vigilo API..." -ForegroundColor Cyan
 
$pythonExe = "$ROOT\api\venv\Scripts\python.exe"
$appScript  = "$ROOT\api\app.py"
 
if (-not (Test-Path $pythonExe)) {
  Write-Host "[XX] Python venv not found. Run install.ps1 first." -ForegroundColor Red
  exit 1
}
 
if (-not (Test-Path $appScript)) {
  Write-Host "[XX] app.py not found at $appScript" -ForegroundColor Red
  exit 1
}
 
# Start process and capture it so we can verify it stayed running
$process = Start-Process `
  -FilePath $pythonExe `
  -ArgumentList $appScript `
  -PassThru `
  -WindowStyle Normal
 
Start-Sleep -Seconds 3
 
# ── Verify API started successfully ───────────────────────────
if ($process.HasExited) {
  Write-Host ""
  Write-Host "[XX] API failed to start (exit code: $($process.ExitCode))." -ForegroundColor Red
  Write-Host "     Common causes:" -ForegroundColor Yellow
  Write-Host "       - Port 5000 already in use" -ForegroundColor White
  Write-Host "       - Missing dependencies (run install.ps1 again)" -ForegroundColor White
  Write-Host "       - Error in app.py" -ForegroundColor White
  Write-Host ""
  Write-Host "     Run manually to see the error:" -ForegroundColor Yellow
  Write-Host "     $pythonExe $appScript" -ForegroundColor White
  exit 1
}
 
Write-Host "[OK] Vigilo API running (PID $($process.Id))" -ForegroundColor Green
 
# ── Open dashboard in browser ─────────────────────────────────
Write-Host "[>>] Opening dashboard in browser..." -ForegroundColor Cyan
Start-Process "http://localhost:5000"
 
# ── Instructions ──────────────────────────────────────────────
Write-Host ""
Write-Host "  ============================================================" -ForegroundColor Green
Write-Host "   Vigilo is running" -ForegroundColor Green
Write-Host "  ============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "   Dashboard     : http://localhost:5000" -ForegroundColor White
Write-Host "   API PID       : $($process.Id)" -ForegroundColor White
Write-Host ""
Write-Host "   To start the network monitor (separate terminal as Admin):" -ForegroundColor Yellow
Write-Host "   .\monitor-start.ps1 -Interface `"Wi-Fi`" -Gateway `"192.168.1.1`"" -ForegroundColor White
Write-Host ""
Write-Host "   Useful commands:" -ForegroundColor Yellow
Write-Host "   Find interface : Get-NetAdapter" -ForegroundColor White
Write-Host "   Find gateway   : Get-NetRoute -DestinationPrefix 0.0.0.0/0" -ForegroundColor White
Write-Host ""
Write-Host "   To stop Vigilo : Stop-Process -Id $($process.Id)" -ForegroundColor White
Write-Host ""
 