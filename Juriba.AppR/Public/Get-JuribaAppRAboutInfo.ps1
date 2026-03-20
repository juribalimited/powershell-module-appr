function Get-JuribaAppRAboutInfo {
    <#
      .SYNOPSIS
      Gets information about the Juriba App Readiness instance.
      .DESCRIPTION
      Retrieves general settings and version information about the connected
      App Readiness instance.
      .PARAMETER Instance
      The URL of the App Readiness instance. Not required if connected via Connect-JuribaAppR.
      .PARAMETER APIKey
      The API key for authentication. Not required if connected via Connect-JuribaAppR.
      .EXAMPLE
      Get-JuribaAppRAboutInfo
      Returns instance information using the current connection.
      .EXAMPLE
      Get-JuribaAppRAboutInfo -Instance "https://appr.example.com" -APIKey "your-key"
      Returns instance information using explicit credentials.
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
        -Uri "api/app/about/info" -Method GET
}
