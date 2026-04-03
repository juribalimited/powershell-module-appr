function Search-JuribaAppRKnowledgeBase {
    <#
      .SYNOPSIS
      Searches the Juriba Knowledge Base for applications.
      .DESCRIPTION
      Searches the Juriba KB for known applications by name. This can be used
      to find applications before adding them to App Readiness, potentially
      avoiding the need to upload an installation file manually. When an
      application is found in the KB, its setup file can be automatically
      downloaded.

      Supports two API backends:
        - Instance-proxied (v5.2): calls the AppR instance's api/kb/ endpoints
        - UDA direct (v6.0+): calls the UDA API directly at uda.api.juriba.app

      By default, tries the instance-proxied endpoint first. If it fails
      (e.g. v6.0 RC returns 500), falls back to the UDA API automatically.
      Use -UseUDA to call the UDA API directly.
      .PARAMETER Instance
      The URL of the App Readiness instance. Not required if connected via Connect-JuribaAppR.
      .PARAMETER APIKey
      The API key for authentication. Not required if connected via Connect-JuribaAppR.
      .PARAMETER Search
      The search term to use when querying the Knowledge Base.
      .PARAMETER ApplicationId
      Optional. The KB application ID to get version/source details for.
      .PARAMETER UseUDA
      When specified, calls the UDA API directly (uda.api.juriba.app) instead
      of the instance-proxied endpoint. Required for v6.0+ until the instance
      proxy is fixed.
      .PARAMETER UDAKey
      Optional. A separate API key for the UDA service. If not specified, uses
      the same API key as the AppR connection.
      .PARAMETER UDAHost
      Optional. Override the UDA API host. Defaults to "https://uda.api.juriba.app".
      .PARAMETER Limit
      Optional. Maximum number of results to return (UDA v2 only). Default: 25.
      .EXAMPLE
      Search-JuribaAppRKnowledgeBase -Search "Firefox"
      Searches the Juriba KB for applications matching "Firefox".
      .EXAMPLE
      Search-JuribaAppRKnowledgeBase -Search "Chrome" -UseUDA
      Searches using the UDA v2 API directly.
      .EXAMPLE
      Search-JuribaAppRKnowledgeBase -ApplicationId "b5108d80-8ee5-47be-b007-7f12451f0806" -UseUDA
      Returns version and source details for a KB application via UDA.
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$Instance,

        [Parameter(Mandatory = $false)]
        [string]$APIKey,

        [Parameter(Mandatory = $true, ParameterSetName = 'Search')]
        [string]$Search,

        [Parameter(Mandatory = $true, ParameterSetName = 'ById')]
        [string]$ApplicationId,

        [Parameter(Mandatory = $false)]
        [switch]$UseUDA,

        [Parameter(Mandatory = $false)]
        [string]$UDAKey,

        [Parameter(Mandatory = $false)]
        [string]$UDAHost = "https://uda.api.juriba.app",

        [Parameter(Mandatory = $false)]
        [int]$Limit = 25
    )

    $conn = Get-JuribaAppRConnection -Instance $Instance -APIKey $APIKey
    $udaApiKey = if ($UDAKey) { $UDAKey } else { $conn.APIKey }

    # UDA direct path
    if ($UseUDA) {
        return Invoke-UDARequest -UDAHost $UDAHost -APIKey $udaApiKey `
            -Search $Search -ApplicationId $ApplicationId -Limit $Limit
    }

    # Try instance-proxied first, fall back to UDA on failure
    try {
        if ($ApplicationId) {
            $uri = "api/kb/application/$ApplicationId/version/sources"
        }
        else {
            $uri = "api/kb/application?search={0}" -f [System.Uri]::EscapeDataString($Search)
        }

        Invoke-JuribaAppRRestMethod -Instance $conn.Instance -APIKey $conn.APIKey `
            -Uri $uri -Method GET
    }
    catch {
        Write-Warning "Instance KB endpoint failed ($($_.Exception.Message)). Falling back to UDA API..."
        Invoke-UDARequest -UDAHost $UDAHost -APIKey $udaApiKey `
            -Search $Search -ApplicationId $ApplicationId -Limit $Limit
    }
}

function Invoke-UDARequest {
    [CmdletBinding()]
    param (
        [string]$UDAHost,
        [string]$APIKey,
        [string]$Search,
        [string]$ApplicationId,
        [int]$Limit
    )

    $headers = @{ "X-API-KEY" = $APIKey }
    $UDAHost = $UDAHost.TrimEnd('/')

    if ($ApplicationId) {
        $uri = "$UDAHost/v1/application/$ApplicationId/version/sources"
    }
    else {
        $encodedSearch = [System.Uri]::EscapeDataString($Search)
        $uri = "$UDAHost/v2/application?search=$encodedSearch&limit=$Limit"
    }

    $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method GET
    $response
}
