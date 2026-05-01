<#
.SYNOPSIS
  Imports a CM (MECM/SCCM) application into App Readiness and starts a smoke
  test of the resulting package against a chosen VM group.

.DESCRIPTION
  End-to-end example of the customer-facing workflow:

    "Pull a specific CM app into AppR, then smoke-test it on a VM group."

  Pre-requisites
  --------------
  - The AppR instance has an MECM/SCCM connector configured AND import
    enabled. Verify with:
        Get-JuribaAppRMECMProvider |
            Where-Object { $_.integrationType -eq 1 -and $_.isImportEnabled }
    integrationType 1 = MECM/SCCM (vs. 3 = Intune). If nothing comes
    back, configure the connector via the AppR admin UI first.
  - You know the exact CM application name to import. Other automation
    in your environment that creates / configures the CM app model object
    knows that name and can hand it off.
  - You know which VM group to test against. List them with:
        Get-JuribaAppRVMGroup
    and pass the chosen `-VMGroupId`.

  How the script flows
  --------------------
    1. Connects to the AppR instance — preferring an existing
       Connect-JuribaAppR session, falling back to -Instance / -SecureAPIKey
       parameters, finally to an interactive secure prompt.
    2. Confirms a configured MECM-type provider with isImportEnabled=$true
       exists. Aborts with a clear message if not.
    3. Reads the provider's scan list (Get-JuribaAppRMECMScanList) and
       finds the row matching -CMApplicationName. The scan list is what
       the AppR UI's "Scan Import" page binds to; each row carries the
       CM-side originalApplicationId + model that the import API expects.
       Pipes the matching row into Start-JuribaAppRMECMImport.
    4. Polls Get-JuribaAppRApplicationList -Query <CMApplicationName> on
       a configurable interval. The MECM importer creates AppR application
       records as it runs; we wait for the one matching our CM name to
       appear. (If your environment uses a custom applicationNameTemplate
       on the connector — see Get-JuribaAppRMECMProvider -Id <providerId>
       — the AppR app name may differ from the raw CM name. Pass that
       templated form via -AppRApplicationName if needed.)
    5. Once the AppR application id is resolved, calls
       Start-JuribaAppRSmokeTest -AppId <id> -PackageType <type>
       -VMGroupId <id>.

  Known gaps / things to watch
  ----------------------------
  - On v6.0.x there is an open server-side regression on
    /api/kb/application that's unrelated to MECM but lives in the same
    codebase. If you see opaque 500s from any /api/admin/sccm/* call,
    capture the response trace id (visible with -Verbose) and add it to
    the open ticket.
  - This script intentionally does NOT wait for the smoke test to
    finish. Hand the returned `AppRApplicationId` to Watch-JuribaApp
    RApplicationStatus or Get-JuribaAppRTestResult for that.
  - Plain-text -APIKey strings should never be checked in. The script
    accepts a SecureString (-SecureAPIKey) or prompts for one. Keys
    stored in the SecretManagement vault can be used by calling
    Connect-JuribaAppR -SecretName ... before invoking this script.

.PARAMETER Instance
  The AppR instance URL (e.g. https://demo.appr.juriba.app). Optional if
  Connect-JuribaAppR has already established a session.

.PARAMETER SecureAPIKey
  The API key as a SecureString. Optional if a session exists. To pass
  one inline:
      $key = Read-Host -AsSecureString "API Key"
      ./Import-MECMAppAndSmokeTest.ps1 -SecureAPIKey $key …
  If neither -SecureAPIKey nor an existing session is present and
  -Instance was supplied, the script prompts interactively with
  Read-Host -AsSecureString.

.PARAMETER CMApplicationName
  The CM (MECM/SCCM) application name to import — the same name used by
  the upstream automation that created / configured the CM app model
  object.

.PARAMETER VMGroupId
  The VM group to run the smoke test against. Find available groups
  with Get-JuribaAppRVMGroup.

.PARAMETER PackageType
  The package type to test. Defaults to 'Msi'. Other values:
  'Msix', 'IntuneWin', 'AppV', 'Psadt', 'AppAttach'. Must match what
  the import produced (visible on the AppR application detail).

.PARAMETER AppRApplicationName
  Optional. When the provider's applicationNameTemplate transforms the
  CM name (e.g. "[Name]_[Version]"), the AppR application appears under
  the templated form, not the raw CM name. If you know that templated
  form, pass it here; otherwise the script searches by `CMApplicationName`.

.PARAMETER ImportEverything
  When set, skips the scan-list lookup and invokes
  Start-JuribaAppRMECMImport with no filteringObjects, which imports
  every discoverable CM application the connector can see. Use sparingly
  — most customer scenarios want to scope to a single CM application
  (the default, driven off -CMApplicationName).

.PARAMETER PollSeconds
  How often to poll while waiting. Default 15 seconds.

.PARAMETER TimeoutMinutes
  How long to wait overall before giving up. Default 30 minutes.

.PARAMETER SkipImport
  When set, skips Start-JuribaAppRMECMImport and goes straight to the
  AppR application lookup + smoke test. Use when an import has already
  completed and you just want to test the result.

.EXAMPLE
  # Variant 1 — interactive: prompt for the API key, drive everything else
  # from parameters. The key never lives in the shell history or scrollback.
  $secure = Read-Host -AsSecureString "Enter AppR API key"
  ./Import-MECMAppAndSmokeTest.ps1 `
      -Instance 'https://demo.appr.juriba.app' `
      -SecureAPIKey $secure `
      -CMApplicationName 'Microsoft Edge' `
      -VMGroupId 1

.EXAMPLE
  # Variant 2 — re-use an existing Connect-JuribaAppR session. No key
  # parameters needed at all.
  Connect-JuribaAppR -Instance 'https://demo.appr.juriba.app' -SecretName 'AppR-Demo'
  ./Import-MECMAppAndSmokeTest.ps1 `
      -CMApplicationName '7-Zip 23.01 (x64)' `
      -VMGroupId 2 `
      -PackageType IntuneWin

.EXAMPLE
  # Variant 3 — import has already run; just kick off the smoke test
  # for the existing AppR app. Useful when the import takes a while and
  # you want to retry the test without re-importing.
  ./Import-MECMAppAndSmokeTest.ps1 `
      -CMApplicationName 'Adobe Reader DC' `
      -AppRApplicationName 'W11_Adobe_Reader_DC_22.0_1.0_DW1' `
      -VMGroupId 3 -SkipImport
#>

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
    Justification = 'Interactive example script — user-facing coloured console output for progress and resolved ids.')]
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $false)] [string]$Instance,

    # SecureString rather than [string]. If a session already exists, this
    # is unnecessary; otherwise pass via Read-Host -AsSecureString or pull
    # from a vault. Never hardcode an API key in plain text.
    [Parameter(Mandatory = $false)] [SecureString]$SecureAPIKey,

    [Parameter(Mandatory = $true)]  [string]$CMApplicationName,
    [Parameter(Mandatory = $true)]  [int]   $VMGroupId,

    [Parameter(Mandatory = $false)] [string]$PackageType        = 'Msi',
    [Parameter(Mandatory = $false)] [string]$AppRApplicationName,
    [Parameter(Mandatory = $false)] [switch]$ImportEverything,

    [Parameter(Mandatory = $false)] [switch]$SkipImport,
    [Parameter(Mandatory = $false)] [int]   $PollSeconds        = 15,
    [Parameter(Mandatory = $false)] [int]   $TimeoutMinutes     = 30
)

$ErrorActionPreference = 'Stop'

# ── 1. Connect (re-use a live session if there is one) ────────────────────
$existingSession = Get-JuribaAppRSession -ErrorAction SilentlyContinue
if (-not $existingSession) {
    if (-not $Instance) {
        throw "No AppR session and no -Instance supplied. Run Connect-JuribaAppR first, or pass -Instance + -SecureAPIKey."
    }
    if (-not $SecureAPIKey) {
        # Prompt rather than expecting a plain-text -APIKey parameter.
        # Read-Host -AsSecureString masks input and returns a SecureString.
        $SecureAPIKey = Read-Host -AsSecureString "Enter API key for $Instance"
    }
    Connect-JuribaAppR -Instance $Instance -SecureAPIKey $SecureAPIKey | Out-Null
}

# ── 2. Verify a usable MECM provider is configured ────────────────────────
Write-Host "→ Looking for a configured MECM provider with import enabled..." -ForegroundColor Cyan
# integrationType / providerType: 1 = MECM/SCCM, 3 = Intune (per
# IntegrationProviderTypes enum). Both kinds appear in this list — we
# only want MECM with import on.
$mecmProvider = @(Get-JuribaAppRMECMProvider) |
    Where-Object { ($_.integrationType -eq 1 -or $_.providerType -eq 1) -and $_.isImportEnabled } |
    Select-Object -First 1
if (-not $mecmProvider) {
    throw "No MECM provider with isImportEnabled=true is configured on this instance. Configure one in the AppR admin UI (Integrations → MECM/SCCM) before running this script."
}
Write-Host "  using provider id=$($mecmProvider.id) ($($mecmProvider.integration ?? $mecmProvider.friendlyName))" -ForegroundColor DarkGray

# ── 3. Trigger the import (unless told to skip) ───────────────────────────
# The import API takes filteringObjects with the CM-side
# originalApplicationId (string) + model (int) — NOT the AppR-side
# numeric id from the scan list. We let Start-JuribaAppRMECMImport derive
# both fields from the matching scan-list row to avoid getting it wrong
# (sending a numeric id silently no-ops on the server).
if (-not $SkipImport) {
    $availability = Get-JuribaAppRMECMImportAvailability
    Write-Verbose "MECM import availability: $availability"

    if ($ImportEverything) {
        if ($PSCmdlet.ShouldProcess($mecmProvider.id, "Trigger MECM import (everything)")) {
            Start-JuribaAppRMECMImport -FilteringObjects @() -Confirm:$false | Out-Null
            Write-Host "→ Import started (no filter — imports everything the provider can see)." -ForegroundColor Cyan
        }
    } else {
        Write-Host "→ Reading scan list for provider id=$($mecmProvider.id) to find '$CMApplicationName'..." -ForegroundColor Cyan
        $scanRows = @(Get-JuribaAppRMECMScanList -ProviderId $mecmProvider.id)
        # status enum: the SPA excludes 2, 4, 5 from selection (already
        # imported / in flight). Status 1 is "discovered, available".
        $candidate = $scanRows |
            Where-Object { $_.applicationName -ieq $CMApplicationName -and $_.status -notin @(2,4,5) } |
            Select-Object -First 1
        if (-not $candidate) {
            $candidate = $scanRows |
                Where-Object { $_.applicationName -like "*$CMApplicationName*" -and $_.status -notin @(2,4,5) } |
                Select-Object -First 1
        }
        if (-not $candidate) {
            $importedAlready = $scanRows | Where-Object { $_.applicationName -ieq $CMApplicationName -and $_.status -in @(2,4,5) }
            if ($importedAlready) {
                Write-Host "  '$CMApplicationName' is already imported (scan-list status=$($importedAlready[0].status)). Skipping import." -ForegroundColor Yellow
            } else {
                throw "No scan-list row matched '$CMApplicationName' on provider id $($mecmProvider.id). Run Get-JuribaAppRMECMScanList -ProviderId $($mecmProvider.id) | Select applicationName to see what is discoverable."
            }
        } elseif ($PSCmdlet.ShouldProcess($candidate.applicationName, "Trigger MECM import")) {
            $candidate | Start-JuribaAppRMECMImport -Confirm:$false | Out-Null
            Write-Host "→ Import started for '$($candidate.applicationName)' (originalApplicationId=$($candidate.originalApplicationId), model=$($candidate.model))." -ForegroundColor Cyan
        }
    }
}

# ── 4. Wait for the AppR application to appear ────────────────────────────
# Search by CM name first, then templated form if provided. The MECM
# importer creates AppR Application records during the job; the
# application list is the authoritative source for our id.
#
# We use Get-JuribaAppRApplicationList -AllUsers -Lite + client-side
# filtering rather than -Query, because -Query hits a broader KB-style
# index (e.g. it returns 332 hits for 'Notepad'), not the AppR-instance
# application list. The Lite list returns flat records with id / name /
# manufacturer / version, which is exactly what we need to pin down a
# single AppR application id.
$lookupNames = @($CMApplicationName)
if ($AppRApplicationName -and $AppRApplicationName -ne $CMApplicationName) {
    $lookupNames += $AppRApplicationName
}

$deadline = (Get-Date).AddMinutes($TimeoutMinutes)
$apprApp  = $null
while ((Get-Date) -lt $deadline) {
    $apps = @(Get-JuribaAppRApplicationList -AllUsers -Lite -ErrorAction SilentlyContinue)
    foreach ($q in $lookupNames) {
        # Prefer exact match; fall back to case-insensitive substring.
        $exact = $apps | Where-Object { $_.name -ieq $q }
        if ($exact) { $apprApp = $exact | Select-Object -First 1; break }
        $partial = $apps | Where-Object { $_.name -like "*$q*" }
        if ($partial) { $apprApp = $partial | Select-Object -First 1; break }
    }
    if ($apprApp) { break }
    Start-Sleep -Seconds $PollSeconds
    Write-Host "  …still waiting for an AppR application matching '$CMApplicationName'" -ForegroundColor DarkGray
}
if (-not $apprApp) {
    throw "Timed out after $TimeoutMinutes min. No AppR application matched '$CMApplicationName' (or '$AppRApplicationName' if supplied). Check Get-JuribaAppRMECMImportEvent for import errors and the provider's applicationNameTemplate (Get-JuribaAppRMECMProvider -Id $($mecmProvider.id)) to see how CM names are transformed."
}

# -Lite returns flat records (id, name, manufacturer, version at root);
# defensive extraction so a future shape change doesn't silently break.
$apprAppId = if ($apprApp.id)        { $apprApp.id }
             elseif ($apprApp.appId) { $apprApp.appId }
             elseif ($apprApp.basic -and $apprApp.basic.id) { $apprApp.basic.id }
             else { $null }
if (-not $apprAppId) {
    $shape = ($apprApp | ConvertTo-Json -Depth 4 -Compress)
    throw "Found a matching AppR application but couldn't pull its id from: $($shape.Substring(0, [Math]::Min(400, $shape.Length)))"
}
Write-Host "→ Resolved AppR application id: $apprAppId" -ForegroundColor Green

# ── 5. Start the smoke test ───────────────────────────────────────────────
Write-Host "→ Starting smoke test: AppId=$apprAppId PackageType=$PackageType VMGroupId=$VMGroupId" -ForegroundColor Cyan
$smokeResult = Start-JuribaAppRSmokeTest `
    -AppId $apprAppId `
    -PackageType $PackageType `
    -VMGroupId $VMGroupId
Write-Verbose ("Smoke test response: " + ($smokeResult | ConvertTo-Json -Depth 5 -Compress))

# Emit a small summary object so the script composes cleanly into pipelines.
[pscustomobject]@{
    CMApplicationName    = $CMApplicationName
    MECMProviderId       = $mecmProvider.id
    AppRApplicationId    = $apprAppId
    AppRApplicationName  = if ($apprApp.name) { $apprApp.name } elseif ($apprApp.basic) { $apprApp.basic.name } else { $null }
    PackageType          = $PackageType
    VMGroupId            = $VMGroupId
    SmokeTestResult      = $smokeResult
}
