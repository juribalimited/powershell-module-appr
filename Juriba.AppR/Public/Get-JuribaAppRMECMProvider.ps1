function Get-JuribaAppRMECMProvider {
    <#
      .SYNOPSIS
      Lists configured integration provider settings on the AppR instance, or returns a specific provider by id.
      .DESCRIPTION
      Returns the integration provider configurations stored at /api/admin/sccm/* —
      typically MECM/SCCM and Intune connectors with their hostnames, site
      codes, application-name templates, and isImportEnabled / isDeployEnabled
      flags. Despite the URL path being /admin/sccm, the list spans every
      integration type configured on the instance, not just SCCM.

      Use this to find the MECM-type provider (`providerType = 1` —
      `IntegrationProviderTypes` enum) that has `isImportEnabled = $true`
      before kicking off Start-JuribaAppRMECMImport.

      Read-only. Provider records are configured via the AppR admin UI;
      Remove-JuribaAppRMECMProvider removes them, Set-JuribaAppRMECMProviderUniqueness
      toggles uniqueness on a single provider.
      .PARAMETER Instance
      The URL of the App Readiness instance. Not required if connected via Connect-JuribaAppR.
      .PARAMETER APIKey
      The API key for authentication. Not required if connected via Connect-JuribaAppR.
      .PARAMETER Id
      Optional. The unique identifier of a specific provider record. When
      omitted, every configured provider is returned.
      .EXAMPLE
      Get-JuribaAppRMECMProvider
      Returns every configured integration provider (Intune + MECM).
      .EXAMPLE
      Get-JuribaAppRMECMProvider | Where-Object { $_.integrationType -eq 1 -and $_.isImportEnabled }
      Filters to only MECM-type providers that have import turned on.
      .EXAMPLE
      Get-JuribaAppRMECMProvider -Id 7
      Returns full configuration detail (hostname, siteCode, templates, …) for provider id 7.
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$Instance,

        [Parameter(Mandatory = $false)]
        [string]$APIKey,

        [Parameter(Mandatory = $false)]
        [int]$Id
    )

    $conn = Get-JuribaAppRConnection -Instance $Instance -APIKey $APIKey

    $uri = if ($PSBoundParameters.ContainsKey('Id')) {
        "api/admin/sccm/$Id"
    } else {
        'api/admin/sccm/list'
    }

    Invoke-JuribaAppRRestMethod -Instance $conn.Instance -APIKey $conn.APIKey `
        -Uri $uri -Method GET
}
