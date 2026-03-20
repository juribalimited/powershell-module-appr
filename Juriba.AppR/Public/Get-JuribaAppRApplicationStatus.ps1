function Get-JuribaAppRApplicationStatus {
    <#
      .SYNOPSIS
      Gets the current status and full workflow tracker for an application.
      .DESCRIPTION
      Retrieves the full workflow tracker for a specific application, showing
      the status of each stage including packaging, testing, quality review,
      UAT, and publishing. This is the primary cmdlet for monitoring an
      application's progress through the App Readiness workflow.
      .PARAMETER Instance
      The URL of the App Readiness instance. Not required if connected via Connect-JuribaAppR.
      .PARAMETER APIKey
      The API key for authentication. Not required if connected via Connect-JuribaAppR.
      .PARAMETER AppId
      The unique identifier of the application.
      .EXAMPLE
      Get-JuribaAppRApplicationStatus -AppId 42
      Returns the full workflow tracker for application 42.
      .EXAMPLE
      Get-JuribaAppRApplication -AppId 42 | ForEach-Object { Get-JuribaAppRApplicationStatus -AppId $_.id }
      Retrieves status for an application found by Get-JuribaAppRApplication.
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$Instance,

        [Parameter(Mandatory = $false)]
        [string]$APIKey,

        [Parameter(Mandatory = $true)]
        [int]$AppId
    )

    $conn = Get-JuribaAppRConnection -Instance $Instance -APIKey $APIKey

    Invoke-JuribaAppRRestMethod -Instance $conn.Instance -APIKey $conn.APIKey `
        -Uri "api/apm/application/$AppId/tracker/full" -Method GET
}
