function Get-JuribaAppRApplicationPackage {
    <#
      .SYNOPSIS
      Gets package information for an application.
      .DESCRIPTION
      Retrieves all available packages for a specific application, or detailed
      packaging information for a specific package type. Returns information
      about MSI, MSIX, IntuneWin, App-V, and other package types.
      .PARAMETER Instance
      The URL of the App Readiness instance. Not required if connected via Connect-JuribaAppR.
      .PARAMETER APIKey
      The API key for authentication. Not required if connected via Connect-JuribaAppR.
      .PARAMETER AppId
      The unique identifier of the application.
      .PARAMETER PackageType
      Optional. Filter to a specific package type (e.g. Msi, Msix, IntuneWin, AppV).
      .EXAMPLE
      Get-JuribaAppRApplicationPackage -AppId 42
      Returns all packages for application 42.
      .EXAMPLE
      Get-JuribaAppRApplicationPackage -AppId 42 -PackageType Msi
      Returns MSI package information for application 42.
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$Instance,

        [Parameter(Mandatory = $false)]
        [string]$APIKey,

        [Parameter(Mandatory = $true)]
        [int]$AppId,

        [Parameter(Mandatory = $false)]
        [string]$PackageType
    )

    $conn = Get-JuribaAppRConnection -Instance $Instance -APIKey $APIKey

    if ($PackageType) {
        $uri = "api/packaging/information/$AppId/$PackageType"
    }
    else {
        $uri = "api/apm/application/$AppId/allPackages"
    }

    Invoke-JuribaAppRRestMethod -Instance $conn.Instance -APIKey $conn.APIKey `
        -Uri $uri -Method GET
}
