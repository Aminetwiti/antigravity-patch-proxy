$ErrorActionPreference = 'Continue'

Write-Host '== [1] Kill Antigravity processes ==' -ForegroundColor Cyan
Get-Process | Where-Object { $_.Name -like 'Antigravity*' -or $_.Name -like 'language_server*' } | ForEach-Object {
  Write-Host ("  killing {0} (PID {1})" -f $_.Name, $_.Id)
  try { $_ | Stop-Process -Force -ErrorAction Stop } catch {}
}
Start-Sleep -Seconds 2

Write-Host ''
Write-Host '== [2] Confirm port 50999 free ==' -ForegroundColor Cyan
$conn = Get-NetTCPConnection -LocalPort 50999 -ErrorAction SilentlyContinue
if ($conn) { Write-Host "  Port 50999 still in use by PID $($conn.OwningProcess)" -ForegroundColor Yellow } else { Write-Host '  Port 50999 is free' -ForegroundColor Green }

Write-Host ''
Write-Host '== [3] Truncate main.log to capture fresh startup ==' -ForegroundColor Cyan
$logPath = "$env:APPDATA\Antigravity\logs\main.log"
if (Test-Path $logPath) {
  # rename current log so the new run creates a fresh one, but keep the old
  Rename-Item -Path $logPath -NewName "main.previous.log" -Force
  Write-Host "  Renamed main.log -> main.previous.log"
}

Write-Host ''
Write-Host '== [4] Launch Antigravity ==' -ForegroundColor Cyan
$exe = 'C:\Users\Admin\AppData\Local\Programs\antigravity\Antigravity.exe'
Start-Process -FilePath $exe
Write-Host '  Launched.'

Write-Host ''
Write-Host '== [5] Poll port 50999 (up to 45s) + scan new log for Proxy ==' -ForegroundColor Cyan
$ready = $false
for ($i = 1; $i -le 45; $i++) {
  $tcp = $null
  try {
    $tcp = New-Object System.Net.Sockets.TcpClient
    $iar = $tcp.BeginConnect('127.0.0.1', 50999, $null, $null)
    if ($iar.AsyncWaitHandle.WaitOne(1000, $false)) {
      $tcp.EndConnect($iar)
      Write-Host ("  Port 50999 OPEN after {0}s" -f $i) -ForegroundColor Green
      $ready = $true
      break
    }
  } catch {} finally { if ($tcp) { $tcp.Close() } }
  Start-Sleep -Seconds 1
}
if (-not $ready) { Write-Host '  Port 50999 NOT reachable after 45s' -ForegroundColor Red }

Write-Host ''
Write-Host '== [6] Grep new main.log for proxy activity ==' -ForegroundColor Cyan
if (Test-Path $logPath) {
  Select-String -Path $logPath -Pattern 'Proxy|50999|listening|EADDRINUSE|patched' | Select-Object -Last 40 | ForEach-Object { Write-Host ("  {0}" -f $_.Line) }
} else {
  Write-Host '  No new main.log yet'
}

Write-Host ''
Write-Host '== [7] ag-doctor doctor ==' -ForegroundColor Cyan
node 'C:\Business\tools\solutions\antigravity-add-model-main\ag-doctor\bin\ag-doctor.js' doctor

Read-Host 'Enter to close'
