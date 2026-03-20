function New-JuribaAppRApplication {
    <#
      .SYNOPSIS
      Creates a new application in Juriba App Readiness.
      .DESCRIPTION
      Creates a new application record in App Readiness from a previously uploaded
      setup file. The application is created asynchronously. Use
      Get-JuribaAppRApplicationCreationState or Watch-JuribaAppRApplicationCreation
      to monitor progress.

      Follows the "path of least information" principle — only the upload UUID and
      file name are required. Everything else uses sensible defaults but can be
      overridden when needed.

      Typical workflow:
        1. Send-JuribaAppRSetupFile to upload the installer
        2. New-JuribaAppRApplication to start processing
        3. Watch-JuribaAppRApplicationCreation to poll until complete
      .PARAMETER Instance
      The URL of the App Readiness instance. Not required if connected via Connect-JuribaAppR.
      .PARAMETER APIKey
      The API key for authentication. Not required if connected via Connect-JuribaAppR.
      .PARAMETER Uuid
      The upload UUID returned by Send-JuribaAppRSetupFile. This identifies the
      uploaded file on the server.
      .PARAMETER FileName
      The original file name of the uploaded setup file. Returned by Send-JuribaAppRSetupFile.
      .PARAMETER Name
      Optional override name for the application. If not specified, the name is
      derived from the uploaded setup file.
      .PARAMETER CommandLine
      Optional override install command line. If not specified, App Readiness will
      suggest a command line based on the installer type.
      .PARAMETER UninstallCommandLine
      Optional uninstall command line.
      .PARAMETER Manufacturer
      Optional manufacturer/vendor name override.
      .PARAMETER Version
      Optional application version override.
      .PARAMETER RunImmediately
      When specified, immediately begins automated packaging after creation.
      This is the default behavior for most automation scenarios.
      .PARAMETER VMGroupId
      Optional. The VM group to use for packaging. If not specified, uses the default.
      .PARAMETER VMGroupForTestingId
      Optional. The VM group to use for smoke testing after packaging.
      .PARAMETER PrePackaged
      When specified, indicates the uploaded file is already in a final package
      format (e.g. an MSI or IntuneWin that does not need repackaging).
      .EXAMPLE
      $upload = Send-JuribaAppRSetupFile -FilePath "C:\Installers\Firefox-Setup.exe"
      New-JuribaAppRApplication -Uuid $upload.Uuid -FileName $upload.FileName
      Uploads a file and creates an application with default settings.
      .EXAMPLE
      $upload = Send-JuribaAppRSetupFile -FilePath "C:\Installers\App.exe"
      New-JuribaAppRApplication -Uuid $upload.Uuid -FileName $upload.FileName `
          -Name "My App 2.0" -CommandLine "/S /v/qn" -RunImmediately
      Creates an application with overrides and starts packaging immediately.
      .EXAMPLE
      $upload = Send-JuribaAppRSetupFile -FilePath "C:\Packages\App.msi"
      $app = New-JuribaAppRApplication -Uuid $upload.Uuid -FileName $upload.FileName -PrePackaged
      Creates a pre-packaged application (no repackaging needed).
    #>

    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory = $false)]
        [string]$Instance,

        [Parameter(Mandatory = $false)]
        [string]$APIKey,

        [Parameter(Mandatory = $true)]
        [string]$Uuid,

        [Parameter(Mandatory = $true)]
        [string]$FileName,

        [Parameter(Mandatory = $false)]
        [string]$Name,

        [Parameter(Mandatory = $false)]
        [string]$CommandLine,

        [Parameter(Mandatory = $false)]
        [string]$UninstallCommandLine,

        [Parameter(Mandatory = $false)]
        [string]$Manufacturer,

        [Parameter(Mandatory = $false)]
        [string]$Version,

        [Parameter(Mandatory = $false)]
        [switch]$RunImmediately,

        [Parameter(Mandatory = $false)]
        [int]$VMGroupId,

        [Parameter(Mandatory = $false)]
        [int]$VMGroupForTestingId,

        [Parameter(Mandatory = $false)]
        [switch]$PrePackaged
    )

    $conn = Get-JuribaAppRConnection -Instance $Instance -APIKey $APIKey

    # Build the applicationInfo sub-object
    $applicationInfo = @{
        sourceFileName = $FileName
    }

    if ($Name) { $applicationInfo['name'] = $Name }
    if ($CommandLine) { $applicationInfo['cmdLine'] = $CommandLine }
    if ($UninstallCommandLine) { $applicationInfo['uninstall'] = $UninstallCommandLine }
    if ($Manufacturer) { $applicationInfo['manufacturer'] = $Manufacturer }
    if ($Version) { $applicationInfo['appVer'] = $Version }

    # Build the main request body (AddApplicationParentViewModel)
    $body = @{
        uuid            = $Uuid
        applicationInfo = $applicationInfo
        runImmediately  = [bool]$RunImmediately
    }

    if ($VMGroupId) { $body['vmGroupId'] = $VMGroupId }
    if ($VMGroupForTestingId) { $body['vmGroupForTestingId'] = $VMGroupForTestingId }

    $Target = if ($Name) { $Name } else { $FileName }

    if ($PSCmdlet.ShouldProcess($Target, "Create Application")) {
        if ($PrePackaged) {
            $uri = "api/apm/application/prePackaged/async"
        }
        else {
            $uri = "api/apm/application/async"
        }

        $result = Invoke-JuribaAppRRestMethod -Instance $conn.Instance -APIKey $conn.APIKey `
            -Uri $uri -Method POST -Body $body

        # Return a useful object with the UUID for tracking
        if ($result) {
            $result | Add-Member -NotePropertyName 'Uuid' -NotePropertyValue $Uuid -Force -PassThru
        }
        else {
            [PSCustomObject]@{
                Uuid     = $Uuid
                FileName = $FileName
                Status   = 'Submitted'
            }
        }
    }
}
