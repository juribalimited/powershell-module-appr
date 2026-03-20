function Get-JuribaAppRApplicationEvent {
    <#
      .SYNOPSIS
      Gets event history for an application.
      .DESCRIPTION
      Retrieves the event log for a specific application, showing all actions
      and status changes that have occurred. Useful for auditing, monitoring
      progress, and pulling back dates and timings.
      .PARAMETER Instance
      The URL of the App Readiness instance. Not required if connected via Connect-JuribaAppR.
      .PARAMETER APIKey
      The API key for authentication. Not required if connected via Connect-JuribaAppR.
      .PARAMETER AppId
      The unique identifier of the application.
      .EXAMPLE
      Get-JuribaAppRApplicationEvent -AppId 42
      Returns all events for application 42.
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$Instance,

        [Parameter(Mandatory = $false)]
        [string]$APIKey,

        [Parameter(Mandatory = $true)]
        [int]$AppId
    )

    $conn = Get-JuribaAppRConnection -Instance $Instance -APIKey $APIKey

    Invoke-JuribaAppRRestMethod -Instance $conn.Instance -APIKey $conn.APIKey `
        -Uri "api/apm/application/$AppId/events" -Method GET
}
