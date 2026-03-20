function Get-JuribaAppRTestStats {
    <#
      .SYNOPSIS
      Gets testing statistics from Juriba App Readiness.
      .DESCRIPTION
      Retrieves aggregate testing statistics, optionally for a specific
      application. Returns summary information about test pass/fail rates.
      .PARAMETER Instance
      The URL of the App Readiness instance. Not required if connected via Connect-JuribaAppR.
      .PARAMETER APIKey
      The API key for authentication. Not required if connected via Connect-JuribaAppR.
      .PARAMETER AppId
      Optional. The unique identifier of an application to get stats for.
      If omitted, returns overall testing statistics.
      .EXAMPLE
      Get-JuribaAppRTestStats
      Returns overall testing statistics.
      .EXAMPLE
      Get-JuribaAppRTestStats -AppId 42
      Returns testing statistics for application 42.
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$Instance,

        [Parameter(Mandatory = $false)]
        [string]$APIKey,

        [Parameter(Mandatory = $false)]
        [int]$AppId
    )

    $conn = Get-JuribaAppRConnection -Instance $Instance -APIKey $APIKey

    if ($AppId) {
        $uri = "api/ace/stats/$AppId"
    }
    else {
        $uri = "api/ace/stats"
    }

    Invoke-JuribaAppRRestMethod -Instance $conn.Instance -APIKey $conn.APIKey `
        -Uri $uri -Method GET
}
