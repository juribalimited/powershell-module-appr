function Start-JuribaAppRSmokeTest {
    <#
      .SYNOPSIS
      Initiates a smoke test for a specific application.
      .DESCRIPTION
      Starts an automated smoke test for the specified application and package type.
      Can target a specific VM group or use the default. For single application
      testing, provide the AppId and PackageType. For manual test runs that
      require a specific VM, also provide VMGroupId.
      .PARAMETER Instance
      The URL of the App Readiness instance. Not required if connected via Connect-JuribaAppR.
      .PARAMETER APIKey
      The API key for authentication. Not required if connected via Connect-JuribaAppR.
      .PARAMETER AppId
      The unique identifier of the application to test.
      .PARAMETER PackageType
      The package type to test (e.g. Msi, Msix, IntuneWin, AppV).
      .PARAMETER VMGroupId
      Optional. The VM group (pool) to run the test on. If not specified,
      runs as a single test using the default environment.
      .EXAMPLE
      Start-JuribaAppRSmokeTest -AppId 42 -PackageType Msi
      Starts a smoke test of the MSI package for application 42.
      .EXAMPLE
      Start-JuribaAppRSmokeTest -AppId 42 -PackageType IntuneWin -VMGroupId 1
      Starts a smoke test on VM group 1 for the IntuneWin package of application 42.
    #>

    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory = $false)]
        [string]$Instance,

        [Parameter(Mandatory = $false)]
        [string]$APIKey,

        [Parameter(Mandatory = $true)]
        [int]$AppId,

        [Parameter(Mandatory = $true)]
        [string]$PackageType,

        [Parameter(Mandatory = $false)]
        [int]$VMGroupId
    )

    $conn = Get-JuribaAppRConnection -Instance $Instance -APIKey $APIKey

    $Target = "App $AppId ($PackageType)"

    if ($PSCmdlet.ShouldProcess($Target, "Start smoke test")) {
        if ($VMGroupId) {
            $uri = "api/ace/testing/manualTest/$AppId/$VMGroupId/$PackageType"
            Invoke-JuribaAppRRestMethod -Instance $conn.Instance -APIKey $conn.APIKey `
                -Uri $uri -Method PUT
        }
        else {
            $uri = "api/ace/testing/singleTest/$AppId/$PackageType"
            Invoke-JuribaAppRRestMethod -Instance $conn.Instance -APIKey $conn.APIKey `
                -Uri $uri -Method POST
        }
    }
}
