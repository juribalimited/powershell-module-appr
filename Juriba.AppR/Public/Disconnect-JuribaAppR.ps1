function Disconnect-JuribaAppR {
    <#
      .SYNOPSIS
      Disconnects from a Juriba App Readiness instance.
      .DESCRIPTION
      Clears the stored connection credentials established by Connect-JuribaAppR.
      After disconnecting, cmdlets will require explicit -Instance and -APIKey parameters.
      .EXAMPLE
      Disconnect-JuribaAppR
      Clears the current App Readiness connection.
    #>

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'Interactive disconnect confirmation for CLI users.')]
    [CmdletBinding()]
    [Alias("Disconnect-AppR")]
    param ()

    if ($script:appRConnection) {
        $instance = $script:appRConnection.Instance
        $script:appRConnection = $null
        Write-Host "Disconnected from Juriba App Readiness at $instance" -ForegroundColor Yellow
    }
    else {
        Write-Warning "No active App Readiness connection to disconnect."
    }
}
