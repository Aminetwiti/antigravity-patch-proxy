$ErrorActionPreference = 'Continue'
Write-Host '== Waiting for 127.0.0.1:50999 (up to 90s) ==' -ForegroundColor Cyan
$ready = $false
for ($i = 1; $i -le 90; $i++) {
  $tcp = $null
  try {
    $tcp = New-Object System.Net.Sockets.TcpClient
    $iar = $tcp.BeginConnect('127.0.0.1', 50999, $null, $null)
    $ok = $iar.AsyncWaitHandle.WaitOne(1000, $false)
    if ($ok) {
      $tcp.EndConnect($iar)
      Write-Host ("Port 50999 OPEN after {0}s" -f $i) -ForegroundColor Green
      $ready = $true
      break
    }
  } catch {
  } finally {
    if ($tcp) { $tcp.Close() }
  }
  if ($i % 10 -eq 0) { Write-Host ("  still waiting... {0}s" -f $i) -ForegroundColor Yellow }
  Start-Sleep -Seconds 1
}
if (-not $ready) { Write-Host 'Port 50999 NOT reachable after 90s' -ForegroundColor Red }

Write-Host ''
Write-Host '== ag-doctor doctor ==' -ForegroundColor Cyan
node 'C:\Business\tools\solutions\antigravity-add-model-main\ag-doctor\bin\ag-doctor.js' doctor

Read-Host 'Enter to close'
