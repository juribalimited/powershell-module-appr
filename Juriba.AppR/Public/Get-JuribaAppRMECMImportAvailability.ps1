function Get-JuribaAppRMECMImportAvailability {
    <#
      .SYNOPSIS
      Checks whether a Microsoft Endpoint Configuration Manager (MECM/SCCM) import can be run right now.
      .DESCRIPTION
      Calls the AppR availability endpoint to determine whether the MECM
      connector is configured and able to start a new import job. Useful as a
      preflight before Start-JuribaAppRMECMImport so a script can fail fast
      with a clear message instead of letting the import attempt return
      a partial / inconsistent result.
      .PARAMETER Instance
      The URL of the App Readiness instance. Not required if connected via Connect-JuribaAppR.
      .PARAMETER APIKey
      The API key for authentication. Not required if connected via Connect-JuribaAppR.
      .EXAMPLE
      Get-JuribaAppRMECMImportAvailability
      Returns the MECM import availability state for the connected instance.
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
        -Uri 'api/admin/sccm/import/availability' -Method GET
}
