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
      .PARAMETER Instance
      The URL of the App Readiness instance. Not required if connected via Connect-JuribaAppR.
      .PARAMETER APIKey
      The API key for authentication. Not required if connected via Connect-JuribaAppR.
      .PARAMETER Search
      The search term to use when querying the Knowledge Base.
      .PARAMETER ApplicationId
      Optional. The KB application ID to get version/source details for.
      .EXAMPLE
      Search-JuribaAppRKnowledgeBase -Search "Firefox"
      Searches the Juriba KB for applications matching "Firefox".
      .EXAMPLE
      Search-JuribaAppRKnowledgeBase -ApplicationId 100
      Returns version and source details for KB application 100.
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
        [string]$ApplicationId
    )

    $conn = Get-JuribaAppRConnection -Instance $Instance -APIKey $APIKey

    if ($ApplicationId) {
        $uri = "api/kb/application/$ApplicationId/version/sources"
    }
    else {
        $uri = "api/kb/application?search={0}" -f [System.Uri]::EscapeDataString($Search)
    }

    Invoke-JuribaAppRRestMethod -Instance $conn.Instance -APIKey $conn.APIKey `
        -Uri $uri -Method GET
}
