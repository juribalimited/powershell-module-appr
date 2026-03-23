# Watch an existing application by ID
param(
    [Parameter(Mandatory)] [int]$AppId,
    [string]$InstanceUrl = "https://demo.appr.juriba.app",
    [string]$APIKey = "WeBP5sp+eQlDOLCAh68+Y7L48lBKq+mDX4KSDcUxzSH8vSoLZ6M+1eNXYNrC1VXQXXaxgsoSbHbuSnw2mz6jHw==",
    [int]$IntervalSeconds = 60,
    [int]$TimeoutMinutes = 30
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..' 'Juriba.AppR.psd1') -Force
Connect-JuribaAppR -Instance $InstanceUrl -APIKey $APIKey

Write-Host "Watching app $AppId every ${IntervalSeconds}s (timeout ${TimeoutMinutes}m)..." -ForegroundColor Cyan
$result = Watch-JuribaAppRApplicationStatus -AppId $AppId `
    -IntervalSeconds $IntervalSeconds -TimeoutMinutes $TimeoutMinutes

Write-Host "`nResult: $($result.Status) ($($result.Progress)%) - Elapsed: $($result.Elapsed), Polls: $($result.PollCount)" `
    -ForegroundColor $(if ($result.Status -eq 'ReadyForQualityReview') { 'Green' } else { 'Yellow' })
