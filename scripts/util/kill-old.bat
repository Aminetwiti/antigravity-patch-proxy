@echo off
REM Kill any process holding port 50999 (no hardcoded PID).
set PORT=50999
for /f "tokens=5" %%P in ('netstat -ano ^| findstr /R "[: ]%PORT% .*LISTENING"') do (
  echo Killing PID %%P on %PORT%
  taskkill /F /T /PID %%P
)
echo DONE > "%TEMP%\kill-done.txt"