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

      Both forms support -WhatIf and -Confirm; -All has ConfirmImpact=High
      because dropping every provider can wipe a lot of state in one call.
      .PARAMETER Instance
      The URL of the App Readiness instance. Not required if connected via Connect-JuribaAppR.
      .PARAMETER APIKey
      The API key for authentication. Not required if connected via Connect-JuribaAppR.
      .PARAMETER Id
      Removes a single provider configuration by id.
      .PARAMETER All
      Removes every configured provider. Mutually exclusive with -Id.
      .EXAMPLE
      Remove-JuribaAppRMECMProvider -Id 7
      Removes a single provider record.
      .EXAMPLE
      Remove-JuribaAppRMECMProvider -All -Confirm:$false
      Removes every configured provider without prompting.
    #>

    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'ById')]
    param (
        [Parameter(Mandatory = $false)]
        [string]$Instance,

        [Parameter(Mandatory = $false)]
        [string]$APIKey,

        [Parameter(Mandatory = $true, ParameterSetName = 'ById')]
        [int]$Id,

        [Parameter(Mandatory = $true, ParameterSetName = 'All')]
        [switch]$All
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

    if ($PSCmdlet.ShouldProcess($target, $action)) {
        Invoke-JuribaAppRRestMethod -Instance $conn.Instance -APIKey $conn.APIKey `
            -Uri $uri -Method DELETE
    }
}
