$ErrorActionPreference = 'Continue'
try {
  $p = Start-Process powershell -Verb RunAs -Wait -PassThru -ArgumentList @(
    '-NoProfile',
    '-File',
    'C:\Business\tools\solutions\antigravity-add-model-main\fix-all.ps1'
  )
  Write-Host "Elevated process exit code: $($p.ExitCode)" -ForegroundColor Yellow
} catch {
  Write-Host "Error launching elevated process: $($_.Exception.Message)" -ForegroundColor Red
}
Read-Host 'Press Enter to close'
