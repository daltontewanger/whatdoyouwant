$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$config = Get-Content (Join-Path $projectRoot 'staging/firebase.web.json') -Raw | ConvertFrom-Json
if ($config.projectId -ne 'whatdoyouwant-staging') { throw 'Refusing to test another project.' }
$session = $null
$passed = $false
try {
    # Never print the responses: they contain temporary authentication tokens.
    $session = Invoke-RestMethod -Method Post -Uri ('https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=' + $config.apiKey) -ContentType 'application/json' -Body '{"returnSecureToken":true}'
    Write-Output 'PASS: staging anonymous sign-in.'
    $readStatus = 0
    try {
        $null = Invoke-RestMethod -Uri 'https://firestore.googleapis.com/v1/projects/whatdoyouwant-staging/databases/(default)/documents/_connection_check/nonexistent' -Headers @{ Authorization = 'Bearer ' + $session.idToken }
        $readStatus = 200
    } catch {
        if ($_.Exception.Response) { $readStatus = [int]$_.Exception.Response.StatusCode }
    }
    if ($readStatus -ne 403) { throw 'Firestore did not return the expected denial.' }
    Write-Output 'PASS: staging Firestore denied an authenticated client read (403).'
    $passed = $true
} catch {
    # Do not forward the exception: URLs/response bodies may contain credentials.
    Write-Output 'FAIL: staging check failed; sensitive error details withheld.'
} finally {
    if ($session) {
        try {
            $body = @{ idToken = $session.idToken } | ConvertTo-Json -Compress
            $null = Invoke-RestMethod -Method Post -Uri ('https://identitytoolkit.googleapis.com/v1/accounts:delete?key=' + $config.apiKey) -ContentType 'application/json' -Body $body
            Write-Output 'PASS: temporary staging test account deleted.'
        } catch {
            Write-Output 'FAIL: temporary staging test account cleanup failed. Review staging Authentication users.'
            $passed = $false
        }
    }
}
if (-not $passed) { exit 1 }
