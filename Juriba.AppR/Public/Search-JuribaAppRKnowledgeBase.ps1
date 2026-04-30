function Search-JuribaAppRKnowledgeBase {
    <#
      .SYNOPSIS
      Searches the Juriba Knowledge Base for applications.
      .DESCRIPTION
      Searches the Juriba KB for known applications by name, or returns the
      version/source list for a specific KB application id. Used to find an
      application before adding it to App Readiness, so the installer can
      be downloaded directly instead of uploaded by hand.

      v6 changed the search endpoint contract from a flat `?search=<term>`
      query that returned a flat array to an OData query
      (`?$filter=contains(tolower(applicationName),'<term>')&$top=N`) that
      returns a wrapped `{ paginationMetadata, data: [...] }` envelope.
      This function speaks the v6 contract first and unwraps the `data`
      array transparently. If the v6 call fails (e.g. older v5.x
      instances that still expect `?search=`), it retries against the
      legacy shape so the same client code works against both.

      In v6.0.x there is a known server-side regression where every
      variation of the search endpoint returns HTTP 500 with no body —
      see the JuribaKB ticket on appr-server. When that's hit, the
      verbose-stream messages will say so. Per-app sources
      (`/api/kb/application/{id}/version/sources`) are unaffected.

      The instance's own API key is used throughout — there is no UDA
      fallback by default. `-UseUDA` is kept as an explicit escape
      hatch for users who already have a UDA key, but it is no longer
      reached automatically.
      .PARAMETER Instance
      The URL of the App Readiness instance. Not required if connected via Connect-JuribaAppR.
      .PARAMETER APIKey
      The API key for authentication. Not required if connected via Connect-JuribaAppR.
      .PARAMETER Search
      The search term to use when querying the Knowledge Base.
      .PARAMETER ApplicationId
      Optional. The KB application ID to get version/source details for.
      .PARAMETER Limit
      Optional. Maximum number of results to return. Default: 25. Maps to
      `$top` on v6 and `limit=` on the legacy UDA path.
      .PARAMETER UseUDA
      Optional escape hatch — call the UDA API directly
      (uda.api.juriba.app) instead of the instance-proxied endpoint. Most
      callers should NOT need this; the AppR instance proxies the same
      data. Provide `-UDAKey` if your UDA key differs from your AppR key.
      .PARAMETER UDAKey
      Optional. Separate UDA API key. Only used when `-UseUDA` is set.
      Defaults to the AppR connection key (UDA may reject it).
      .PARAMETER UDAHost
      Optional. Override the UDA API host. Defaults to "https://uda.api.juriba.app".
      .EXAMPLE
      Search-JuribaAppRKnowledgeBase -Search "Firefox"
      Searches the Juriba KB for applications matching "Firefox".
      .EXAMPLE
      Search-JuribaAppRKnowledgeBase -ApplicationId "b5108d80-8ee5-47be-b007-7f12451f0806"
      Returns version/source details for a specific KB application.
    #>

    [CmdletBinding()]
    [OutputType([object[]])]
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
        [int]$Limit = 25,

        [Parameter(Mandatory = $false)]
        [switch]$UseUDA,

        [Parameter(Mandatory = $false)]
        [string]$UDAKey,

        [Parameter(Mandatory = $false)]
        [string]$UDAHost = "https://uda.api.juriba.app"
    )

    $conn = Get-JuribaAppRConnection -Instance $Instance -APIKey $APIKey

    # Explicit UDA opt-in. Not used as a fallback any more — see the
    # description block. Caller must pass `-UseUDA` deliberately.
    if ($UseUDA) {
        $udaApiKey = if ($UDAKey) { $UDAKey } else { $conn.APIKey }
        return Invoke-UDARequest -UDAHost $UDAHost -APIKey $udaApiKey `
            -Search $Search -ApplicationId $ApplicationId -Limit $Limit
    }

    # By-id lookup is the same on v5 and v6 — flat array of source rows
    # (versionId, version, sourceId, packageType, fileName, fileHash,
    # architecture, productName, vendor, sourceVersion, downloadUrl).
    if ($ApplicationId) {
        $uri = "api/kb/application/$ApplicationId/version/sources"
        return Invoke-JuribaAppRRestMethod -Instance $conn.Instance -APIKey $conn.APIKey `
            -Uri $uri -Method GET
    }

    # ── Search ─────────────────────────────────────────────────────────
    # Try the v6 OData contract first. The escape on the search term
    # handles single quotes (OData literal escape: '' for ').
    $needle = ($Search ?? '').ToLower().Replace("'", "''")
    $filter = "contains(tolower(applicationName),'$needle')"
    $v6Query = '$filter={0}&$top={1}' -f `
        [System.Uri]::EscapeDataString($filter), `
        $Limit

    try {
        Write-Verbose "KB search (v6 OData): $v6Query"
        $response = Invoke-JuribaAppRRestMethod -Instance $conn.Instance -APIKey $conn.APIKey `
            -Uri ("api/kb/application?$v6Query") -Method GET

        # Normalise both response shapes into the same flat array of
        # ApplicationSearchResponseProduct items so callers don't have to
        # branch on server version.
        if ($null -eq $response)                              { return @() }
        if ($response -is [array])                            { return $response }       # legacy shape leaked through
        if ($response.PSObject.Properties['data'])            { return @($response.data) } # v6 envelope
        return @($response)
    }
    catch {
        $msg = $_.Exception.Message
        Write-Verbose "v6 OData KB search failed ($msg); retrying with legacy v5 ?search= shape."
        # On v6, the server is documented as OData but currently 500s on
        # every input (open ticket). On v5 the legacy shape works.
        # Re-throw with both attempts in the message so a user hitting
        # the v6 regression sees what's going on.
        try {
            $legacyUri = "api/kb/application?search={0}" -f [System.Uri]::EscapeDataString($Search)
            return Invoke-JuribaAppRRestMethod -Instance $conn.Instance -APIKey $conn.APIKey `
                -Uri $legacyUri -Method GET
        }
        catch {
            $legacyMsg = $_.Exception.Message
            throw "Juriba KB search failed against both v6 OData and legacy ?search= shapes. v6: $msg. legacy: $legacyMsg. If the instance is on v6.0.x, this matches the open server-side regression on /api/kb/application — sister endpoints (/api/kb/application/{id}/version/sources) are unaffected."
        }
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
