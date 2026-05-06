function Get-JuribaAppRUser {
    <#
      .SYNOPSIS
      Gets user information from Juriba App Readiness.
      .DESCRIPTION
      Retrieves user information. Can return the current user's details,
      a specific user by ID, or a list of all users.

      The -Me path merges /api/apm/user/whoAmI (which returns just the
      numeric user id) into /api/apm/user/whoAmI/full (which has
      everything else but omits the id), so callers can resolve their
      own id with a single call — handy for Set-JuribaAppRApplicationOwner.
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
        Invoke-JuribaAppRRestMethod -Instance $conn.Instance -APIKey $conn.APIKey `
            -Uri "api/apm/user/$UserId" -Method GET
    }
    elseif ($All) {
        Invoke-JuribaAppRRestMethod -Instance $conn.Instance -APIKey $conn.APIKey `
            -Uri 'api/apm/users/all' -Method GET
    }
    else {
        # Default behavior: -Me switch or no explicit parameter set.
        # /api/apm/user/whoAmI returns just the integer user id.
        # /api/apm/user/whoAmI/full returns the full profile but
        # without the id. Merge them so callers can resolve the id
        # without needing two endpoints.
        Write-Verbose "Fetching current user (Me=$Me)"
        $full = Invoke-JuribaAppRRestMethod -Instance $conn.Instance -APIKey $conn.APIKey `
            -Uri 'api/apm/user/whoAmI/full' -Method GET
        $id = Invoke-JuribaAppRRestMethod -Instance $conn.Instance -APIKey $conn.APIKey `
            -Uri 'api/apm/user/whoAmI' -Method GET
        # whoAmI may come back as int / long / string depending on parser;
        # accept anything that converts to a positive int.
        $idAsInt = 0
        if ($null -ne $id -and [int]::TryParse([string]$id, [ref]$idAsInt) -and $idAsInt -gt 0) {
            if ($full) {
                $full | Add-Member -NotePropertyName 'userId' -NotePropertyValue $idAsInt -Force -PassThru
            } else {
                [pscustomobject]@{ userId = $idAsInt }
            }
        } else {
            Write-Verbose "whoAmI returned '$id'; userId not added to result."
            $full
        }
    }
}
