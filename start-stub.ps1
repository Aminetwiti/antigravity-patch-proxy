$ErrorActionPreference = 'Continue'

$nodeCmd = Get-Command node.exe -ErrorAction SilentlyContinue
if (-not $nodeCmd) { Write-Host 'node.exe not found in PATH' -ForegroundColor Red; exit 1 }
$nodeExe = $nodeCmd.Source
Write-Host ("node.exe = " + $nodeExe) -ForegroundColor DarkGray

# Free port 50999
Get-NetTCPConnection -LocalPort 50999 -State Listen -ErrorAction SilentlyContinue |
  ForEach-Object { Write-Host ("killing PID " + $_.OwningProcess + " on 50999"); Stop-Process -Id $_.OwningProcess -Force -ErrorAction SilentlyContinue }
# Kill any previous stub node process
Get-CimInstance Win32_Process -Filter "Name='node.exe'" -ErrorAction SilentlyContinue |
  Where-Object { $_.CommandLine -match 'proxy-stub' } |
  ForEach-Object { Write-Host ("killing previous stub pid=" + $_.ProcessId); Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Start-Sleep -Seconds 1

$stub = 'C:\Business\tools\solutions\antigravity-add-model-main\proxy-stub.js'
Start-Process -FilePath $nodeExe -ArgumentList "`"$stub`"" -WindowStyle Hidden `
  -RedirectStandardOutput 'C:\Users\Admin\AppData\Local\Temp\proxy-stub.out' `
  -RedirectStandardError 'C:\Users\Admin\AppData\Local\Temp\proxy-stub.err'
Write-Host 'Stub launched.' -ForegroundColor Cyan

Write-Host 'Waiting for 127.0.0.1:50999...' -ForegroundColor Cyan
$ready = $false
for ($i = 1; $i -le 20; $i++) {
  $tcp = $null
  try {
    $tcp = New-Object System.Net.Sockets.TcpClient
    $iar = $tcp.BeginConnect('127.0.0.1', 50999, $null, $null)
    if ($iar.AsyncWaitHandle.WaitOne(800, $false)) { $tcp.EndConnect($iar); $ready = $true; Write-Host ("  OPEN after {0}s" -f $i) -ForegroundColor Green; break }
  } catch {} finally { if ($tcp) { $tcp.Close() } }
  Start-Sleep -Seconds 1
}
if (-not $ready) {
  Write-Host 'Port 50999 did NOT open. Logs:' -ForegroundColor Red
  $lf = 'C:\Users\Admin\AppData\Local\Temp\proxy-stub.log'
  if (Test-Path $lf) { Get-Content $lf }
  $ef = 'C:\Users\Admin\AppData\Local\Temp\proxy-stub.err'
  if (Test-Path $ef) { Get-Content $ef }
  exit 1
}

try {
  $r = Invoke-WebRequest -Uri 'http://127.0.0.1:50999/health' -UseBasicParsing -TimeoutSec 3
  Write-Host ("  /health -> " + $r.StatusCode + " " + $r.Content) -ForegroundColor Green
} catch { Write-Host "  /health probe failed: $($_.Exception.Message)" -ForegroundColor Yellow }

Write-Host ''
Write-Host '== ag-doctor doctor ==' -ForegroundColor Cyan
& $nodeExe 'C:\Business\tools\solutions\antigravity-add-model-main\ag-doctor\bin\ag-doctor.js' doctor

Write-Host ''
Write-Host '(Proxy stub log: C:\Users\Admin\AppData\Local\Temp\proxy-stub.log)' -ForegroundColor DarkGray
