function Set-JuribaAppRApplicationCommandLine {
    <#
      .SYNOPSIS
      Sets an override command line for an application.
      .DESCRIPTION
      Specifies a custom command line for an application, overriding the
      automatically suggested command line. Use this when the requester
      knows the desired installation command line.
      .PARAMETER Instance
      The URL of the App Readiness instance. Not required if connected via Connect-JuribaAppR.
      .PARAMETER APIKey
      The API key for authentication. Not required if connected via Connect-JuribaAppR.
      .PARAMETER AppId
      The unique identifier of the application.
      .PARAMETER CommandLine
      The command line string to set for the application.
      .EXAMPLE
      Set-JuribaAppRApplicationCommandLine -AppId 42 -CommandLine "/S /v/qn"
      Sets a silent install command line for application 42.
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
        [string]$CommandLine
    )

    $conn = Get-JuribaAppRConnection -Instance $Instance -APIKey $APIKey

    $body = @{
        commandLine = $CommandLine
    }

    if ($PSCmdlet.ShouldProcess("App $AppId", "Set command line to '$CommandLine'")) {
        Invoke-JuribaAppRRestMethod -Instance $conn.Instance -APIKey $conn.APIKey `
            -Uri "api/apm/application/$AppId/commandLine" -Method PUT -Body $body
    }
}
