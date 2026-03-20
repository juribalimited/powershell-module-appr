function Get-JuribaAppRApplicationPackageDetail {
    <#
      .SYNOPSIS
      Gets detailed package information for a specific application and package type.
      .DESCRIPTION
      Retrieves detailed information about a specific package version for an application,
      using the v1 API endpoint. Returns packaging details including version information.

      This is a refactored version of the original Get-ApplicationPackageInformation cmdlet.
      .PARAMETER Instance
      The URL of the App Readiness instance. Not required if connected via Connect-JuribaAppR.
      .PARAMETER APIKey
      The API key for authentication. Not required if connected via Connect-JuribaAppR.
      .PARAMETER ApplicationId
      The unique identifier of the application.
      .PARAMETER PackageType
      The package type to retrieve (e.g. Msi, Msix, IntuneWin, AppV).
      .EXAMPLE
      Get-JuribaAppRApplicationPackageDetail -ApplicationId 1 -PackageType Msi
      Returns MSI package details for application 1.
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$Instance,

        [Parameter(Mandatory = $false)]
        [string]$APIKey,

        [Parameter(Mandatory = $true)]
        [int]$ApplicationId,

        [Parameter(Mandatory = $true)]
        [string]$PackageType
    )

    $conn = Get-JuribaAppRConnection -Instance $Instance -APIKey $APIKey

    Invoke-JuribaAppRRestMethod -Instance $conn.Instance -APIKey $conn.APIKey `
        -Uri "api/v1/application/$ApplicationId/package/$PackageType" -Method GET
}
