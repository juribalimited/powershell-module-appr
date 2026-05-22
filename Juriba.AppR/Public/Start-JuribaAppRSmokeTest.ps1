function Start-JuribaAppRSmokeTest {
    <#
      .SYNOPSIS
      Initiates a smoke test for a specific application.
      .DESCRIPTION
      Starts an automated smoke test for the specified application and package type.
      Can target a specific VM group or use the default. For single application
      testing, provide the AppId and PackageType. For manual test runs that
      require a specific VM, also provide VMGroupId.
      .PARAMETER Instance
      The URL of the App Readiness instance. Not required if connected via Connect-JuribaAppR.
      .PARAMETER APIKey
      The API key for authentication. Not required if connected via Connect-JuribaAppR.
      .PARAMETER AppId
      The unique identifier of the application to test.
      .PARAMETER PackageType
      The package type to test. AppR recognizes the string names of the
      standard formats (Msi, Msix, IntuneWin, AppV, Psadt, AppAttach)
      via a server-side name-to-enum lookup. For values outside that set
      — most notably 'nonStd', which AppR uses for packages that don't
      fit the standard formats (commonly PSADT wrappers on older AppR /
      AppM builds before PSADT-specific detection was fully exposed) —
      pass either the string 'nonStd' (the cmdlet maps it to its integer
      enum value 10 before sending) or the integer directly. PowerShell
      coerces integers to strings on parameter binding, so any future
      enum value not in the map can be sent verbatim as an int.
      .PARAMETER VMGroupId
      Optional. The VM group (pool) to run the test on. If not specified,
      runs as a single test using the default environment.
      .EXAMPLE
      Start-JuribaAppRSmokeTest -AppId 42 -PackageType Msi
      Starts a smoke test of the MSI package for application 42.
      .EXAMPLE
      Start-JuribaAppRSmokeTest -AppId 42 -PackageType IntuneWin -VMGroupId 1
      Starts a smoke test on VM group 1 for the IntuneWin package of application 42.
      .EXAMPLE
      Start-JuribaAppRSmokeTest -AppId 3592 -PackageType nonStd -VMGroupId 17
      Starts a smoke test on VM group 17 for a non-standard package (e.g. a PSADT wrapper on a build where AppR classifies it as 'nonStd' rather than 'psadt'). The cmdlet sends the integer enum value 10 under the hood.
      .EXAMPLE
      Start-JuribaAppRSmokeTest -AppId 3592 -PackageType 10 -VMGroupId 17
      Same call by integer. Useful when a server-side enum value isn't in the cmdlet's name-to-int map yet.
    #>

    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory = $false)]
        [string]$Instance,

        [Parameter(Mandatory = $false)]
        [string]$APIKey,

        [Parameter(Mandatory = $true)]
        [int]$AppId,

        [Parameter(Mandatory = $true)]
        [string]$PackageType,

        [Parameter(Mandatory = $false)]
        [int]$VMGroupId
    )

    $conn = Get-JuribaAppRConnection -Instance $Instance -APIKey $APIKey

    # Standard package-type names resolve server-side via a name-to-enum
    # lookup. Names outside that set (notably 'nonStd' for non-standard /
    # PSADT-wrapper packages on builds where PSADT-specific detection
    # wasn't yet exposed) don't have a string-name entry on the server,
    # so the request resolves to a non-existent type and the server
    # returns a 400 'CantFindTheAppInformation'. Map those to their
    # integer enum value before sending. Values not in the map fall
    # through unchanged — callers can pass any future enum value as an
    # integer; PowerShell coerces it to a string on parameter binding.
    $packageTypeForUri = switch -CaseSensitive ($PackageType) {
        'nonStd' { '10' }
        default  { $PackageType }
    }

    $Target = "App $AppId ($PackageType)"

    if ($PSCmdlet.ShouldProcess($Target, "Start smoke test")) {
        if ($VMGroupId) {
            $uri = "api/ace/testing/manualTest/$AppId/$VMGroupId/$packageTypeForUri"
            Invoke-JuribaAppRRestMethod -Instance $conn.Instance -APIKey $conn.APIKey `
                -Uri $uri -Method PUT
        }
        else {
            $uri = "api/ace/testing/singleTest/$AppId/$packageTypeForUri"
            Invoke-JuribaAppRRestMethod -Instance $conn.Instance -APIKey $conn.APIKey `
                -Uri $uri -Method POST
        }
    }
}
