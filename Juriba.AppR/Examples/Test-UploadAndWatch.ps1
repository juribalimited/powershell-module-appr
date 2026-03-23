<#
.SYNOPSIS
  Real-world end-to-end test: upload a package, create the app, and poll until packaging completes.
.DESCRIPTION
  Demonstrates the primary automation use case: upload an installer, create the application
  with -RunImmediately, and watch the workflow status every 5 minutes until it reaches
  "ReadyForQualityReview" (Ready for QR).
.PARAMETER InstanceUrl
  The base URL of the App Readiness instance.
.PARAMETER APIKey
  Your API key for authentication.
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

param (
    [Parameter(Mandatory = $true)]
    [string]$InstanceUrl,

    [Parameter(Mandatory = $true)]
    [string]$APIKey,

    [Parameter(Mandatory = $true)]
    [string]$SetupFilePath,

    [int]$IntervalSeconds = 300,

    [int]$TimeoutMinutes = 30
)

$ErrorActionPreference = 'Stop'

# Import the module
$modulePath = Join-Path $PSScriptRoot '..' 'Juriba.AppR.psd1'
Import-Module $modulePath -Force
Write-Host "Module imported" -ForegroundColor Cyan

# 1. CONNECT
Write-Host "`n=== Step 1: Connect ===" -ForegroundColor Magenta
Connect-JuribaAppR -Instance $InstanceUrl -APIKey $APIKey
Write-Host "Connected to $InstanceUrl"

# 2. UPLOAD
Write-Host "`n=== Step 2: Upload ===" -ForegroundColor Magenta
$upload = Send-JuribaAppRSetupFile -FilePath $SetupFilePath -Verbose
Write-Host "Uploaded: $($upload.FileName) ($([Math]::Round($upload.FileSize / 1MB, 2)) MB)"
Write-Host "  UUID:         $($upload.Uuid)"
Write-Host "  ProductName:  $($upload.ProductName)"
Write-Host "  CompanyName:  $($upload.CompanyName)"
Write-Host "  Version:      $($upload.ProductVersion)"

# 3. CREATE APPLICATION (with RunImmediately)
Write-Host "`n=== Step 3: Create Application ===" -ForegroundColor Magenta

$splatCreate = @{
    Uuid           = $upload.Uuid
    FileName       = $upload.FileName
    FileSize       = $upload.FileSize
    TotalChunks    = $upload.TotalChunks
    RunImmediately = $true
}
if ($upload.ProductName)    { $splatCreate['Name']         = $upload.ProductName }
if ($upload.CompanyName)    { $splatCreate['Manufacturer'] = $upload.CompanyName }
if ($upload.ProductVersion) { $splatCreate['Version']      = $upload.ProductVersion }

# Select the default repackaging VM group — the server requires vmGroupId
# to allocate a real VM. Without it, only a "Temporary machine" is assigned
# and no VM spins up.
$vmGroups = Get-JuribaAppRVMGroup
$repackVm = $vmGroups | Where-Object { $_.isDefaultForRepackaging -eq $true } | Select-Object -First 1
if (-not $repackVm) {
    # Fall back to any group with machines
    $repackVm = $vmGroups | Where-Object { $_.machines.Count -gt 0 } | Select-Object -First 1
}
if ($repackVm) {
    $splatCreate['VMGroupId'] = $repackVm.id
    Write-Host "Using VM group: $($repackVm.name) (id=$($repackVm.id))"
}
else {
    Write-Warning "No VM group with machines found. Packaging may not start."
}

$app = New-JuribaAppRApplication @splatCreate -Verbose
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
    $match = $allApps | Where-Object { $_.basic.name -eq $upload.ProductName -or $_.basic.name -like "*$([System.IO.Path]::GetFileNameWithoutExtension($upload.FileName))*" } |
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

# Disconnect
Disconnect-JuribaAppR
