@echo off
echo Applying Antigravity patch (one-click fix)...
cd /d "%~dp0"
powershell -ExecutionPolicy Bypass -File ".\fix-all.ps1"
