Stop-Process -Name Antigravity,language_server -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3
$remaining = Get-Process -Name Antigravity,language_server -ErrorAction SilentlyContinue
if ($remaining) {
  Write-Host "Remaining processes:"
  $remaining | Select-Object Name,Id | Format-Table | Out-String | Write-Host
} else {
  Write-Host "All stopped."
}
