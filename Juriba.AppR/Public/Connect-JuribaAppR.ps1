function Connect-JuribaAppR {
    <#
      .SYNOPSIS
      Establishes a connection to a Juriba App Readiness instance.
      .DESCRIPTION
      Creates a persistent connection to Juriba App Readiness by storing the instance URL
      and API key securely in a global variable. Once connected, subsequent cmdlets can
      use the stored credentials without requiring -Instance and -APIKey parameters.

      The API key can be provided in three ways (from most to least secure):

        1. SecretManagement vault  — -SecretName "AppR-Production"
        2. SecureString prompt     — -APIKey (Read-Host -AsSecureString "API Key")
        3. Plain text parameter    — -APIKey "your-key" (least secure, avoid in scripts)

      For automation and shared scripts, using SecretManagement is strongly recommended.
      Store the key once with Set-JuribaAppRAPIKey, then connect by name.
      .PARAMETER Instance
      The full URL of the Juriba App Readiness instance (e.g. https://appr.example.com).
      .PARAMETER APIKey
      The API key as a plain text string. Accepted for interactive use and backward
      compatibility, but SecretManagement is preferred for scripts and automation.
      .PARAMETER SecureAPIKey
      The API key as a SecureString. Use with Read-Host -AsSecureString for interactive
      prompts that never expose the key in the console history.
      .PARAMETER SecretName
      The name of a secret stored in a PowerShell SecretManagement vault.
      Requires the Microsoft.PowerShell.SecretManagement module and a registered vault.
      Use Set-JuribaAppRAPIKey to store the key, or Set-Secret directly.
      .PARAMETER VaultName
      Optional. The name of the SecretManagement vault to retrieve the secret from.
      If omitted, the default vault is used.
      .EXAMPLE
      Connect-JuribaAppR -Instance "https://appr.example.com" -SecretName "AppR-Production"
      Connects using an API key stored in the default SecretManagement vault.
      .EXAMPLE
      Connect-JuribaAppR -Instance "https://appr.example.com" -SecretName "AppR-Key" -VaultName "CompanyVault"
      Connects using a key from a specific named vault.
      .EXAMPLE
      Connect-JuribaAppR -Instance "https://appr.example.com" -APIKey "your-api-key-here"
      Connects with a plain text API key (backward compatible, less secure).
      .EXAMPLE
      $secure = Read-Host "Enter API Key" -AsSecureString
      Connect-JuribaAppR -Instance "https://appr.example.com" -SecureAPIKey $secure
      Connects with a SecureString that never appears in console history.
    #>

    [CmdletBinding(DefaultParameterSetName = 'PlainText')]
    [Alias("Connect-AppR")]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Instance,

        [Parameter(Mandatory = $true, ParameterSetName = 'PlainText', Position = 1)]
        [string]$APIKey,

        [Parameter(Mandatory = $true, ParameterSetName = 'SecureString')]
        [SecureString]$SecureAPIKey,

        [Parameter(Mandatory = $true, ParameterSetName = 'SecretManagement')]
        [string]$SecretName,

        [Parameter(Mandatory = $false, ParameterSetName = 'SecretManagement')]
        [string]$VaultName
    )

    $Instance = $Instance.TrimEnd('/')

    # ── Resolve the API key from whichever source was provided ──

    $resolvedKey = $null

    switch ($PSCmdlet.ParameterSetName) {

        'SecretManagement' {
            # Verify SecretManagement is available
            if (-not (Get-Module -ListAvailable -Name 'Microsoft.PowerShell.SecretManagement')) {
                throw "The Microsoft.PowerShell.SecretManagement module is not installed. Install it with: Install-Module Microsoft.PowerShell.SecretManagement -Scope CurrentUser"
            }
            Import-Module Microsoft.PowerShell.SecretManagement -ErrorAction Stop

            $getSecretParams = @{ Name = $SecretName; AsPlainText = $true }
            if ($VaultName) { $getSecretParams['Vault'] = $VaultName }

            try {
                $resolvedKey = Get-Secret @getSecretParams
            }
            catch {
                throw "Failed to retrieve secret '$SecretName'$( if ($VaultName) { " from vault '$VaultName'" } ). Error: $($_.Exception.Message)"
            }

            if ([string]::IsNullOrWhiteSpace($resolvedKey)) {
                throw "Secret '$SecretName' exists but is empty. Store a valid API key with: Set-JuribaAppRAPIKey -SecretName '$SecretName' -APIKey <key>"
            }

            Write-Verbose "API key retrieved from SecretManagement (secret: '$SecretName')"
        }

        'SecureString' {
            $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureAPIKey)
            try {
                $resolvedKey = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
            }
            finally {
                [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
            }
            Write-Verbose "API key provided as SecureString"
        }

        'PlainText' {
            $resolvedKey = $APIKey
            Write-Verbose "API key provided as plain text"
        }
    }

    # ── Validate the connection ──

    try {
        $headers = @{
            "x-api-key" = $resolvedKey
            "Accept"    = "application/json"
        }
        $response = Invoke-WebRequest -Uri "$Instance/api/packaging/upload/packageTypesMatrix" `
            -Headers $headers -Method GET

        # Verify we got actual JSON back, not the SPA HTML fallback.
        # An invalid/expired API key returns 200 with the Angular index.html.
        $contentType = $response.Headers['Content-Type']
        if ($contentType -and $contentType -match 'text/html') {
            throw "API key authentication failed — server returned HTML instead of JSON. The API key may be invalid or expired."
        }

        Write-Verbose "Successfully connected to $Instance (validated via packageTypesMatrix)"
    }
    catch {
        throw "Failed to connect to '$Instance'. Please verify the instance URL and API key. Error: $($_.Exception.Message)"
    }

    # ── Store connection securely (always as SecureString in memory) ──

    $secureKey = $resolvedKey | ConvertTo-SecureString -AsPlainText -Force

    # Clear the plain text key from memory as soon as possible
    $resolvedKey = $null

    $global:appRConnection = @{
        Instance     = $Instance
        SecureAPIKey = $secureKey
        ConnectedAt  = Get-Date
    }

    Write-Host "Connected to Juriba App Readiness at $Instance" -ForegroundColor Green

    if ($response) {
        Write-Verbose "Auth validation successful (HTTP $($response.StatusCode))"
    }
}
