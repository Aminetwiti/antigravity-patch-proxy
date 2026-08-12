@echo off
REM ============================================================
REM  repatch.bat — One-click Antigravity patch (any version)
REM ============================================================
REM  Auto-detects the installed product and applies the correct
REM  patch:
REM
REM    A) Antigravity IDE (v1.107.0+, VS Code-based)
REM         - settings override: jetski.cloudCodeUrl -> localhost:50999
REM         - starts the local proxy (real proxy via bundled Electron)
REM
REM    B) Classic Antigravity (2.x shell)
REM         - version-aware asar surgery (2.2.x / 2.3.x / ...)
REM         - binary patch: language_server URL -> localhost:50999
REM         - optional MITM 443 (admin)
REM
REM  Pipeline:
REM    1. Stop Antigravity processes
REM    2. npm run build (compile TS to dist/)
REM    3. ag-doctor patch apply  (binary + IDE override, auto-detected)
REM    4. ag-doctor proxy start  (real proxy; stub fallback)
REM    5. Launch the detected app
REM ============================================================

setlocal EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
set "AG_IDE=%LOCALAPPDATA%\Programs\Antigravity IDE"
set "AG_CLASSIC=%LOCALAPPDATA%\Programs\Antigravity"
set "AG_IDE_EXE=%AG_IDE%\Antigravity IDE.exe"
set "AG_CLASSIC_EXE=%AG_CLASSIC%\Antigravity.exe"

cd /d "%SCRIPT_DIR%"

echo.
echo ============================================================
echo  Antigravity Patch (one-click, version-agnostic)
echo ============================================================
echo.

REM -- 1. Stop Antigravity + language servers + proxy-stub
echo [1/5] Stopping Antigravity processes...
powershell -ExecutionPolicy Bypass -Command "Stop-Process -Name 'Antigravity IDE', Antigravity, language_server, language_server_windows_x64 -Force -ErrorAction SilentlyContinue"
powershell -ExecutionPolicy Bypass -Command "Get-Process -Name node -ErrorAction SilentlyContinue | ForEach-Object { try { $cmd = (Get-CimInstance Win32_Process -Filter 'ProcessId='+$_.Id).CommandLine; if ($cmd -like '*proxy-stub*' -or $cmd -like '*standalone-proxy-runner*') { $_ | Stop-Process -Force } } catch {} }"
timeout /t 2 /nobreak >nul

REM -- 2. Build TS
echo [2/5] Building TypeScript...
call npm run build
if errorlevel 1 (
  echo   [WARN] tsc build failed -- continuing with existing dist/
)

REM -- 3. Detect target install
echo [3/5] Detecting Antigravity installation...
set "TARGET=CLASSIC"
if exist "%AG_IDE_EXE%" (
  set "TARGET=IDE"
  echo   Found Antigravity IDE: %AG_IDE%
) else if exist "%AG_CLASSIC_EXE%" (
  echo   Found classic Antigravity: %AG_CLASSIC%
) else (
  echo   [ERROR] No Antigravity installation found.
  echo   Looked for:
  echo     - %AG_IDE_EXE%
  echo     - %AG_CLASSIC_EXE%
  exit /b 1
)

if "%TARGET%"=="CLASSIC" goto classic_path
goto common_patch

REM ------------------------------------------------------------
REM  Classic path: asar overlay surgery (patch-version.js) +
REM  binary patch. The overlay injects dist/ + proxy-runner.js
REM  into app.asar; without it the classic shell has no proxy.
REM ------------------------------------------------------------
:classic_path
set "AG_ASAR=%AG_CLASSIC%\resources\app.asar"
if not exist "%AG_ASAR%" (
  echo   [ERROR] app.asar not found at %AG_ASAR%
  exit /b 1
)
echo [3b/5] Backing up and applying asar overlay...
set "STAGING_DIR=%TEMP%\antigravity-asar-staging-%RANDOM%"
if exist "%AG_ASAR%.bak" (
  echo   Backup already exists at %AG_ASAR%.bak -- skipping
) else (
  copy /Y "%AG_ASAR%" "%AG_ASAR%.bak" >nul
  echo   Backup created: %AG_ASAR%.bak
  if exist "%AG_ASAR%.unpacked" (
    if not exist "%AG_ASAR%.bak.unpacked" (
      xcopy /E /I /H /Y "%AG_ASAR%.unpacked" "%AG_ASAR%.bak.unpacked" >nul
      echo   Backup created: %AG_ASAR%.bak.unpacked
    )
  )
)
node "%SCRIPT_DIR%scripts\patch-version.js" "%AG_ASAR%.bak" "%STAGING_DIR%" "%AG_ASAR%"
if errorlevel 1 (
  echo   [ERROR] Asar overlay failed. Restoring backup...
  copy /Y "%AG_ASAR%.bak" "%AG_ASAR%" >nul
  exit /b 1
)
if exist "%STAGING_DIR%" rmdir /S /Q "%STAGING_DIR%"
echo   Asar overlay applied.

REM ------------------------------------------------------------
REM  Common path: binary patch (+ IDE override) + proxy + launch
REM ------------------------------------------------------------
:common_patch
echo [4/5] Applying patch (ag-doctor patch apply)...
node "%SCRIPT_DIR%ag-doctor\bin\ag-doctor.js" patch apply --yes
if errorlevel 1 (
  echo   [ERROR] Patch failed. Re-run ag-doctor repair to recover.
  exit /b 1
)

REM -- 5. Start the local proxy (real proxy via bundled Electron; stub fallback)
echo [5/5] Starting local proxy on port 50999...
node "%SCRIPT_DIR%ag-doctor\bin\ag-doctor.js" proxy start
if errorlevel 1 (
  echo   [WARN] Proxy did not start cleanly -- models may not be injected.
)

REM -- Launch the detected app
echo.
echo ============================================================
if "%TARGET%"=="IDE" (
  echo  Launching Antigravity IDE...
  start "" "%AG_IDE_EXE%"
) else (
  echo  Launching Antigravity (classic)...
  start "" "%AG_CLASSIC_EXE%"
)
echo.
echo  Patch complete!
echo  - Custom models now route through the local proxy (port 50999)
echo  - Verify with:  ag-doctor doctor
echo ============================================================
echo.

endlocal
