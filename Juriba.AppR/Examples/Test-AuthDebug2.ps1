# Auth debug 2 — probe the real /api/authentication/login endpoint
# and verify which responses are JSON vs SPA HTML fallback
param(
    [string]$InstanceUrl = "https://demo.appr.juriba.app",
    [string]$APIKey = "94c23191-948e-4790-83a1-010827a02e8d"
)

$headers = @{ "x-api-key" = $APIKey; "Accept" = "application/json" }

Write-Host "=== Test 1: Is whoami actually returning JSON or SPA HTML? ===" -ForegroundColor Cyan
try {
    $resp = Invoke-WebRequest -Uri "$InstanceUrl/api/user/whoami" -Headers $headers -Method GET
    $body = $resp.Content
    $isHtml = $body -match '<!DOCTYPE|<html'
    Write-Host "Content-Type: $($resp.Headers['Content-Type'])"
    Write-Host "Is HTML: $isHtml"
    if ($isHtml) {
        Write-Host "BODY (first 200 chars): $($body.Substring(0, [Math]::Min(200, $body.Length)))" -ForegroundColor Yellow
    } else {
        Write-Host "BODY: $($body.Substring(0, [Math]::Min(500, $body.Length)))" -ForegroundColor Green
    }
} catch { Write-Host "FAILED: $_" -ForegroundColor Red }

Write-Host ""
Write-Host "=== Test 2: POST /api/authentication/login with apiKey ===" -ForegroundColor Cyan
$loginBodies = @(
    @{ desc = "apiKey field"; body = @{ apiKey = $APIKey } | ConvertTo-Json },
    @{ desc = "api_key field"; body = @{ api_key = $APIKey } | ConvertTo-Json },
    @{ desc = "token field"; body = @{ token = $APIKey } | ConvertTo-Json },
    @{ desc = "key field"; body = @{ key = $APIKey } | ConvertTo-Json }
)

foreach ($attempt in $loginBodies) {
    try {
        $resp = Invoke-WebRequest -Uri "$InstanceUrl/api/authentication/login" `
            -Method POST -ContentType 'application/json' -Body $attempt.body `
            -Headers @{ "Accept" = "application/json" }
        $isHtml = $resp.Content -match '<!DOCTYPE|<html'
        $status = $resp.StatusCode
        if ($isHtml) {
            Write-Host "  $($attempt.desc) => $status (HTML fallback)" -ForegroundColor Gray
        } else {
            Write-Host "  $($attempt.desc) => $status REAL RESPONSE:" -ForegroundColor Green
            Write-Host "    $($resp.Content.Substring(0, [Math]::Min(300, $resp.Content.Length)))"
            Write-Host "    Set-Cookie: $($resp.Headers['Set-Cookie'])"
        }
    } catch {
        $statusCode = $null
        $errBody = ""
        if ($_.Exception.Response) {
            $statusCode = [int]$_.Exception.Response.StatusCode
        }
        if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
            $errBody = $_.ErrorDetails.Message
        }
        Write-Host "  $($attempt.desc) => $statusCode : $errBody" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "=== Test 3: POST /api/authentication/login with x-api-key header (no body) ===" -ForegroundColor Cyan
try {
    $resp = Invoke-WebRequest -Uri "$InstanceUrl/api/authentication/login" `
        -Method POST -ContentType 'application/json' `
        -Headers @{ "x-api-key" = $APIKey; "Accept" = "application/json" } `
        -Body '{}'
    $isHtml = $resp.Content -match '<!DOCTYPE|<html'
    if (-not $isHtml) {
        Write-Host "  Status: $($resp.StatusCode) - REAL RESPONSE:" -ForegroundColor Green
        Write-Host "  $($resp.Content.Substring(0, [Math]::Min(300, $resp.Content.Length)))"
        Write-Host "  Set-Cookie: $($resp.Headers['Set-Cookie'])"
    } else {
        Write-Host "  Status: $($resp.StatusCode) - HTML fallback" -ForegroundColor Gray
    }
} catch {
    $statusCode = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { "?" }
    $errBody = if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $_.ErrorDetails.Message } else { $_.Exception.Message }
    Write-Host "  Status: $statusCode : $errBody" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== Test 4: Check actual POST to uploadChunk with x-api-key (minimal, no file) ===" -ForegroundColor Cyan
try {
    $handler = [System.Net.Http.HttpClientHandler]::new()
    $handler.CookieContainer = [System.Net.CookieContainer]::new()
    $client = [System.Net.Http.HttpClient]::new($handler)
    $client.DefaultRequestHeaders.Add("x-api-key", $APIKey)
    $client.DefaultRequestHeaders.Add("Accept", "application/json")

    # Minimal multipart just to see auth response
    $mc = [System.Net.Http.MultipartFormDataContent]::new()
    $mc.Add([System.Net.Http.StringContent]::new("test"), "dzUuid")
    $resp = $client.PostAsync("$InstanceUrl/api/uploadChunk", $mc).GetAwaiter().GetResult()
    $body = $resp.Content.ReadAsStringAsync().GetAwaiter().GetResult()
    $isHtml = $body -match '<!DOCTYPE|<html'
    Write-Host "  Status: $([int]$resp.StatusCode) $($resp.ReasonPhrase)"
    Write-Host "  Is HTML: $isHtml"
    if (-not $isHtml -and $body) {
        Write-Host "  Body: $($body.Substring(0, [Math]::Min(300, $body.Length)))"
    }
    $client.Dispose()
} catch { Write-Host "FAILED: $_" -ForegroundColor Red }

Write-Host ""
Write-Host "=== Test 5: Try GET /api/packaging/upload/packageTypesMatrix (known working endpoint?) ===" -ForegroundColor Cyan
try {
    $resp = Invoke-WebRequest -Uri "$InstanceUrl/api/packaging/upload/packageTypesMatrix" -Headers $headers -Method GET
    $isHtml = $resp.Content -match '<!DOCTYPE|<html'
    Write-Host "  Status: $($resp.StatusCode), Content-Type: $($resp.Headers['Content-Type']), IsHTML: $isHtml"
    if (-not $isHtml) {
        Write-Host "  Body (first 300): $($resp.Content.Substring(0, [Math]::Min(300, $resp.Content.Length)))" -ForegroundColor Green
    } else {
        Write-Host "  Got SPA HTML — x-api-key NOT working for this endpoint" -ForegroundColor Yellow
    }
} catch {
    $statusCode = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { "?" }
    Write-Host "  Status: $statusCode" -ForegroundColor Yellow
}
