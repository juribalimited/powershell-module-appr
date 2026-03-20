function Get-JuribaAppRGenericIntegration {
    <#
      .SYNOPSIS
      Gets generic integrations from Juriba App Readiness.
      .DESCRIPTION
      Retrieves the collection of configured generic integrations. Generic integrations
      are custom publishing endpoints that allow App Readiness to publish packages
      to third-party or custom distribution systems.

      This is a refactored version of the original Get-GenericIntegrationsList cmdlet.
      .PARAMETER Instance
      The URL of the App Readiness instance. Not required if connected via Connect-JuribaAppR.
      .PARAMETER APIKey
      The API key for authentication. Not required if connected via Connect-JuribaAppR.
      .EXAMPLE
      Get-JuribaAppRGenericIntegration
      Returns all generic integrations using the current connection.
      .EXAMPLE
      Get-JuribaAppRGenericIntegration -Instance "https://appr.example.com" -APIKey "your-key"
      Returns all generic integrations using explicit credentials.
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$Instance,

        [Parameter(Mandatory = $false)]
        [string]$APIKey
    )

    $conn = Get-JuribaAppRConnection -Instance $Instance -APIKey $APIKey

    Invoke-JuribaAppRRestMethod -Instance $conn.Instance -APIKey $conn.APIKey `
        -Uri "api/v1/integration/generic" -Method GET
}
