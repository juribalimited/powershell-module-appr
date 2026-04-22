<#
.SYNOPSIS
  Interactive self-service packaging with smoke-test visibility for Juriba App Readiness.
.DESCRIPTION
  PowerShell replacement for the appr-self-service-with-testing-visibility
  HTML portal. Runs the full self-service workflow (KB search or local file
  upload, upload, create, watch packaging) and - if automatic smoke testing
  is enabled in Default Settings - continues watching per-package ACE
  (Automated Compatibility Engine) test results until they complete.

  Per-format test results are reported as a table: format (MSI / MSIX /
  IntuneWin / ...), RAG status (Pass / Warn / Fail), progress, and time taken.
.PARAMETER InstanceUrl
  Base URL of the App Readiness instance. Not required if already connected
  via Connect-JuribaAppR.
.PARAMETER APIKey
  API key. Not required if already connected.
.PARAMETER SearchTerm
  Non-interactive: search the KB for this term and auto-select the top result
  and latest version/x64-preferred source.
.PARAMETER SetupFilePath
  Non-interactive: skip the KB, upload this local installer directly.
.PARAMETER IntervalSeconds
  Packaging status poll interval. Default 60.
.PARAMETER TimeoutMinutes
  Packaging status timeout. Default 60.
.PARAMETER TestTimeoutMinutes
  Smoke-test poll timeout once packaging completes. Default 60.
.PARAMETER TestIntervalSeconds
  Smoke-test poll interval. Default 20.
.PARAMETER SkipTestVisibility
  When specified, stops after packaging even if auto smoke testing is enabled.
.EXAMPLE
  .\Invoke-JuribaAppRSelfServiceWithTesting.ps1 -InstanceUrl "https://sandbox.appr.juriba.app" -APIKey $key
  Fully interactive mode.
.EXAMPLE
  .\Invoke-JuribaAppRSelfServiceWithTesting.ps1 -InstanceUrl "https://sandbox.appr.juriba.app" -APIKey $key -SearchTerm "7-Zip"
  Non-interactive KB run with post-packaging smoke-test monitoring.
#>

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
    Justification = 'Interactive example script - user-facing colored console output for progress and results.')]
[CmdletBinding(DefaultParameterSetName = 'Interactive')]
param (
    [Parameter(Mandatory = $false)]
    [string]$InstanceUrl,

    [Parameter(Mandatory = $false)]
    [string]$APIKey,

    [Parameter(ParameterSetName = 'KB')]
    [string]$SearchTerm,

    [Parameter(ParameterSetName = 'Local')]
    [string]$SetupFilePath,

    [int]$IntervalSeconds     = 60,
    [int]$TimeoutMinutes      = 60,
    [int]$TestIntervalSeconds = 20,
    [int]$TestTimeoutMinutes  = 60,

    [switch]$SkipTestVisibility
)

$ErrorActionPreference = 'Stop'

# --- Import module -----------------------------------------------------------
$modulePath = Join-Path (Join-Path $PSScriptRoot '..') 'Juriba.AppR.psd1'
if (-not (Test-Path $modulePath)) {
    Write-Error "Cannot find Juriba.AppR.psd1 at $modulePath. Run this script from its own folder."
}
Import-Module $modulePath -Force
Write-Host "Juriba.AppR module imported" -ForegroundColor Cyan

# --- Connect -----------------------------------------------------------------
$connectedHere  = $false
$existing       = Get-JuribaAppRSession
$activeInstance = $null
if ($existing -and -not $InstanceUrl) {
    $activeInstance = $existing.Instance
    Write-Host "Using existing session: $activeInstance" -ForegroundColor Green
}
else {
    if (-not $InstanceUrl) { $InstanceUrl = Read-Host "Instance URL (e.g. https://sandbox.appr.juriba.app)" }
    if (-not $APIKey)      { $APIKey      = Read-Host "API key" -MaskInput }
    Connect-JuribaAppR -Instance $InstanceUrl -APIKey $APIKey
    $activeInstance = $InstanceUrl
    Write-Host "Connected to $activeInstance" -ForegroundColor Green
    $connectedHere  = $true
}

# --- Helpers -----------------------------------------------------------------
# Package type labels (server TypeOfPackage enum, matching the HTML portal)
$pkgLabels = @{
    0  = 'MSI'
    1  = 'App-V'
    2  = 'MSIX'
    3  = 'MSIX'
    4  = 'IntuneWin'
    5  = 'MSIX App Attach'
    6  = 'PSADT'
    -1 = 'Source'
}

function Get-TestState {
    <#
    Returns @{ Status = string; Color = ConsoleColor; Done = bool; Progress = int }
    from an ACE evergreenInformation entry.
    #>
    param($EgEntry)

    if (-not $EgEntry) { return @{ Status = 'Pending'; Color = 'DarkGray'; Done = $false; Progress = 0 } }
    $t = $EgEntry[0]
    if ($t.complete -and $t.rAGStatus -eq 1) { return @{ Status = 'Passed';                Color = 'Green';     Done = $true;  Progress = 100 } }
    if ($t.complete -and $t.rAGStatus -eq 2) { return @{ Status = 'Passed with warnings';  Color = 'Yellow';    Done = $true;  Progress = 100 } }
    if ($t.complete -and ($t.rAGStatus -eq 3 -or $t.statusId -eq 100)) {
                                               return @{ Status = 'Failed';                Color = 'Red';       Done = $true;  Progress = ($t.progress ?? 0) } }
    if ($t.progress -gt 0)                   { return @{ Status = "Testing $($t.progress)%"; Color = 'Cyan';   Done = $false; Progress = $t.progress } }
    return @{ Status = 'Queued'; Color = 'DarkGray'; Done = $false; Progress = 0 }
}

function Watch-SmokeTest {
    param (
        [int]$AppId,
        [int]$IntervalSeconds,
        [int]$TimeoutMinutes
    )

    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    $lastSummary = $null
    $finalEntries = $null

    while ((Get-Date) -lt $deadline) {
        try {
            $tests = @(Get-JuribaAppRTestApplication -AppId $AppId)
        }
        catch {
            Write-Host "  Test poll error: $($_.Exception.Message)" -ForegroundColor DarkGray
            Start-Sleep -Seconds $IntervalSeconds
            continue
        }

        $entries = @($tests | Where-Object { $_.typeOfPackage -ge 0 })
        if (-not $entries.Count) {
            Start-Sleep -Seconds $IntervalSeconds
            continue
        }

        $summary = foreach ($t in $entries) {
            $format = $script:pkgLabels[[int]$t.typeOfPackage]
            if (-not $format) { $format = "Type $($t.typeOfPackage)" }
            $eg = $t.evergreenInformation
            $st = Get-TestState -EgEntry $eg
            $vm = if ($eg) { $eg[0].virtualMachineName } else { $null }
            $tt = if ($eg) { $eg[0].testingTimeTakenString } else { $null }
            [PSCustomObject]@{
                Format  = $format
                Status  = $st.Status
                Done    = $st.Done
                Color   = $st.Color
                VM      = $vm
                Time    = $tt
                Entry   = $t
            }
        }

        $summaryKey = ($summary | ForEach-Object { "$($_.Format)=$($_.Status)" }) -join ';'
        if ($summaryKey -ne $lastSummary) {
            Write-Host ""
            Write-Host ("{0,-18} {1,-30} {2,-30} {3}" -f 'Format', 'Status', 'VM', 'Time')
            Write-Host ("{0,-18} {1,-30} {2,-30} {3}" -f ('-' * 18), ('-' * 30), ('-' * 30), ('-' * 10))
            foreach ($row in $summary) {
                $line = "{0,-18} {1,-30} {2,-30} {3}" -f $row.Format, $row.Status, ($row.VM ?? ''), ($row.Time ?? '')
                Write-Host $line -ForegroundColor $row.Color
            }
            $lastSummary = $summaryKey
        }

        $finalEntries = $summary
        if (($summary | Where-Object { -not $_.Done }).Count -eq 0) {
            Write-Host "`nAll smoke tests complete." -ForegroundColor Green
            return $finalEntries
        }

        Start-Sleep -Seconds $IntervalSeconds
    }

    Write-Warning "Smoke-test watch timed out after $TimeoutMinutes minutes."
    return $finalEntries
}

try {
    # --- Detect autoSmokeTest from Default Settings --------------------------
    # Default-setting type 8 with value=true indicates auto smoke testing.
    $autoSmokeTest = $false
    try {
        $settings = Get-JuribaAppRDefaultSetting
        if ($settings.Raw) {
            $smokeSetting = $settings.Raw | Where-Object { [int]$_.defaultSettingType -eq 8 } | Select-Object -First 1
            if ($smokeSetting -and $smokeSetting.value -eq 'true') { $autoSmokeTest = $true }
        }
    }
    catch {
        Write-Warning "Could not read Default Settings: $($_.Exception.Message)"
    }
    Write-Host ("Auto smoke testing: {0}" -f ($(if ($autoSmokeTest) { 'enabled' } else { 'disabled' }))) -ForegroundColor Cyan

    # --- Choose source -------------------------------------------------------
    $mode = switch ($PSCmdlet.ParameterSetName) {
        'KB'    { 'kb' }
        'Local' { 'local' }
        default {
            Write-Host ""
            Write-Host "Choose a source:" -ForegroundColor Cyan
            Write-Host "  [1] Search the Knowledge Base"
            Write-Host "  [2] Upload a local installer"
            $choice = Read-Host "Select (1-2)"
            if ($choice -eq '2') { 'local' } else { 'kb' }
        }
    }

    $localPath = $null
    $metaHint  = $null
    $cleanupTempDownload = $false

    # --- KB source -----------------------------------------------------------
    if ($mode -eq 'kb') {
        if (-not $SearchTerm) { $SearchTerm = Read-Host "Search term" }

        Write-Host "`n=== Searching Knowledge Base for '$SearchTerm' ===" -ForegroundColor Magenta
        $kbResults = @(Search-JuribaAppRKnowledgeBase -Search $SearchTerm)
        if (-not $kbResults.Count) { throw "No Knowledge Base matches for '$SearchTerm'." }

        Write-Host "Found $($kbResults.Count) application(s):"
        for ($i = 0; $i -lt $kbResults.Count; $i++) {
            Write-Host ("  [{0}] {1} ({2})" -f ($i + 1), $kbResults[$i].applicationName, $kbResults[$i].vendorName)
        }
        $appChoice = if ($kbResults.Count -eq 1 -or $PSCmdlet.ParameterSetName -eq 'KB') {
            $kbResults[0]
        }
        else {
            $idx = [int](Read-Host "Select application number (1-$($kbResults.Count))")
            $kbResults[$idx - 1]
        }
        Write-Host "Selected: $($appChoice.applicationName)" -ForegroundColor Green

        Write-Host "`n=== Fetching sources ===" -ForegroundColor Magenta
        $sources = @(Search-JuribaAppRKnowledgeBase -ApplicationId $appChoice.applicationId)
        if (-not $sources.Count) { throw "No sources found for '$($appChoice.applicationName)'." }

        $uniqueVersions = $sources |
            Select-Object -ExpandProperty version -Unique |
            Sort-Object { try { [version]($_ -replace '[^0-9.]', '') } catch { [version]'0.0' } } -Descending
        $topVersions = @($uniqueVersions | Select-Object -First 5)

        $verChoice = if ($topVersions.Count -eq 1 -or $PSCmdlet.ParameterSetName -eq 'KB') {
            $topVersions[0]
        }
        else {
            Write-Host "Latest versions:"
            for ($i = 0; $i -lt $topVersions.Count; $i++) {
                Write-Host ("  [{0}] {1}" -f ($i + 1), $topVersions[$i])
            }
            $idx = Read-Host "Select version (1-$($topVersions.Count)) [default: 1 = latest]"
            if (-not $idx) { $idx = 1 }
            $topVersions[[int]$idx - 1]
        }
        Write-Host "Version: $verChoice" -ForegroundColor Green

        $versionSources = @($sources | Where-Object { $_.version -eq $verChoice })
        $srcChoice = if ($versionSources.Count -eq 1 -or $PSCmdlet.ParameterSetName -eq 'KB') {
            $x64Exe = $versionSources | Where-Object { $_.architecture -eq 64 -and $_.fileName -match '\.exe$' } | Select-Object -First 1
            if ($x64Exe) { $x64Exe } else { $versionSources[0] }
        }
        else {
            Write-Host "Sources for v${verChoice}:"
            for ($i = 0; $i -lt $versionSources.Count; $i++) {
                $arch = switch ($versionSources[$i].architecture) { 32 { 'x86' } 64 { 'x64' } default { "arch$($versionSources[$i].architecture)" } }
                Write-Host ("  [{0}] {1} ({2})" -f ($i + 1), $versionSources[$i].fileName, $arch)
            }
            $idx = Read-Host "Select source (1-$($versionSources.Count))"
            $versionSources[[int]$idx - 1]
        }
        Write-Host "Source: $($srcChoice.fileName)" -ForegroundColor Green

        Write-Host "`n=== Downloading $($srcChoice.fileName) ===" -ForegroundColor Magenta
        $downloadDir = Join-Path ([System.IO.Path]::GetTempPath()) "JuribaAppR-SelfService"
        if (-not (Test-Path $downloadDir)) { New-Item -ItemType Directory -Path $downloadDir | Out-Null }
        $localPath = Join-Path $downloadDir $srcChoice.fileName

        if (Test-Path $localPath) {
            Write-Host "Already cached: $localPath" -ForegroundColor DarkGray
        }
        else {
            Invoke-WebRequest -Uri $srcChoice.downloadUrl -OutFile $localPath -UseBasicParsing
            Write-Host ("Downloaded {0:N2} MB to {1}" -f ((Get-Item $localPath).Length / 1MB), $localPath) -ForegroundColor Green
            $cleanupTempDownload = $true
        }

        $metaHint = @{
            Name         = $srcChoice.productName -as [string] ?? $appChoice.applicationName
            Manufacturer = $srcChoice.vendor      -as [string] ?? $appChoice.vendorName
            Version      = $srcChoice.version
        }
    }
    # --- Local source --------------------------------------------------------
    else {
        if (-not $SetupFilePath) { $SetupFilePath = Read-Host "Path to installer" }
        if (-not (Test-Path $SetupFilePath -PathType Leaf)) { throw "File not found: $SetupFilePath" }
        $localPath = (Resolve-Path $SetupFilePath).Path
    }

    # --- Upload --------------------------------------------------------------
    Write-Host "`n=== Uploading ===" -ForegroundColor Magenta
    $upload = Send-JuribaAppRSetupFile -FilePath $localPath -Verbose:$VerbosePreference
    Write-Host ("Uploaded: {0} ({1:N2} MB, {2} chunks, UUID={3})" -f $upload.FileName, ($upload.FileSize / 1MB), $upload.TotalChunks, $upload.Uuid) -ForegroundColor Green

    # --- Create application --------------------------------------------------
    Write-Host "`n=== Creating application ===" -ForegroundColor Magenta
    $splat = @{
        Uuid           = $upload.Uuid
        FileName       = $upload.FileName
        FileSize       = $upload.FileSize
        TotalChunks    = $upload.TotalChunks
        RunImmediately = $true
    }
    if ($metaHint) {
        if ($metaHint.Name)         { $splat['Name']         = $metaHint.Name }
        if ($metaHint.Manufacturer) { $splat['Manufacturer'] = $metaHint.Manufacturer }
        if ($metaHint.Version)      { $splat['Version']      = $metaHint.Version }
    }
    else {
        if ($upload.Name)         { $splat['Name']         = $upload.Name }
        if ($upload.Manufacturer) { $splat['Manufacturer'] = $upload.Manufacturer }
        if ($upload.Version)      { $splat['Version']      = $upload.Version }
    }
    New-JuribaAppRApplication @splat -Verbose:$VerbosePreference | Out-Null
    Write-Host "Application submitted" -ForegroundColor Green

    # --- Wait for application ID ---------------------------------------------
    Write-Host "`n=== Waiting for application ID ===" -ForegroundColor Magenta
    $appId = $null
    $creationDeadline = (Get-Date).AddMinutes(5)
    while ((Get-Date) -lt $creationDeadline) {
        try {
            $state = Get-JuribaAppRApplicationCreationState -UploadId $upload.Uuid
            $resolved = if ($state.data.applicationId) { $state.data.applicationId }
                        elseif ($state.applicationId)   { $state.applicationId }
                        else { $null }
            if ($resolved -and $resolved -gt 0) { $appId = $resolved; break }
        }
        catch { Write-Verbose "Creation-state poll failed: $($_.Exception.Message)" }
        Write-Host "  waiting..." -ForegroundColor DarkGray
        Start-Sleep -Seconds 10
    }
    if (-not $appId) { throw "Timed out waiting for the application ID." }
    Write-Host "Application ID: $appId" -ForegroundColor Green
    Write-Host ("View in App Readiness: {0}/applications/fullStatus/{1}" -f $activeInstance, $appId) -ForegroundColor Cyan

    # --- Watch packaging -----------------------------------------------------
    Write-Host "`n=== Watching packaging (Step 2 of 3) ===" -ForegroundColor Magenta
    $pkgResult = Watch-JuribaAppRApplicationStatus -AppId $appId `
        -IntervalSeconds $IntervalSeconds -TimeoutMinutes $TimeoutMinutes
    $packagingSucceeded = $pkgResult.Status -notmatch 'Fail|Cancel|Timeout'

    # --- Watch smoke tests ---------------------------------------------------
    $testResults = $null
    if ($packagingSucceeded -and $autoSmokeTest -and -not $SkipTestVisibility) {
        Write-Host "`n=== Watching smoke tests (Step 3 of 3) ===" -ForegroundColor Magenta
        $testResults = Watch-SmokeTest -AppId $appId `
            -IntervalSeconds $TestIntervalSeconds -TimeoutMinutes $TestTimeoutMinutes
    }
    elseif ($packagingSucceeded -and -not $autoSmokeTest) {
        Write-Host "`n(Auto smoke testing is not enabled on this instance; skipping Step 3.)" -ForegroundColor DarkGray
    }

    # --- Result summary ------------------------------------------------------
    Write-Host "`n=== Result ===" -ForegroundColor Magenta
    $statusColor = if ($packagingSucceeded) { 'Green' } else { 'Red' }
    Write-Host ("Packaging: {0} ({1}%)" -f $pkgResult.Status, $pkgResult.Progress) -ForegroundColor $statusColor
    if ($testResults) {
        Write-Host "Smoke tests:"
        foreach ($row in $testResults) {
            Write-Host ("  {0,-18} {1,-30} {2}" -f $row.Format, $row.Status, ($row.Time ?? '')) -ForegroundColor $row.Color
        }
    }
    Write-Host ("URL: {0}/applications/fullStatus/{1}" -f $activeInstance, $appId) -ForegroundColor Cyan

    if (-not $packagingSucceeded) {
        Write-Host "`nEvent history:" -ForegroundColor Yellow
        try {
            $events = Get-JuribaAppRApplicationEvent -AppId $appId
            $events | ForEach-Object {
                $ts  = $_.date ?? $_.timestamp ?? ''
                $msg = $_.message ?? $_.description ?? ($_ | ConvertTo-Json -Compress)
                Write-Host "  [$ts] $msg"
            }
        }
        catch { Write-Host "  (could not retrieve events: $($_.Exception.Message))" -ForegroundColor DarkGray }
    }

    [PSCustomObject]@{
        AppId            = $appId
        PackagingStatus  = $pkgResult.Status
        PackagingResult  = $pkgResult
        AutoSmokeTest    = $autoSmokeTest
        TestResults      = $testResults
    }
}
finally {
    if ($cleanupTempDownload -and $localPath -and (Test-Path $localPath)) {
        Remove-Item $localPath -Force -ErrorAction SilentlyContinue
    }
    if ($connectedHere) { Disconnect-JuribaAppR }
}
