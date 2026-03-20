function Get-JuribaAppRApplicationList {
    <#
      .SYNOPSIS
      Gets a filtered list of applications from Juriba App Readiness.
      .DESCRIPTION
      Retrieves a list of applications with optional filtering. Supports searching
      by query string and returning results for specific users or all users.
      Use this cmdlet for browsing and filtering applications rather than
      Get-JuribaAppRApplication which retrieves full details for a single app.
      .PARAMETER Instance
      The URL of the App Readiness instance. Not required if connected via Connect-JuribaAppR.
      .PARAMETER APIKey
      The API key for authentication. Not required if connected via Connect-JuribaAppR.
      .PARAMETER Query
      A search query to filter applications by name, vendor, or other attributes.
      .PARAMETER AllUsers
      When specified, returns applications for all users rather than just the current user.
      .PARAMETER Lite
      When specified with -AllUsers, returns a lightweight result set with minimal fields.
      .EXAMPLE
      Get-JuribaAppRApplicationList
      Returns applications assigned to the current user.
      .EXAMPLE
      Get-JuribaAppRApplicationList -Query "Chrome"
      Searches for applications matching "Chrome".
      .EXAMPLE
      Get-JuribaAppRApplicationList -AllUsers
      Returns applications for all users.
      .EXAMPLE
      Get-JuribaAppRApplicationList -AllUsers -Lite
      Returns a lightweight list of all applications.
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$Instance,

        [Parameter(Mandatory = $false)]
        [string]$APIKey,

        [Parameter(Mandatory = $false)]
        [string]$Query,

        [Parameter(Mandatory = $false)]
        [switch]$AllUsers,

        [Parameter(Mandatory = $false)]
        [switch]$Lite
    )

    $conn = Get-JuribaAppRConnection -Instance $Instance -APIKey $APIKey

    if ($Query) {
        $uri = "api/apm/applications/query/{0}" -f [System.Uri]::EscapeDataString($Query)
    }
    elseif ($AllUsers -and $Lite) {
        $uri = "api/apm/applications/listOfAppsLite/true"
    }
    elseif ($AllUsers) {
        $uri = "api/apm/applications/listOfAppsV2/true"
    }
    else {
        $uri = "api/apm/applications/user"
    }

    Invoke-JuribaAppRRestMethod -Instance $conn.Instance -APIKey $conn.APIKey `
        -Uri $uri -Method GET
}
