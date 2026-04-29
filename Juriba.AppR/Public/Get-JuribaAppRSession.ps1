function Get-JuribaAppRSession {
    <#
      .SYNOPSIS
      Gets information about the current Juriba App Readiness connection.
      .DESCRIPTION
      Returns public-safe details (instance URL, connected-at timestamp) for the
      active session established by Connect-JuribaAppR. Returns $null if there
      is no active connection. The API key is NOT exposed.

      Useful for scripts that need to check whether a session exists or display
      the current instance URL without poking at module internals.
      .EXAMPLE
      Get-JuribaAppRSession
      Returns @{ Instance = 'https://appr.example.com'; ConnectedAt = <date> }
      when connected, or $null when not.
      .EXAMPLE
      if (Get-JuribaAppRSession) { "Already connected" } else { Connect-JuribaAppR ... }
      Uses the session as a truthy check for an active connection.
      .EXAMPLE
      (Get-JuribaAppRSession).Instance
      Returns just the instance URL of the current session.
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param ()

    if ($script:appRConnection) {
        [PSCustomObject]@{
            Instance    = $script:appRConnection.Instance
            ConnectedAt = $script:appRConnection.ConnectedAt
        }
    }
}
