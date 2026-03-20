function Stop-JuribaAppRSmokeTest {
    <#
      .SYNOPSIS
      Cancels a running smoke test.
      .DESCRIPTION
      Cancels an in-progress smoke test. The test will be marked as cancelled
      and the associated virtual machine will be released.
      .PARAMETER Instance
      The URL of the App Readiness instance. Not required if connected via Connect-JuribaAppR.
      .PARAMETER APIKey
      The API key for authentication. Not required if connected via Connect-JuribaAppR.
      .EXAMPLE
      Stop-JuribaAppRSmokeTest
      Cancels the current smoke test.
    #>

    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory = $false)]
        [string]$Instance,

        [Parameter(Mandatory = $false)]
        [string]$APIKey
    )

    $conn = Get-JuribaAppRConnection -Instance $Instance -APIKey $APIKey

    if ($PSCmdlet.ShouldProcess("Smoke test", "Cancel")) {
        Invoke-JuribaAppRRestMethod -Instance $conn.Instance -APIKey $conn.APIKey `
            -Uri "api/ace/testing/cancel" -Method POST
    }
}
