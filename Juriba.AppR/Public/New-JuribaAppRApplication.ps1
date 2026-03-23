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
      .PARAMETER FileSize
      The size in bytes of the uploaded file. Returned by Send-JuribaAppRSetupFile.
      .PARAMETER TotalChunks
      The number of chunks the file was split into during upload. Returned by Send-JuribaAppRSetupFile.
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
      New-JuribaAppRApplication -Uuid $upload.Uuid -FileName $upload.FileName `
          -FileSize $upload.FileSize -TotalChunks $upload.TotalChunks
      Uploads a file and creates an application with default settings.
      .EXAMPLE
      $upload = Send-JuribaAppRSetupFile -FilePath "C:\Installers\App.exe"
      New-JuribaAppRApplication -Uuid $upload.Uuid -FileName $upload.FileName `
          -FileSize $upload.FileSize -TotalChunks $upload.TotalChunks `
          -Name "My App 2.0" -CommandLine "/S /v/qn" -RunImmediately
      Creates an application with overrides and starts packaging immediately.
      .EXAMPLE
      $upload = Send-JuribaAppRSetupFile -FilePath "C:\Packages\App.msi"
      $app = New-JuribaAppRApplication -Uuid $upload.Uuid -FileName $upload.FileName `
          -FileSize $upload.FileSize -TotalChunks $upload.TotalChunks -PrePackaged
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

        [Parameter(Mandatory = $true)]
        [long]$FileSize,

        [Parameter(Mandatory = $true)]
        [int]$TotalChunks,

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
        [switch]$PrePackaged,

        [Parameter(Mandatory = $false)]
        [string]$OperatingSystemName,

        [Parameter(Mandatory = $false)]
        [int]$OperatingSystemBuild,

        [Parameter(Mandatory = $false)]
        [int]$OperatingSystemType = 1,

        [Parameter(Mandatory = $false)]
        [string]$PackageVersion = "1.0",

        [Parameter(Mandatory = $false)]
        [string]$Site = "GLOBAL"
    )

    $conn = Get-JuribaAppRConnection -Instance $Instance -APIKey $APIKey

    # The server does NOT auto-detect name/version/manufacturer from the binary.
    # We must always supply name, manufacturer (min 3 chars), and appVer.
    # Use explicit parameter values first, then fall back to the file name.
    # Callers should pass metadata extracted from Send-JuribaAppRSetupFile
    # (ProductName, CompanyName, ProductVersion) via -Name, -Manufacturer, -Version.
    $appName   = if ($Name)         { $Name }
                 else { [System.IO.Path]::GetFileNameWithoutExtension($FileName) }
    $appMfg    = if ($Manufacturer) { $Manufacturer }
                 else { "Unknown" }
    $appVer    = if ($Version)      { $Version }
                 else { "1.0" }

    # Build the applicationInfo sub-object
    # Only include fields the server requires; let Default Settings handle
    # VM groups, OS details, site, etc.
    $applicationInfo = @{
        sourceFileName = $FileName
        name           = $appName
        manufacturer   = $appMfg
        appVer         = $appVer
        source         = 2    # TypeOfSource: 2 = local file upload
        actionType     = 1    # TypeOfAction: 1 = repackage
    }

    # Optional fields — only add when explicitly provided
    if ($PackageVersion -and $PackageVersion -ne "1.0") { $applicationInfo['packageVersion'] = $PackageVersion }
    if ($Site -and $Site -ne "GLOBAL")                  { $applicationInfo['site'] = $Site }
    if ($OperatingSystemName)  { $applicationInfo['operatingSystemName']  = $OperatingSystemName }
    if ($OperatingSystemBuild) { $applicationInfo['operatingSystemBuild'] = $OperatingSystemBuild }
    if ($OperatingSystemType -ne 1) { $applicationInfo['operatingSystemType'] = $OperatingSystemType }
    if ($CommandLine) { $applicationInfo['cmdLine'] = $CommandLine }
    if ($UninstallCommandLine) { $applicationInfo['uninstall'] = $UninstallCommandLine }

    # Build the uploadChunkModel (tells the server which uploaded chunks to use)
    $uploadChunkModel = @{
        dzIdentifier = $Uuid
        fileName     = $FileName
        expectedBytes = $FileSize
        totalChunks  = $TotalChunks
        uploadType   = 0
    }

    # Build the packageTypeMatrixModel — required by the server to resolve the
    # source-action mapping.  Values come from GET /api/packaging/upload/packageTypesMatrix.
    # from=0 (TypeOfPackageAction: default), sourceAction=1 (matches applicationInfo.source),
    # to=0 (OutputPackages: default/all).
    $packageTypeMatrixModel = @{
        from         = 0
        sourceAction = 1
        to           = 0
    }

    # Build the main request body (AddApplicationParentViewModel)
    $body = @{
        uuid                   = $Uuid
        applicationInfo        = $applicationInfo
        uploadChunkModel       = $uploadChunkModel
        packageTypeMatrixModel = $packageTypeMatrixModel
        setAsMainSource        = $true
        runImmediately         = [bool]$RunImmediately
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
            # API returned success but empty body — return tracking object
            [PSCustomObject]@{
                Uuid     = $Uuid
                FileName = $FileName
                Status   = 'Submitted'
            }
        }
    }
}
