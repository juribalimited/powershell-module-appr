<#
.SYNOPSIS
  Search the Juriba Knowledge Base, pick an application, download it, and package it.
.DESCRIPTION
  Demonstrates the KB-driven automation use case:
    1. Search the Juriba KB by application name
    2. Present results and let the user choose an app, version, and architecture
    3. Download the setup file from the KB's download URL
    4. Upload it via Send-JuribaAppRSetupFile
    5. Create the application via New-JuribaAppRApplication with -RunImmediately
    6. Watch packaging status to completion
.PARAMETER InstanceUrl
  The base URL of the App Readiness instance.
.PARAMETER APIKey
  Your API key for authentication.
.PARAMETER SearchTerm
  The application name to search for in the Knowledge Base.
.PARAMETER IntervalSeconds
  Seconds between status polls. Default 60.
.PARAMETER TimeoutMinutes
  Maximum minutes to wait for packaging. Default 30.
.EXAMPLE
  .\Test-KBSearchAndPackage.ps1 -InstanceUrl "https://demo.appr.juriba.app" `
      -APIKey "your-key" -SearchTerm "7-Zip"
#>

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
    Justification = 'Interactive example script - user-facing colored console output for progress and results.')]
[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string]$InstanceUrl,

    [Parameter(Mandatory = $true)]
    [string]$APIKey,

    [Parameter(Mandatory = $true)]
    [string]$SearchTerm,

    [int]$IntervalSeconds = 60,

    [int]$TimeoutMinutes = 30
)

$ErrorActionPreference = 'Stop'

# Import the module
$modulePath = Join-Path (Join-Path $PSScriptRoot '..') 'Juriba.AppR.psd1'
Import-Module $modulePath -Force
Write-Host "Module imported" -ForegroundColor Cyan

# 1. CONNECT
Write-Host "`n=== Step 1: Connect ===" -ForegroundColor Magenta
Connect-JuribaAppR -Instance $InstanceUrl -APIKey $APIKey
Write-Host "Connected to $InstanceUrl"

# 2. SEARCH THE KNOWLEDGE BASE
Write-Host "`n=== Step 2: Search Knowledge Base for '$SearchTerm' ===" -ForegroundColor Magenta
$kbResults = Search-JuribaAppRKnowledgeBase -Search $SearchTerm

if (-not $kbResults -or $kbResults.Count -eq 0) {
    Write-Error "No results found in the Knowledge Base for '$SearchTerm'."
}

Write-Host "Found $($kbResults.Count) application(s):`n"
for ($i = 0; $i -lt $kbResults.Count; $i++) {
    Write-Host "  [$($i + 1)] $($kbResults[$i].applicationName)  ($($kbResults[$i].vendorName))"
}

# Choose application
if ($kbResults.Count -eq 1) {
    $appChoice = $kbResults[0]
    Write-Host "`nAuto-selected: $($appChoice.applicationName)" -ForegroundColor Green
}
else {
    $appIdx = Read-Host "`nSelect application number (1-$($kbResults.Count))"
    $appChoice = $kbResults[[int]$appIdx - 1]
    Write-Host "Selected: $($appChoice.applicationName)" -ForegroundColor Green
}

# 3. GET VERSIONS / SOURCES
Write-Host "`n=== Step 3: Get available versions ===" -ForegroundColor Magenta
$sources = Search-JuribaAppRKnowledgeBase -ApplicationId $appChoice.applicationId

if (-not $sources -or $sources.Count -eq 0) {
    Write-Error "No versions found for '$($appChoice.applicationName)'."
}

# Get unique versions sorted descending, show latest few
$uniqueVersions = $sources | Select-Object -Property version -Unique | Sort-Object { [version]($_.version -replace '[^0-9.]', '') } -Descending -ErrorAction SilentlyContinue
if (-not $uniqueVersions) {
    $uniqueVersions = $sources | Select-Object -Property version -Unique
}
$topVersions = @($uniqueVersions | Select-Object -First 5)

Write-Host "Latest versions:"
for ($i = 0; $i -lt $topVersions.Count; $i++) {
    Write-Host "  [$($i + 1)] $($topVersions[$i].version)"
}

# Choose version
if ($topVersions.Count -eq 1) {
    $verChoice = $topVersions[0].version
    Write-Host "`nAuto-selected version: $verChoice" -ForegroundColor Green
}
else {
    $verIdx = Read-Host "`nSelect version number (1-$($topVersions.Count)) [default: 1 = latest]"
    if (-not $verIdx) { $verIdx = 1 }
    $verChoice = $topVersions[[int]$verIdx - 1].version
    Write-Host "Selected version: $verChoice" -ForegroundColor Green
}

# Filter sources for chosen version, prefer x64 EXE
$versionSources = @($sources | Where-Object { $_.version -eq $verChoice })
Write-Host "`nAvailable sources for v$verChoice`:"
for ($i = 0; $i -lt $versionSources.Count; $i++) {
    $archLabel = switch ($versionSources[$i].architecture) { 32 { 'x86' } 64 { 'x64' } default { "arch$($versionSources[$i].architecture)" } }
    Write-Host "  [$($i + 1)] $($versionSources[$i].fileName)  ($archLabel)"
}

# Choose source
if ($versionSources.Count -eq 1) {
    $srcChoice = $versionSources[0]
    Write-Host "`nAuto-selected: $($srcChoice.fileName)" -ForegroundColor Green
}
else {
    # Default to first x64 EXE if available
    $defaultIdx = 0
    $x64Exe = $versionSources | Where-Object { $_.architecture -eq 64 -and $_.fileName -match '\.exe$' } | Select-Object -First 1
    if ($x64Exe) {
        $defaultIdx = [Array]::IndexOf($versionSources, $x64Exe)
    }
    $srcIdx = Read-Host "`nSelect source number (1-$($versionSources.Count)) [default: $($defaultIdx + 1)]"
    if (-not $srcIdx) { $srcIdx = $defaultIdx + 1 }
    $srcChoice = $versionSources[[int]$srcIdx - 1]
    Write-Host "Selected: $($srcChoice.fileName)" -ForegroundColor Green
}

# 4. DOWNLOAD THE SETUP FILE
Write-Host "`n=== Step 4: Download setup file ===" -ForegroundColor Magenta
$downloadDir = Join-Path ([System.IO.Path]::GetTempPath()) "JuribaAppR-KB"
if (-not (Test-Path $downloadDir)) { New-Item -ItemType Directory -Path $downloadDir | Out-Null }
$localPath = Join-Path $downloadDir $srcChoice.fileName

if (Test-Path $localPath) {
    Write-Host "File already exists locally: $localPath" -ForegroundColor DarkGray
}
else {
    Write-Host "Downloading $($srcChoice.downloadUrl)..."
    Invoke-WebRequest -Uri $srcChoice.downloadUrl -OutFile $localPath -UseBasicParsing
    Write-Host "Downloaded to: $localPath ($([Math]::Round((Get-Item $localPath).Length / 1MB, 2)) MB)" -ForegroundColor Green
}

# 5. UPLOAD
Write-Host "`n=== Step 5: Upload ===" -ForegroundColor Magenta
$upload = Send-JuribaAppRSetupFile -FilePath $localPath -Verbose
Write-Host "Uploaded: $($upload.FileName) ($([Math]::Round($upload.FileSize / 1MB, 2)) MB)"
Write-Host "  UUID: $($upload.Uuid)"

# 6. CREATE APPLICATION
Write-Host "`n=== Step 6: Create Application ===" -ForegroundColor Magenta
$splatCreate = @{
    Uuid           = $upload.Uuid
    FileName       = $upload.FileName
    FileSize       = $upload.FileSize
    TotalChunks    = $upload.TotalChunks
    RunImmediately = $true
}

# Pass KB metadata as hints
if ($srcChoice.productName)  { $splatCreate['Name']         = $srcChoice.productName }
if ($srcChoice.vendor)       { $splatCreate['Manufacturer'] = $srcChoice.vendor }
if ($srcChoice.version)      { $splatCreate['Version']      = $srcChoice.version }

$app = New-JuribaAppRApplication @splatCreate -Verbose
Write-Host "Application created."
$app | Format-List

# 7. WAIT FOR CREATION TO RESOLVE
Write-Host "`n=== Step 7: Wait for creation to resolve ===" -ForegroundColor Magenta
$appId = $null
$creationTimeout = (Get-Date).AddMinutes(5)
while ((Get-Date) -lt $creationTimeout) {
    try {
        $state = Get-JuribaAppRApplicationCreationState -UploadId $upload.Uuid
        $resolvedId = if ($state.data.applicationId) { $state.data.applicationId }
                      elseif ($state.applicationId)   { $state.applicationId }
                      else { $null }
        if ($resolvedId -and $resolvedId -gt 0) {
            $appId = $resolvedId
            Write-Host "Application ID resolved: $appId" -ForegroundColor Green
            break
        }
        Write-Host "  Waiting for app ID... (state: $($state | ConvertTo-Json -Compress))"
    }
    catch {
        Write-Host "  Waiting for creation state... ($($_.Exception.Message))" -ForegroundColor DarkGray
    }
    Start-Sleep -Seconds 10
}

if (-not $appId) {
    Write-Error "Could not determine the application ID. Check the UI manually."
}

# 8. POLL STATUS
Write-Host "`n=== Step 8: Watch packaging status (every $IntervalSeconds seconds, timeout $TimeoutMinutes min) ===" -ForegroundColor Magenta
$result = Watch-JuribaAppRApplicationStatus -AppId $appId `
    -IntervalSeconds $IntervalSeconds -TimeoutMinutes $TimeoutMinutes

Write-Host "`n=== Result ===" -ForegroundColor Magenta
Write-Host "Status:   $($result.Status)" -ForegroundColor $(if ($result.Status -eq 'ReadyForQualityReview') { 'Green' } else { 'Yellow' })
Write-Host "Progress: $($result.Progress)%"
Write-Host "Elapsed:  $($result.Elapsed)"
Write-Host "Polls:    $($result.PollCount)"

# On failure, dump diagnostics
if ($result.Status -match 'Fail|Cancel') {
    Write-Host "`n=== Failure Diagnostics ===" -ForegroundColor Red
    if ($result.AppDetail) {
        $ext = $result.AppDetail.ext
        if ($ext) {
            Write-Host "  ext.status:          $($ext.status)"
            Write-Host "  ext.progressPercent: $($ext.progressPercent)"
        }
        Write-Host "`n  Full ext object:" -ForegroundColor Yellow
        $ext | ConvertTo-Json -Depth 3 | Write-Host
    }
    try {
        Write-Host "`n  Event history:" -ForegroundColor Yellow
        $events = Get-JuribaAppRApplicationEvent -AppId $appId
        $events | ForEach-Object {
            $ts = if ($_.date) { $_.date } elseif ($_.timestamp) { $_.timestamp } else { '' }
            $msg = if ($_.message) { $_.message } elseif ($_.description) { $_.description } else { ($_ | ConvertTo-Json -Compress) }
            Write-Host "    [$ts] $msg"
        }
    }
    catch {
        Write-Host "    Could not retrieve events: $($_.Exception.Message)" -ForegroundColor DarkGray
    }
}

# Disconnect
Disconnect-JuribaAppR
