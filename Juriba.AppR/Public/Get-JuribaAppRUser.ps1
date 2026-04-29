function Get-JuribaAppRUser {
    <#
      .SYNOPSIS
      Gets user information from Juriba App Readiness.
      .DESCRIPTION
      Retrieves user information. Can return the current user's details,
      a specific user by ID, or a list of all users.
      .PARAMETER Instance
      The URL of the App Readiness instance. Not required if connected via Connect-JuribaAppR.
      .PARAMETER APIKey
      The API key for authentication. Not required if connected via Connect-JuribaAppR.
      .PARAMETER UserId
      The unique identifier of a specific user to retrieve.
      .PARAMETER All
      When specified, returns all users in the system.
      .PARAMETER Me
      When specified, returns details for the currently authenticated user.
      .EXAMPLE
      Get-JuribaAppRUser -Me
      Returns information about the current user.
      .EXAMPLE
      Get-JuribaAppRUser -All
      Returns all users in the system.
      .EXAMPLE
      Get-JuribaAppRUser -UserId 5
      Returns information for user with ID 5.
    #>

    [CmdletBinding(DefaultParameterSetName = 'Me')]
    param (
        [Parameter(Mandatory = $false)]
        [string]$Instance,

        [Parameter(Mandatory = $false)]
        [string]$APIKey,

        [Parameter(Mandatory = $true, ParameterSetName = 'ById')]
        [int]$UserId,

        [Parameter(Mandatory = $false, ParameterSetName = 'All')]
        [switch]$All,

        [Parameter(Mandatory = $false, ParameterSetName = 'Me')]
        [switch]$Me
    )

    $conn = Get-JuribaAppRConnection -Instance $Instance -APIKey $APIKey

    if ($UserId) {
        $uri = "api/apm/user/$UserId"
    }
    elseif ($All) {
        $uri = "api/apm/users/all"
    }
    else {
        # Default behavior: -Me switch or no explicit parameter set
        Write-Verbose "Fetching current user (Me=$Me)"
        $uri = "api/apm/user/whoAmI/full"
    }

    Invoke-JuribaAppRRestMethod -Instance $conn.Instance -APIKey $conn.APIKey `
        -Uri $uri -Method GET
}
