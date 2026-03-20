function Get-JuribaAppRApplication {
    <#
      .SYNOPSIS
      Gets application details from Juriba App Readiness.
      .DESCRIPTION
      Retrieves detailed information about a specific application by its ID,
      or returns a list of all applications. When called with -AppId, returns
      full application details including status, packages, and assignment information.
      .PARAMETER Instance
      The URL of the App Readiness instance. Not required if connected via Connect-JuribaAppR.
      .PARAMETER APIKey
      The API key for authentication. Not required if connected via Connect-JuribaAppR.
      .PARAMETER AppId
      The unique identifier of the application to retrieve. If omitted, returns all applications.
      .PARAMETER Basic
      When specified with -AppId, returns only basic application information.
      .EXAMPLE
      Get-JuribaAppRApplication
      Returns a list of all applications in App Readiness.
      .EXAMPLE
      Get-JuribaAppRApplication -AppId 42
      Returns detailed information for the application with ID 42.
      .EXAMPLE
      Get-JuribaAppRApplication -AppId 42 -Basic
      Returns only basic information for the application with ID 42.
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$Instance,

        [Parameter(Mandatory = $false)]
        [string]$APIKey,

        [Parameter(Mandatory = $false)]
        [int]$AppId,

        [Parameter(Mandatory = $false)]
        [switch]$Basic
    )

    $conn = Get-JuribaAppRConnection -Instance $Instance -APIKey $APIKey

    if ($AppId) {
        if ($Basic) {
            $uri = "api/apm/application/$AppId/basic"
        }
        else {
            $uri = "api/apm/application/$AppId"
        }
    }
    else {
        $uri = "api/apm/applications"
    }

    Invoke-JuribaAppRRestMethod -Instance $conn.Instance -APIKey $conn.APIKey `
        -Uri $uri -Method GET
}
