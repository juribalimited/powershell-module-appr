function Set-JuribaAppRApplication {
    <#
      .SYNOPSIS
      Updates basic properties of an application in Juriba App Readiness.
      .DESCRIPTION
      Updates the basic properties of an application such as its name or
      other editable attributes. Use this cmdlet to override the application
      name when it differs from what the uploaded file contains.
      .PARAMETER Instance
      The URL of the App Readiness instance. Not required if connected via Connect-JuribaAppR.
      .PARAMETER APIKey
      The API key for authentication. Not required if connected via Connect-JuribaAppR.
      .PARAMETER AppId
      The unique identifier of the application to update.
      .PARAMETER Body
      A hashtable of properties to update. The properties depend on the
      application's current state and the API schema.
      .EXAMPLE
      Set-JuribaAppRApplication -AppId 42 -Body @{ name = "Firefox ESR 115.0" }
      Updates the name of application 42.
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
        [hashtable]$Body
    )

    $conn = Get-JuribaAppRConnection -Instance $Instance -APIKey $APIKey

    if ($PSCmdlet.ShouldProcess("App $AppId", "Update application properties")) {
        Invoke-JuribaAppRRestMethod -Instance $conn.Instance -APIKey $conn.APIKey `
            -Uri "api/apm/application/$AppId/basic" -Method PUT -Body $body
    }
}
