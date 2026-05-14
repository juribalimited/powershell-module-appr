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

      Returns an integer state flag (the swagger schema doesn't enumerate
      it; observed semantics):
        0 — unavailable (no MECM connector configured, or import disabled
            on the configured connector)
        1 — available (a connector is configured with isImportEnabled=true
            and the server is ready to accept Start-JuribaAppRMECMImport)
      Other values may exist for transient states (busy / errored); treat
      anything other than 1 as "do not start an import yet" and inspect
      Get-JuribaAppRMECMProvider for diagnostic details.
      .PARAMETER Instance
      The URL of the App Readiness instance. Not required if connected via Connect-JuribaAppR.
      .PARAMETER APIKey
      The API key for authentication. Not required if connected via Connect-JuribaAppR.
      .EXAMPLE
      Get-JuribaAppRMECMImportAvailability
      Returns the MECM import availability state (e.g. 1 = ready) for the connected instance.
      .EXAMPLE
      if ((Get-JuribaAppRMECMImportAvailability) -ne 1) { throw 'MECM not ready' }
      Pattern for guarding a script against an unconfigured / disabled connector before triggering an import.
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
