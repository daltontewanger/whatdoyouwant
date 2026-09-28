param(
    [string]$Device = 'chrome',
    [switch]$Android,
    [string]$FlutterSdk,
    [string]$AppCheckDebugFile
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
$flutter = Join-Path $FlutterSdk 'bin/flutter.bat'
$flavorArgs = @()
if ($Android) { $flavorArgs = @('--flavor', 'staging') }
$webArgs = @()
if (-not $Android) { $webArgs = @('--web-hostname', 'localhost', '--web-port', '7357') }
$debugArgs = @()
if ($AppCheckDebugFile) {
    if (-not (Test-Path -LiteralPath $AppCheckDebugFile -PathType Leaf)) { throw 'App Check debug file not found.' }
    $debugArgs = @('--dart-define-from-file', (Resolve-Path -LiteralPath $AppCheckDebugFile).Path)
}
Push-Location $projectRoot
try {
    & $flutter --suppress-analytics --no-version-check run --debug --no-pub -t lib/main_staging.dart -d $Device @flavorArgs @webArgs @debugArgs
    exit $LASTEXITCODE
} finally { Pop-Location }
