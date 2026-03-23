# Dump VM group details and try creating with additional fields
param(
    [string]$InstanceUrl = "https://demo.appr.juriba.app",
    [string]$APIKey = "WeBP5sp+eQlDOLCAh68+Y7L48lBKq+mDX4KSDcUxzSH8vSoLZ6M+1eNXYNrC1VXQXXaxgsoSbHbuSnw2mz6jHw=="
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..' 'Juriba.AppR.psd1') -Force
Connect-JuribaAppR -Instance $InstanceUrl -APIKey $APIKey

$headers = @{ "x-api-key" = $APIKey; "Accept" = "application/json" }

Write-Host "=== VM Group List ===" -ForegroundColor Cyan
$groups = Get-JuribaAppRVMGroup
$groups | ForEach-Object { Write-Host ($_ | ConvertTo-Json -Depth 5) }

Write-Host "`n=== VM Group detail for id=1 ===" -ForegroundColor Cyan
try {
    $detail = Invoke-RestMethod -Uri "$InstanceUrl/api/virtual-machine/group/1" `
        -Headers $headers -Method GET
    Write-Host ($detail | ConvertTo-Json -Depth 5)
} catch { Write-Host "FAILED: $_" -ForegroundColor Red }

Write-Host "`n=== OS Types/Builds endpoint probe ===" -ForegroundColor Cyan
$osEndpoints = @(
    "api/packaging/os",
    "api/packaging/operatingsystem",
    "api/packaging/upload/operatingsystems",
    "api/app/operatingsystem",
    "api/settings/operatingsystem"
)
foreach ($ep in $osEndpoints) {
    try {
        $resp = Invoke-WebRequest -Uri "$InstanceUrl/$ep" -Headers $headers -Method GET
        $isHtml = $resp.Content -match '<!DOCTYPE|<html'
        if (-not $isHtml) {
            Write-Host "  $ep => REAL: $($resp.Content.Substring(0, [Math]::Min(300, $resp.Content.Length)))" -ForegroundColor Green
        } else {
            Write-Host "  $ep => HTML/SPA" -ForegroundColor Gray
        }
    } catch {
        $sc = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { "?" }
        Write-Host "  $ep => $sc" -ForegroundColor Gray
    }
}

Write-Host "`n=== App 3081 full detail (UI-created, working) ===" -ForegroundColor Cyan
try {
    $app = Invoke-RestMethod -Uri "$InstanceUrl/api/apm/application/3081" `
        -Headers $headers -Method GET
    Write-Host ($app | ConvertTo-Json -Depth 5 | Out-String).Substring(0, 2000)
} catch { Write-Host "FAILED: $_" -ForegroundColor Red }
