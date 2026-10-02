param(
    [string]$Device,
    [switch]$Android,
    [switch]$Accounts,
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
if (-not $Device) {
    if ($Android) { throw 'Pass -Device with the emulator or device ID shown by adb devices.' }
    $Device = 'web-server'
}
$flavorArgs = @()
if ($Android) { $flavorArgs = @('--flavor', 'staging') }
$webArgs = @()
if (-not $Android) {
    # The staging browser key only allows this origin.
    $webArgs = @('--web-hostname', 'localhost', '--web-port', '7357')
    if ($Device -eq 'web-server') {
        if (Get-NetTCPConnection -State Listen -LocalPort 7357 -ErrorAction SilentlyContinue) {
            throw 'Port 7357 is already in use. Stop the other staging web session first.'
        }
        # Flutter's own Chrome launch is unreliable on this machine; open the page instead.
        $url = 'http://localhost:7357/whatdoyouwant/'
        Start-Job -ArgumentList $url -ScriptBlock {
            param($target)
            for ($i = 0; $i -lt 180; $i++) {
                try {
                    Invoke-WebRequest -Uri $target -UseBasicParsing -TimeoutSec 2 | Out-Null
                    Start-Process $target
                    return
                } catch { Start-Sleep -Seconds 1 }
            }
        } | Out-Null
        Write-Output "Opening $url once it is ready. Use a private window for a second, separate user."
    }
}
$debugArgs = @()
if ($AppCheckDebugFile) {
    if (-not (Test-Path -LiteralPath $AppCheckDebugFile -PathType Leaf)) { throw 'App Check debug file not found.' }
    $debugArgs = @('--dart-define-from-file', (Resolve-Path -LiteralPath $AppCheckDebugFile).Path)
}
$previewArgs = if ($Accounts) { @('--dart-define=ACCOUNT_FLOW_PREVIEW=true') } else { @() }
Push-Location $projectRoot
try {
    & $flutter --suppress-analytics --no-version-check run --debug --no-pub -t lib/main_staging.dart -d $Device @flavorArgs @webArgs @debugArgs @previewArgs
    exit $LASTEXITCODE
} finally { Pop-Location }
