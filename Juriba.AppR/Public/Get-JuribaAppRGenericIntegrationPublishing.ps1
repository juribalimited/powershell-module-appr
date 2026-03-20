function Get-JuribaAppRGenericIntegrationPublishing {
    <#
      .SYNOPSIS
      Gets publishing records for a generic integration.
      .DESCRIPTION
      Retrieves a collection of publishing records created for a specific generic
      integration. Can be filtered by limit and package types.

      This is a refactored version of the original Get-IntegrationPublishingsList cmdlet.
      .PARAMETER Instance
      The URL of the App Readiness instance. Not required if connected via Connect-JuribaAppR.
      .PARAMETER APIKey
      The API key for authentication. Not required if connected via Connect-JuribaAppR.
      .PARAMETER IntegrationId
      The unique identifier of the generic integration.
      .PARAMETER Limit
      Optional. Maximum number of publishing records to return.
      .PARAMETER PackageTypes
      Optional. Comma-separated list of package types to filter by (e.g. "Msi,AppV").
      .EXAMPLE
      Get-JuribaAppRGenericIntegrationPublishing -IntegrationId 1
      Returns all publishing records for generic integration 1.
      .EXAMPLE
      Get-JuribaAppRGenericIntegrationPublishing -IntegrationId 1 -Limit 10 -PackageTypes "Msi,AppV"
      Returns the last 10 MSI and App-V publishing records for integration 1.
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$Instance,

        [Parameter(Mandatory = $false)]
        [string]$APIKey,

        [Parameter(Mandatory = $true)]
        [int]$IntegrationId,

        [Parameter(Mandatory = $false)]
        [int]$Limit,

        [Parameter(Mandatory = $false)]
        [string]$PackageTypes
    )

    $conn = Get-JuribaAppRConnection -Instance $Instance -APIKey $APIKey

    $uri = "api/v1/integration/generic/$IntegrationId/published-app"

    # Build query string
    $queryParams = @()
    if ($Limit -gt 0) { $queryParams += "limit=$Limit" }
    if ($PackageTypes) { $queryParams += "packageTypes=$PackageTypes" }
    if ($queryParams.Count -gt 0) { $uri += "?" + ($queryParams -join "&") }

    Invoke-JuribaAppRRestMethod -Instance $conn.Instance -APIKey $conn.APIKey `
        -Uri $uri -Method GET
}
