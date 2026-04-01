<#
.SYNOPSIS
  Downloads MSIX App Attach packages from a Generic Integration and copies them
  to an SMB file share.

.DESCRIPTION
  Demonstrates the API flow for exporting MSIX App Attach packages from Juriba
  App Readiness to a network share. This is useful for organizations that need
  to distribute MSIX App Attach packages to Azure Virtual Desktop (AVD) or
  Windows 365 environments via file shares.

  The flow:
    1. Connect to the App Readiness instance
    2. Find the Generic Integration configured for MSIX exports
    3. List all published MSIX App Attach packages in that integration
    4. Download each package to a local staging directory
    5. Copy the packages to the target SMB share
    6. Update the publishing state and log the result in App Readiness

  Prerequisites:
    - A Generic Integration must be configured in App Readiness
    - Applications must be published to that integration with MSIX App Attach output
    - The user/service account must have write access to the target SMB share

.PARAMETER InstanceUrl
  The base URL of the App Readiness instance.

.PARAMETER SecretName
  The name of the secret in SecretManagement containing the API key.
  Use Set-JuribaAppRAPIKey to store the key. Alternatively, pass -APIKey.

.PARAMETER APIKey
  The API key for authentication. Prefer -SecretName for automation.

.PARAMETER IntegrationId
  The ID of the Generic Integration to pull packages from.
  If not specified, the script lists all integrations and prompts you to pick one.

.PARAMETER SMBSharePath
  The UNC path to the SMB share (e.g. \\fileserver\msix-packages).

.PARAMETER StagingPath
  Local staging directory for downloads before copying to the share.
  Defaults to a temp directory.

.PARAMETER PackageTypes
  Comma-separated package types to download. Default: "MsixAppAttach".
  Other options: "Msix", "Msi", "AppV", "IntuneWin", "Psadt".

.PARAMETER Limit
  Maximum number of publishing records to process. Default: 50.

.EXAMPLE
  .\Export-MSIXAppAttachToShare.ps1 `
      -InstanceUrl "https://appr.example.com" `
      -SecretName "AppR-Production" `
      -IntegrationId 3 `
      -SMBSharePath "\\fileserver\msix-appattach"

  Downloads all MSIX App Attach packages from integration 3 to the SMB share.

.EXAMPLE
  .\Export-MSIXAppAttachToShare.ps1 `
      -InstanceUrl "https://appr.example.com" `
      -APIKey "your-key" `
      -SMBSharePath "\\avd-share\packages" `
      -PackageTypes "MsixAppAttach,Msix"

  Downloads both MSIX and MSIX App Attach packages. Lists available integrations
  if -IntegrationId is not specified.
#>

[CmdletBinding(DefaultParameterSetName = 'SecretName')]
param (
    [Parameter(Mandatory = $true)]
    [string]$InstanceUrl,

    [Parameter(Mandatory = $true, ParameterSetName = 'SecretName')]
    [string]$SecretName,

    [Parameter(Mandatory = $true, ParameterSetName = 'PlainText')]
    [string]$APIKey,

    [Parameter(Mandatory = $false)]
    [int]$IntegrationId,

    [Parameter(Mandatory = $true)]
    [string]$SMBSharePath,

    [Parameter(Mandatory = $false)]
    [string]$StagingPath,

    [Parameter(Mandatory = $false)]
    [string]$PackageTypes = "MsixAppAttach",

    [Parameter(Mandatory = $false)]
    [int]$Limit = 50
)

$ErrorActionPreference = 'Stop'

# ── Import module ─────────────────────────────────────────────────────────────

$modulePath = Join-Path $PSScriptRoot '..' 'Juriba.AppR.psd1'
Import-Module $modulePath -Force


# ── Connect ───────────────────────────────────────────────────────────────────

Write-Host "Connecting to $InstanceUrl..." -ForegroundColor Cyan
if ($SecretName) {
    Connect-JuribaAppR -Instance $InstanceUrl -SecretName $SecretName
}
else {
    Connect-JuribaAppR -Instance $InstanceUrl -APIKey $APIKey
}


# ── Find the Generic Integration ──────────────────────────────────────────────

if (-not $IntegrationId) {
    Write-Host "`nAvailable Generic Integrations:" -ForegroundColor Cyan
    $integrations = Get-JuribaAppRGenericIntegration
    if (-not $integrations -or $integrations.Count -eq 0) {
        Write-Error "No Generic Integrations found. Configure one in Admin > Integrations."
    }
    foreach ($i in $integrations) {
        Write-Host "  [$($i.id)] $($i.name)" -ForegroundColor Yellow
    }

    # If only one integration exists, use it automatically
    if ($integrations.Count -eq 1) {
        $IntegrationId = $integrations[0].id
        Write-Host "`nAuto-selected integration $IntegrationId (only one configured)" -ForegroundColor Green
    }
    else {
        Write-Error "Multiple integrations found. Please specify -IntegrationId."
    }
}

Write-Host "`nUsing Generic Integration ID: $IntegrationId" -ForegroundColor Cyan


# ── List published packages ───────────────────────────────────────────────────

Write-Host "Querying published $PackageTypes packages (limit: $Limit)..." -ForegroundColor Cyan
$publishings = Get-JuribaAppRGenericIntegrationPublishing `
    -IntegrationId $IntegrationId -Limit $Limit -PackageTypes $PackageTypes

if (-not $publishings -or $publishings.Count -eq 0) {
    Write-Host "No published $PackageTypes packages found in integration $IntegrationId." -ForegroundColor Yellow
    Disconnect-JuribaAppR
    return
}

Write-Host "Found $($publishings.Count) published package(s)" -ForegroundColor Green


# ── Prepare staging directory ─────────────────────────────────────────────────

if (-not $StagingPath) {
    $StagingPath = Join-Path ([System.IO.Path]::GetTempPath()) "AppR-Export-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
}
if (-not (Test-Path $StagingPath)) {
    $null = New-Item -Path $StagingPath -ItemType Directory -Force
}
Write-Host "Staging directory: $StagingPath" -ForegroundColor DarkGray


# ── Validate SMB share ────────────────────────────────────────────────────────

if (-not (Test-Path $SMBSharePath)) {
    Write-Error "SMB share not accessible: $SMBSharePath. Check the path and permissions."
}


# ── Download and copy each package ────────────────────────────────────────────

$successCount = 0
$failCount    = 0

foreach ($pub in $publishings) {
    $pubId   = $pub.publishingId
    $appName = $pub.applicationName
    $pkgType = $pub.packageType
    $version = $pub.applicationVersion

    Write-Host "`n─── [$pubId] $appName v$version ($pkgType) ───" -ForegroundColor Magenta

    try {
        # Download the package source to the staging directory
        Write-Host "  Downloading..." -ForegroundColor Cyan
        $downloadedFile = Get-JuribaAppRGenericIntegrationSource `
            -IntegrationId $IntegrationId -PublishingId $pubId -SourcePath $StagingPath

        if (-not $downloadedFile) {
            throw "Download returned no file name"
        }

        $sourcePath = Join-Path $StagingPath $downloadedFile
        $fileSize   = (Get-Item $sourcePath).Length
        Write-Host "  Downloaded: $downloadedFile ($([Math]::Round($fileSize / 1MB, 2)) MB)" -ForegroundColor Green

        # Copy to SMB share
        $destPath = Join-Path $SMBSharePath $downloadedFile
        Write-Host "  Copying to $SMBSharePath..." -ForegroundColor Cyan
        Copy-Item -Path $sourcePath -Destination $destPath -Force
        Write-Host "  Copied to: $destPath" -ForegroundColor Green

        # Log success in App Readiness
        Add-JuribaAppRGenericIntegrationLog `
            -IntegrationId $IntegrationId -PublishingId $pubId `
            -Message "Package exported to SMB share: $destPath" `
            -Level "Information" -Date (Get-Date)

        # Mark as succeeded
        Update-JuribaAppRGenericIntegrationPublishingState `
            -IntegrationId $IntegrationId -PublishingId $pubId `
            -PublishingState "Succeeded"

        $successCount++
    }
    catch {
        Write-Warning "  FAILED: $($_.Exception.Message)"

        # Log the failure in App Readiness
        try {
            Add-JuribaAppRGenericIntegrationLog `
                -IntegrationId $IntegrationId -PublishingId $pubId `
                -Message "Export failed: $($_.Exception.Message)" `
                -Level "Error" -Date (Get-Date)

            Update-JuribaAppRGenericIntegrationPublishingState `
                -IntegrationId $IntegrationId -PublishingId $pubId `
                -PublishingState "Failed"
        }
        catch {
            Write-Warning "  Could not update publishing state: $($_.Exception.Message)"
        }

        $failCount++
    }
}


# ── Summary ───────────────────────────────────────────────────────────────────

Write-Host "`n══════════════════════════════════════" -ForegroundColor Cyan
Write-Host "Export complete" -ForegroundColor Cyan
Write-Host "  Succeeded: $successCount" -ForegroundColor Green
if ($failCount -gt 0) {
    Write-Host "  Failed:    $failCount" -ForegroundColor Red
}
Write-Host "  Share:     $SMBSharePath" -ForegroundColor Cyan
Write-Host "══════════════════════════════════════" -ForegroundColor Cyan

# Clean up staging
if ($successCount -gt 0 -and $StagingPath -match 'AppR-Export-') {
    Write-Host "Cleaning up staging directory..." -ForegroundColor DarkGray
    Remove-Item $StagingPath -Recurse -Force -ErrorAction SilentlyContinue
}

Disconnect-JuribaAppR
