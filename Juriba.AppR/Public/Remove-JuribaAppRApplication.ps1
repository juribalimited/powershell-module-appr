function Remove-JuribaAppRApplication {
    <#
      .SYNOPSIS
      Removes an application from Juriba App Readiness.
      .DESCRIPTION
      Deletes an application and all associated data from App Readiness.
      This action cannot be undone.
      .PARAMETER Instance
      The URL of the App Readiness instance. Not required if connected via Connect-JuribaAppR.
      .PARAMETER APIKey
      The API key for authentication. Not required if connected via Connect-JuribaAppR.
      .PARAMETER AppId
      The unique identifier of the application to remove.
      .EXAMPLE
      Remove-JuribaAppRApplication -AppId 42
      Removes application 42 from App Readiness.
      .EXAMPLE
      Remove-JuribaAppRApplication -AppId 42 -WhatIf
      Shows what would happen if application 42 were removed, without actually removing it.
    #>

    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [Parameter(Mandatory = $false)]
        [string]$Instance,

        [Parameter(Mandatory = $false)]
        [string]$APIKey,

        [Parameter(Mandatory = $true)]
        [int]$AppId
    )

    $conn = Get-JuribaAppRConnection -Instance $Instance -APIKey $APIKey

    if ($PSCmdlet.ShouldProcess("App $AppId", "Remove application")) {
        Invoke-JuribaAppRRestMethod -Instance $conn.Instance -APIKey $conn.APIKey `
            -Uri "api/apm/application/$AppId" -Method DELETE
    }
}
