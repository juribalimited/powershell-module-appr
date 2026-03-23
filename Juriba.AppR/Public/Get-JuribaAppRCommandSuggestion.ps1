function Get-JuribaAppRCommandSuggestion {
    <#
      .SYNOPSIS
      Gets suggested install/uninstall command lines for an uploaded setup file.
      .DESCRIPTION
      Calls the server's command suggestion engine which uses hash matching,
      naming conventions, and AI-based detection to suggest the best install
      and uninstall command lines for a given setup file.
      .PARAMETER Instance
      The URL of the App Readiness instance. Not required if connected via Connect-JuribaAppR.
      .PARAMETER APIKey
      The API key for authentication. Not required if connected via Connect-JuribaAppR.
      .PARAMETER UploadId
      The UUID of the uploaded file.
      .PARAMETER FileName
      The file name of the uploaded setup file.
      .PARAMETER Name
      The application name.
      .PARAMETER Manufacturer
      The application manufacturer.
      .PARAMETER Version
      The application version.
      .EXAMPLE
      $cmds = Get-JuribaAppRCommandSuggestion -UploadId $upload.Uuid -FileName $upload.FileName `
          -Name "7-Zip" -Manufacturer "Igor Pavlov" -Version "24.07"
      Returns suggested install and uninstall command lines.
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$Instance,

        [Parameter(Mandatory = $false)]
        [string]$APIKey,

        [Parameter(Mandatory = $true)]
        [string]$UploadId,

        [Parameter(Mandatory = $true)]
        [string]$FileName,

        [Parameter(Mandatory = $false)]
        [string]$Name,

        [Parameter(Mandatory = $false)]
        [string]$Manufacturer,

        [Parameter(Mandatory = $false)]
        [string]$Version
    )

    $conn = Get-JuribaAppRConnection -Instance $Instance -APIKey $APIKey

    $body = @{
        uid                     = $UploadId
        filename                = $FileName
        applicationName         = $Name
        applicationManufacture  = $Manufacturer   # Note: server uses "Manufacture" not "Manufacturer"
        applicationVersion      = $Version
        packageType             = 10
        appId                   = 0
        sendUda                 = $true
    }

    Invoke-JuribaAppRRestMethod -Instance $conn.Instance -APIKey $conn.APIKey `
        -Uri "api/application/temp/commands/suggestion" -Method POST -Body $body
}
