# Compare API-created app (3080) vs UI-created app (3081)
# and probe for packaging trigger endpoints
param(
    [string]$InstanceUrl = "https://demo.appr.juriba.app",
    [string]$APIKey = "WeBP5sp+eQlDOLCAh68+Y7L48lBKq+mDX4KSDcUxzSH8vSoLZ6M+1eNXYNrC1VXQXXaxgsoSbHbuSnw2mz6jHw=="
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..' 'Juriba.AppR.psd1') -Force
Connect-JuribaAppR -Instance $InstanceUrl -APIKey $APIKey

$headers = @{ "x-api-key" = $APIKey; "Accept" = "application/json" }

Write-Host "=== Compare app 3080 (API) vs 3081 (UI) ===" -ForegroundColor Cyan

foreach ($id in @(3080, 3081)) {
    Write-Host "`n--- App $id ---" -ForegroundColor Yellow

    # Get tracker/status info
    try {
        $resp = Invoke-RestMethod -Uri "$InstanceUrl/api/apm/application/$id/workflow/tracker" `
            -Headers $headers -Method GET
        Write-Host "  Tracker: $($resp | ConvertTo-Json -Compress -Depth 3)"
    } catch {
        Write-Host "  Tracker: FAILED - $($_.Exception.Message)" -ForegroundColor Red
    }

    # Get app details
    try {
        $resp = Invoke-RestMethod -Uri "$InstanceUrl/api/apm/application/$id" `
            -Headers $headers -Method GET
        $json = $resp | ConvertTo-Json -Depth 5
        # Just show key fields, not the whole thing
        Write-Host "  App detail (first 500 chars): $($json.Substring(0, [Math]::Min(500, $json.Length)))"
    } catch {
        Write-Host "  App detail: FAILED - $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "`n=== Probe for packaging trigger endpoints ===" -ForegroundColor Cyan
$probeEndpoints = @(
    @{ method = "POST"; path = "api/apm/application/3080/run" },
    @{ method = "POST"; path = "api/apm/application/3080/package" },
    @{ method = "POST"; path = "api/apm/application/3080/workflow/run" },
    @{ method = "POST"; path = "api/apm/application/3080/workflow/start" },
    @{ method = "PUT";  path = "api/apm/application/3080/workflow/tracker" },
    @{ method = "POST"; path = "api/packaging/run/3080" },
    @{ method = "POST"; path = "api/packaging/application/3080/run" },
    @{ method = "POST"; path = "api/packaging/start" },
    @{ method = "POST"; path = "api/apm/application/3080/repackage" }
)

foreach ($ep in $probeEndpoints) {
    try {
        $resp = Invoke-WebRequest -Uri "$InstanceUrl/$($ep.path)" -Headers $headers `
            -Method $ep.method -ContentType 'application/json' -Body '{}'
        $isHtml = $resp.Content -match '<!DOCTYPE|<html'
        if ($isHtml) {
            Write-Host "  $($ep.method) $($ep.path) => $($resp.StatusCode) (HTML/SPA)" -ForegroundColor Gray
        } else {
            Write-Host "  $($ep.method) $($ep.path) => $($resp.StatusCode) REAL: $($resp.Content.Substring(0, [Math]::Min(200, $resp.Content.Length)))" -ForegroundColor Green
        }
    } catch {
        $sc = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { "?" }
        $eb = if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $_.ErrorDetails.Message.Substring(0, [Math]::Min(200, $_.ErrorDetails.Message.Length)) } else { "" }
        Write-Host "  $($ep.method) $($ep.path) => $sc $eb" -ForegroundColor $(if ($sc -eq 404 -or $sc -eq 200) { 'Gray' } else { 'Yellow' })
    }
}
