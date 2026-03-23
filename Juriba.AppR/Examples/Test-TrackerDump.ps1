# Dump full tracker for failed app 3082 to see what "Failed to package" looks like
param(
    [int]$AppId = 3082,
    [string]$InstanceUrl = "https://demo.appr.juriba.app",
    [string]$APIKey = "WeBP5sp+eQlDOLCAh68+Y7L48lBKq+mDX4KSDcUxzSH8vSoLZ6M+1eNXYNrC1VXQXXaxgsoSbHbuSnw2mz6jHw=="
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..' 'Juriba.AppR.psd1') -Force
Connect-JuribaAppR -Instance $InstanceUrl -APIKey $APIKey

$headers = @{ "x-api-key" = $APIKey; "Accept" = "application/json" }

Write-Host "=== Tracker /full for app $AppId ===" -ForegroundColor Cyan
$tracker = Invoke-RestMethod -Uri "$InstanceUrl/api/apm/application/$AppId/tracker/full" `
    -Headers $headers -Method GET
Write-Host ($tracker | ConvertTo-Json -Depth 10)

Write-Host "`n=== App detail for $AppId ===" -ForegroundColor Cyan
$app = Invoke-RestMethod -Uri "$InstanceUrl/api/apm/application/$AppId" `
    -Headers $headers -Method GET
# Show ext section which has status info
Write-Host ($app.ext | ConvertTo-Json -Depth 5)
