$ErrorActionPreference = 'Continue'

# 1. Set system proxy via netsh winhttp
Write-Host '== [1/4] netsh winhttp set proxy ==' -ForegroundColor Cyan
$netshOut = netsh winhttp set proxy proxy-server="127.0.0.1:50999" 2>&1 | Out-String
Write-Host $netshOut
Write-Host '-- netsh winhttp show proxy --' -ForegroundColor Cyan
netsh winhttp show proxy | Out-String | Write-Host

# 2. Launch Antigravity (its internal proxy listens on 50999)
Write-Host ''
Write-Host '== [2/4] Launching Antigravity ==' -ForegroundColor Cyan
$exe = 'C:\Users\Admin\AppData\Local\Programs\antigravity\Antigravity.exe'
if (Test-Path $exe) {
  try {
    Start-Process -FilePath $exe
    Write-Host "Started: $exe" -ForegroundColor Green
  } catch {
    Write-Host "Start-Process failed: $($_.Exception.Message)" -ForegroundColor Red
  }
} else {
  Write-Host "Antigravity.exe not found at $exe" -ForegroundColor Red
}

# 3. Poll port 50999 until reachable (up to 60s)
Write-Host ''
Write-Host '== [3/4] Waiting for 127.0.0.1:50999 ==' -ForegroundColor Cyan
$ready = $false
for ($i = 1; $i -le 60; $i++) {
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
  if ($i % 5 -eq 0) { Write-Host ("  still waiting... {0}s" -f $i) -ForegroundColor Yellow }
  Start-Sleep -Seconds 1
}
if (-not $ready) {
  Write-Host 'Port 50999 did NOT become reachable within 60s' -ForegroundColor Red
}

# 4. Re-run ag-doctor doctor
Write-Host ''
Write-Host '== [4/4] ag-doctor doctor ==' -ForegroundColor Cyan
node 'C:\Business\tools\solutions\antigravity-add-model-main\ag-doctor\bin\ag-doctor.js' doctor

Read-Host 'Press Enter to close'
