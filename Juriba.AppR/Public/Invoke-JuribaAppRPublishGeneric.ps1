function Invoke-JuribaAppRPublishGeneric {
    <#
      .SYNOPSIS
      Publishes a package to a generic integration.
      .DESCRIPTION
      Triggers the publishing of a completed package to a configured generic
      integration endpoint. Generic integrations allow publishing to custom
      or third-party distribution systems.
      .PARAMETER Instance
      The URL of the App Readiness instance. Not required if connected via Connect-JuribaAppR.
      .PARAMETER APIKey
      The API key for authentication. Not required if connected via Connect-JuribaAppR.
      .PARAMETER Body
      A hashtable containing the publishing configuration, including the application
      ID, package type, and integration-specific properties.
      .EXAMPLE
      Invoke-JuribaAppRPublishGeneric -Body @{ applicationId = 42; packageType = "Msi" }
      Publishes the MSI package for application 42 to the configured generic integration.
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

    if ($PSCmdlet.ShouldProcess($Target, "Publish to generic integration")) {
        Invoke-JuribaAppRRestMethod -Instance $conn.Instance -APIKey $conn.APIKey `
            -Uri "api/publishing/generic" -Method POST -Body $Body
    }
}
