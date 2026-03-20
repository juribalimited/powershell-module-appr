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

        if ($_.Exception.Response) {
            $statusCode = [int]$_.Exception.Response.StatusCode

            try {
                $errorStream = $_.Exception.Response.GetResponseStream()
                $reader = New-Object System.IO.StreamReader($errorStream)
                $errorBody = $reader.ReadToEnd()
                $reader.Close()

                if ($errorBody) {
                    $errorMessage = "{0} - {1}" -f $errorMessage, $errorBody
                }
            }
            catch {
                # Could not read error body, use original message
            }
        }

        switch ($statusCode) {
            401 { Write-Error "Authentication failed. Please check your API key. $errorMessage" }
            403 { Write-Error "Access denied. You do not have permission for this operation. $errorMessage" }
            404 { Write-Error "Resource not found. $errorMessage" }
            default { Write-Error "API request failed: $errorMessage" }
        }
    }
}
