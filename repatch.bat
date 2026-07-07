@echo off
echo Applying Antigravity patch...
cd /d "%~dp0"
npm run build
powershell -ExecutionPolicy Bypass -File ".\deploy.ps1"
echo.
echo Patch applied successfully! Antigravity has been restarted.
pause
