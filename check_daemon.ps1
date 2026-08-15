$l = Get-NetTCPConnection -LocalPort 8090 -State Listen -ErrorAction SilentlyContinue
if ($l) {
    $owner = ($l | Select-Object -First 1).OwningProcess
    $p = Get-CimInstance Win32_Process -Filter "ProcessId=$owner"
    Write-Host "PID=$owner Name=$($p.Name)"
    Write-Host "Cmd=$($p.CommandLine)"
    $exeTime = (Get-Item $p.ExecutablePath -ErrorAction SilentlyContinue).LastWriteTime
    Write-Host "ExeLastWrite=$exeTime"
} else {
    Write-Host 'NO LISTENER'
}
