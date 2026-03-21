# Quick auth debug script — probe for session cookie and alternative auth mechanisms
param(
    [string]$InstanceUrl = "https://demo.appr.juriba.app",
    [string]$APIKey = "94c23191-948e-4790-83a1-010827a02e8d"
)

$headers = @{ "x-api-key" = $APIKey; "Accept" = "application/json" }

Write-Host "=== Test 1: Check response headers from whoami ===" -ForegroundColor Cyan
try {
    $resp = Invoke-WebRequest -Uri "$InstanceUrl/api/user/whoami" -Headers $headers -Method GET
    Write-Host "Status: $($resp.StatusCode)" -ForegroundColor Green
    Write-Host "Response Headers:"
    $resp.Headers.GetEnumerator() | ForEach-Object {
        Write-Host "  $($_.Key): $($_.Value -join ', ')"
    }
} catch { Write-Host "FAILED: $_" -ForegroundColor Red }

Write-Host ""
Write-Host "=== Test 2: Check response headers from uploadChunk (GET, just to see auth behavior) ===" -ForegroundColor Cyan
try {
    $resp = Invoke-WebRequest -Uri "$InstanceUrl/api/uploadChunk" -Headers $headers -Method GET
    Write-Host "Status: $($resp.StatusCode)" -ForegroundColor Green
    $resp.Headers.GetEnumerator() | ForEach-Object {
        Write-Host "  $($_.Key): $($_.Value -join ', ')"
    }
} catch {
    $statusCode = $null
    if ($_.Exception.Response) { $statusCode = [int]$_.Exception.Response.StatusCode }
    Write-Host "Status: $statusCode - $($_.Exception.Message)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== Test 3: Try HttpClient with CookieContainer for session persistence ===" -ForegroundColor Cyan
try {
    $handler = [System.Net.Http.HttpClientHandler]::new()
    $handler.CookieContainer = [System.Net.CookieContainer]::new()
    $handler.UseCookies = $true
    $client = [System.Net.Http.HttpClient]::new($handler)
    $client.DefaultRequestHeaders.Add("x-api-key", $APIKey)
    $client.DefaultRequestHeaders.Add("Accept", "application/json")

    # Step A: Call whoami to establish session
    $whoamiResp = $client.GetAsync("$InstanceUrl/api/user/whoami").GetAwaiter().GetResult()
    Write-Host "whoami status: $([int]$whoamiResp.StatusCode)" -ForegroundColor Green

    # Check Set-Cookie headers
    $setCookies = $whoamiResp.Headers.GetValues("Set-Cookie") 2>$null
    if ($setCookies) {
        Write-Host "Set-Cookie headers from whoami:"
        $setCookies | ForEach-Object { Write-Host "  $_" }
    } else {
        Write-Host "No Set-Cookie headers from whoami" -ForegroundColor Yellow
    }

    # Check what cookies are in the container
    $cookies = $handler.CookieContainer.GetCookies([Uri]$InstanceUrl)
    if ($cookies.Count -gt 0) {
        Write-Host "Cookies in jar after whoami:"
        $cookies | ForEach-Object { Write-Host "  $($_.Name)=$($_.Value.Substring(0, [Math]::Min(30, $_.Value.Length)))..." }
    } else {
        Write-Host "No cookies in jar after whoami" -ForegroundColor Yellow
    }

    # Step B: Now try uploadChunk with the same client (should have cookies if any were set)
    $testContent = [System.Net.Http.MultipartFormDataContent]::new()
    $testContent.Add([System.Net.Http.StringContent]::new("test"), "dzUuid")
    $uploadResp = $client.PostAsync("$InstanceUrl/api/uploadChunk", $testContent).GetAwaiter().GetResult()
    Write-Host "uploadChunk status (with session): $([int]$uploadResp.StatusCode)" -ForegroundColor $(if ($uploadResp.IsSuccessStatusCode) { 'Green' } else { 'Yellow' })
    $uploadBody = $uploadResp.Content.ReadAsStringAsync().GetAwaiter().GetResult()
    if ($uploadBody) { Write-Host "uploadChunk response: $($uploadBody.Substring(0, [Math]::Min(200, $uploadBody.Length)))" }

    $client.Dispose()
    $handler.Dispose()
} catch { Write-Host "FAILED: $_" -ForegroundColor Red }

Write-Host ""
Write-Host "=== Test 4: Probe for auth/token endpoints ===" -ForegroundColor Cyan
$authEndpoints = @(
    "api/authentication/login",
    "api/authentication/token",
    "api/authentication/apikey",
    "api/auth/token",
    "api/token"
)
foreach ($ep in $authEndpoints) {
    try {
        $resp = Invoke-WebRequest -Uri "$InstanceUrl/$ep" -Headers $headers -Method POST `
            -ContentType 'application/json' -Body '{}' -MaximumRedirection 0
        Write-Host "  $ep => $($resp.StatusCode)" -ForegroundColor Green
    } catch {
        $statusCode = $null
        if ($_.Exception.Response) { $statusCode = [int]$_.Exception.Response.StatusCode }
        Write-Host "  $ep => $statusCode" -ForegroundColor Gray
    }
}

Write-Host ""
Write-Host "=== Test 5: Keycloak direct access grant (ROPC) ===" -ForegroundColor Cyan
Write-Host "Token endpoint: https://identity.eu.juriba.app/realms/juriba/protocol/openid-connect/token"
Write-Host "Client ID: demo-appm"
Write-Host "(This would require username/password - skipping actual call)"
