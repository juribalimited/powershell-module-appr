<#
.SYNOPSIS
    End-to-end example: Upload a setup file, create an application, and monitor
    it through the App Readiness workflow.

.DESCRIPTION
    This script demonstrates the primary automation use case for Juriba App Readiness:
      1. Connect to the instance
      2. Upload a setup file (chunked)
      3. Create an application from the upload
      4. Poll for creation completion
      5. Monitor the packaging/testing workflow

    This is the pattern you would call from ServiceNow, a CI/CD pipeline, or any
    external system that needs to submit a packaging request and track it to completion.

.PARAMETER InstanceUrl
    The URL of the App Readiness instance (e.g. https://appr.example.com)

.PARAMETER APIKey
    The API key for authentication.

.PARAMETER SetupFilePath
    The full path to the installer file to upload (MSI, EXE, ZIP, etc.)

.PARAMETER ApplicationName
    Optional override name for the application.

.PARAMETER PollIntervalSeconds
    How often to check status, in seconds. Default: 300 (5 minutes).

.EXAMPLE
    .\Upload-And-Monitor.ps1 -InstanceUrl "https://appr.example.com" `
        -APIKey "your-key" `
        -SetupFilePath "C:\Installers\Firefox-Setup-115.0.exe"

.EXAMPLE
    .\Upload-And-Monitor.ps1 -InstanceUrl "https://appr.example.com" `
        -APIKey "your-key" `
        -SetupFilePath "C:\Installers\App.msi" `
        -ApplicationName "My Custom App 2.0" `
        -PollIntervalSeconds 60
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string]$InstanceUrl,

    [Parameter(Mandatory = $true)]
    [string]$APIKey,

    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$SetupFilePath,

    [Parameter(Mandatory = $false)]
    [string]$ApplicationName,

    [Parameter(Mandatory = $false)]
    [int]$PollIntervalSeconds = 300
)

# Ensure the module is loaded
$modulePath = Join-Path $PSScriptRoot ".." "Juriba.AppR.psd1"
if (Test-Path $modulePath) {
    Import-Module $modulePath -Force
}

# ─── Step 1: Connect ─────────────────────────────────────────────────────────
Write-Host "`n=== Step 1: Connecting to App Readiness ===" -ForegroundColor Cyan
Connect-JuribaAppR -Instance $InstanceUrl -APIKey $APIKey

# ─── Step 2: Upload the setup file ───────────────────────────────────────────
Write-Host "`n=== Step 2: Uploading setup file ===" -ForegroundColor Cyan
$fileName = (Get-Item $SetupFilePath).Name
Write-Host "File: $fileName"

$upload = Send-JuribaAppRSetupFile -FilePath $SetupFilePath
Write-Host "Upload complete. UUID: $($upload.Uuid)" -ForegroundColor Green

# ─── Step 3: Create the application ──────────────────────────────────────────
Write-Host "`n=== Step 3: Creating application ===" -ForegroundColor Cyan

$newAppParams = @{
    Uuid           = $upload.Uuid
    FileName       = $upload.FileName
    RunImmediately = $true
}

if ($ApplicationName) {
    $newAppParams['Name'] = $ApplicationName
}

$app = New-JuribaAppRApplication @newAppParams
Write-Host "Application creation submitted." -ForegroundColor Green

# ─── Step 4: Poll for creation completion ────────────────────────────────────
Write-Host "`n=== Step 4: Waiting for application creation ===" -ForegroundColor Cyan

$creationResult = Watch-JuribaAppRApplicationCreation `
    -UploadId $upload.Uuid `
    -IntervalSeconds $PollIntervalSeconds `
    -TimeoutMinutes 60

# Check if creation succeeded
$appId = $creationResult.applicationId ?? $creationResult.ApplicationId ?? $creationResult.appId ?? $null

if (-not $appId) {
    Write-Host "`nApplication creation did not return an App ID." -ForegroundColor Red
    Write-Host "Final status:" -ForegroundColor Red
    $creationResult | Format-List
    exit 1
}

Write-Host "`nApplication created with ID: $appId" -ForegroundColor Green

# ─── Step 5: Monitor the workflow ────────────────────────────────────────────
Write-Host "`n=== Step 5: Monitoring workflow (packaging/testing/publishing) ===" -ForegroundColor Cyan

$finalResult = Watch-JuribaAppRApplicationStatus `
    -AppId $appId `
    -IntervalSeconds $PollIntervalSeconds `
    -TimeoutMinutes 240

# ─── Summary ─────────────────────────────────────────────────────────────────
Write-Host "`n=== Summary ===" -ForegroundColor Cyan
Write-Host "File:           $fileName"
Write-Host "Upload UUID:    $($upload.Uuid)"
Write-Host "Application ID: $appId"
Write-Host "Final status:"
$finalResult | Format-List

# Disconnect
Disconnect-JuribaAppR
