# Antigravity Model Support Patch Repack & Deploy Script

Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "Stopping all running Antigravity processes..." -ForegroundColor Yellow
Write-Host "==============================================" -ForegroundColor Cyan

# Terminate running app and language server processes
Stop-Process -Name "Antigravity" -Force -ErrorAction SilentlyContinue
Stop-Process -Name "language_server" -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "Repacking app.asar package..." -ForegroundColor Yellow
Write-Host "==============================================" -ForegroundColor Cyan

# Define source and destination paths (portable — uses LOCALAPPDATA)
# NOTE: this repack targets the CLASSIC 2.x shell (app.asar merge). The
# VS Code-based "Antigravity IDE" has no app.asar — it is patched via the
# jetski.cloudCodeUrl settings override (see ag-doctor/src/core/ide-patch.ts).
$SourceDir = Resolve-Path "$PSScriptRoot\..\.."
$DestAsar = "$env:LOCALAPPDATA\Programs\antigravity\resources\app.asar"

if (-not (Test-Path $SourceDir)) {
    Write-Host "==============================================" -ForegroundColor Red
    Write-Host "Error: Source directory not found at $SourceDir" -ForegroundColor Red
    Write-Host "==============================================" -ForegroundColor Red
    exit 1
}

# Remove transient build junk that must never reach the asar
# (a stray nested dist/dist or dist/__mocks__ bricked the app on 2026-07-11).
$JunkTargets = @(
  (Join-Path $SourceDir "dist\dist"),
  (Join-Path $SourceDir "dist\node_modules"),
  (Join-Path $SourceDir "dist\__mocks__")
)
foreach ($Junk in $JunkTargets) {
  if (Test-Path $Junk) {
    Write-Host "Removing build junk: $Junk" -ForegroundColor DarkYellow
    Remove-Item -Recurse -Force $Junk -ErrorAction SilentlyContinue
  }
}

# Repack using @electron/asar (excluding large/unnecessary directories)
$AsarBin = Join-Path $SourceDir "node_modules\@electron\asar\bin\asar.js"
if (Test-Path $AsarBin) {
    node $AsarBin pack $SourceDir $DestAsar --unpack-dir "{node_modules,scratch,.git}"
} else {
    npx -y @electron/asar pack $SourceDir $DestAsar --unpack-dir "{node_modules,scratch,.git}"
}

if ($LASTEXITCODE -eq 0) {
    Write-Host "==============================================" -ForegroundColor Cyan
    Write-Host "Success! app.asar repacked successfully." -ForegroundColor Green
    Write-Host "Restarting Antigravity..." -ForegroundColor Yellow
    Write-Host "==============================================" -ForegroundColor Cyan

    $ExePath = "$env:LOCALAPPDATA\Programs\antigravity\Antigravity.exe"
    if (Test-Path $ExePath) {
        Start-Process -FilePath $ExePath
    } else {
        Write-Host "Warning: Antigravity.exe not found at $ExePath" -ForegroundColor Yellow
        Write-Host "Please restart Antigravity manually." -ForegroundColor Yellow
    }
} else {
    Write-Host "==============================================" -ForegroundColor Red
    Write-Host "Error: Repacking failed!" -ForegroundColor Red
    Write-Host "==============================================" -ForegroundColor Red
    exit 1
}
