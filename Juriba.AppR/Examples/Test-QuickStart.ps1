<#
.SYNOPSIS
  Quick-start test script for the Juriba.AppR PowerShell module.
.DESCRIPTION
  Tests the core upload-and-monitor workflow against a live App Readiness instance.
  Run this script from a machine with PowerShell 7+ to validate the module works end-to-end.
.PARAMETER InstanceUrl
  The base URL of the App Readiness instance (e.g. https://demo.appr.juriba.app).
.PARAMETER APIKey
  Your API key for authentication.
.PARAMETER SetupFilePath
  (Optional) Path to a setup file to upload. If not provided, the script creates a small
  dummy MSI for testing the upload flow.
.PARAMETER SkipUpload
  When specified, skips the upload/create test and only validates read-only cmdlets.
.EXAMPLE
  .\Test-QuickStart.ps1 -InstanceUrl "https://demo.appr.juriba.app" -APIKey "your-key-here"
.EXAMPLE
  .\Test-QuickStart.ps1 -InstanceUrl "https://demo.appr.juriba.app" -APIKey "your-key-here" -SetupFilePath "C:\Installers\Firefox-Setup.exe"
#>

param (
    [Parameter(Mandatory = $true)]
    [string]$InstanceUrl,

    [Parameter(Mandatory = $true)]
    [string]$APIKey,

    [Parameter(Mandatory = $false)]
    [string]$SetupFilePath,

    [switch]$SkipUpload
)

$ErrorActionPreference = 'Stop'

# --- Locate and import the module ---
$modulePath = Join-Path (Join-Path $PSScriptRoot '..') 'Juriba.AppR.psd1'
if (-not (Test-Path $modulePath)) {
    Write-Error "Cannot find Juriba.AppR.psd1 at $modulePath. Run this script from the Examples folder."
}
Import-Module $modulePath -Force
Write-Host "Module imported from $modulePath" -ForegroundColor Cyan

$passed = 0
$failed = 0
$results = @()

function Test-Cmdlet {
    param ([string]$Name, [scriptblock]$Script)
    Write-Host "`n--- Testing: $Name ---" -ForegroundColor Yellow
    try {
        $result = & $Script
        Write-Host "  PASSED" -ForegroundColor Green
        $script:passed++
        $script:results += [PSCustomObject]@{ Test = $Name; Status = 'PASSED'; Detail = '' }
        return $result
    }
    catch {
        Write-Host "  FAILED: $($_.Exception.Message)" -ForegroundColor Red
        $script:failed++
        $script:results += [PSCustomObject]@{ Test = $Name; Status = 'FAILED'; Detail = $_.Exception.Message }
        return $null
    }
}

# ============================================================
# 1. CONNECT
# ============================================================
Test-Cmdlet "Connect-JuribaAppR" {
    Connect-JuribaAppR -Instance $InstanceUrl -APIKey $APIKey -Verbose
    Write-Host "  Connected as: $($global:appRConnection.Instance)"
}

# ============================================================
# 2. READ-ONLY CMDLETS
# ============================================================
Test-Cmdlet "Get-JuribaAppRAboutInfo" {
    $info = Get-JuribaAppRAboutInfo
    Write-Host "  Returned $($info.Count) items"
}

$user = Test-Cmdlet "Get-JuribaAppRUser (whoami)" {
    $u = Get-JuribaAppRUser
    Write-Host "  Logged in as: $($u.userName) ($($u.emailAddress))"
    $u
}

$apps = Test-Cmdlet "Get-JuribaAppRApplicationList -AllUsers" {
    $list = Get-JuribaAppRApplicationList -AllUsers
    Write-Host "  Found $($list.Count) applications"
    $list
}

$firstAppId = if ($apps -and $apps.Count -gt 0) { $apps[0].basic.id } else { $null }

if ($firstAppId) {
    Test-Cmdlet "Get-JuribaAppRApplication -AppId $firstAppId" {
        $app = Get-JuribaAppRApplication -AppId $firstAppId
        Write-Host "  App: $($app.basic.name) v$($app.basic.applicationVersion) by $($app.basic.manufacturer)"
    }

    Test-Cmdlet "Get-JuribaAppRApplication -AppId $firstAppId -Basic" {
        $basic = Get-JuribaAppRApplication -AppId $firstAppId -Basic
        Write-Host "  Name=$($basic.applicationName), Mfg=$($basic.manufacturer)"
    }

    Test-Cmdlet "Get-JuribaAppRApplicationEvent -AppId $firstAppId" {
        $events = Get-JuribaAppRApplicationEvent -AppId $firstAppId
        $count = if ($events.listOfEvents) { $events.listOfEvents.Count } else { 0 }
        Write-Host "  Found $count events"
    }

    Test-Cmdlet "Get-JuribaAppRApplicationPackage -AppId $firstAppId" {
        $pkgs = Get-JuribaAppRApplicationPackage -AppId $firstAppId
        $count = if ($pkgs.versions) { $pkgs.versions.Count } else { 0 }
        Write-Host "  Found $count package versions"
    }

    Test-Cmdlet "Get-JuribaAppRApplicationPackageDetail -ApplicationId $firstAppId -PackageType 0" {
        $detail = Get-JuribaAppRApplicationPackageDetail -ApplicationId $firstAppId -PackageType 0
        Write-Host "  Package: $($detail.applicationName) type=$($detail.applicationPackageType)"
    }

    Test-Cmdlet "Get-JuribaAppRApplicationStatus -AppId $firstAppId" {
        $tracker = Get-JuribaAppRApplicationStatus -AppId $firstAppId
        Write-Host "  Status: $($tracker.status), Progress: $($tracker.currentProgressPercent)%"
    }
}

Test-Cmdlet "Get-JuribaAppRVMGroup" {
    $vms = Get-JuribaAppRVMGroup
    Write-Host "  Found $($vms.Count) VM group(s)"
    foreach ($vm in $vms) { Write-Host "    - $($vm.name) (id=$($vm.id), status=$($vm.status))" }
}

Test-Cmdlet "Get-JuribaAppRIntegrationConnector" {
    $connectors = Get-JuribaAppRIntegrationConnector
    Write-Host "  Found $($connectors.Count) connector(s)"
    foreach ($c in $connectors) { Write-Host "    - $($c.name) v$($c.version) (id=$($c.id))" }
}

Test-Cmdlet "Get-JuribaAppRGenericIntegration" {
    $gi = Get-JuribaAppRGenericIntegration
    $count = if ($gi) { @($gi).Count } else { 0 }
    Write-Host "  Found $count generic integration(s)"
}

Test-Cmdlet "Search-JuribaAppRKnowledgeBase -Search 'Firefox'" {
    $kb = Search-JuribaAppRKnowledgeBase -Search 'Firefox'
    $count = if ($kb) { @($kb).Count } else { 0 }
    Write-Host "  Found $count KB result(s)"
}

Test-Cmdlet "Get-JuribaAppRTestApplication" {
    $ace = Get-JuribaAppRTestApplication
    $count = if ($ace) { @($ace).Count } else { 0 }
    Write-Host "  Found $count test application(s)"
}

# ============================================================
# 3. UPLOAD & CREATE (Primary Use Case)
# ============================================================
if (-not $SkipUpload) {
    Write-Host "`n============================================================" -ForegroundColor Magenta
    Write-Host "  UPLOAD & CREATE WORKFLOW TEST" -ForegroundColor Magenta
    Write-Host "============================================================" -ForegroundColor Magenta

    # Create a small dummy file if none provided
    if (-not $SetupFilePath) {
        $SetupFilePath = Join-Path $env:TEMP "TestApp-1.0.0-Setup.msi"
        Write-Host "`nNo setup file provided. Creating dummy file at $SetupFilePath" -ForegroundColor Cyan
        # Create a small file (~100KB) that can be uploaded
        $bytes = New-Object byte[] (100 * 1024)
        (New-Object Random).NextBytes($bytes)
        [System.IO.File]::WriteAllBytes($SetupFilePath, $bytes)
        $cleanupDummy = $true
    }

    $upload = Test-Cmdlet "Send-JuribaAppRSetupFile -FilePath '$SetupFilePath'" {
        $u = Send-JuribaAppRSetupFile -FilePath $SetupFilePath -Verbose
        Write-Host "  UUID: $($u.Uuid)"
        Write-Host "  FileName: $($u.FileName)"
        Write-Host "  FileSize: $($u.FileSize) bytes in $($u.TotalChunks) chunk(s)"
        $u
    }

    if ($upload) {
        $creation = Test-Cmdlet "New-JuribaAppRApplication" {
            # Pass metadata extracted from the installer by Send-JuribaAppRSetupFile.
            # The server requires name, manufacturer (min 3 chars), and appVer.
            $splatCreate = @{
                Uuid           = $upload.Uuid
                FileName       = $upload.FileName
                FileSize       = $upload.FileSize
                TotalChunks    = $upload.TotalChunks
                RunImmediately = $true
                Verbose        = $true
            }
            if ($upload.ProductName)    { $splatCreate['Name']         = $upload.ProductName }
            if ($upload.CompanyName)    { $splatCreate['Manufacturer'] = $upload.CompanyName }
            if ($upload.ProductVersion) { $splatCreate['Version']      = $upload.ProductVersion }

            # Auto-select the first active VM group (status=2) for packaging
            $vmGroups = Get-JuribaAppRVMGroup
            $activeVm = $vmGroups | Where-Object { $_.status -eq 2 } | Select-Object -First 1
            if ($activeVm) {
                $splatCreate['VMGroupId'] = $activeVm.id
                Write-Host "  Using VM group: $($activeVm.name) (id=$($activeVm.id))"
            }

            $c = New-JuribaAppRApplication @splatCreate
            Write-Host "  Creation response: $($c | ConvertTo-Json -Compress)"
            $c
        }

        if ($creation) {
            # The creation response should contain an uploadId for polling
            $uploadId = if ($creation.uploadId) { $creation.uploadId }
                        elseif ($creation.id) { $creation.id }
                        else { $upload.Uuid }

            Test-Cmdlet "Get-JuribaAppRApplicationCreationState -UploadId '$uploadId'" {
                $state = Get-JuribaAppRApplicationCreationState -UploadId $uploadId
                Write-Host "  State: $($state | ConvertTo-Json -Compress)"
            }

            Write-Host "`n  To monitor the full workflow, run:" -ForegroundColor Cyan
            Write-Host "    Watch-JuribaAppRApplicationCreation -UploadId '$uploadId' -IntervalSeconds 30 -TimeoutMinutes 10" -ForegroundColor White
        }
    }

    # Cleanup dummy file
    if ($cleanupDummy -and (Test-Path $SetupFilePath)) {
        Remove-Item $SetupFilePath -Force -ErrorAction SilentlyContinue
    }
}

# ============================================================
# 4. DISCONNECT
# ============================================================
Test-Cmdlet "Disconnect-JuribaAppR" {
    Disconnect-JuribaAppR
    if (-not $global:appRConnection) { Write-Host "  Session cleared" }
    else { throw "Session not cleared" }
}

# ============================================================
# SUMMARY
# ============================================================
Write-Host "`n============================================================" -ForegroundColor Cyan
Write-Host "  TEST RESULTS: $passed passed, $failed failed (total $($passed + $failed))" -ForegroundColor $(if ($failed -eq 0) { 'Green' } else { 'Red' })
Write-Host "============================================================" -ForegroundColor Cyan
$results | Format-Table -AutoSize

if ($failed -gt 0) {
    Write-Host "`nFailed tests:" -ForegroundColor Red
    $results | Where-Object Status -eq 'FAILED' | Format-List
}
