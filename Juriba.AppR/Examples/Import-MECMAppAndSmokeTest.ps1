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
       Snapshots the existing AppR application ids, then pipes the
       matching row into Start-JuribaAppRMECMImport.
    4. Polls Get-JuribaAppRApplicationList -AllUsers -Lite for new ids
       (i.e. not in the pre-import snapshot). The MECM importer creates
       AppR application records during the job, but the AppR-side name
       it picks is the *extracted* name (e.g. "Notepad++") rather than
       the templated scan-list name (e.g.
       "x64_Notepad++_Notepad_1.5_1.0_GLOBAL"). The snapshot-diff
       approach side-steps that mismatch entirely. When several new
       apps appear in the same window we prefer the one whose name
       contains -CMApplicationName, otherwise the most recent.
    5. Assigns ownership of the new app to the API-key user (resolved
       via /api/apm/user/whoAmI). MECM-imported apps come back with no
       owner, which makes "Created By" on subsequent smoke-test runs
       fall back to the integration connector's system user (e.g.
       appmintegrationconnectorsystemuser@juriba.com). Setting the
       owner makes the smoke-test attribution match the calling user.
    6. Polls Get-JuribaAppRApplication on the new app until
       availPackages.<PackageType> is true. The MECM importer creates
       the AppR application record early, then copies the package zip
       from the MECM source path; only after the copy completes and
       the importer derives a deployable package of the requested
       type does Start-JuribaAppRSmokeTest accept the call (otherwise
       it returns "CantFindTheAppInformation"). If the requested
       PackageType never becomes available the script reports which
       types ARE present so the caller can pick one or fix the MECM
       deployment-type configuration.
    7. Calls Start-JuribaAppRSmokeTest -AppId <id> -PackageType <type>
       -VMGroupId <id>.

  Known gaps / things to watch
  ----------------------------
  - On v6.0.x there is an open server-side regression on
    /api/kb/application that's unrelated to MECM but lives in the same
    codebase. If you see opaque 500s from any /api/admin/sccm/* call,
    capture the response trace id (visible with -Verbose) and add it to
    the open ticket.
  - This script intentionally does NOT wait for the smoke test to
    finish. Hand the returned `AppRApplicationId` to
    Watch-JuribaAppRApplicationStatus or Get-JuribaAppRTestResult
    for that.
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
  The package type to test. Defaults to 'Msi'. Other recognised values:
  'Msix', 'IntuneWin', 'AppV', 'Psadt', 'AppAttach', 'nonStd'. Must
  match a key on the AppR application's availPackages map. AppR
  classifies anything outside the standard formats as 'nonStd', which
  is most commonly seen on PSADT wrappers under AppR / AppM builds
  where PSADT-specific detection wasn't yet fully exposed; the script
  prints which availPackages keys are currently true on each poll, so
  if a run times out the log shows the actual classification to pass
  on a retry.

.PARAMETER AppRApplicationName
  Optional. Used only when -SkipImport is set: the name of the existing
  AppR application to smoke-test. When importing, the script identifies
  the resulting app via snapshot-diff and ignores this parameter — the
  imported app's AppR-side name is whatever the importer extracted from
  the installer, which usually doesn't match the scan-list templated
  name.

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

# Different AppR versions / list endpoints expose the application id under
# different property names (id / appId / applicationId / nested basic.id).
# Normalise once so the rest of the script never has to care which one came
# back. Returning $null for a row without any of these is intentional —
# callers filter empty results out of the snapshot.
function Resolve-AppRId {
    param([Parameter(Mandatory = $true)] $InputObject)
    if ($null -eq $InputObject) { return $null }
    if ($InputObject.PSObject.Properties['id']            -and $InputObject.id)            { return $InputObject.id }
    if ($InputObject.PSObject.Properties['appId']         -and $InputObject.appId)         { return $InputObject.appId }
    if ($InputObject.PSObject.Properties['applicationId'] -and $InputObject.applicationId) { return $InputObject.applicationId }
    if ($InputObject.basic -and $InputObject.basic.id) { return $InputObject.basic.id }
    return $null
}

# Mirror of Resolve-AppRId for the application name: Lite returns .name at
# the root, V2 nests it under .basic.name. Without this helper, display and
# name-match filters that read $row.name silently see $null when the V2
# fallback kicks in.
function Resolve-AppRName {
    param([Parameter(Mandatory = $true)] $InputObject)
    if ($null -eq $InputObject) { return $null }
    if ($InputObject.PSObject.Properties['name'] -and $InputObject.name) { return $InputObject.name }
    if ($InputObject.basic -and $InputObject.basic.name) { return $InputObject.basic.name }
    return $null
}

# Get the AppR application list for the pre-import snapshot and post-import
# diff. Prefers the cheap Lite endpoint, but some AppR / AppM versions gate
# Lite behind a permission set that callers with otherwise-broad admin
# access don't have — in that case the server returns the SPA HTML page
# (200 OK with text/html) rather than 401/403. Invoke-RestMethod surfaces
# that as a string, which we detect and retry against the V2 endpoint.
# V2 carries the same data nested under .basic; Resolve-AppRId handles
# both shapes.
function Get-AppRAppList {
    $r = Get-JuribaAppRApplicationList -AllUsers -Lite
    if ($r -is [string]) {
        Write-Verbose "listOfAppsLite returned non-JSON (likely an SPA-HTML fallthrough for a key without Lite-endpoint permission); retrying with listOfAppsV2."
        $r = Get-JuribaAppRApplicationList -AllUsers
    }
    return @($r)
}

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

# ── 3. Trigger the import + identify the resulting AppR app ───────────────
# The import API takes filteringObjects with the CM-side
# originalApplicationId (string) + model (int) — NOT the AppR-side
# numeric id from the scan list. We let Start-JuribaAppRMECMImport derive
# both fields from the matching scan-list row to avoid getting it wrong
# (sending a numeric id silently no-ops on the server).
#
# The AppR-side name of the imported app is the *extracted* name from
# the installer (e.g. "Notepad++"), not the scan-list templated name
# (e.g. "x64_Notepad++_Notepad_1.5_1.0_GLOBAL"), so we can't lookup by
# the CMApplicationName string. Snapshot the AppR app ids before
# triggering the import, then poll for any new ids.
$apprApp = $null
if ($SkipImport) {
    Write-Host "→ -SkipImport: looking up an existing AppR application by name..." -ForegroundColor Cyan
    $lookupNames = @($AppRApplicationName, $CMApplicationName) | Where-Object { $_ }
    # Get-AppRAppList + Resolve-AppRName so the lookup works against both
    # Lite (.name at root) and V2 (.basic.name nested) shapes.
    $apps = @(Get-AppRAppList)
    foreach ($q in $lookupNames) {
        $apprApp = $apps | Where-Object { (Resolve-AppRName $_) -ieq $q } | Select-Object -First 1
        if (-not $apprApp) { $apprApp = $apps | Where-Object { (Resolve-AppRName $_) -like "*$q*" } | Select-Object -First 1 }
        if ($apprApp) { break }
    }
    if (-not $apprApp) {
        throw "-SkipImport set but no AppR application matched '$CMApplicationName' (or -AppRApplicationName if supplied). List with: Get-JuribaAppRApplicationList -AllUsers -Lite (or -AllUsers without -Lite if your API key lacks the Lite endpoint)."
    }
} else {
    $availability = Get-JuribaAppRMECMImportAvailability
    Write-Verbose "MECM import availability: $availability"

    Write-Host "→ Snapshotting existing AppR app ids before import..." -ForegroundColor Cyan
    # Get-AppRAppList prefers Lite, falls back to V2 if the key can't see
    # Lite. Resolve-AppRId normalises across schema variants. Drop empty
    # results so $beforeIds only contains real ids and the post-import
    # diff stays correct.
    $beforeIds = @(Get-AppRAppList |
        ForEach-Object { Resolve-AppRId $_ } |
        Where-Object { $_ })
    Write-Host "  $($beforeIds.Count) existing apps." -ForegroundColor DarkGray

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
            # Distinguish "no name match" from "name matched but status
            # filtered out" — the latter usually means the app is already
            # in AppR (status 2 = imported, 4/5 = import in flight) and
            # -SkipImport is the answer. Bare "no row matched" sent users
            # chasing a name-lookup problem that didn't exist.
            $nameMatches = @($scanRows | Where-Object { $_.applicationName -like "*$CMApplicationName*" })
            if ($nameMatches.Count -gt 0) {
                $statuses = ($nameMatches | ForEach-Object { $_.status } | Sort-Object -Unique) -join ', '
                throw "Scan-list row(s) matched '$CMApplicationName' on provider id $($mecmProvider.id), but all have a non-importable status (observed: $statuses). Status 2 = already imported into AppR, 4 or 5 = import already in flight. If the app is already in AppR, re-run this script with -SkipImport to bypass the import step and go straight to the smoke test against the existing record. To inspect: Get-JuribaAppRMECMScanList -ProviderId $($mecmProvider.id) | Where-Object applicationName -like '*$CMApplicationName*' | Select applicationName, status"
            }
            throw "No scan-list row matched '$CMApplicationName' on provider id $($mecmProvider.id). Inspect what is discoverable: Get-JuribaAppRMECMScanList -ProviderId $($mecmProvider.id) | Select applicationName, status"
        }
        if ($PSCmdlet.ShouldProcess($candidate.applicationName, "Trigger MECM import")) {
            $candidate | Start-JuribaAppRMECMImport -Confirm:$false | Out-Null
            Write-Host "→ Import started for '$($candidate.applicationName)' (originalApplicationId=$($candidate.originalApplicationId), model=$($candidate.model))." -ForegroundColor Cyan
        }
    }

    # Poll for any new app id (i.e. not in the pre-import snapshot).
    # Imports take a few minutes — be patient.
    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds $PollSeconds
        $now = @(Get-AppRAppList)
        $new = @($now | Where-Object {
            $rowId = Resolve-AppRId $_
            $rowId -and ($beforeIds -notcontains $rowId)
        })
        if ($new.Count -gt 0) {
            # When several apps materialise (e.g. ImportEverything), pick
            # the one whose name best matches the requested CM app. Use
            # Resolve-AppRName so the match works against both Lite and
            # V2 row shapes.
            $apprApp = $new |
                Where-Object { (Resolve-AppRName $_) -like "*$CMApplicationName*" } |
                Select-Object -First 1
            if (-not $apprApp) { $apprApp = $new | Select-Object -First 1 }
            $pickedId   = Resolve-AppRId   $apprApp
            $pickedName = Resolve-AppRName $apprApp
            Write-Host "  ✓ Found new AppR app: id=$pickedId, name=$pickedName" -ForegroundColor Green
            if ($new.Count -gt 1) {
                $others = $new |
                    Where-Object { (Resolve-AppRId $_) -ne $pickedId } |
                    ForEach-Object { "$(Resolve-AppRId $_):$(Resolve-AppRName $_)" }
                Write-Host "    ($($new.Count) new apps in total — picked the closest match. Others: $(($others) -join ', '))" -ForegroundColor DarkGray
            }
            break
        }
        Write-Host "  …still waiting (no new app yet, $((@($now)).Count) total)" -ForegroundColor DarkGray
    }

    if (-not $apprApp) {
        throw "Timed out after $TimeoutMinutes min. No new AppR application appeared. Check the AppR UI for import errors, and verify the provider host (Get-JuribaAppRMECMProvider -Id $($mecmProvider.id) | Select hostname, sourcePath) is reachable."
    }
}

$apprAppId = Resolve-AppRId $apprApp
if (-not $apprAppId) {
    $shape = ($apprApp | ConvertTo-Json -Depth 4 -Compress)
    throw "Found a matching AppR application but couldn't pull its id from: $($shape.Substring(0, [Math]::Min(400, $shape.Length)))"
}
Write-Host "→ Resolved AppR application id: $apprAppId" -ForegroundColor Green

# ── 5. Claim ownership for the calling user ───────────────────────────────
# MECM imports come back with no owner — without this step the UI's
# "Created By" on the smoke test falls back to the connector's system
# user (e.g. appmintegrationconnectorsystemuser@juriba.com), not the
# API caller. /api/apm/user/whoAmI returns the calling user's id
# directly (Get-JuribaAppRUser doesn't surface it), so we go via the
# rest method helper. Skip when -SkipImport: the caller picked an
# existing app that presumably already has the right owner.
if (-not $SkipImport) {
    try {
        $me = Get-JuribaAppRUser -Me
        if ($me.userId) {
            Write-Host "→ Assigning owner=$($me.userId) ($($me.userName)) on app $apprAppId..." -ForegroundColor Cyan
            Set-JuribaAppRApplicationOwner -AppId $apprAppId -UserId ([int]$me.userId) -Confirm:$false | Out-Null
        } else {
            Write-Warning "Get-JuribaAppRUser -Me did not return a userId; skipping owner assignment. Smoke-test attribution will fall back to the integration connector's system user."
        }
    } catch {
        Write-Warning "Couldn't assign owner: $($_.Exception.Message). Smoke-test attribution will fall back to the integration connector's system user."
    }
}

# ── 6. Wait for the requested PackageType to be available ─────────────────
# Get-JuribaAppRApplication returns availPackages — a per-package-type
# boolean map (msi, msix, intune, appV, psadt, appAttach, etc.). The
# importer first creates the AppR app record, then copies the source
# zip, then derives deployable packages from it. Smoke testing the
# requested PackageType returns "CantFindTheAppInformation" until the
# matching availPackages flag flips true.
if (-not $SkipImport) {
    # Map the script's friendly PackageType to the availPackages key
    # the server returns (it's lowercase + abbreviated for some types).
    $availKey = switch ($PackageType) {
        'Msi'       { 'msi' }
        'Msix'      { 'msiX' }
        'IntuneWin' { 'intune' }
        'AppV'      { 'appV' }
        'Psadt'     { 'psadt' }
        'AppAttach' { 'appAttach' }
        default     { $PackageType.ToLower() }
    }
    Write-Host "→ Waiting for availPackages.$availKey to become true on app $apprAppId..." -ForegroundColor Cyan
    $pkgDeadline = (Get-Date).AddMinutes($TimeoutMinutes)
    $pkgReady = $false
    $lastAvail = $null
    while ((Get-Date) -lt $pkgDeadline) {
        $a = Get-JuribaAppRApplication -AppId $apprAppId -ErrorAction SilentlyContinue
        $lastAvail = $a.availPackages
        if ($lastAvail -and $lastAvail.$availKey) {
            Write-Host "  ✓ availPackages.$availKey = true." -ForegroundColor Green
            $pkgReady = $true
            break
        }
        Start-Sleep -Seconds $PollSeconds
        $present = if ($lastAvail) {
            ($lastAvail.PSObject.Properties |
                Where-Object { $_.Value -eq $true -and $_.Name -ne 'appId' } |
                ForEach-Object { $_.Name }) -join ','
        } else { '<none yet>' }
        Write-Host "  …still waiting (currently available: $present)" -ForegroundColor DarkGray
    }
    if (-not $pkgReady) {
        $present = if ($lastAvail) {
            ($lastAvail.PSObject.Properties |
                Where-Object { $_.Value -eq $true -and $_.Name -ne 'appId' } |
                ForEach-Object { $_.Name }) -join ','
        } else { '<none>' }
        throw "Imported AppR app $apprAppId never produced a $PackageType package within $TimeoutMinutes min. availPackages: $present. The MECM Application's deployment-type configuration may not produce a $PackageType-compatible package — pick one of the available types or correct the deployment type on the MECM side."
    }
}

# ── 7. Start the smoke test ───────────────────────────────────────────────
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
    AppRApplicationName  = Resolve-AppRName $apprApp
    PackageType          = $PackageType
    VMGroupId            = $VMGroupId
    SmokeTestResult      = $smokeResult
}
