function Start-JuribaAppRMECMScan {
    <#
      .SYNOPSIS
      Triggers a scan on an MECM/SCCM (or other integration) provider so newly-created CM applications appear in the scan list.
      .DESCRIPTION
      Wraps POST /api/integration/{providerId}/scan, the same call the AppR
      admin UI's "Start scan" button on the Scan & Import page makes. The
      server queues the scan, returns 200 OK immediately, and runs the work
      asynchronously. Track completion with Get-JuribaAppRMECMScanList (rows
      with a recent createdAt timestamp appear as the scan progresses) or
      via the AppR UI's progress banner.

      Useful in two scenarios:

        - A CM application was created in MECM after the connector's last
          scheduled scan; Get-JuribaAppRMECMScanList won't surface it until
          the next scan runs. Trigger one now to skip the wait.
        - End-to-end automation (create CM app -> import to AppR -> smoke
          test) where the autoscheduler's cadence is too slow.

      The request body is an empty JSON object; the scope of the scan is
      determined by the provider configuration on the server, not by the
      caller.
      .PARAMETER Instance
      The URL of the App Readiness instance. Not required if connected via Connect-JuribaAppR.
      .PARAMETER APIKey
      The API key for authentication. Not required if connected via Connect-JuribaAppR.
      .PARAMETER ProviderId
      The integration provider id (Get-JuribaAppRMECMProvider | Select id)
      to scan. Accepts pipeline input by property name, so a provider object
      can be piped directly.
      .EXAMPLE
      Start-JuribaAppRMECMScan -ProviderId 7
      Starts a scan on provider 7. Returns immediately; the scan continues
      in the background on the server.
      .EXAMPLE
      Get-JuribaAppRMECMProvider |
          Where-Object { $_.integrationType -eq 1 -and $_.isImportEnabled } |
          Start-JuribaAppRMECMScan
      Pipes every MECM provider with import enabled into the scan trigger.
      .EXAMPLE
      Start-JuribaAppRMECMScan -ProviderId 7
      Start-Sleep -Seconds 60
      Get-JuribaAppRMECMScanList -ProviderId 7 |
          Where-Object { $_.applicationName -ieq 'Notepad++' -and $_.status -eq 1 } |
          Start-JuribaAppRMECMImport
      The end-to-end "scan then import a newly-created CM app" recipe.
    #>

    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory = $false)]
        [string]$Instance,

        [Parameter(Mandatory = $false)]
        [string]$APIKey,

        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('id')]
        [int]$ProviderId
    )

    process {
        $conn = Get-JuribaAppRConnection -Instance $Instance -APIKey $APIKey

        if ($PSCmdlet.ShouldProcess("provider id=$ProviderId", 'Start MECM scan')) {
            Invoke-JuribaAppRRestMethod -Instance $conn.Instance -APIKey $conn.APIKey `
                -Uri "api/integration/$ProviderId/scan" -Method POST -Body @{}
        }
    }
}
