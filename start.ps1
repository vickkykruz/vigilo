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
 
$PORT = if ($env:PORT) { $env:PORT } else { "5000" }
 
# ── Check port is free ────────────────────────────────────────
Write-Host "[>>] Checking port $PORT is available..." -ForegroundColor Cyan
 
$portInUse = Get-NetTCPConnection -LocalPort $PORT -ErrorAction SilentlyContinue
if ($portInUse) {
  $pidUsing = $portInUse.OwningProcess | Select-Object -First 1
  $procName = (Get-Process -Id $pidUsing -ErrorAction SilentlyContinue).ProcessName
 
  Write-Host ""
  Write-Host "[XX] Port $PORT is already in use." -ForegroundColor Red
  Write-Host "     Process : $procName (PID $pidUsing)" -ForegroundColor Yellow
  Write-Host ""
  Write-Host "     To kill it run:" -ForegroundColor Yellow
  Write-Host "     Stop-Process -Id $pidUsing -Force" -ForegroundColor White
  Write-Host "     Then re-run: .\start.ps1" -ForegroundColor White
  exit 1
}
 
Write-Host "[OK] Port $PORT is free" -ForegroundColor Green
 
# ── Verify files exist ────────────────────────────────────────
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
 
# ── Start Flask API ───────────────────────────────────────────
Write-Host "[>>] Starting Vigilo API on port $PORT..." -ForegroundColor Cyan
 
$process = Start-Process `
  -FilePath $pythonExe `
  -ArgumentList $appScript `
  -PassThru `
  -WindowStyle Normal
 
# ── Wait and verify API is actually serving ───────────────────
Write-Host "     Waiting for API to be ready..." -ForegroundColor Cyan
 
$ready = $false
for ($i = 1; $i -le 5; $i++) {
  Start-Sleep -Seconds 1
 
  # Check process is still alive
  if ($process.HasExited) {
    Write-Host ""
    Write-Host "[XX] API process died during startup (exit code: $($process.ExitCode))." -ForegroundColor Red
    Write-Host "     Run manually to see the error:" -ForegroundColor Yellow
    Write-Host "     $pythonExe $appScript" -ForegroundColor White
    exit 1
  }
 
  # Check if API is actually responding
  try {
    $response = Invoke-WebRequest `
      -Uri "http://localhost:$PORT/api/health" `
      -UseBasicParsing `
      -TimeoutSec 2 `
      -ErrorAction SilentlyContinue
    if ($response.StatusCode -eq 200) {
      $ready = $true
      break
    }
  } catch {
    # Not ready yet — keep waiting
  }
}
 
if (-not $ready) {
  Write-Host ""
  Write-Host "[XX] API started but is not responding after 5 seconds." -ForegroundColor Red
  Write-Host "     Check the API window for errors." -ForegroundColor Yellow
  Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
  exit 1
}
 
Write-Host "[OK] Vigilo API running and responding (PID $($process.Id))" -ForegroundColor Green
 
# ── Open dashboard in browser ─────────────────────────────────
Write-Host "[>>] Opening dashboard in browser..." -ForegroundColor Cyan
Start-Process "http://localhost:$PORT"
 
# ── Instructions ──────────────────────────────────────────────
Write-Host ""
Write-Host "  ============================================================" -ForegroundColor Green
Write-Host "   Vigilo is running" -ForegroundColor Green
Write-Host "  ============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "   Dashboard     : http://localhost:$PORT" -ForegroundColor White
Write-Host "   API PID       : $($process.Id)" -ForegroundColor White
Write-Host ""
Write-Host "   To start the network monitor (separate terminal as Admin):" -ForegroundColor Yellow
Write-Host "   .\monitor-start.ps1 -Interface `"Wi-Fi`" -Gateway `"192.168.1.1`"" -ForegroundColor White
Write-Host ""
Write-Host "   Useful commands:" -ForegroundColor Yellow
Write-Host "   Find interface : Get-NetAdapter" -ForegroundColor White
Write-Host "   Find gateway   : Get-NetRoute -DestinationPrefix 0.0.0.0/0" -ForegroundColor White
Write-Host ""
Write-Host "   To stop Vigilo : Stop-Process -Id $($process.Id) -Force" -ForegroundColor White
Write-Host ""
 