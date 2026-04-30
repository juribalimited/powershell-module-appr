function Get-JuribaAppRMECMImportEvent {
    <#
      .SYNOPSIS
      Returns the MECM (SCCM) import event log.
      .DESCRIPTION
      Retrieves the event stream for MECM import jobs — start / progress /
      completion / failure entries — useful for diagnosing a stalled or
      partial import without leaving the PowerShell session.
      .PARAMETER Instance
      The URL of the App Readiness instance. Not required if connected via Connect-JuribaAppR.
      .PARAMETER APIKey
      The API key for authentication. Not required if connected via Connect-JuribaAppR.
      .EXAMPLE
      Get-JuribaAppRMECMImportEvent
      Returns the most recent MECM import events.
      .EXAMPLE
      Get-JuribaAppRMECMImportEvent | Where-Object { $_.level -eq 'Error' }
      Filters the event stream client-side for errors.
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
        -Uri 'api/admin/sccm/events' -Method GET
}
