<#
.SYNOPSIS
  Interactive self-service packaging for Juriba App Readiness.
.DESCRIPTION
  A console-driven replacement for the HTML/JS self-service portal. Mirrors
  the portal's workflow end-to-end using only the Juriba.AppR PowerShell module:

    1. Connect to the App Readiness instance.
    2. Choose a source:
         KB   - Search the Knowledge Base, pick an application/version/file,
                download it locally, then upload.
         File - Point at an existing installer on disk.
    3. Upload the installer (chunked).
    4. Create the application - server-side metadata extraction and command
       suggestion are used automatically by New-JuribaAppRApplication.
    5. Wait for the application ID to resolve.
    6. Watch packaging status through to a terminal state.

  The script can be driven interactively (prompted menus) or non-interactively
  by passing -SearchTerm or -SetupFilePath.
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
.EXAMPLE
  .\Invoke-JuribaAppRSelfService.ps1 -InstanceUrl "https://sandbox.appr.juriba.app" -APIKey $key
  Fully interactive mode.
.EXAMPLE
  .\Invoke-JuribaAppRSelfService.ps1 -InstanceUrl "https://sandbox.appr.juriba.app" -APIKey $key -SearchTerm "7-Zip"
  Non-interactive KB run.
.EXAMPLE
  .\Invoke-JuribaAppRSelfService.ps1 -InstanceUrl "https://sandbox.appr.juriba.app" -APIKey $key -SetupFilePath "C:\Installers\Firefox-Setup.exe"
  Non-interactive local-file run.
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

    [int]$IntervalSeconds = 60,
    [int]$TimeoutMinutes  = 60
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

try {
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

    $localPath    = $null
    $metaHint     = $null  # KB-provided metadata hints (name, manufacturer, version)
    $cleanupTempDownload = $false

    # --- KB source -----------------------------------------------------------
    if ($mode -eq 'kb') {
        if (-not $SearchTerm) { $SearchTerm = Read-Host "Search term" }

        Write-Host "`n=== Searching Knowledge Base for '$SearchTerm' ===" -ForegroundColor Magenta
        $kbResults = @(Search-JuribaAppRKnowledgeBase -Search $SearchTerm)
        if (-not $kbResults.Count) {
            throw "No Knowledge Base matches for '$SearchTerm'. Try the -SetupFilePath path instead."
        }

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

        # Get versions + sources for the chosen app
        Write-Host "`n=== Fetching sources ===" -ForegroundColor Magenta
        $sources = @(Search-JuribaAppRKnowledgeBase -ApplicationId $appChoice.applicationId)
        if (-not $sources.Count) { throw "No sources found for '$($appChoice.applicationName)'." }

        # Latest versions first
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

        # Filter sources for the chosen version
        $versionSources = @($sources | Where-Object { $_.version -eq $verChoice })

        $srcChoice = if ($versionSources.Count -eq 1 -or $PSCmdlet.ParameterSetName -eq 'KB') {
            # Auto-select: prefer x64 EXE
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

        # Download the installer locally for Send-JuribaAppRSetupFile
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
        if (-not (Test-Path $SetupFilePath -PathType Leaf)) {
            throw "File not found: $SetupFilePath"
        }
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
    # Metadata priority: KB hint > PE info on disk > server extraction (handled by cmdlet)
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
    if (-not $appId) { throw "Timed out waiting for the application ID. Check the UI at $activeInstance." }
    Write-Host "Application ID: $appId" -ForegroundColor Green
    Write-Host ("View in App Readiness: {0}/applications/fullStatus/{1}" -f $activeInstance, $appId) -ForegroundColor Cyan

    # --- Watch packaging -----------------------------------------------------
    Write-Host "`n=== Watching packaging status ===" -ForegroundColor Magenta
    $result = Watch-JuribaAppRApplicationStatus -AppId $appId `
        -IntervalSeconds $IntervalSeconds -TimeoutMinutes $TimeoutMinutes

    # --- Result summary ------------------------------------------------------
    Write-Host "`n=== Result ===" -ForegroundColor Magenta
    $statusColor = if ($result.Status -match 'Fail|Cancel|Timeout') { 'Red' } else { 'Green' }
    Write-Host ("Status:   {0}" -f $result.Status)   -ForegroundColor $statusColor
    Write-Host ("Progress: {0}%" -f $result.Progress)
    Write-Host ("Elapsed:  {0}"  -f $result.Elapsed)
    Write-Host ("Polls:    {0}"  -f $result.PollCount)
    Write-Host ("URL:      {0}/applications/fullStatus/{1}" -f $activeInstance, $appId) -ForegroundColor Cyan

    if ($result.Status -match 'Fail|Cancel') {
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

    # Return the result object for pipeline use
    $result
}
finally {
    if ($cleanupTempDownload -and $localPath -and (Test-Path $localPath)) {
        Remove-Item $localPath -Force -ErrorAction SilentlyContinue
    }
    if ($connectedHere) { Disconnect-JuribaAppR }
}
