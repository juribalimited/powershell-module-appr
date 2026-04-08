<#
.SYNOPSIS
  Real-world end-to-end test: upload a package, create the app, and poll until packaging completes.
.DESCRIPTION
  Demonstrates the primary automation use case: upload an installer, create the application
  with -RunImmediately, and watch the workflow status every 5 minutes until it reaches
  "ReadyForQualityReview" (Ready for QR).

  New-JuribaAppRApplication handles the heavy lifting automatically:
    - Reads Default Settings for VM groups and output format bitmask
    - Calls server-side metadata extraction for name/manufacturer/version
    - Command lines are determined server-side by the product (not sent in the payload)
.PARAMETER InstanceUrl
  The base URL of the App Readiness instance. Not required if already connected via Connect-JuribaAppR.
.PARAMETER APIKey
  Your API key for authentication. Not required if already connected via Connect-JuribaAppR.
.PARAMETER SetupFilePath
  Path to the installer to upload (EXE, MSI, etc.).
.PARAMETER IntervalSeconds
  Seconds between status polls. Default 300 (5 minutes).
.PARAMETER TimeoutMinutes
  Maximum minutes to wait. Default 30.
.EXAMPLE
  .\Test-UploadAndWatch.ps1 -InstanceUrl "https://demo.appr.juriba.app" `
      -APIKey "your-key" -SetupFilePath "C:\Installers\7z2407-x64.exe"
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]$InstanceUrl,

    [Parameter(Mandatory = $false)]
    [string]$APIKey,

    [Parameter(Mandatory = $true)]
    [string]$SetupFilePath,

    [int]$IntervalSeconds = 300,

    [int]$TimeoutMinutes = 30
)

$ErrorActionPreference = 'Stop'

# Import the module
$modulePath = Join-Path (Join-Path $PSScriptRoot '..') 'Juriba.AppR.psd1'
Import-Module $modulePath -Force
Write-Host "Module imported" -ForegroundColor Cyan

# 1. CONNECT (skip if already connected)
Write-Host "`n=== Step 1: Connect ===" -ForegroundColor Magenta
if ($global:appRConnection) {
    Write-Host "Already connected to $($global:appRConnection.Instance)" -ForegroundColor Green
}
elseif ($InstanceUrl -and $APIKey) {
    Connect-JuribaAppR -Instance $InstanceUrl -APIKey $APIKey
    Write-Host "Connected to $InstanceUrl"
}
else {
    Write-Error "Not connected. Either run Connect-JuribaAppR first, or pass -InstanceUrl and -APIKey."
}

# 2. UPLOAD
Write-Host "`n=== Step 2: Upload ===" -ForegroundColor Magenta
$upload = Send-JuribaAppRSetupFile -FilePath $SetupFilePath -Verbose:$VerbosePreference
Write-Host "Uploaded: $($upload.FileName) ($([Math]::Round($upload.FileSize / 1MB, 2)) MB)"
Write-Host "  UUID:         $($upload.Uuid)"
Write-Host "  Name:         $($upload.Name)"
Write-Host "  Manufacturer: $($upload.Manufacturer)"
Write-Host "  Version:      $($upload.Version)"

# 3. CREATE APPLICATION
# New-JuribaAppRApplication now automatically:
#   - Reads Default Settings (VM groups, output format bitmask)
#   - Extracts metadata from the server (name, manufacturer, version)
#   - Command lines are NOT sent — the product determines them server-side
#     using hash matching, Juriba KB, and AI-based detection
Write-Host "`n=== Step 3: Create Application ===" -ForegroundColor Magenta

$splatCreate = @{
    Uuid           = $upload.Uuid
    FileName       = $upload.FileName
    FileSize       = $upload.FileSize
    TotalChunks    = $upload.TotalChunks
    RunImmediately = $true
}

# Pass any client-side metadata as hints (server-side extraction takes priority
# inside New-JuribaAppRApplication, but these serve as fallbacks)
if ($upload.Name)         { $splatCreate['Name']         = $upload.Name }
if ($upload.Manufacturer) { $splatCreate['Manufacturer'] = $upload.Manufacturer }
if ($upload.Version)      { $splatCreate['Version']      = $upload.Version }

$app = New-JuribaAppRApplication @splatCreate -Verbose:$VerbosePreference
Write-Host "Application created. Response:"
$app | Format-List

# 4. WAIT FOR CREATION TO RESOLVE (get the app ID)
Write-Host "`n=== Step 4: Wait for creation to resolve ===" -ForegroundColor Magenta
$appId = $null

# Poll the creation state to get the actual app ID
$creationTimeout = (Get-Date).AddMinutes(5)
while ((Get-Date) -lt $creationTimeout) {
    try {
        $state = Get-JuribaAppRApplicationCreationState -UploadId $upload.Uuid
        # applicationId is nested inside .data
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
    # Try to find it by listing recent apps
    Write-Host "  Searching application list for uploaded file..." -ForegroundColor Yellow
    $allApps = Get-JuribaAppRApplicationList -AllUsers
    $match = $allApps | Where-Object { $_.basic.name -eq $upload.Name -or $_.basic.name -like "*$([System.IO.Path]::GetFileNameWithoutExtension($upload.FileName))*" } |
        Sort-Object { $_.basic.id } -Descending | Select-Object -First 1
    if ($match) {
        $appId = $match.basic.id
        Write-Host "Found app by name: $($match.basic.name) (id=$appId)" -ForegroundColor Green
    }
    else {
        Write-Error "Could not determine the application ID. Check the UI manually."
    }
}

# 5. POLL STATUS
Write-Host "`n=== Step 5: Watch packaging status (every $IntervalSeconds seconds, timeout $TimeoutMinutes min) ===" -ForegroundColor Magenta
$result = Watch-JuribaAppRApplicationStatus -AppId $appId `
    -IntervalSeconds $IntervalSeconds -TimeoutMinutes $TimeoutMinutes

Write-Host "`n=== Result ===" -ForegroundColor Magenta
Write-Host "Status:   $($result.Status)" -ForegroundColor $(if ($result.Status -eq 'ReadyForQualityReview') { 'Green' } else { 'Yellow' })
Write-Host "Progress: $($result.Progress)%"
Write-Host "Elapsed:  $($result.Elapsed)"
Write-Host "Polls:    $($result.PollCount)"

# On failure, dump diagnostics to help debug
if ($result.Status -match 'Fail|Cancel') {
    Write-Host "`n=== Failure Diagnostics ===" -ForegroundColor Red

    # Dump relevant fields from the app detail returned by Watch
    if ($result.AppDetail) {
        $ext = $result.AppDetail.ext
        if ($ext) {
            Write-Host "  ext.status:          $($ext.status)"
            Write-Host "  ext.progressPercent: $($ext.progressPercent)"
            Write-Host "  ext.statusMessage:   $($ext.statusMessage)"
            Write-Host "  ext.errorMessage:    $($ext.errorMessage)"
        }
        # Show packaging info if present
        if ($result.AppDetail.packages) {
            Write-Host "`n  Packages:" -ForegroundColor Yellow
            $result.AppDetail.packages | ForEach-Object {
                Write-Host "    Type=$($_.packageType) Status=$($_.status) Error=$($_.errorMessage)"
            }
        }
        # Full ext dump for anything we missed
        Write-Host "`n  Full ext object:" -ForegroundColor Yellow
        $ext | ConvertTo-Json -Depth 3 | Write-Host
    }

    # Pull event history for the app
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

# Disconnect only if we connected in this script
if ($InstanceUrl -and $APIKey) {
    Disconnect-JuribaAppR
}
