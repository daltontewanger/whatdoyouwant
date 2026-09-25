param(
    [string]$Device = 'chrome',
    [switch]$Android,
    [switch]$Accounts,
    [string]$FlutterSdk
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
& node (Join-Path $PSScriptRoot 'check-environments.mjs')
if ($LASTEXITCODE -ne 0) { throw 'Environment preflight failed.' }
if (-not $FlutterSdk) {
    $propertiesPath = Join-Path $projectRoot 'android/local.properties'
    if (Test-Path $propertiesPath) {
        $sdkLine = Get-Content $propertiesPath | Where-Object { $_ -match '^flutter\.sdk=' } | Select-Object -First 1
        if ($sdkLine) { $FlutterSdk = $sdkLine.Substring('flutter.sdk='.Length).Replace('\\', '\').Replace('\:', ':') }
    }
}
if (-not $FlutterSdk) { throw 'Pass -FlutterSdk with your existing Flutter SDK directory.' }
$dart = Join-Path $FlutterSdk 'bin/cache/dart-sdk/bin/dart.exe'
$snapshot = Join-Path $FlutterSdk 'bin/cache/flutter_tools.snapshot'
if (-not (Test-Path $dart) -or -not (Test-Path $snapshot)) { throw 'The existing Flutter SDK cache is incomplete.' }
foreach ($port in @(9099, 8080, 5001)) {
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $connection = $client.ConnectAsync('127.0.0.1', $port)
        if (-not $connection.Wait(1500) -or -not $client.Connected) { throw 'Not listening' }
    } catch {
        $startMode = if ($Accounts) { 'preview' } else { 'start' }
        throw "Local emulator port $port is unavailable. Run: node scripts/local.mjs $startMode"
    }
    finally { $client.Dispose() }
}
$emulatorHost = if ($Android) { '10.0.2.2' } else { '127.0.0.1' }
if ($Accounts) {
    try {
        $preview = Invoke-RestMethod -Method Post -Uri 'http://127.0.0.1:5001/demo-whatdoyouwant/us-central1/phase1Status' -ContentType 'application/json' -Body '{"data":{}}' -TimeoutSec 10
        if ($preview.result.project -ne 'demo-whatdoyouwant' -or $preview.result.policy -ne 'phase1') { throw 'Wrong preview' }
    } catch { throw 'Account/room preview requires: node scripts/local.mjs preview. Stop the baseline emulators first.' }
}
$flavorArgs = if ($Android) { @('--flavor', 'local') } else { @() }
Push-Location $projectRoot
try {
    & $dart --disable-analytics $snapshot --suppress-analytics --no-version-check run --debug --no-pub -t lib/main_local.dart -d $Device "--dart-define=EMULATOR_HOST=$emulatorHost" "--dart-define=ACCOUNT_FLOW_PREVIEW=$($Accounts.IsPresent.ToString().ToLowerInvariant())" @flavorArgs
    exit $LASTEXITCODE
} finally { Pop-Location }
