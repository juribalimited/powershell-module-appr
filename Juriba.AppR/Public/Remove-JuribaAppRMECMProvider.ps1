function Remove-JuribaAppRMECMProvider {
    <#
      .SYNOPSIS
      Removes one or all integration provider configurations from App Readiness.
      .DESCRIPTION
      Deletes an integration provider configuration (the connector settings
      stored at /api/admin/sccm/*) — either a specific one by `-Id` or every
      configured provider with `-All`. The remote MECM/Intune side is not
      touched; only the AppR-side connector settings are removed. Use this
      to reset connector state before re-configuring with different
      hostname / site code / template values.

      Both forms support -WhatIf and -Confirm. The -All branch always
      prompts (even with $ConfirmPreference=None) because dropping every
      provider can wipe a lot of state in one call; -Confirm:$false
      still suppresses the prompt for unattended use.
      .PARAMETER Instance
      The URL of the App Readiness instance. Not required if connected via Connect-JuribaAppR.
      .PARAMETER APIKey
      The API key for authentication. Not required if connected via Connect-JuribaAppR.
      .PARAMETER Id
      Removes a single provider configuration by id.
      .PARAMETER All
      Removes every configured provider. Mutually exclusive with -Id.
      .PARAMETER Force
      With -All, suppresses the bulk-removal prompt. Equivalent to
      -Confirm:$false but also bypasses an explicit ShouldContinue
      gate. Has no effect on the -Id path.
      .EXAMPLE
      Remove-JuribaAppRMECMProvider -Id 7
      Removes a single provider record.
      .EXAMPLE
      Remove-JuribaAppRMECMProvider -All -Force
      Removes every configured provider without any prompt — for
      unattended scripts.
    #>

    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ById')]
    param (
        [Parameter(Mandatory = $false)]
        [string]$Instance,

        [Parameter(Mandatory = $false)]
        [string]$APIKey,

        [Parameter(Mandatory = $true, ParameterSetName = 'ById')]
        [int]$Id,

        [Parameter(Mandatory = $true, ParameterSetName = 'All')]
        [switch]$All,

        [Parameter(ParameterSetName = 'All')]
        [switch]$Force
    )

    $conn = Get-JuribaAppRConnection -Instance $Instance -APIKey $APIKey

    if ($All) {
        $uri = 'api/admin/sccm/all'
        $target = 'ALL configured integration providers'
        $action = 'Remove all integration providers'
    } else {
        $uri = "api/admin/sccm/$Id"
        $target = "integration provider $Id"
        $action = 'Remove integration provider'
    }

    # ConfirmImpact is per-function and applies to the whole cmdlet. Keep
    # the function at Medium so single-id deletion uses the regular
    # Confirm flow, then layer an explicit ShouldContinue on the -All
    # branch so the bulk path still prompts when $ConfirmPreference is
    # below High. -Confirm:$false suppresses both gates for unattended use.
    if ($All -and -not $Force -and -not $WhatIfPreference -and $ConfirmPreference -ne 'None') {
        if (-not $PSCmdlet.ShouldContinue(
                'This will remove ALL configured integration providers (every Intune + MECM connector). Continue?',
                'Confirm bulk removal')) {
            return
        }
    }

    if ($PSCmdlet.ShouldProcess($target, $action)) {
        Invoke-JuribaAppRRestMethod -Instance $conn.Instance -APIKey $conn.APIKey `
            -Uri $uri -Method DELETE
    }
}
