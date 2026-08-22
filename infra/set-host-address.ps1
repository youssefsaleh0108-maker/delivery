# Points the whole stack at one host address and restarts what needs to change.
#
# WHY THIS EXISTS: Keycloak stamps exactly ONE issuer into every token, and MinIO signs presigned
# URLs against one endpoint. Both must be an address the CLIENT can reach. A LAN IP is the only
# thing a physical phone can use - and DHCP moves it, which has already broken sign-in twice with a
# symptom (a long hang, then "site cannot be reached") that looks nothing like its cause.
#
# Run this whenever the machine's IP changes, or to switch between device and browser-only testing.
#
#   .\set-host-address.ps1              # auto-detect the current Wi-Fi IP (for phone testing)
#   .\set-host-address.ps1 -Loopback    # 127.0.0.1 (browser only, immune to DHCP and firewall)
#   .\set-host-address.ps1 -Address 192.168.1.50

[CmdletBinding()]
param(
    [string]$Address,
    [switch]$Loopback
)

$ErrorActionPreference = 'Stop'
$infra = $PSScriptRoot
$repo = Split-Path $infra -Parent

if ($Loopback) {
    $Address = '127.0.0.1'
} elseif (-not $Address) {
    $Address = (Get-NetIPAddress -AddressFamily IPv4 |
        Where-Object { $_.InterfaceAlias -eq 'Wi-Fi' -and $_.IPAddress -notlike '169.254.*' } |
        Select-Object -First 1).IPAddress
    if (-not $Address) { Write-Error 'Could not auto-detect a Wi-Fi IPv4 address. Pass -Address.' }
}

Write-Host "Host address -> $Address" -ForegroundColor Cyan

# ---- infra/.env -------------------------------------------------------------------------------
$envFile = Join-Path $infra '.env'
$lines = Get-Content $envFile |
    Where-Object { $_ -notmatch '^(KEYCLOAK_PUBLIC_URL|MINIO_PUBLIC_ENDPOINT|CORS_ALLOWED_ORIGINS)=' }
$lines += "KEYCLOAK_PUBLIC_URL=http://${Address}:8180"
$lines += "MINIO_PUBLIC_ENDPOINT=http://${Address}:9010"
# The browser treats localhost, 127.0.0.1 and the LAN IP as three different origins, so all three
# are allowed - otherwise opening a portal on the "wrong" one fails every API call with what looks
# like a network error.
$lines += "CORS_ALLOWED_ORIGINS=http://localhost:*,http://127.0.0.1:*,http://${Address}:*"
Set-Content $envFile $lines -Encoding ascii
Write-Host '  updated infra/.env'

# ---- Keycloak redirect URIs -------------------------------------------------------------------
# Keycloak matches redirect URIs against an allow-list and its wildcards only work at the END of a
# URI, so each host has to be listed explicitly. 127.0.0.1 and localhost stay registered so the
# browser keeps working regardless of which address the stack is currently issuing for.
$kcAdmin = 'http://keycloak:8080'
$curl = 'curlimages/curl:latest'
$token = (docker run --rm --network delivery $curl -s -X POST `
    "$kcAdmin/realms/master/protocol/openid-connect/token" `
    -d 'client_id=admin-cli' -d 'username=admin' -d 'password=admin' -d 'grant_type=password' |
    ConvertFrom-Json).access_token

$clients = @(
    @{ id = 'merchant-portal'; uris = @("http://127.0.0.1:5010/*", "http://localhost:5010/*", "http://${Address}:5010/*") },
    @{ id = 'backoffice-web';  uris = @("http://127.0.0.1:5011/*", "http://localhost:5011/*", "http://${Address}:5011/*") },
    @{ id = 'mobile-app';      uris = @('com.delivery.app://oauth2redirect', 'com.delivery.app://oauth2redirect/*', "http://127.0.0.1:5012/*", "http://localhost:5012/*", "http://${Address}:5012/*") }
)

foreach ($c in $clients) {
    $raw = docker run --rm --network delivery $curl -s `
        "$kcAdmin/admin/realms/delivery-platform/clients?clientId=$($c.id)" `
        -H "Authorization: Bearer $token"
    $obj = @($raw | ConvertFrom-Json)[0]
    if (-not $obj) { Write-Warning "  client $($c.id) not found"; continue }

    # Rebuilt rather than mutated: PowerShell 5.1 member-enumeration makes in-place assignment on a
    # ConvertFrom-Json object silently fail.
    $obj.PSObject.Properties.Remove('redirectUris')
    $obj | Add-Member -NotePropertyName redirectUris -NotePropertyValue ([string[]]$c.uris) -Force

    $tmp = Join-Path $env:TEMP 'kc-client.json'
    ($obj | ConvertTo-Json -Depth 25 -Compress) | Set-Content $tmp -Encoding utf8 -NoNewline
    docker run --rm --network delivery -v "${tmp}:/c.json:ro" $curl -s -o /dev/null `
        -X PUT "$kcAdmin/admin/realms/delivery-platform/clients/$($obj.id)" `
        -H "Authorization: Bearer $token" -H 'Content-Type: application/json' -d '@/c.json' | Out-Null
    Write-Host "  registered redirect URIs for $($c.id)"
}

# ---- restart what bakes the address in ---------------------------------------------------------
# EVERY service validates the `iss` claim against KEYCLOAK_ISSUER_URI, so every service has to be
# recreated - not just the ones that route or issue. Restarting a subset leaves the others rejecting
# every freshly minted token with a 401, which surfaces as a screen that never loads rather than as
# an addressing error. Learned the hard way: Connector Settings broke because connector-settings and
# notifications-manager were missing from this list.
$services = @(
    'product-service', 'order-manager', 'order-tracking',
    'notifications-manager', 'connector-settings', 'app-notification', 'accounting-service',
    'mail-worker', 'push-worker', 'sms-worker',
    'email-connector', 'sms-connector', 'push-connector',
    'corebanking-connector', 'corebanking-simulator',
    'whatsapp-service', 'onboarding-service'
)
Push-Location $infra
# docker compose writes progress to stderr, which Windows PowerShell 5.1 turns into a terminating
# NativeCommandError even on a successful run. Relaxing the preference around the call is the only
# reliable way to let it complete.
$previous = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
docker compose up -d --force-recreate keycloak @services *>&1 | Out-Null
$ErrorActionPreference = $previous
Pop-Location
Write-Host '  recreated keycloak + services'

Write-Host ''
Write-Host 'Flutter clients must use the same address. For Android Studio:' -ForegroundColor Yellow
Write-Host "  Run > Edit Configurations > Additional run args:"
Write-Host "  --dart-define=API_BASE_URL=http://${Address}:8100 --dart-define=KEYCLOAK_ISSUER=http://${Address}:8180/realms/delivery-platform"
Write-Host ''
if ($Address -ne '127.0.0.1') {
    Write-Host 'A physical device also needs:' -ForegroundColor Yellow
    Write-Host "  1. $Address added to clients/apps/mobile_app/android/app/src/main/res/xml/network_security_config.xml"
    Write-Host '  2. An inbound firewall rule (elevated PowerShell), scoped to your network profile:'
    Write-Host '     New-NetFirewallRule -DisplayName "Delivery dev stack" -Direction Inbound -Action Allow -Protocol TCP -LocalPort 8100,8180,9010 -Profile Any'
    Write-Host ''
    Write-Host '  Rebuild the web portals so they use this issuer too:'
    Write-Host "     cd clients/apps/merchant_portal; flutter build web --release --dart-define=KEYCLOAK_ISSUER=http://${Address}:8180/realms/delivery-platform"
}
