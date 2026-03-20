function Add-JuribaAppRGenericIntegrationLog {
    <#
      .SYNOPSIS
      Adds a log entry for a publishing in a generic integration.
      .DESCRIPTION
      Adds a new log entry for a publishing that is executing against a specific
      generic integration. Use this to record progress, warnings, or errors
      during the publishing process.

      This is a refactored version of the original Add-PublishingLog cmdlet.
      .PARAMETER Instance
      The URL of the App Readiness instance. Not required if connected via Connect-JuribaAppR.
      .PARAMETER APIKey
      The API key for authentication. Not required if connected via Connect-JuribaAppR.
      .PARAMETER IntegrationId
      The unique identifier of the generic integration.
      .PARAMETER PublishingId
      The unique identifier of the publishing record.
      .PARAMETER Message
      The log message text.
      .PARAMETER Level
      The severity level of the log entry. Must be one of: Information, Warning, Error, Debug.
      .PARAMETER Date
      The date/time of the log entry.
      .PARAMETER PublishedAppId
      Optional. The identifier of the published application in the target system.
      .PARAMETER PublishedAppName
      Optional. The name of the published application in the target system.
      .EXAMPLE
      Add-JuribaAppRGenericIntegrationLog -IntegrationId 1 -PublishingId 2 -Message "Package uploaded successfully" -Level "Information" -Date (Get-Date)
      Adds an informational log entry for publishing 2 in integration 1.
    #>

    [CmdletBinding()]
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
        [string]$Message,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Information', 'Warning', 'Error', 'Debug')]
        [string]$Level,

        [Parameter(Mandatory = $true)]
        [DateTime]$Date,

        [Parameter(Mandatory = $false)]
        [string]$PublishedAppId,

        [Parameter(Mandatory = $false)]
        [string]$PublishedAppName
    )

    $conn = Get-JuribaAppRConnection -Instance $Instance -APIKey $APIKey

    $body = @{
        message        = $Message
        level          = $Level
        date           = $Date
        publishedAppId = $PublishedAppId
        publishedAppName = $PublishedAppName
    }

    Invoke-JuribaAppRRestMethod -Instance $conn.Instance -APIKey $conn.APIKey `
        -Uri "api/v1/integration/generic/$IntegrationId/published-app/$PublishingId/logs" `
        -Method POST -Body $body
}
