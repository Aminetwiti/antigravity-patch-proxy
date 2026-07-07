@echo off
REM Lance le MITM Antigravity HTTPS sur le port 443 (nécessite admin).
set SCRIPT=C:\Users\amine\Downloads\antigravity-add-model-main\antigravity-add-model-main\start_mitm_443.ps1
powershell -Command "Start-Process PowerShell -Verb RunAs -ArgumentList '-ExecutionPolicy Bypass -File \"%SCRIPT%\"'"
