function Update-JuribaAppRGenericIntegrationPublishingState {
    <#
      .SYNOPSIS
      Updates the state of a publishing in a generic integration.
      .DESCRIPTION
      Updates the state of a publishing that is executing against a specific
      generic integration. Use this to mark a publishing as succeeded or failed.

      This is a refactored version of the original Update-PublishingState cmdlet.
      .PARAMETER Instance
      The URL of the App Readiness instance. Not required if connected via Connect-JuribaAppR.
      .PARAMETER APIKey
      The API key for authentication. Not required if connected via Connect-JuribaAppR.
      .PARAMETER IntegrationId
      The unique identifier of the generic integration.
      .PARAMETER PublishingId
      The unique identifier of the publishing record.
      .PARAMETER PublishingState
      The new state. Must be 'Succeeded' or 'Failed'.
      .PARAMETER PublishedAppId
      Optional. The identifier of the published application in the target system.
      .PARAMETER PublishedApplicationVersion
      Optional. The version of the published application.
      .EXAMPLE
      Update-JuribaAppRGenericIntegrationPublishingState -IntegrationId 1 -PublishingId 2 -PublishingState "Succeeded" -PublishedAppId "app-001"
      Marks publishing 2 in integration 1 as succeeded.
    #>

    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory = $false)]
        [string]$Instance,

        [Parameter(Mandatory = $false)]
        [string]$APIKey,

        [Parameter(Mandatory = $true)]
        [int]$IntegrationId,

        [Parameter(Mandatory = $true)]
        [int]$PublishingId,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Succeeded', 'Failed')]
        [string]$PublishingState,

        [Parameter(Mandatory = $false)]
        [string]$PublishedAppId,

        [Parameter(Mandatory = $false)]
        [string]$PublishedApplicationVersion
    )

    $conn = Get-JuribaAppRConnection -Instance $Instance -APIKey $APIKey

    $body = @{
        publishedAppId              = $PublishedAppId
        publishingState             = $PublishingState
        publishedApplicationVersion = $PublishedApplicationVersion
    }

    $Target = "Integration $IntegrationId, Publishing $PublishingId"

    if ($PSCmdlet.ShouldProcess($Target, "Update state to '$PublishingState'")) {
        Invoke-JuribaAppRRestMethod -Instance $conn.Instance -APIKey $conn.APIKey `
            -Uri "api/v1/integration/generic/$IntegrationId/published-app/$PublishingId" `
            -Method PUT -Body $body
    }
}
