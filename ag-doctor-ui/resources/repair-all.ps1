#Requires -Version 5.1
<#
.SYNOPSIS
    Self-elevating repair script that fixes the WinHTTP proxy and installs the CA.
#>
$ErrorActionPreference = "Stop"

# Self-elevation check
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $IsAdmin) {
    Write-Host "Elevating privileges to repair proxy and CA..."
    $Args = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    Start-Process powershell -Verb RunAs -ArgumentList $Args -Wait
    exit $LASTEXITCODE
}

Write-Host "Running as Administrator."
$Result = @{
    proxy = $false
    ca = $false
}

# 1. Set WinHTTP Proxy (port 51999 for the ag-doctor-ui stub proxy,
#    NOT 50999 which is reserved for the main Antigravity proxy)
Write-Host "Setting WinHTTP proxy to 127.0.0.1:51999..."
try {
    netsh winhttp set proxy proxy-server="127.0.0.1:51999" | Out-Null
    $Result.proxy = $true
    Write-Host "WinHTTP proxy set successfully." -ForegroundColor Green
} catch {
    Write-Host "Failed to set WinHTTP proxy: $_" -ForegroundColor Red
}

# 2. Install CA Cert
# We need to find the CA cert. It should be in the user's .gemini/antigravity/certs/ folder.
$CaCert = "$env:USERPROFILE\.gemini\antigravity\certs\ca-cert.pem"
if (Test-Path $CaCert) {
    Write-Host "Installing CA certificate from $CaCert..."
    try {
        certutil -addstore -f ROOT "$CaCert" | Out-Null
        $Result.ca = $true
        Write-Host "CA certificate installed successfully." -ForegroundColor Green
    } catch {
        Write-Host "Failed to install CA certificate: $_" -ForegroundColor Red
    }
} else {
    Write-Host "CA certificate not found at $CaCert. Run 'ag-doctor mitm install' first to generate it." -ForegroundColor Yellow
}

# Write result to temp file for UI to read
$ResultJson = $Result | ConvertTo-Json -Compress
$TempFile = "$env:TEMP\ag-repair-result.json"
Set-Content -Path $TempFile -Value $ResultJson

Write-Host "Repair complete. You can close this window."
Start-Sleep -Seconds 2
