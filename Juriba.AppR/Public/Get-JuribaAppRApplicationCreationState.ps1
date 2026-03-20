function Get-JuribaAppRApplicationCreationState {
    <#
      .SYNOPSIS
      Gets the creation state of an asynchronously created application.
      .DESCRIPTION
      After creating an application with New-JuribaAppRApplication, use this cmdlet
      to check the progress of the asynchronous creation process. Returns the current
      state including any errors that may have occurred.
      .PARAMETER Instance
      The URL of the App Readiness instance. Not required if connected via Connect-JuribaAppR.
      .PARAMETER APIKey
      The API key for authentication. Not required if connected via Connect-JuribaAppR.
      .PARAMETER UploadId
      The upload identifier returned by New-JuribaAppRApplication or Send-JuribaAppRSetupFile.
      .EXAMPLE
      Get-JuribaAppRApplicationCreationState -UploadId "abc-123-def"
      Returns the current creation state for the specified upload.
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$Instance,

        [Parameter(Mandatory = $false)]
        [string]$APIKey,

        [Parameter(Mandatory = $true)]
        [string]$UploadId
    )

    $conn = Get-JuribaAppRConnection -Instance $Instance -APIKey $APIKey

    Invoke-JuribaAppRRestMethod -Instance $conn.Instance -APIKey $conn.APIKey `
        -Uri "api/apm/application/creation/$UploadId/state" -Method GET
}
