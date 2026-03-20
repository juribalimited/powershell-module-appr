function Get-JuribaAppRGenericIntegrationSource {
    <#
      .SYNOPSIS
      Downloads the package source for a publishing in a generic integration.
      .DESCRIPTION
      Downloads the publishing package source file chosen for a specific generic
      integration. The file is saved to the specified output path.

      This is a refactored version of the original Get-PublishingSource cmdlet.
      .PARAMETER Instance
      The URL of the App Readiness instance. Not required if connected via Connect-JuribaAppR.
      .PARAMETER APIKey
      The API key for authentication. Not required if connected via Connect-JuribaAppR.
      .PARAMETER IntegrationId
      The unique identifier of the generic integration.
      .PARAMETER PublishingId
      The unique identifier of the publishing record.
      .PARAMETER SourcePath
      The local directory path where the downloaded source file will be saved.
      .EXAMPLE
      Get-JuribaAppRGenericIntegrationSource -IntegrationId 1 -PublishingId 2 -SourcePath "C:\Packages"
      Downloads the source package for publishing 2 from integration 1 to C:\Packages.
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$Instance,

        [Parameter(Mandatory = $false)]
        [string]$APIKey,

        [Parameter(Mandatory = $true)]
        [int]$IntegrationId,

        [Parameter(Mandatory = $true)]
        [int]$PublishingId,

        [Parameter(Mandatory = $true)]
        [string]$SourcePath
    )

    $conn = Get-JuribaAppRConnection -Instance $Instance -APIKey $APIKey

    $TempName = New-Guid
    $OutFile = Join-Path $SourcePath -ChildPath $TempName

    $fullUri = "{0}/api/v1/integration/generic/{1}/published-app/{2}/source" -f $conn.Instance, $IntegrationId, $PublishingId

    $headers = @{ "x-api-key" = $conn.APIKey }

    try {
        $Source = Invoke-WebRequest -Uri $fullUri -Headers $headers -OutFile $OutFile -PassThru
        $Content = [System.Net.Mime.ContentDisposition]::new($Source.Headers['Content-Disposition'])
        $FinalPath = $OutFile.Replace($TempName, $Content.FileName)
        Rename-Item $OutFile $FinalPath
        Write-Verbose "Downloaded source to: $FinalPath"
        $Content.FileName
    }
    catch {
        if (Test-Path $OutFile) { Remove-Item $OutFile -ErrorAction SilentlyContinue }
        Write-Error "Failed to download source: $($_.Exception.Message)"
    }
}
