param(
    [string]$Device = 'chrome',
    [switch]$Android,
    [string]$FlutterSdk
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
& node (Join-Path $PSScriptRoot 'check-environments.mjs')
if ($LASTEXITCODE -ne 0) { throw 'Environment preflight failed.' }
if (-not $FlutterSdk) {
    $sdkLine = Get-Content (Join-Path $projectRoot 'android/local.properties') |
        Where-Object { $_ -match '^flutter\.sdk=' } | Select-Object -First 1
    if ($sdkLine) { $FlutterSdk = $sdkLine.Substring('flutter.sdk='.Length).Replace('\\', '\').Replace('\:', ':') }
}
if (-not $FlutterSdk) { throw 'Pass -FlutterSdk with your Flutter SDK directory.' }
$dart = Join-Path $FlutterSdk 'bin/cache/dart-sdk/bin/dart.exe'
$snapshot = Join-Path $FlutterSdk 'bin/cache/flutter_tools.snapshot'
$flavorArgs = @()
if ($Android) { $flavorArgs = @('--flavor', 'staging') }
Push-Location $projectRoot
try {
    & $dart --disable-analytics $snapshot --suppress-analytics --no-version-check run --debug --no-pub -t lib/main_staging.dart -d $Device @flavorArgs
    exit $LASTEXITCODE
} finally { Pop-Location }
