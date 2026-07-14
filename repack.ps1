# repack.ps1 - Antigravity Model Support Patch - Repack & Deploy
#
# Creates a CLEAN staging directory with only the files the Electron app needs,
# then packs it into app.asar. Packing the entire project root (including .git,
# ag-doctor, tools, dev node_modules) produces a broken ~500MB asar that crashes
# on startup. The staging approach produces a working ~20MB asar.
param(
    [switch]$SkipBuild,
    [switch]$SkipRestart,
    [switch]$NoPause
)

$ErrorActionPreference = "Stop"
$SourceDir = $PSScriptRoot
$StagingDir = Join-Path $env:LOCALAPPDATA "Temp\antigravity-asar-staging"
$DestAsar = Join-Path $env:LOCALAPPDATA "Programs\antigravity\resources\app.asar"
$AntigravityExe = Join-Path $env:LOCALAPPDATA "Programs\antigravity\Antigravity.exe"

function Write-Step($msg) { Write-Host "`n== $msg ==" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "  [OK] $msg" -ForegroundColor Green }
function Write-Err($msg)  { Write-Host "  [ERROR] $msg" -ForegroundColor Red }

# -- 1. Stop everything
Write-Step "Stopping Antigravity, language_server, and proxy-stub"
Stop-Process -Name "Antigravity"   -Force -ErrorAction SilentlyContinue
Stop-Process -Name "language_server" -Force -ErrorAction SilentlyContinue
Get-Process -Name "node" -ErrorAction SilentlyContinue | ForEach-Object {
    try {
        $cmd = (Get-CimInstance Win32_Process -Filter "ProcessId=$($_.Id)").CommandLine
        if ($cmd -like "*proxy-stub*") {
            Write-Host "  Killing proxy-stub (PID $($_.Id))" -ForegroundColor Yellow
            $_ | Stop-Process -Force
        }
    } catch {}
}
Start-Sleep -Seconds 2
$busy = Get-NetTCPConnection -LocalPort 50999 -ErrorAction SilentlyContinue
if ($busy) { Write-Err "Port 50999 still occupied by PID $($busy.OwningProcess)" } else { Write-Ok "Port 50999 is free" }

# -- 2. TypeScript build (optional)
if (-not $SkipBuild) {
    Write-Step "Building TypeScript"
    Push-Location $SourceDir
    try {
        $tsc = Join-Path $SourceDir "node_modules\.bin\tsc"
        if (-not (Test-Path $tsc)) { $tsc = "tsc" }
        & $tsc -p tsconfig.json 2>&1 | Select-Object -Last 20
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  [WARN] tsc build failed -- using existing dist/" -ForegroundColor Yellow
        } else {
            Write-Ok "TypeScript compiled"
        }
    } catch {
        Write-Host "  [WARN] tsc not found -- using existing dist/" -ForegroundColor Yellow
    } finally {
        Pop-Location
    }
}

# -- 3. Verify dist/ has the proxy module
Write-Step "Verifying dist/ contains proxy module"
$requiredFiles = @("dist\main.js", "dist\proxy.js", "dist\proxy\modelLoader.js")
$missing = @()
foreach ($f in $requiredFiles) {
    if (-not (Test-Path (Join-Path $SourceDir $f))) { $missing += $f }
}
if ($missing.Count -gt 0) {
    Write-Err "Missing critical files: $($missing -join ', ')"
    Write-Host "  Run 'tsc -p tsconfig.json' first." -ForegroundColor Red
    exit 1
}
Write-Ok "dist/main.js, dist/proxy.js, dist/proxy/modelLoader.js all present"

# -- 4. Build clean staging directory
Write-Step "Building clean staging directory"
if (Test-Path $StagingDir) { Remove-Item $StagingDir -Recurse -Force }
New-Item -ItemType Directory -Path $StagingDir | Out-Null

Copy-Item (Join-Path $SourceDir "package.json") $StagingDir
Copy-Item (Join-Path $SourceDir "dist") (Join-Path $StagingDir "dist") -Recurse

$htmlDir = Join-Path $SourceDir "html"
if (Test-Path $htmlDir) {
    Copy-Item $htmlDir (Join-Path $StagingDir "html") -Recurse
}

$tray = Join-Path $SourceDir "trayTemplate.png"
$tray2x = Join-Path $SourceDir "trayTemplate@2x.png"
if (Test-Path $tray)   { Copy-Item $tray $StagingDir }
if (Test-Path $tray2x) { Copy-Item $tray2x $StagingDir }

Push-Location $StagingDir
try {
    npm install --omit=dev 2>&1 | Select-Object -Last 5
    if ($LASTEXITCODE -ne 0) {
        Write-Err "npm install --omit=dev failed"
        exit 1
    }
} finally {
    Pop-Location
}
$depCount = (Get-ChildItem (Join-Path $StagingDir "node_modules") -Directory -ErrorAction SilentlyContinue).Count
Write-Ok "Staging directory ready ($depCount production modules)"

# -- 5. Pack asar
Write-Step "Packing app.asar"
& npx -y @electron/asar pack $StagingDir $DestAsar --unpack-dir "{node_modules}"
if ($LASTEXITCODE -ne 0) {
    Write-Err "asar pack failed"
    exit 1
}
$sizeMB = [math]::Round((Get-Item $DestAsar).Length / 1MB, 1)
Write-Ok "app.asar packed (${sizeMB}MB)"

# -- 6. Verify asar contents
Write-Step "Verifying asar contents"
$entries = & npx -y @electron/asar list $DestAsar 2>&1
$hasProxy  = ($entries | Select-String "dist\\proxy\.js").Count -gt 0
$hasLoader = ($entries | Select-String "dist\\proxy\\modelLoader\.js").Count -gt 0
$hasMain   = ($entries | Select-String "\\main\.js").Count -gt 0
if ($hasProxy -and $hasLoader -and $hasMain) {
    Write-Ok "asar contains proxy.js, modelLoader.js, main.js"
} else {
    Write-Err "asar missing critical modules (proxy=$hasProxy loader=$hasLoader main=$hasMain)"
    exit 1
}

# -- 7. Clean up staging
Remove-Item $StagingDir -Recurse -Force -ErrorAction SilentlyContinue

# -- 8. Restart Antigravity
if (-not $SkipRestart) {
    Write-Step "Restarting Antigravity"
    if (Test-Path $AntigravityExe) {
        Start-Process -FilePath $AntigravityExe
        Write-Ok "Antigravity launched"
    } else {
        Write-Host "  [WARN] Antigravity.exe not found at $AntigravityExe" -ForegroundColor Yellow
    }
}

Write-Host "`n== Done ==" -ForegroundColor Green
Write-Host "  Custom models will appear in the chat model dropdown." -ForegroundColor Gray
if (-not $NoPause) { Read-Host "Press Enter to close" }
