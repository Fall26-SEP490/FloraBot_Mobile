param(
    [string]$ApiBaseUrl = 'https://api.florabot.site',
    [string]$Origin = 'http://localhost:57466'
)

$ErrorActionPreference = 'Stop'
$api = [uri]$ApiBaseUrl
if (-not $api.IsAbsoluteUri -or $api.Scheme -ne 'https' -or
    $api.UserInfo -or $api.Query -or $api.Fragment -or $api.AbsolutePath -ne '/') {
    throw 'ApiBaseUrl must be an HTTPS origin without credentials, path or query.'
}
$browser = [uri]$Origin
if (-not $browser.IsAbsoluteUri -or $browser.Scheme -notin @('http', 'https') -or
    $browser.UserInfo -or $browser.Query -or $browser.Fragment -or $browser.AbsolutePath -ne '/' -or
    $Origin.EndsWith('/')) {
    throw 'Origin must be an HTTP(S) origin without credentials, path, query or trailing slash.'
}

$failed = $false
foreach ($path in @('/api/mobile/auth/login', '/api/auth/register')) {
    try {
        # Preflight only: no cookies, passwords, tokens or account creation.
        $response = Invoke-WebRequest -UseBasicParsing -Method Options `
            -Uri ($ApiBaseUrl.TrimEnd('/') + $path) -TimeoutSec 15 `
            -Headers @{
                Origin = $Origin
                'Access-Control-Request-Method' = 'POST'
                'Access-Control-Request-Headers' = 'content-type,authorization'
            }
        $allowedOrigin = [string]$response.Headers['Access-Control-Allow-Origin']
        $methods = (([string]$response.Headers['Access-Control-Allow-Methods']) -split ',').Trim()
        $headers = (([string]$response.Headers['Access-Control-Allow-Headers']) -split ',').Trim()
        $ok = $response.StatusCode -ge 200 -and $response.StatusCode -lt 300 -and
            $allowedOrigin -ceq $Origin -and ('POST' -in $methods) -and
            (('*' -in $headers) -or (('content-type' -in $headers) -and ('authorization' -in $headers)))
        if ($ok) {
            Write-Output "PASS $path : status=$($response.StatusCode), origin=$allowedOrigin"
        } else {
            $failed = $true
            if (-not $allowedOrigin) { $allowedOrigin = '(missing)' }
            Write-Output "FAIL $path : status=$($response.StatusCode), allow-origin=$allowedOrigin"
            Write-Output "Expected origin=$Origin, method=POST, headers=content-type,authorization"
        }
    } catch {
        $failed = $true
        Write-Output "FAIL $path : request did not complete successfully. $($_.Exception.Message)"
    }
}
if ($failed) {
    Write-Output 'Update the running API ALLOWED_ORIGINS, preserve existing origins, then restart the API and rerun this check.'
    exit 1
}
Write-Output 'Preflight passed. Verify the actual API login separately; preflight does not prove the endpoint exists.'
