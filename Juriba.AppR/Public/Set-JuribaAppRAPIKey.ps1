function Set-JuribaAppRAPIKey {
    <#
      .SYNOPSIS
      Stores an App Readiness API key in a PowerShell SecretManagement vault.
      .DESCRIPTION
      Convenience wrapper around Set-Secret that stores an API key for later use
      with Connect-JuribaAppR -SecretName. The key is encrypted at rest by the
      vault provider (e.g. SecretStore, Azure Key Vault, etc.).

      This is a one-time setup step. After storing the key, connect with:
        Connect-JuribaAppR -Instance "https://..." -SecretName "AppR-Production"

      Requires:
        - Microsoft.PowerShell.SecretManagement module
        - At least one registered vault (e.g. Microsoft.PowerShell.SecretStore)

      Quick setup if you have no vault yet:
        Install-Module Microsoft.PowerShell.SecretManagement -Scope CurrentUser
        Install-Module Microsoft.PowerShell.SecretStore -Scope CurrentUser
        Register-SecretVault -Name "Default" -ModuleName Microsoft.PowerShell.SecretStore -DefaultVault
      .PARAMETER SecretName
      The name to store the secret under. Use a descriptive name like
      "AppR-Production" or "AppR-JnJ" so it's clear which instance it belongs to.
      .PARAMETER APIKey
      The API key as a plain text string. It will be stored encrypted in the vault
      and the plain text variable should be cleared afterward.
      .PARAMETER SecureAPIKey
      The API key as a SecureString. Preferred for interactive use:
        Set-JuribaAppRAPIKey -SecretName "AppR-Prod" -SecureAPIKey (Read-Host "Key" -AsSecureString)
      .PARAMETER VaultName
      Optional. The vault to store the secret in. If omitted, uses the default vault.
      .EXAMPLE
      Set-JuribaAppRAPIKey -SecretName "AppR-Production" -APIKey "WeBP5sp+eQ..."
      Stores the key in the default vault. Then connect with:
        Connect-JuribaAppR -Instance "https://appr.example.com" -SecretName "AppR-Production"
      .EXAMPLE
      Set-JuribaAppRAPIKey -SecretName "AppR-JnJ" -SecureAPIKey (Read-Host "API Key" -AsSecureString)
      Prompts for the key without displaying it, then stores it securely.
      .EXAMPLE
      Set-JuribaAppRAPIKey -SecretName "AppR-Dev" -APIKey $key -VaultName "TeamVault"
      Stores the key in a specific named vault.
    #>

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'Interactive confirmation shown to the user after storing the API key in the vault.')]
    [CmdletBinding(DefaultParameterSetName = 'PlainText', SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$SecretName,

        [Parameter(Mandatory = $true, ParameterSetName = 'PlainText', Position = 1)]
        [string]$APIKey,

        [Parameter(Mandatory = $true, ParameterSetName = 'SecureString')]
        [SecureString]$SecureAPIKey,

        [Parameter(Mandatory = $false)]
        [string]$VaultName
    )

    # Verify SecretManagement is available
    if (-not (Get-Module -ListAvailable -Name 'Microsoft.PowerShell.SecretManagement')) {
        throw @"
The Microsoft.PowerShell.SecretManagement module is not installed.

To set up secure secret storage, run:

  Install-Module Microsoft.PowerShell.SecretManagement -Scope CurrentUser
  Install-Module Microsoft.PowerShell.SecretStore -Scope CurrentUser
  Register-SecretVault -Name "Default" -ModuleName Microsoft.PowerShell.SecretStore -DefaultVault

Then retry this command.
"@
    }

    Import-Module Microsoft.PowerShell.SecretManagement -ErrorAction Stop

    # Resolve to plain text for Set-Secret (it handles encryption internally)
    $plainKey = $null
    if ($PSCmdlet.ParameterSetName -eq 'SecureString') {
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureAPIKey)
        try {
            $plainKey = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
        }
        finally {
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
    }
    else {
        $plainKey = $APIKey
    }

    # Store the secret
    $setParams = @{ Name = $SecretName; Secret = $plainKey }
    if ($VaultName) { $setParams['Vault'] = $VaultName }
    $vaultMsg = if ($VaultName) { " in vault '$VaultName'" } else { " in the default vault" }

    if (-not $PSCmdlet.ShouldProcess("secret '$SecretName'$vaultMsg", 'Set')) {
        $plainKey = $null
        return
    }

    try {
        Set-Secret @setParams
    }
    catch {
        throw "Failed to store secret '$SecretName'$vaultMsg. Error: $($_.Exception.Message)"
    }
    finally {
        # Clear plain text from memory
        $plainKey = $null
    }

    Write-Host "API key stored as '$SecretName'$vaultMsg." -ForegroundColor Green
    Write-Host "Connect with: Connect-JuribaAppR -Instance `"https://...`" -SecretName `"$SecretName`"" -ForegroundColor Cyan
}
