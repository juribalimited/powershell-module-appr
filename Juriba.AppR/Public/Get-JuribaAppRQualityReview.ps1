function Get-JuribaAppRQualityReview {
    <#
      .SYNOPSIS
      Gets quality review results for an application.
      .DESCRIPTION
      Retrieves quality review (QR) information for a specific application.
      Returns the QR checklist results and status. Can also retrieve
      screenshots associated with the QR process.
      .PARAMETER Instance
      The URL of the App Readiness instance. Not required if connected via Connect-JuribaAppR.
      .PARAMETER APIKey
      The API key for authentication. Not required if connected via Connect-JuribaAppR.
      .PARAMETER AppId
      The unique identifier of the application.
      .PARAMETER PackageType
      The package type to get QR results for (e.g. Msi, Msix, IntuneWin).
      .PARAMETER IncludeScreenshots
      When specified, also retrieves screenshot information from the QR process.
      .EXAMPLE
      Get-JuribaAppRQualityReview -AppId 42
      Returns QR results for application 42.
      .EXAMPLE
      Get-JuribaAppRQualityReview -AppId 42 -PackageType Msi -IncludeScreenshots
      Returns QR results with screenshots for the MSI package of application 42.
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$Instance,

        [Parameter(Mandatory = $false)]
        [string]$APIKey,

        [Parameter(Mandatory = $true)]
        [int]$AppId,

        [Parameter(Mandatory = $false)]
        [string]$PackageType,

        [Parameter(Mandatory = $false)]
        [switch]$IncludeScreenshots
    )

    $conn = Get-JuribaAppRConnection -Instance $Instance -APIKey $APIKey

    # Get the QR status
    $qrResult = Invoke-JuribaAppRRestMethod -Instance $conn.Instance -APIKey $conn.APIKey `
        -Uri "api/apm/qualityReview/inQr/$AppId" -Method GET

    # If screenshots requested and package type specified
    if ($IncludeScreenshots -and $PackageType) {
        $screenshots = Invoke-JuribaAppRRestMethod -Instance $conn.Instance -APIKey $conn.APIKey `
            -Uri "api/apm/qualityReview/pictures/$AppId/$PackageType/screenshots" -Method GET

        # Add screenshots to result
        $qrResult | Add-Member -NotePropertyName 'Screenshots' -NotePropertyValue $screenshots -PassThru
    }
    else {
        $qrResult
    }
}
