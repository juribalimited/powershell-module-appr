function Get-JuribaAppRDefaultSetting {
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
      $settings = Get-JuribaAppRDefaultSetting
      Returns all default settings as an array of setting objects.
    #>

    [CmdletBinding()]
    [Alias('Get-JuribaAppRDefaultSettings')]
    param (
        [Parameter(Mandatory = $false)]
        [string]$Instance,

        [Parameter(Mandatory = $false)]
        [string]$APIKey
    )

    $conn = Get-JuribaAppRConnection -Instance $Instance -APIKey $APIKey

    $raw = Invoke-JuribaAppRRestMethod -Instance $conn.Instance -APIKey $conn.APIKey `
        -Uri "api/default-settings" -Method GET

    # Dump all raw settings for diagnostics
    Write-Verbose "Raw default settings ($($raw.Count) entries):"
    foreach ($s in $raw) {
        Write-Verbose "  id=$($s.defaultSettingId) type=$($s.defaultSettingType) value='$($s.value)'"
    }

    # Parse into a friendly hashtable
    # Known defaultSettingType mappings (from demo HAR):
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
        # Cast to [int] — JSON parser returns [long] but hashtable keys are [int]
        $settingType = [int]$setting.defaultSettingType
        switch ($settingType) {
            11 { $result.VMGroupForRepackaging = [int]$setting.value }
            12 { $result.VMGroupForTesting     = [int]$setting.value }
            13 { $result.VMGroupForUAT         = [int]$setting.value }
            default {
                if ($formatBits.ContainsKey($settingType)) {
                    $fmt = $formatBits[$settingType]
                    $enabled = $setting.value -eq 'true'
                    $result.OutputFormats[$fmt.Name] = $enabled
                    Write-Verbose "  Format: $($fmt.Name) (type=$settingType, bit=$($fmt.Bit)) = $enabled"
                    if ($enabled) {
                        $result.OutputFormatBitmask = $result.OutputFormatBitmask -bor $fmt.Bit
                    }
                }
                else {
                    Write-Verbose "  Unknown setting type $settingType = '$($setting.value)'"
                }
            }
        }
    }

    Write-Verbose "Resolved: VMGroup=$($result.VMGroupForRepackaging), TestGroup=$($result.VMGroupForTesting), UAT=$($result.VMGroupForUAT), Bitmask=$($result.OutputFormatBitmask)"

    if ($result.OutputFormatBitmask -eq 0) {
        Write-Warning "No output formats are enabled in Default Settings. The packaging job may fail. Check Default Settings in the UI."
    }

    [PSCustomObject]$result
}
