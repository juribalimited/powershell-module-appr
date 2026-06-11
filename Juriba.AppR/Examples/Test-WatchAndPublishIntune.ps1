<#
.SYNOPSIS
  Watch for applications with IntuneWin packages that have passed smoke testing
  and automatically publish them to Intune.

.DESCRIPTION
  End-to-end example of a "watch and publish" automation loop:

    1. Connect to the AppR instance, preferring an existing Connect-JuribaAppR
       session and falling back to -SecretName (recommended), -SecureAPIKey,
       interactive prompt, or -APIKey (least secure).
    2. Every -IntervalSeconds, pull the full application list and filter to
       apps whose status is in -TargetStatuses and that we have not already
       attempted to publish in this run.
    3. For each candidate, pull its smoke-test results and look for a
       completed IntuneWin (packageType 4) test with an acceptable RAG
       result (green by default; amber too if -AllowAmber).
    4. Publish the qualifying app via Invoke-JuribaAppRPublishIntune. The
       call passes -Confirm:$false so the watcher does not block on a
       confirmation prompt in unattended runs.

  Robustness notes:

  - The application list is read from the cheap Lite endpoint when possible,
    falling back to the V2 endpoint when Lite misbehaves (permission
    fallthrough to SPA HTML, HTTP errors on builds where the Lite contract
    changed, or rows with no recognizable id). Field access goes through a
    resolver because the two endpoints nest id / name / status / version
    differently and the shapes also vary across AppR versions.
  - The polling body is wrapped in try/catch so a transient API error does
    not kill the watcher; the next poll re-tries.
  - A candidate whose publish attempt errors is retried on later polls, but
    parked after 3 failed attempts so a permanently broken app does not spam
    the log forever.
  - If this script established the AppR session (rather than re-using an
    existing one), it disconnects on exit via try/finally so Ctrl+C still
    cleans up.

  Requires an Intune integration connector configured on the AppR instance
  with isDeployEnabled.

.PARAMETER Instance
  The AppR instance URL (e.g. https://appr.example.com). Optional if a
  Connect-JuribaAppR session is already established. Accepts -InstanceUrl
  as an alias for backward compatibility.

.PARAMETER SecretName
  Name of an entry in a PowerShell SecretManagement vault holding the
  API key. Recommended for unattended use. Use Set-JuribaAppRAPIKey to
  store the key once, then reference it by name from any automation.

.PARAMETER VaultName
  Optional. Name of the SecretManagement vault to read SecretName from.
  Defaults to the registered default vault.

.PARAMETER SecureAPIKey
  The API key as a SecureString. Use with Read-Host -AsSecureString for
  interactive runs where the key never appears in console history.

.PARAMETER APIKey
  Plain-text API key. Documented for backward compatibility; the script
  emits a warning when used. Prefer -SecretName or -SecureAPIKey.

.PARAMETER TargetStatuses
  Workflow statuses to consider for publishing. Defaults cover both the
  display-name form ("Ready for UAT", "Ready for Publishing") and the
  camelCase API form ("ReadyForUat", "ReadyForPublishing") because
  different AppR versions surface the status field in different shapes.

.PARAMETER AllowAmber
  When set, apps with amber (passed-with-warnings) smoke test results
  qualify in addition to green (clean pass). By default only green
  results trigger a publish.

.PARAMETER IntervalSeconds
  Seconds between polling cycles. Default 300 (5 minutes).

.PARAMETER TimeoutMinutes
  Maximum minutes to run before exiting. Default 0 (run until stopped).

.PARAMETER DryRun
  When set, reports which apps would be published but does not call the
  publish endpoint. Dry-run still records each "would publish" candidate
  in the dedupe set so the same app is not reported on every poll.

.EXAMPLE
  # Variant 1 - re-use an existing Connect-JuribaAppR session
  Connect-JuribaAppR -Instance 'https://appr.example.com' -SecretName 'AppR-Production'
  .\Test-WatchAndPublishIntune.ps1 -DryRun

.EXAMPLE
  # Variant 2 - drive the connection from a SecretManagement vault
  .\Test-WatchAndPublishIntune.ps1 -Instance 'https://appr.example.com' -SecretName 'AppR-Production'

.EXAMPLE
  # Variant 3 - interactive SecureString prompt; key never lives in shell history
  $key = Read-Host -AsSecureString "Enter AppR API key"
  .\Test-WatchAndPublishIntune.ps1 -Instance 'https://appr.example.com' -SecureAPIKey $key

.EXAMPLE
  # Variant 4 - publish green or amber, poll every 60 seconds, stop after 30 minutes
  .\Test-WatchAndPublishIntune.ps1 -SecretName 'AppR-Production' -AllowAmber -IntervalSeconds 60 -TimeoutMinutes 30
#>

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
    Justification = 'Interactive example script - user-facing colored console output for watcher progress and results.')]
[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [Alias('InstanceUrl')]
    [string]$Instance,

    [Parameter(Mandatory = $false)]
    [string]$SecretName,

    [Parameter(Mandatory = $false)]
    [string]$VaultName,

    [Parameter(Mandatory = $false)]
    [SecureString]$SecureAPIKey,

    [Parameter(Mandatory = $false)]
    [string]$APIKey,

    [Parameter(Mandatory = $false)]
    [string[]]$TargetStatuses = @('Ready for UAT', 'ReadyForUat', 'Ready for Publishing', 'ReadyForPublishing'),

    [switch]$AllowAmber,

    [Parameter(Mandatory = $false)]
    [int]$IntervalSeconds = 300,

    [Parameter(Mandatory = $false)]
    [int]$TimeoutMinutes = 0,

    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

# Different AppR versions / list endpoints expose the same logical field
# under different property names and nesting levels. Observed shapes:
#   - Lite rows: id / name / status / version / manufacturer at the root.
#   - V2 rows:   id, appId, name, applicationVersion, manufacturer nested
#     under .basic; status (camelCase, e.g. "ReadyForUat") and displayName
#     nested under .ext.
# Resolve-AppRField checks each requested property name at the root, then
# under .basic, then under .ext, and returns the first non-empty value.
# This generalizes the Resolve-AppRId helper from Import-MECMAppAndSmokeTest
# so one function covers id, name, status, version, and manufacturer.
function Resolve-AppRField {
    param(
        [Parameter(Mandatory = $true)]  $Row,
        [Parameter(Mandatory = $true)]  [string[]]$Name
    )
    if ($null -eq $Row) { return $null }
    $holders = @($Row)
    foreach ($sub in 'basic', 'ext') {
        $p = $Row.PSObject.Properties[$sub]
        if ($p -and $p.Value) { $holders += $p.Value }
    }
    foreach ($n in $Name) {
        foreach ($holder in $holders) {
            $p = $holder.PSObject.Properties[$n]
            if ($p -and $null -ne $p.Value -and '' -ne $p.Value) { return $p.Value }
        }
    }
    return $null
}

# Get the AppR application list. Prefers the cheap Lite endpoint, but the
# Lite route has three observed failure modes across AppR / AppM versions:
#   1. 200 OK with the SPA HTML page (string) instead of JSON, for API keys
#      with partial admin scope (V2 allowed, Lite denied).
#   2. An outright HTTP error (e.g. 400 serializer error on builds where the
#      Lite route's contract changed).
#   3. 200 OK with JSON rows whose id property the script cannot resolve.
# Any of the three falls back to the V2 endpoint, which has been reliable
# across every version tested. Once the fallback trips, subsequent polls go
# straight to V2 instead of re-failing on Lite every interval.
$script:preferV2 = $false
function Get-AppRAppList {
    if (-not $script:preferV2) {
        try {
            $r = Get-JuribaAppRApplicationList -AllUsers -Lite
            if ($r -is [string]) {
                Write-Verbose "listOfAppsLite returned non-JSON (likely an SPA-HTML permission fallthrough); switching to listOfAppsV2 for this run."
                $script:preferV2 = $true
            }
            elseif (@($r).Count -gt 0 -and -not (Resolve-AppRField @($r)[0] -Name 'id', 'appId', 'applicationId')) {
                Write-Verbose "listOfAppsLite rows carry no recognizable application id; switching to listOfAppsV2 for this run."
                $script:preferV2 = $true
            }
            else {
                return @($r)
            }
        }
        catch {
            Write-Verbose "listOfAppsLite failed ($($_.Exception.Message)); switching to listOfAppsV2 for this run."
            $script:preferV2 = $true
        }
    }
    return @(Get-JuribaAppRApplicationList -AllUsers)
}

# --- 1. Ensure the Juriba.AppR module is loaded --------------------------
# Prefer a module already on the path (Install-Module / PSGallery scenario);
# fall back to the sibling .psd1 (development / repo-clone scenario).
if (-not (Get-Module -Name Juriba.AppR)) {
    $localPsd1 = Join-Path (Join-Path $PSScriptRoot '..') 'Juriba.AppR.psd1'
    if (Test-Path $localPsd1) {
        Import-Module $localPsd1 -Force -ErrorAction Stop
    } else {
        Import-Module Juriba.AppR -ErrorAction Stop
    }
    Write-Host "Module imported" -ForegroundColor Cyan
}

# --- 2. Connect (re-use a live session if there is one) -------------------
# Resolution order, from most secure to least:
#   1. Existing Connect-JuribaAppR session  - no action, just observe.
#   2. -SecretName (+ optional -VaultName)  - SecretManagement vault.
#   3. -SecureAPIKey                        - SecureString already in hand.
#   4. -APIKey (plain text)                 - explicit opt-in; warning printed.
#   5. Interactive Read-Host -AsSecureString prompt.
# Get-JuribaAppRSession only exists from module v0.2.0; guard with
# Get-Command so this script does not hard-fail if an older module version
# happens to be the one loaded.
$existingSession = if (Get-Command Get-JuribaAppRSession -ErrorAction SilentlyContinue) {
    Get-JuribaAppRSession -ErrorAction SilentlyContinue
} else { $null }
$sessionEstablishedHere = $false

if (-not $existingSession) {
    if (-not $Instance) {
        throw "No active AppR session and no -Instance supplied. Either run Connect-JuribaAppR first, or pass -Instance with -SecretName / -SecureAPIKey / -APIKey."
    }

    if ($SecretName) {
        $connectParams = @{ Instance = $Instance; SecretName = $SecretName }
        if ($VaultName) { $connectParams['VaultName'] = $VaultName }
        Connect-JuribaAppR @connectParams | Out-Null
    }
    elseif ($SecureAPIKey) {
        Connect-JuribaAppR -Instance $Instance -SecureAPIKey $SecureAPIKey | Out-Null
    }
    elseif ($APIKey) {
        Write-Warning "Plain-text -APIKey is the least-secure option. Prefer -SecretName or -SecureAPIKey for unattended runs."
        Connect-JuribaAppR -Instance $Instance -APIKey $APIKey | Out-Null
    }
    else {
        # No credential parameter; prompt interactively. Read-Host masks
        # input and returns a SecureString that never enters scrollback.
        $promptedKey = Read-Host -AsSecureString "Enter API key for $Instance"
        Connect-JuribaAppR -Instance $Instance -SecureAPIKey $promptedKey | Out-Null
    }

    $sessionEstablishedHere = $true
    Write-Host "Connected to $Instance" -ForegroundColor Cyan
}
else {
    Write-Host "Re-using existing AppR session on $($existingSession.Instance)" -ForegroundColor Cyan
}

# --- 3. Watcher setup -----------------------------------------------------
# Track which apps we have already published in this run so subsequent polls
# do not re-trigger the publish (or re-report in dry-run). Keys are stringified
# app ids so int-vs-string differences between endpoints cannot split the set.
$publishedAppIds = @{}

# Apps whose publish attempt errored get retried on later polls, but only up
# to this many times - a permanently broken app (bad connector config, wrong
# package state) should not generate an error line every poll forever.
$MAX_PUBLISH_ATTEMPTS = 3
$publishFailures = @{}

# RAG status values from evergreenInformation.rAGStatus:
#   1 = green (clean pass), 2 = amber (warnings), 3 = red (fail).
$acceptableRAG = @(1)
if ($AllowAmber) { $acceptableRAG += 2 }

$ragLabel = if ($AllowAmber) { 'green or amber' } else { 'green only' }
$modeLabel = if ($DryRun) { 'DRY RUN' } else { 'LIVE' }

# IntuneWin package type id used by both the test-result filter (typeOfPackage)
# and the publish body (packageType). Defined as a constant so it is easy to
# spot and change if AppR ever renumbers the enum on a future release.
$INTUNE_WIN_PACKAGE_TYPE_ID  = 4

# Publish-body packageType value. Invoke-JuribaAppRPublishIntune's docstring
# example uses the string name ("IntuneWin"); some older AppR builds accept
# only the integer enum value. Pass as string by default to match the
# documented contract; if a customer hits a 400 here on an older build, swap
# to $INTUNE_WIN_PACKAGE_TYPE_ID.
$INTUNE_WIN_PUBLISH_PACKAGE_TYPE = 'IntuneWin'

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

try {
    while ((Get-Date) -lt $timeoutTime) {
        $pollCount++
        $timestamp = (Get-Date).ToString('HH:mm:ss')
        Write-Host "`n[$timestamp] Poll #$pollCount" -ForegroundColor Cyan

        # Each poll is wrapped so a transient API error does not take down
        # the whole watcher. The next iteration just re-tries.
        try {
            $allApps = Get-AppRAppList

            # Filter to target statuses, skipping anything we have already
            # published in this run. Status and id are resolved through
            # Resolve-AppRField because Lite carries them at the row root
            # while V2 nests status under .ext and id under .basic.
            $candidates = @($allApps | Where-Object {
                $appId  = Resolve-AppRField $_ -Name 'id', 'appId', 'applicationId'
                $status = Resolve-AppRField $_ -Name 'status'
                $status -and ($TargetStatuses -contains $status) -and
                $appId -and (-not $publishedAppIds.ContainsKey([string]$appId))
            })

            if ($candidates.Count -eq 0) {
                Write-Host "  No new candidates in target statuses." -ForegroundColor DarkGray
            }
            else {
                Write-Host "  Checking $($candidates.Count) candidate app(s)..."

                foreach ($app in $candidates) {
                    $appId    = Resolve-AppRField $app -Name 'id', 'appId', 'applicationId'
                    $appKey   = [string]$appId
                    $appName  = Resolve-AppRField $app -Name 'name', 'displayName'
                    $appVer   = Resolve-AppRField $app -Name 'version', 'applicationVersion'
                    $appMfr   = Resolve-AppRField $app -Name 'manufacturer'
                    $appLabel = "$appName v$appVer ($appMfr) [id=$appId]"

                    # Each candidate gets its own try/catch so one bad app
                    # does not skip the rest. Add to publishedAppIds in the
                    # finally so we never re-evaluate the same id mid-loop.
                    try {
                        $testResults = Get-JuribaAppRTestResult -AppId $appId

                        # Filter to IntuneWin test rows.
                        $intuneTests = @($testResults | Where-Object { $_.typeOfPackage -eq $INTUNE_WIN_PACKAGE_TYPE_ID })
                        if ($intuneTests.Count -eq 0) {
                            Write-Host "  $appLabel - No IntuneWin package" -ForegroundColor DarkGray
                            continue
                        }

                        # First completed IntuneWin evergreen result with an
                        # acceptable RAG status.
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
                            # Distinguish "completed but failed/wrong-RAG" from
                            # "still running" so the customer can tell which.
                            $failedTest = $intuneTests.evergreenInformation |
                                Where-Object { $_.complete } |
                                Select-Object -First 1
                            if ($failedTest) {
                                $ragText = switch ($failedTest.rAGStatus) {
                                    1       { 'GREEN' }
                                    2       { 'AMBER' }
                                    3       { 'RED' }
                                    default { "RAG=$($failedTest.rAGStatus)" }
                                }
                                Write-Host "  $appLabel - IntuneWin test completed but $ragText (skipping)" -ForegroundColor Yellow
                            }
                            else {
                                Write-Host "  $appLabel - IntuneWin test not yet complete" -ForegroundColor DarkGray
                            }
                            continue
                        }

                        $ragText = switch ($passedTest.rAGStatus) {
                            1 { 'GREEN' }
                            2 { 'AMBER' }
                        }
                        Write-Host "  $appLabel - IntuneWin test PASSED ($ragText)" -ForegroundColor Green

                        if ($DryRun) {
                            Write-Host "    [DRY RUN] Would publish to Intune" -ForegroundColor Yellow
                            $publishedAppIds[$appKey] = $true
                            continue
                        }

                        # Live publish. -Confirm:$false because
                        # Invoke-JuribaAppRPublishIntune declares
                        # SupportsShouldProcess; without the suppression a
                        # non-default $ConfirmPreference would block the
                        # watcher waiting for input that never comes.
                        Write-Host "    Publishing to Intune..." -ForegroundColor Cyan
                        $publishBody = @{
                            applicationId = $appId
                            packageType   = $INTUNE_WIN_PUBLISH_PACKAGE_TYPE
                        }
                        $result = Invoke-JuribaAppRPublishIntune -Body $publishBody -Confirm:$false
                        Write-Host "    Published successfully." -ForegroundColor Green
                        if ($result) {
                            Write-Host "    Response: $($result | ConvertTo-Json -Compress -Depth 5)"
                        }
                        $publishedAppIds[$appKey] = $true
                    }
                    catch {
                        # Failed candidates are retried on later polls, up to
                        # MAX_PUBLISH_ATTEMPTS - after that the app is parked
                        # so a permanently broken one cannot spam the log
                        # forever. Restart the script to retry parked apps.
                        $publishFailures[$appKey] = 1 + ($publishFailures[$appKey] ?? 0)
                        if ($publishFailures[$appKey] -ge $MAX_PUBLISH_ATTEMPTS) {
                            $publishedAppIds[$appKey] = $true
                            Write-Host "    $appLabel - error: $($_.Exception.Message)" -ForegroundColor Red
                            Write-Host "    Giving up on this app after $MAX_PUBLISH_ATTEMPTS failed attempts. Restart the watcher to retry it." -ForegroundColor Red
                        }
                        else {
                            Write-Host "    $appLabel - error (attempt $($publishFailures[$appKey]) of $MAX_PUBLISH_ATTEMPTS, will retry next poll): $($_.Exception.Message)" -ForegroundColor Red
                        }
                    }
                }

                if ($publishedAppIds.Count -gt 0) {
                    Write-Host "`n  Total published / dry-run reported so far: $($publishedAppIds.Count)" -ForegroundColor Green
                }
            }
        }
        catch {
            # Transient error in the poll body itself (e.g. network blip).
            # Log and continue so the watcher survives.
            Write-Host "  Poll #$pollCount error (continuing): $($_.Exception.Message)" -ForegroundColor Red
        }

        # Skip the final sleep when the next poll would land past the
        # timeout anyway - otherwise a short -TimeoutMinutes with a long
        # -IntervalSeconds keeps the script alive well past its deadline.
        if ((Get-Date).AddSeconds($IntervalSeconds) -ge $timeoutTime) { break }
        Start-Sleep -Seconds $IntervalSeconds
    }

    if ($TimeoutMinutes -gt 0) {
        Write-Host "`nTimeout reached after $TimeoutMinutes minutes ($pollCount polls)." -ForegroundColor Yellow
    }

    Write-Host "`n=== Summary ===" -ForegroundColor Magenta
    Write-Host "Total apps published / dry-run reported: $($publishedAppIds.Count)"
    Write-Host "Polls completed: $pollCount"
}
finally {
    # Only disconnect the session we created. Re-used sessions belong to the
    # caller and must outlive the script.
    if ($sessionEstablishedHere) {
        Disconnect-JuribaAppR -ErrorAction SilentlyContinue
    }
}
