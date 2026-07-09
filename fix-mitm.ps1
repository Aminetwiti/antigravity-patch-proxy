$ErrorActionPreference = 'Continue'
Write-Host '== Setting system proxy to 127.0.0.1:50999 ==' -ForegroundColor Cyan
try {
  netsh winhttp set proxy proxy-server="127.0.0.1:50999" | Out-String | Write-Host
  Write-Host 'OK: netsh winhttp set proxy succeeded' -ForegroundColor Green
} catch {
  Write-Host "FAIL: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ''
Write-Host '== Current WinHTTP proxy ==' -ForegroundColor Cyan
netsh winhttp show proxy | Out-String | Write-Host

Write-Host ''
Write-Host '== Re-running ag-doctor doctor ==' -ForegroundColor Cyan
node 'C:\Business\tools\solutions\antigravity-add-model-main\ag-doctor\bin\ag-doctor.js' doctor

Read-Host 'Press Enter to close'
