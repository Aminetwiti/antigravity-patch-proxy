$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
Write-Output "=== reverse ==="
& $adb -s emulator-5554 reverse tcp:8090 tcp:8090 2>&1
Write-Output "=== install ==="
& $adb -s emulator-5554 install -r remote\mobile\build\app\outputs\flutter-apk\app-debug.apk 2>&1
Write-Output "=== launch ==="
& $adb -s emulator-5554 shell am start -n com.antigravity.remote.mobile/.MainActivity 2>&1
Write-Output "=== done ==="
