param(
    [string]$Device,
    [switch]$Android,
    [int]$WebPort = 5080,
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
# flutter.bat passes the tool's own package map; web runs crash without it.
$toolPackages = Join-Path $FlutterSdk 'packages/flutter_tools/.dart_tool/package_config.json'
if (-not (Test-Path $dart) -or -not (Test-Path $snapshot) -or -not (Test-Path $toolPackages)) {
    throw 'The existing Flutter SDK cache is incomplete.'
}
foreach ($port in @(9099, 8080, 5001)) {
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $connection = $client.ConnectAsync('127.0.0.1', $port)
        if (-not $connection.Wait(1500) -or -not $client.Connected) { throw 'Not listening' }
    } catch {
        throw "Local emulator port $port is unavailable. Run: node scripts/local.mjs preview"
    }
    finally { $client.Dispose() }
}
$emulatorHost = if ($Android) { '10.0.2.2' } else { '127.0.0.1' }
# The app uses the room callables.
try {
    $preview = Invoke-RestMethod -Method Post -Uri 'http://127.0.0.1:5001/demo-whatdoyouwant/us-central1/roomsStatus' -ContentType 'application/json' -Body '{"data":{}}' -TimeoutSec 10
    if ($preview.result.project -ne 'demo-whatdoyouwant' -or $preview.result.policy -ne 'rooms') { throw 'Wrong preview' }
} catch { throw 'The local app needs the room emulators: node scripts/local.mjs preview. Stop the baseline emulators first.' }
if (-not $Device) {
    if ($Android) { throw 'Pass -Device with the emulator or device ID shown by adb devices.' }
    $Device = 'web-server'
}
$flavorArgs = if ($Android) { @('--flavor', 'local') } else { @() }
$webArgs = @()
if ($Device -eq 'web-server') {
    if (Get-NetTCPConnection -State Listen -LocalPort $WebPort -ErrorAction SilentlyContinue) {
        throw "Port $WebPort is already in use. Stop the other server or pass -WebPort."
    }
    $webArgs = @('--web-hostname', 'localhost', '--web-port', "$WebPort")
    # Flutter's own Chrome launch fails intermittently on this machine, so serve the app and
    # open it in the default browser. A fixed origin also keeps the signed-in session between runs.
    $url = "http://localhost:$WebPort/whatdoyouwant/"
    Start-Job -ArgumentList $url -ScriptBlock {
        param($target)
        # The page is served before the app finishes compiling; until then the app's
        # entrypoint script comes back as the HTML page, and opening early shows a blank tab.
        for ($i = 0; $i -lt 300; $i++) {
            try {
                $entry = Invoke-WebRequest -Uri ($target + 'web_entrypoint.dart.js') -UseBasicParsing -TimeoutSec 2
                if ($entry.Headers['Content-Type'] -match 'javascript') {
                    Start-Process $target
                    return
                }
            } catch { }
            Start-Sleep -Seconds 1
        }
    } | Out-Null
    Write-Output "Opening $url once it is ready. Use a private window for a second, separate user."
}
Push-Location $projectRoot
try {
    & $dart "--packages=$toolPackages" $snapshot --suppress-analytics --no-version-check run --debug --no-pub -t lib/main_local.dart -d $Device "--dart-define=EMULATOR_HOST=$emulatorHost" @flavorArgs @webArgs
    exit $LASTEXITCODE
} finally { Pop-Location }
