function Get-JuribaAppRPublishingProperty {
    <#
      .SYNOPSIS
      Gets publishing properties and templates from Juriba App Readiness.
      .DESCRIPTION
      Retrieves publishing configuration properties and templates. These define
      how packages are published to integration targets such as Intune or MECM.
      Use this to understand the available publishing options and their current
      configuration.
      .PARAMETER Instance
      The URL of the App Readiness instance. Not required if connected via Connect-JuribaAppR.
      .PARAMETER APIKey
      The API key for authentication. Not required if connected via Connect-JuribaAppR.
      .PARAMETER PropertyId
      Optional. The unique identifier of a specific publishing property to retrieve.
      .PARAMETER ProviderId
      Optional. Filter properties by integration provider ID.
      .PARAMETER PackageType
      Optional. Filter properties by package type.
      .EXAMPLE
      Get-JuribaAppRPublishingProperty
      Returns all publishing properties.
      .EXAMPLE
      Get-JuribaAppRPublishingProperty -ProviderId 1 -PackageType IntuneWin
      Returns publishing properties for provider 1 filtered to IntuneWin packages.
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$Instance,

        [Parameter(Mandatory = $false)]
        [string]$APIKey,

        [Parameter(Mandatory = $false)]
        [int]$PropertyId,

        [Parameter(Mandatory = $false)]
        [int]$ProviderId,

        [Parameter(Mandatory = $false)]
        [string]$PackageType
    )

    $conn = Get-JuribaAppRConnection -Instance $Instance -APIKey $APIKey

    if ($PropertyId) {
        $uri = "api/integration/publishing/properties/$PropertyId"
    }
    elseif ($ProviderId -and $PackageType) {
        $uri = "api/integration/provider/$ProviderId/properties/package-type/$PackageType"
    }
    elseif ($ProviderId) {
        $uri = "api/integration/provider/$ProviderId/properties"
    }
    else {
        $uri = "api/integration/publishing/properties"
    }

    Invoke-JuribaAppRRestMethod -Instance $conn.Instance -APIKey $conn.APIKey `
        -Uri $uri -Method GET
}
