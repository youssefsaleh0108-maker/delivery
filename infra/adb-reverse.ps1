# Forwards the Android device's loopback to this machine's, so the mobile app can use the same
# 127.0.0.1 addresses as the web portals.
#
# Run this AFTER the emulator (or USB device) is booted, and again after every reboot or reconnect -
# adb reverse mappings do not survive either.
#
# Why this instead of 10.0.2.2: Keycloak stamps exactly ONE issuer into every token. If the mobile
# app used 10.0.2.2 and the browser used 127.0.0.1, one of them would always be holding a token the
# backend rejects. Reverse-forwarding gives every client one address that works.

$ErrorActionPreference = 'Stop'

$adb = Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'
if (-not (Test-Path $adb)) {
    Write-Error "adb not found at $adb - install Android SDK platform-tools."
}

$devices = & $adb devices | Select-Object -Skip 1 | Where-Object { $_ -match '\tdevice$' }
if (-not $devices) {
    Write-Error 'No device or emulator attached. Start the emulator first, then re-run this.'
}

# 8100 API Gateway, 8180 Keycloak, 9010 MinIO (product images load directly from presigned URLs).
foreach ($port in 8100, 8180, 9010) {
    & $adb reverse "tcp:$port" "tcp:$port" | Out-Null
    Write-Host "  device 127.0.0.1:$port -> host 127.0.0.1:$port"
}

Write-Host ''
Write-Host 'Active reverse mappings:'
& $adb reverse --list
