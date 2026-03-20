function Get-JuribaAppRIntegrationConnector {
    <#
      .SYNOPSIS
      Gets integration connectors configured in Juriba App Readiness.
      .DESCRIPTION
      Retrieves the list of configured integration connectors (e.g. Intune, MECM,
      generic integrations). Use this to interrogate available integration options
      and determine where packages can be published.
      .PARAMETER Instance
      The URL of the App Readiness instance. Not required if connected via Connect-JuribaAppR.
      .PARAMETER APIKey
      The API key for authentication. Not required if connected via Connect-JuribaAppR.
      .PARAMETER ConnectorId
      Optional. The unique identifier of a specific connector to retrieve.
      .EXAMPLE
      Get-JuribaAppRIntegrationConnector
      Returns all configured integration connectors.
      .EXAMPLE
      Get-JuribaAppRIntegrationConnector -ConnectorId 1
      Returns details for connector with ID 1.
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$Instance,

        [Parameter(Mandatory = $false)]
        [string]$APIKey,

        [Parameter(Mandatory = $false)]
        [int]$ConnectorId
    )

    $conn = Get-JuribaAppRConnection -Instance $Instance -APIKey $APIKey

    if ($ConnectorId) {
        $uri = "api/integration/integrationConnector/$ConnectorId"
    }
    else {
        $uri = "api/integration/integrationConnector/list"
    }

    Invoke-JuribaAppRRestMethod -Instance $conn.Instance -APIKey $conn.APIKey `
        -Uri $uri -Method GET
}
