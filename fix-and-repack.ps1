#Requires -RunAsAdministrator
<#
  Safe Antigravity repack script.
  - Restores app.asar from the original backup created by deploy.ps1.
  - Replaces dist/ with the freshly built dist/ from this repo.
  - Repacks app.asar and restarts Antigravity.
#>

$ErrorActionPreference = "Stop"

$RepoDir = "C:\Users\amine\Downloads\antigravity-add-model-main\antigravity-add-model-main"
$AsarPath = "$env:LOCALAPPDATA\Programs\antigravity\resources\app.asar"
$BackupAsar = "$AsarPath.backup"
$TempDir = Join-Path $env:TEMP "antigravity_fix_repack"

Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "Stopping Antigravity..." -ForegroundColor Yellow
Write-Host "==============================================" -ForegroundColor Cyan
Stop-Process -Name "Antigravity" -Force -ErrorAction SilentlyContinue
Stop-Process -Name "language_server" -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

if (-not (Test-Path $BackupAsar)) {
    Write-Host "ERROR: Backup not found: $BackupAsar" -ForegroundColor Red
    Write-Host "You must restore app.asar manually or reinstall Antigravity." -ForegroundColor Red
    exit 1
}

Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "Restoring original app.asar from backup..." -ForegroundColor Yellow
Write-Host "==============================================" -ForegroundColor Cyan
Copy-Item $BackupAsar $AsarPath -Force

Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "Extracting app.asar..." -ForegroundColor Yellow
Write-Host "==============================================" -ForegroundColor Cyan
if (Test-Path $TempDir) { Remove-Item $TempDir -Recurse -Force }
$env:NODE_OPTIONS = "--max-old-space-size=4096"
npx -y @electron/asar extract $AsarPath $TempDir
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to extract app.asar" -ForegroundColor Red
    exit 1
}

Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "Updating dist/ with freshly built files..." -ForegroundColor Yellow
Write-Host "==============================================" -ForegroundColor Cyan
$SrcDist = Join-Path $RepoDir "dist"
$DestDist = Join-Path $TempDir "dist"
if (-not (Test-Path $SrcDist)) {
    Write-Host "ERROR: dist/ not found at $SrcDist. Run 'npm run build' first." -ForegroundColor Red
    exit 1
}
if (Test-Path $DestDist) { Remove-Item $DestDist -Recurse -Force }
Copy-Item $SrcDist $DestDist -Recurse -Force

Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "Repacking app.asar..." -ForegroundColor Yellow
Write-Host "==============================================" -ForegroundColor Cyan
$UnpackedDir = "$AsarPath.unpacked"
if (Test-Path $UnpackedDir) { Remove-Item $UnpackedDir -Recurse -Force }
npx -y @electron/asar pack $TempDir $AsarPath --unpack-dir "node_modules"
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to repack app.asar" -ForegroundColor Red
    Copy-Item $BackupAsar $AsarPath -Force
    exit 1
}

Remove-Item $TempDir -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "Starting Antigravity..." -ForegroundColor Yellow
Write-Host "==============================================" -ForegroundColor Cyan
$ExePath = "$env:LOCALAPPDATA\Programs\antigravity\Antigravity.exe"
if (Test-Path $ExePath) {
    Start-Process -FilePath $ExePath
    Write-Host "Done! Antigravity should open now." -ForegroundColor Green
} else {
    Write-Host "Warning: Antigravity.exe not found at $ExePath" -ForegroundColor Yellow
}
