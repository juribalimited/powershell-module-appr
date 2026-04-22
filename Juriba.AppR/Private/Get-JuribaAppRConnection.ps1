function Get-JuribaAppRConnection {
    <#
      .SYNOPSIS
      Internal helper that resolves Instance and APIKey from parameters or the active session.
      .DESCRIPTION
      Checks if explicit parameters were provided. If not, falls back to the module-scoped
      session ($script:appRConnection) established by Connect-JuribaAppR. Returns a hashtable
      with Instance and APIKey, or throws an error if neither source is available.
      This function is not exported and is used internally by public cmdlets.
    #>

    [CmdletBinding()]
    [OutputType([hashtable])]
    param (
        [Parameter(Mandatory = $false)]
        [string]$Instance,

        [Parameter(Mandatory = $false)]
        [string]$APIKey
    )

    # If explicit parameters provided, use them
    if ($Instance -and $APIKey) {
        return @{
            Instance = $Instance.TrimEnd('/')
            APIKey   = $APIKey
        }
    }

    # Fall back to the active module-scoped session
    if ($script:appRConnection) {
        $resolvedInstance = if ($Instance) { $Instance.TrimEnd('/') } else { $script:appRConnection.Instance }
        $resolvedAPIKey = if ($APIKey) { $APIKey } else {
            # Decrypt the SecureString back to plain text for API calls
            $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($script:appRConnection.SecureAPIKey)
            try {
                [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
            }
            finally {
                [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
            }
        }

        return @{
            Instance   = $resolvedInstance
            APIKey     = $resolvedAPIKey
        }
    }

    throw "No connection found. Please provide -Instance and -APIKey parameters, or connect using Connect-JuribaAppR before proceeding."
}
