<#
.SYNOPSIS
  Watch for applications with IntuneWin packages that have passed smoke testing
  and automatically publish them to Intune.
.DESCRIPTION
  Polls the application list on an interval, looking for apps that:
    1. Are in a publishable workflow state (ReadyForUat, ReadyForPublishing, or configurable)
    2. Have an IntuneWin package (packageType 4)
    3. Have completed smoke testing with a pass (green) or pass-with-warnings (amber) result

  When a qualifying app is found, it is published to Intune via the configured
  integration connector. Already-published apps are tracked so they are not
  published twice.

  Requires an Intune integration connector to be configured on the instance.
.PARAMETER InstanceUrl
  The base URL of the App Readiness instance.
.PARAMETER APIKey
  Your API key for authentication.
.PARAMETER TargetStatuses
  Workflow statuses to consider for publishing. Default: ReadyForUat, ReadyForPublishing.
.PARAMETER AllowAmber
  When specified, apps with amber (warnings) smoke test results are also published.
  By default, only green (clean pass) results qualify.
.PARAMETER IntervalSeconds
  Seconds between polling cycles. Default 300 (5 minutes).
.PARAMETER TimeoutMinutes
  Maximum minutes to run before exiting. Default 0 (run indefinitely).
.PARAMETER DryRun
  When specified, identifies qualifying apps but does not actually publish them.
.EXAMPLE
  .\Test-WatchAndPublishIntune.ps1 -InstanceUrl "https://demo.appr.juriba.app" `
      -APIKey "your-key" -DryRun
  Dry-run: shows which apps would be published without actually publishing.
.EXAMPLE
  .\Test-WatchAndPublishIntune.ps1 -InstanceUrl "https://demo.appr.juriba.app" `
      -APIKey "your-key" -AllowAmber -IntervalSeconds 60
  Watches every 60 seconds, publishing apps with green or amber test results.
#>

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
    Justification = 'Interactive example script - user-facing colored console output for watcher progress and results.')]
[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string]$InstanceUrl,

    [Parameter(Mandatory = $true)]
    [string]$APIKey,

    [string[]]$TargetStatuses = @('Ready for UAT', 'ReadyForUat', 'Ready for Publishing', 'ReadyForPublishing'),

    [switch]$AllowAmber,

    [int]$IntervalSeconds = 300,

    [int]$TimeoutMinutes = 0,

    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

# Import the module
$modulePath = Join-Path (Join-Path $PSScriptRoot '..') 'Juriba.AppR.psd1'
Import-Module $modulePath -Force
Write-Host "Module imported" -ForegroundColor Cyan

# Connect
Write-Host "`n=== Connect ===" -ForegroundColor Magenta
Connect-JuribaAppR -Instance $InstanceUrl -APIKey $APIKey
Write-Host "Connected to $InstanceUrl"

# Track which apps we've already published to avoid duplicates
$publishedAppIds = @{}

# RAG status values: 1 = green (pass), 2 = amber (warnings), 3 = red (fail)
$acceptableRAG = @(1)
if ($AllowAmber) { $acceptableRAG += 2 }

$ragLabel = if ($AllowAmber) { 'green or amber' } else { 'green only' }
$modeLabel = if ($DryRun) { 'DRY RUN' } else { 'LIVE' }

Write-Host "`n=== Watching for IntuneWin apps ready to publish ===" -ForegroundColor Magenta
Write-Host "  Mode:             $modeLabel"
Write-Host "  Target statuses:  $($TargetStatuses -join ', ')"
Write-Host "  Test threshold:   $ragLabel"
Write-Host "  Poll interval:    $IntervalSeconds seconds"
if ($TimeoutMinutes -gt 0) {
    Write-Host "  Timeout:          $TimeoutMinutes minutes"
}
else {
    Write-Host "  Timeout:          none (runs until stopped)"
}

$startTime = Get-Date
$timeoutTime = if ($TimeoutMinutes -gt 0) { $startTime.AddMinutes($TimeoutMinutes) } else { [DateTime]::MaxValue }
$pollCount = 0

while ((Get-Date) -lt $timeoutTime) {
    $pollCount++
    $timestamp = (Get-Date).ToString('HH:mm:ss')
    Write-Host "`n[$timestamp] Poll #$pollCount" -ForegroundColor Cyan

    # Get all applications
    $allApps = Get-JuribaAppRApplicationList -AllUsers -Lite

    # Filter to target statuses
    $candidates = @($allApps | Where-Object {
        $_.status -and ($TargetStatuses -contains $_.status) -and
        $_.id -and (-not $publishedAppIds.ContainsKey($_.id))
    })

    if ($candidates.Count -eq 0) {
        Write-Host "  No new candidates in target statuses." -ForegroundColor DarkGray
        Start-Sleep -Seconds $IntervalSeconds
        continue
    }

    Write-Host "  Checking $($candidates.Count) candidate app(s)..."

    foreach ($app in $candidates) {
        $appLabel = "$($app.name) v$($app.version) ($($app.manufacturer)) [id=$($app.id)]"

        # Get smoke test results
        try {
            $testResults = Get-JuribaAppRTestResult -AppId $app.id
        }
        catch {
            Write-Host "  $appLabel - Could not get test results: $($_.Exception.Message)" -ForegroundColor DarkGray
            continue
        }

        # Find IntuneWin test results (typeOfPackage = 4)
        $intuneTests = @($testResults | Where-Object { $_.typeOfPackage -eq 4 })
        if ($intuneTests.Count -eq 0) {
            Write-Host "  $appLabel - No IntuneWin package" -ForegroundColor DarkGray
            continue
        }

        # Check if any IntuneWin smoke test is complete and passed
        $passedTest = $null
        foreach ($test in $intuneTests) {
            foreach ($eg in $test.evergreenInformation) {
                if ($eg.complete -and $acceptableRAG -contains $eg.rAGStatus) {
                    $passedTest = $eg
                    break
                }
            }
            if ($passedTest) { break }
        }

        if (-not $passedTest) {
            # Check if there's a completed but failed test
            $failedTest = $intuneTests.evergreenInformation | Where-Object { $_.complete } | Select-Object -First 1
            if ($failedTest) {
                $ragText = switch ($failedTest.rAGStatus) { 1 { 'GREEN' } 2 { 'AMBER' } 3 { 'RED' } default { "RAG=$($failedTest.rAGStatus)" } }
                Write-Host "  $appLabel - IntuneWin test completed but $ragText (skipping)" -ForegroundColor Yellow
            }
            else {
                Write-Host "  $appLabel - IntuneWin test not yet complete" -ForegroundColor DarkGray
            }
            continue
        }

        $ragText = switch ($passedTest.rAGStatus) { 1 { 'GREEN' } 2 { 'AMBER' } }
        Write-Host "  $appLabel - IntuneWin test PASSED ($ragText)" -ForegroundColor Green

        if ($DryRun) {
            Write-Host "    [DRY RUN] Would publish to Intune" -ForegroundColor Yellow
            $publishedAppIds[$app.id] = $true
            continue
        }

        # Publish to Intune
        Write-Host "    Publishing to Intune..." -ForegroundColor Cyan
        try {
            $publishBody = @{
                applicationId = $app.id
                packageType   = 4   # IntuneWin
            }
            $result = Invoke-JuribaAppRPublishIntune -Body $publishBody
            Write-Host "    Published successfully." -ForegroundColor Green
            if ($result) {
                Write-Host "    Response: $($result | ConvertTo-Json -Compress)"
            }
            $publishedAppIds[$app.id] = $true
        }
        catch {
            Write-Host "    Publish FAILED: $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    # Summary
    if ($publishedAppIds.Count -gt 0) {
        Write-Host "`n  Total published so far: $($publishedAppIds.Count)" -ForegroundColor Green
    }

    Start-Sleep -Seconds $IntervalSeconds
}

if ($TimeoutMinutes -gt 0) {
    Write-Host "`nTimeout reached after $TimeoutMinutes minutes ($pollCount polls)." -ForegroundColor Yellow
}

Write-Host "`n=== Summary ===" -ForegroundColor Magenta
Write-Host "Total apps published: $($publishedAppIds.Count)"
Write-Host "Polls completed: $pollCount"

# Disconnect
Disconnect-JuribaAppR
