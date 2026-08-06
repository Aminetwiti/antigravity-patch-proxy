$ErrorActionPreference = 'Continue'
Write-Host '== Setting netsh winhttp proxy ==' -ForegroundColor Cyan
netsh winhttp set proxy proxy-server="127.0.0.1:50999" | Out-String | Write-Host
Write-Host '-- Current --' -ForegroundColor Cyan
netsh winhttp show proxy | Out-String | Write-Host
Write-Host 'DONE' -ForegroundColor Green
Read-Host 'Enter'
