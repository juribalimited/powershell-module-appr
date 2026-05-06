function Set-JuribaAppRMECMProviderUniqueness {
    <#
      .SYNOPSIS
      Toggles the uniqueness flag on a configured integration provider.
      .DESCRIPTION
      Flips the per-provider uniqueness setting at /api/admin/sccm/{id}/uniqueness.
      Uniqueness controls whether AppR should de-duplicate applications coming
      from this provider against existing records — useful when the same app
      may exist multiple times in the source catalogue (e.g. duplicate
      deployment types or supersedence chains in MECM).

      The endpoint is a parameterless toggle on the server side — call it
      to flip the current value; there is no separate "true / false" body.
      Inspect the result via Get-JuribaAppRMECMProvider -Id $Id afterwards
      to confirm.
      .PARAMETER Instance
      The URL of the App Readiness instance. Not required if connected via Connect-JuribaAppR.
      .PARAMETER APIKey
      The API key for authentication. Not required if connected via Connect-JuribaAppR.
      .PARAMETER Id
      The unique identifier of the integration provider whose uniqueness flag
      to toggle.
      .EXAMPLE
      Set-JuribaAppRMECMProviderUniqueness -Id 7
      Toggles the uniqueness flag on the MECM provider with id 7.
    #>

    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory = $false)]
        [string]$Instance,

        [Parameter(Mandatory = $false)]
        [string]$APIKey,

        [Parameter(Mandatory = $true)]
        [int]$Id
    )

    $conn = Get-JuribaAppRConnection -Instance $Instance -APIKey $APIKey

    if ($PSCmdlet.ShouldProcess("integration provider $Id", 'Toggle uniqueness flag')) {
        Invoke-JuribaAppRRestMethod -Instance $conn.Instance -APIKey $conn.APIKey `
            -Uri "api/admin/sccm/$Id/uniqueness" -Method PUT
    }
}
