function Set-JuribaAppRApplicationOwner {
    <#
      .SYNOPSIS
      Assigns an owner to an application in Juriba App Readiness.
      .DESCRIPTION
      Sets the owner of an application to the specified user. This is used
      to assign the application to the requester from an external request system
      such as ServiceNow.
      .PARAMETER Instance
      The URL of the App Readiness instance. Not required if connected via Connect-JuribaAppR.
      .PARAMETER APIKey
      The API key for authentication. Not required if connected via Connect-JuribaAppR.
      .PARAMETER AppId
      The unique identifier of the application.
      .PARAMETER UserId
      The unique identifier of the user to assign as owner.
      .EXAMPLE
      Set-JuribaAppRApplicationOwner -AppId 42 -UserId 5
      Assigns user 5 as the owner of application 42.
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
        [int]$UserId
    )

    $conn = Get-JuribaAppRConnection -Instance $Instance -APIKey $APIKey

    if ($PSCmdlet.ShouldProcess("App $AppId", "Assign owner User $UserId")) {
        Invoke-JuribaAppRRestMethod -Instance $conn.Instance -APIKey $conn.APIKey `
            -Uri "api/apm/application/$AppId/owner/$UserId" -Method PUT
    }
}
