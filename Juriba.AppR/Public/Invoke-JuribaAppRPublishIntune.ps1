function Invoke-JuribaAppRPublishIntune {
    <#
      .SYNOPSIS
      Publishes a package to Microsoft Intune.
      .DESCRIPTION
      Triggers the publishing of a completed package to Microsoft Intune. This is
      one of the primary publishing actions, allowing automated deployment of
      packaged applications to Intune for assignment to users and devices.
      .PARAMETER Instance
      The URL of the App Readiness instance. Not required if connected via Connect-JuribaAppR.
      .PARAMETER APIKey
      The API key for authentication. Not required if connected via Connect-JuribaAppR.
      .PARAMETER Body
      A hashtable containing the publishing configuration, including the application
      ID, package type, and any Intune-specific properties.
      .EXAMPLE
      Invoke-JuribaAppRPublishIntune -Body @{ applicationId = 42; packageType = "IntuneWin" }
      Publishes the IntuneWin package for application 42 to Intune.
    #>

    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory = $false)]
        [string]$Instance,

        [Parameter(Mandatory = $false)]
        [string]$APIKey,

        [Parameter(Mandatory = $true)]
        [hashtable]$Body
    )

    $conn = Get-JuribaAppRConnection -Instance $Instance -APIKey $APIKey

    $Target = "App {0} ({1})" -f $Body['applicationId'], $Body['packageType']

    if ($PSCmdlet.ShouldProcess($Target, "Publish to Intune")) {
        Invoke-JuribaAppRRestMethod -Instance $conn.Instance -APIKey $conn.APIKey `
            -Uri "api/publishing/intune" -Method POST -Body $Body
    }
}
