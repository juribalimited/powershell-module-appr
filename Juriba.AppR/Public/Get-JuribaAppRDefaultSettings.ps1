function Get-JuribaAppRDefaultSettings {
    <#
      .SYNOPSIS
      Gets the default settings for the App Readiness instance.
      .DESCRIPTION
      Retrieves default settings including VM group assignments, output package
      formats, and other configuration. These settings determine which VM groups
      are used for repackaging, testing, and UAT, and which output formats
      (MSI, IntuneWin, PSADT, etc.) are enabled.
      .PARAMETER Instance
      The URL of the App Readiness instance. Not required if connected via Connect-JuribaAppR.
      .PARAMETER APIKey
      The API key for authentication. Not required if connected via Connect-JuribaAppR.
      .EXAMPLE
      $settings = Get-JuribaAppRDefaultSettings
      Returns all default settings as an array of setting objects.
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$Instance,

        [Parameter(Mandatory = $false)]
        [string]$APIKey
    )

    $conn = Get-JuribaAppRConnection -Instance $Instance -APIKey $APIKey

    $raw = Invoke-JuribaAppRRestMethod -Instance $conn.Instance -APIKey $conn.APIKey `
        -Uri "api/default-settings" -Method GET

    # Parse into a friendly hashtable
    # Known defaultSettingType mappings:
    #   1=MSI, 2=AppV, 3=MSIX, 4=MSIXAppAttach, 5=IntuneWin, 6=PSADT
    #   7=? (value=1), 8=? (value=true)
    #   11=vmGroupForRepackaging, 12=vmGroupForTesting, 13=vmGroupForUAT
    $result = @{
        Raw                    = $raw
        VMGroupForRepackaging  = $null
        VMGroupForTesting      = $null
        VMGroupForUAT          = $null
        OutputFormats          = @{}
        OutputFormatBitmask    = 0
    }

    # Package type bitmask values (matching the server's TypeOfPackage enum)
    $formatBits = @{
        1 = @{ Name = 'MSI';            Bit = 1 }
        2 = @{ Name = 'AppV';           Bit = 2 }
        3 = @{ Name = 'MSIX';           Bit = 4 }
        4 = @{ Name = 'MSIXAppAttach';  Bit = 8 }
        5 = @{ Name = 'IntuneWin';      Bit = 32 }
        6 = @{ Name = 'PSADT';          Bit = 128 }
    }

    foreach ($setting in $raw) {
        switch ($setting.defaultSettingType) {
            11 { $result.VMGroupForRepackaging = [int]$setting.value }
            12 { $result.VMGroupForTesting     = [int]$setting.value }
            13 { $result.VMGroupForUAT         = [int]$setting.value }
            default {
                if ($formatBits.ContainsKey($setting.defaultSettingType)) {
                    $fmt = $formatBits[$setting.defaultSettingType]
                    $enabled = $setting.value -eq 'true'
                    $result.OutputFormats[$fmt.Name] = $enabled
                    if ($enabled) {
                        $result.OutputFormatBitmask = $result.OutputFormatBitmask -bor $fmt.Bit
                    }
                }
            }
        }
    }

    [PSCustomObject]$result
}
