function Connect-JuribaAppR {
    <#
      .SYNOPSIS
      Establishes a connection to a Juriba App Readiness instance.
      .DESCRIPTION
      Creates a persistent connection to Juriba App Readiness by storing the instance URL
      and API key securely in a global variable. Once connected, subsequent cmdlets can
      use the stored credentials without requiring -Instance and -APIKey parameters.
      .PARAMETER Instance
      The full URL of the Juriba App Readiness instance (e.g. https://appr.example.com).
      .PARAMETER APIKey
      The API key for authenticating to the App Readiness instance.
      Can be obtained from your user profile in the App Readiness web interface.
      .EXAMPLE
      Connect-JuribaAppR -Instance "https://appr.example.com" -APIKey "your-api-key-here"
      Establishes a connection to the specified App Readiness instance.
      .EXAMPLE
      $key = Get-Secret -Name "AppR-APIKey" -AsPlainText
      Connect-JuribaAppR -Instance "https://appr.example.com" -APIKey $key
      Connects using an API key stored in the PowerShell SecretManagement vault.
    #>

    [CmdletBinding()]
    [Alias("Connect-AppR")]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Instance,

        [Parameter(Mandatory = $true)]
        [string]$APIKey
    )

    $Instance = $Instance.TrimEnd('/')

    # Validate connection by calling the whoami endpoint (reliable with API key auth)
    # Use Invoke-WebRequest with -SessionVariable to capture session cookies.
    # Some endpoints (e.g. uploadChunk) require cookie auth even when x-api-key
    # was used for the initial request, so we preserve the session for later use.
    try {
        $headers = @{
            "x-api-key" = $APIKey
            "Accept"    = "application/json"
        }
        $response = Invoke-WebRequest -Uri "$Instance/api/user/whoami" -Headers $headers `
            -Method GET -SessionVariable 'appRSession'

        # Verify we got actual JSON back, not the SPA HTML fallback.
        # An invalid/expired API key returns 200 with the Angular index.html.
        $contentType = $response.Headers['Content-Type']
        if ($contentType -and $contentType -match 'text/html') {
            throw "API key authentication failed — server returned HTML instead of JSON. The API key may be invalid or expired."
        }

        Write-Verbose "Successfully connected to $Instance"
    }
    catch {
        throw "Failed to connect to '$Instance'. Please verify the instance URL and API key. Error: $($_.Exception.Message)"
    }

    # Store connection securely — include the WebSession for cookie-based endpoints
    $secureAPIKey = $APIKey | ConvertTo-SecureString -AsPlainText -Force

    $global:appRConnection = @{
        Instance     = $Instance
        SecureAPIKey = $secureAPIKey
        WebSession   = $appRSession
        ConnectedAt  = Get-Date
    }

    Write-Host "Connected to Juriba App Readiness at $Instance" -ForegroundColor Green

    # Log response details if verbose
    if ($response) {
        Write-Verbose "Auth validation successful (HTTP $($response.StatusCode))"
    }
}
