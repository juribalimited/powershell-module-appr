function New-JuribaAppRApplication {
    <#
      .SYNOPSIS
      Creates a new application in Juriba App Readiness.
      .DESCRIPTION
      Creates a new application record in App Readiness. The application can be
      created with an uploaded setup file for automated processing, or as an
      empty application record. Optionally specify an override name, command line,
      and output package types. The creation is performed asynchronously and the
      cmdlet returns a tracking object for monitoring progress.

      This is the primary cmdlet for the "Add an application" use case, supporting
      the path-of-least-information approach where only essential details are
      required and everything else uses sensible defaults.
      .PARAMETER Instance
      The URL of the App Readiness instance. Not required if connected via Connect-JuribaAppR.
      .PARAMETER APIKey
      The API key for authentication. Not required if connected via Connect-JuribaAppR.
      .PARAMETER Name
      Optional override name for the application. If not specified, the name will
      be derived from the uploaded file.
      .PARAMETER SetupFileUrl
      The URL or path of the setup file to process. Use with Send-JuribaAppRSetupFile
      to upload the file first and obtain this URL.
      .PARAMETER UploadId
      The upload identifier returned by Send-JuribaAppRSetupFile after uploading
      a setup file.
      .PARAMETER PrePackaged
      When specified, indicates the uploaded file is a pre-packaged application
      (already in the desired output format).
      .EXAMPLE
      New-JuribaAppRApplication -UploadId "abc-123-def"
      Creates a new application from a previously uploaded setup file.
      .EXAMPLE
      New-JuribaAppRApplication -Name "Firefox ESR 115" -UploadId "abc-123-def"
      Creates a new application with an override name from an uploaded file.
    #>

    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory = $false)]
        [string]$Instance,

        [Parameter(Mandatory = $false)]
        [string]$APIKey,

        [Parameter(Mandatory = $false)]
        [string]$Name,

        [Parameter(Mandatory = $false)]
        [string]$UploadId,

        [Parameter(Mandatory = $false)]
        [switch]$PrePackaged
    )

    $conn = Get-JuribaAppRConnection -Instance $Instance -APIKey $APIKey

    $body = @{}

    if ($Name) {
        $body['name'] = $Name
    }

    if ($UploadId) {
        $body['uploadId'] = $UploadId
    }

    $Target = if ($Name) { $Name } else { "Upload ID: $UploadId" }

    if ($PSCmdlet.ShouldProcess($Target, "Create Application")) {
        if ($PrePackaged) {
            $uri = "api/apm/application/prePackaged/async"
        }
        else {
            $uri = "api/apm/application/async"
        }

        Invoke-JuribaAppRRestMethod -Instance $conn.Instance -APIKey $conn.APIKey `
            -Uri $uri -Method POST -Body $body
    }
}
