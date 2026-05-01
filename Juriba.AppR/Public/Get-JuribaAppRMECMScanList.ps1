function Get-JuribaAppRMECMScanList {
    <#
      .SYNOPSIS
      Lists applications discovered by an MECM/SCCM (or other integration) scan and surfaces the fields needed to import them.
      .DESCRIPTION
      Wraps GET /api/integration/{providerId}/scan/list — the discovered-
      applications table the AppR UI's "Scan Import" page is built on.
      Each row carries:

        - id                      — AppR-side numeric id (used by the UI's
                                    selection state, NOT by the import body)
        - originalApplicationId   — CM-side identifier (this is the field
                                    the import body wants — see
                                    Start-JuribaAppRMECMImport)
        - model                   — integer enum mirrored verbatim into the
                                    import body (typically 0 for an MECM
                                    Application record)
        - applicationName / manufacturer / version — display fields
        - status                  — discovery status enum; UI excludes
                                    statuses 2, 4 and 5 from the selection
                                    set ("already imported" / "in progress"
                                    style states)

      Use the output to find a specific CM application, then pipe (or pass
      via -InputObject) to Start-JuribaAppRMECMImport, which extracts
      originalApplicationId + model into the API's filteringObjects body.
      .PARAMETER Instance
      The URL of the App Readiness instance. Not required if connected via Connect-JuribaAppR.
      .PARAMETER APIKey
      The API key for authentication. Not required if connected via Connect-JuribaAppR.
      .PARAMETER ProviderId
      The integration provider id (Get-JuribaAppRMECMProvider | Select id)
      whose scan results to read.
      .EXAMPLE
      Get-JuribaAppRMECMScanList -ProviderId 7
      Returns every discovered application for provider 7.
      .EXAMPLE
      Get-JuribaAppRMECMScanList -ProviderId 7 |
          Where-Object { $_.applicationName -eq 'Notepad++' -and $_.status -ne 2 } |
          Start-JuribaAppRMECMImport
      Filters to a single un-imported CM application and pipes it into the
      import cmdlet.
    #>

    [CmdletBinding()]
    [OutputType([object[]])]
    param (
        [Parameter(Mandatory = $false)]
        [string]$Instance,

        [Parameter(Mandatory = $false)]
        [string]$APIKey,

        [Parameter(Mandatory = $true)]
        [int]$ProviderId
    )

    $conn = Get-JuribaAppRConnection -Instance $Instance -APIKey $APIKey

    Invoke-JuribaAppRRestMethod -Instance $conn.Instance -APIKey $conn.APIKey `
        -Uri "api/integration/$ProviderId/scan/list" -Method GET
}
