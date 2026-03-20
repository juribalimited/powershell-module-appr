function Invoke-JuribaAppRPublishMECM {
    <#
      .SYNOPSIS
      Publishes a package to Microsoft Endpoint Configuration Manager (MECM/SCCM).
      .DESCRIPTION
      Triggers the publishing of a completed package to MECM. This allows
      automated deployment of packaged applications to MECM for distribution
      to managed devices.
      .PARAMETER Instance
      The URL of the App Readiness instance. Not required if connected via Connect-JuribaAppR.
      .PARAMETER APIKey
      The API key for authentication. Not required if connected via Connect-JuribaAppR.
      .PARAMETER Body
      A hashtable containing the publishing configuration, including the application
      ID, package type, and any MECM-specific properties.
      .EXAMPLE
      Invoke-JuribaAppRPublishMECM -Body @{ applicationId = 42; packageType = "Msi" }
      Publishes the MSI package for application 42 to MECM.
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

    if ($PSCmdlet.ShouldProcess($Target, "Publish to MECM")) {
        Invoke-JuribaAppRRestMethod -Instance $conn.Instance -APIKey $conn.APIKey `
            -Uri "api/publishing/mecm" -Method POST -Body $Body
    }
}
