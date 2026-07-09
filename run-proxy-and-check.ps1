$ErrorActionPreference = 'Continue'

Write-Host '== Launch proxy via Antigravity.exe ==' -ForegroundColor Cyan
$exe = 'C:\Users\Admin\AppData\Local\Programs\antigravity\Antigravity.exe'
$script = 'C:\Business\tools\solutions\antigravity-add-model-main\proxy-runner.js'

if (-not (Test-Path $exe))    { Write-Host "MISSING: $exe"    -ForegroundColor Red; exit 1 }
if (-not (Test-Path $script)) { Write-Host "MISSING: $script" -ForegroundColor Red; exit 1 }

# Kill any stale runner instance (by script path in command line isn't trivial;
# we identify by the temp port file existing from a prior run).
$portFile = Join-Path $env:TEMP 'ag-proxy-runner.port'
if (Test-Path $portFile) { Remove-Item $portFile -Force }

Start-Process -FilePath $exe -ArgumentList "`"$script`"" -WindowStyle Hidden
Write-Host 'Launched.'

Write-Host ''
Write-Host '== Polling 127.0.0.1:50999 (up to 30s) ==' -ForegroundColor Cyan
$ready = $false
for ($i = 1; $i -le 30; $i++) {
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
  if ($i % 5 -eq 0) { Write-Host ("  waiting... {0}s" -f $i) -ForegroundColor Yellow }
  Start-Sleep -Seconds 1
}

if (-not $ready) {
  Write-Host 'Port 50999 did NOT open. Runner log:' -ForegroundColor Red
  $logFile = Join-Path $env:TEMP 'ag-proxy-runner.log'
  if (Test-Path $logFile) { Get-Content $logFile -Tail 40 | ForEach-Object { Write-Host "  $_" } }
} else {
  Write-Host ''
  Write-Host '== ag-doctor doctor ==' -ForegroundColor Cyan
  node 'C:\Business\tools\solutions\antigravity-add-model-main\ag-doctor\bin\ag-doctor.js' doctor
  Write-Host ''
  Write-Host '== Proxy runner log ==' -ForegroundColor Cyan
  $logFile = Join-Path $env:TEMP 'ag-proxy-runner.log'
  if (Test-Path $logFile) { Get-Content $logFile -Tail 20 | ForEach-Object { Write-Host "  $_" } }
}
