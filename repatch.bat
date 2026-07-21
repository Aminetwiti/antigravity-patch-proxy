@echo off
REM ============================================================
REM  repatch.bat — One-click Antigravity patch (any 2.x version)
REM ============================================================
REM  Auto-detects installed Antigravity version and applies the
REM  correct surgical patch (2.2.x, 2.3.x, ...).
REM
REM  Pipeline:
REM    1. Stop Antigravity
REM    2. npm run build (compile TS to dist/)
REM    3. Detect installed version (scripts/patch-version.js)
REM    4. Apply version-specific patcher
REM       - 2.2.x -> patch_2_2_1.js  (3 missing modules)
REM       - 2.3.x -> patch_2_3.js    (25 modules + 5 overwrites)
REM    5. ag-doctor patch apply  (binary URL redirect)
REM    6. Start MITM 443
REM    7. Launch Antigravity
REM ============================================================

setlocal EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
set "AG_INSTALL=%LOCALAPPDATA%\Programs\Antigravity"
set "AG_ASAR=%AG_INSTALL%\resources\app.asar"
set "AG_BIN_LS=%AG_INSTALL%\resources\bin\language_server.exe"
set "STAGING_DIR=%TEMP%\antigravity-asar-staging-%RANDOM%"

cd /d "%SCRIPT_DIR%"

echo.
echo ============================================================
echo  Antigravity Patch (version-agnostic)
echo ============================================================
echo.

REM -- 1. Stop Antigravity + language_server + proxy-stub
echo [1/7] Stopping Antigravity processes...
powershell -ExecutionPolicy Bypass -Command "Stop-Process -Name Antigravity, language_server -Force -ErrorAction SilentlyContinue"
powershell -ExecutionPolicy Bypass -Command "Get-Process -Name node -ErrorAction SilentlyContinue | ForEach-Object { try { $cmd = (Get-CimInstance Win32_Process -Filter 'ProcessId='+$_.Id).CommandLine; if ($cmd -like '*proxy-stub*') { $_ | Stop-Process -Force } } catch {} }"
timeout /t 2 /nobreak >nul

REM -- 2. Build TS
echo [2/7] Building TypeScript...
call npm run build
if errorlevel 1 (
  echo   [WARN] tsc build failed -- continuing with existing dist/
)

REM -- 3+4. Detect version + apply surgical patch
echo [3/7] Detecting Antigravity version + [4/7] applying patch...
if not exist "%AG_ASAR%" (
  echo   [ERROR] Antigravity not found at %AG_INSTALL%
  echo   Install Antigravity first, then run this script.
  exit /b 1
)

REM Backup before mutation
if exist "%AG_ASAR%.bak" (
  echo   Backup already exists at %AG_ASAR%.bak -- skipping
) else (
  copy /Y "%AG_ASAR%" "%AG_ASAR%.bak" >nul
  echo   Backup created: %AG_ASAR%.bak
)

node "%SCRIPT_DIR%scripts\patch-version.js" "%AG_ASAR%" "%STAGING_DIR%" "%AG_ASAR%"
if errorlevel 1 (
  echo   [ERROR] Patch failed. Restoring backup...
  copy /Y "%AG_ASAR%.bak" "%AG_ASAR%" >nul
  exit /b 1
)

REM Clean staging
if exist "%STAGING_DIR%" rmdir /S /Q "%STAGING_DIR%"

REM -- 5. Binary patch (language_server URL -> localhost:50999)
echo [5/7] Applying binary patch to language_server...
if exist "%AG_BIN_LS%" (
  echo y | node "%SCRIPT_DIR%ag-doctor\bin\ag-doctor.js" patch apply
) else (
  echo   [WARN] language_server.exe not found, skipping binary patch
)

REM -- 6. Start MITM 443 (requires admin UAC)
echo [6/7] Starting MITM on port 443 (admin required)...
powershell -ExecutionPolicy Bypass -File "%SCRIPT_DIR%scripts\mitm\start_mitm_443.ps1"
echo   (close this MITM window with Ctrl+C when done)

REM -- 7. Launch Antigravity
echo [7/7] Launching Antigravity...
if exist "%AG_INSTALL%\Antigravity.exe" (
  start "" "%AG_INSTALL%\Antigravity.exe"
) else (
  echo   [ERROR] Antigravity.exe not found at %AG_INSTALL%
)

echo.
echo ============================================================
echo  Patch complete!
echo  - Custom models now visible in Settings -> Models
echo  - MITM 443 must stay running (separate window)
echo ============================================================
echo.

endlocal