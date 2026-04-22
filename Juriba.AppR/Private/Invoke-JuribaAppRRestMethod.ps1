function Invoke-JuribaAppRRestMethod {
    <#
      .SYNOPSIS
      Internal helper that wraps Invoke-RestMethod with standard AppR authentication and error handling.
      .DESCRIPTION
      Constructs the full URI, adds the x-api-key header, and invokes the REST method.
      Supports all HTTP methods and handles common error patterns consistently.
      This function is not exported and is used internally by public cmdlets.
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Instance,

        [Parameter(Mandatory = $true)]
        [string]$APIKey,

        [Parameter(Mandatory = $true)]
        [string]$Uri,

        [Parameter(Mandatory = $false)]
        [ValidateSet('GET', 'POST', 'PUT', 'PATCH', 'DELETE')]
        [string]$Method = 'GET',

        [Parameter(Mandatory = $false)]
        [object]$Body,

        [Parameter(Mandatory = $false)]
        [string]$ContentType = 'application/json',

        [Parameter(Mandatory = $false)]
        [string]$OutFile
    )

    # Build full URI
    $fullUri = "{0}/{1}" -f $Instance.TrimEnd('/'), $Uri.TrimStart('/')

    # Build headers — Accept: application/json is critical; without it many
    # endpoints return the SPA HTML instead of JSON data.
    $headers = @{
        "x-api-key" = $APIKey
        "Accept"    = "application/json"
    }

    # Build splat for Invoke-RestMethod
    $splat = @{
        Uri         = $fullUri
        Method      = $Method
        Headers     = $headers
        ContentType = $ContentType
    }

    if ($Body) {
        if ($Body -is [string]) {
            $splat['Body'] = $Body
        }
        else {
            $splat['Body'] = $Body | ConvertTo-Json -Depth 10
        }
        Write-Verbose "Request body: $($splat['Body'])"
    }

    if ($OutFile) {
        $splat['OutFile'] = $OutFile
    }

    Write-Verbose "$Method $fullUri"

    try {
        $response = Invoke-RestMethod @splat
        return $response
    }
    catch {
        $statusCode = $null
        $errorMessage = $_.Exception.Message
        $errorBody = $null

        # PowerShell 7: ErrorDetails.Message contains the response body
        if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
            $errorBody = $_.ErrorDetails.Message
        }

        if ($_.Exception.Response) {
            $statusCode = [int]$_.Exception.Response.StatusCode

            # PowerShell 5.1 fallback: read from response stream
            if (-not $errorBody) {
                try {
                    $errorStream = $_.Exception.Response.GetResponseStream()
                    $reader = New-Object System.IO.StreamReader($errorStream)
                    $errorBody = $reader.ReadToEnd()
                    $reader.Close()
                }
                catch {
                    Write-Verbose "Could not read error body from response stream: $($_.Exception.Message)"
                }
            }
        }

        if ($errorBody) {
            $errorMessage = "{0} - {1}" -f $errorMessage, $errorBody
        }

        Write-Verbose "API Error [$statusCode]: $errorMessage"

        # Use throw (not Write-Error) so callers always see a terminating error
        switch ($statusCode) {
            401 { throw "Authentication failed. Please check your API key. $errorMessage" }
            403 { throw "Access denied. You do not have permission for this operation. $errorMessage" }
            404 { throw "Resource not found. $errorMessage" }
            default { throw "API request failed: $errorMessage" }
        }
    }
}
