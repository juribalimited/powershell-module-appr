function Get-JuribaAppRTestResult {
    <#
      .SYNOPSIS
      Gets smoke test results for an application.
      .DESCRIPTION
      Retrieves the smoke test results for a specific application, including
      pass/fail status, warnings, and failure details for each package type
      and VM group. Use this to interrogate results and pull back any warning
      or failure information.
      .PARAMETER Instance
      The URL of the App Readiness instance. Not required if connected via Connect-JuribaAppR.
      .PARAMETER APIKey
      The API key for authentication. Not required if connected via Connect-JuribaAppR.
      .PARAMETER AppId
      The unique identifier of the application.
      .PARAMETER VMGroupId
      Optional. Filter results to a specific VM group.
      .PARAMETER PackageType
      Optional. Filter results to a specific package type (e.g. Msi, Msix, IntuneWin).
      .EXAMPLE
      Get-JuribaAppRTestResult -AppId 42
      Returns all smoke test results for application 42.
      .EXAMPLE
      Get-JuribaAppRTestResult -AppId 42 -VMGroupId 1 -PackageType Msi
      Returns MSI test results for application 42 on VM group 1.
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$Instance,

        [Parameter(Mandatory = $false)]
        [string]$APIKey,

        [Parameter(Mandatory = $true)]
        [int]$AppId,

        [Parameter(Mandatory = $false)]
        [int]$VMGroupId,

        [Parameter(Mandatory = $false)]
        [string]$PackageType
    )

    $conn = Get-JuribaAppRConnection -Instance $Instance -APIKey $APIKey

    if ($VMGroupId -and $PackageType) {
        $uri = "api/ace/application/$AppId/$VMGroupId/$PackageType"
    }
    elseif ($AppId) {
        $uri = "api/ace/application/$AppId"
    }

    Invoke-JuribaAppRRestMethod -Instance $conn.Instance -APIKey $conn.APIKey `
        -Uri $uri -Method GET
}
