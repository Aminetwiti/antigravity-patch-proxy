@echo off
set ADB="%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe"
echo === reverse ===
%ADB% -s emulator-5554 reverse tcp:8090 tcp:8090
echo === install ===
%ADB% -s emulator-5554 install -r remote\mobile\build\app\outputs\flutter-apk\app-debug.apk
echo === launch ===
%ADB% -s emulator-5554 shell am start -n com.antigravity.remote.mobile/.MainActivity
echo === done ===
