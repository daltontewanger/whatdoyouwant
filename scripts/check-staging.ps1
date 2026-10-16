param(
    [string]$Device = 'chrome',
    [switch]$Android,
    [string]$FlutterSdk,
    [string]$AppCheckDebugFile
)
$ErrorActionPreference = 'Stop'
# Run through the actual SDK client so API application restrictions are honored.
# This launches an interactive check; process exit is not a test-pass assertion.
Write-Output 'In the app, select Check staging connection and review its result.'
Write-Output 'The check obtains App Check, creates a temporary staging guest, refreshes its token, checks denied Firestore access, and deletes the guest.'
& (Join-Path $PSScriptRoot 'run-staging.ps1') @PSBoundParameters -ConnectionCheck
exit $LASTEXITCODE
