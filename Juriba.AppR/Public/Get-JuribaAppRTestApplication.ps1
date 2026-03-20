function Get-JuribaAppRTestApplication {
    <#
      .SYNOPSIS
      Gets applications available for testing in Juriba App Readiness.
      .DESCRIPTION
      Retrieves applications that are available in the ACE (Automated Compatibility
      Engine) testing environment. Returns testing status, results, and available
      package information for each application.
      .PARAMETER Instance
      The URL of the App Readiness instance. Not required if connected via Connect-JuribaAppR.
      .PARAMETER APIKey
      The API key for authentication. Not required if connected via Connect-JuribaAppR.
      .PARAMETER AppId
      Optional. The unique identifier of a specific application to get test details for.
      .PARAMETER AllEnvironments
      When specified, returns applications across all testing environments.
      .EXAMPLE
      Get-JuribaAppRTestApplication
      Returns all applications available for testing.
      .EXAMPLE
      Get-JuribaAppRTestApplication -AppId 42
      Returns test details for application 42.
      .EXAMPLE
      Get-JuribaAppRTestApplication -AllEnvironments
      Returns test applications across all environments.
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
        [switch]$AllEnvironments
    )

    $conn = Get-JuribaAppRConnection -Instance $Instance -APIKey $APIKey

    if ($AppId) {
        $uri = "api/ace/application/$AppId"
    }
    elseif ($AllEnvironments) {
        $uri = "api/ace/applications/allEnvironments"
    }
    else {
        $uri = "api/ace/applications"
    }

    Invoke-JuribaAppRRestMethod -Instance $conn.Instance -APIKey $conn.APIKey `
        -Uri $uri -Method GET
}
