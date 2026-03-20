function Watch-JuribaAppRApplicationStatus {
    <#
      .SYNOPSIS
      Polls the full workflow status of an application until it reaches a target state or times out.
      .DESCRIPTION
      Monitors an application's progress through the App Readiness workflow by polling
      the full tracker at a defined interval. Can watch for specific stages to complete
      (packaging, testing, publishing) or just report status changes.

      Use this after the application has been created and is processing through the
      packaging, testing, and publishing pipeline.
      .PARAMETER Instance
      The URL of the App Readiness instance. Not required if connected via Connect-JuribaAppR.
      .PARAMETER APIKey
      The API key for authentication. Not required if connected via Connect-JuribaAppR.
      .PARAMETER AppId
      The application ID to monitor.
      .PARAMETER IntervalSeconds
      The number of seconds between status checks. Default is 300 (5 minutes).
      .PARAMETER TimeoutMinutes
      Maximum minutes to poll before giving up. Default is 240 (4 hours).
      .PARAMETER Quiet
      When specified, suppresses progress output. Only returns the final status object.
      .EXAMPLE
      Watch-JuribaAppRApplicationStatus -AppId 42
      Polls application 42 every 5 minutes until the workflow completes or 4 hours elapse.
      .EXAMPLE
      Watch-JuribaAppRApplicationStatus -AppId 42 -IntervalSeconds 60 -TimeoutMinutes 60
      Polls every 60 seconds with a 1-hour timeout.
      .EXAMPLE
      $upload = Send-JuribaAppRSetupFile -FilePath "C:\Installers\App.exe"
      $app = New-JuribaAppRApplication -Uuid $upload.Uuid -FileName $upload.FileName -RunImmediately
      $created = Watch-JuribaAppRApplicationCreation -UploadId $upload.Uuid
      $final = Watch-JuribaAppRApplicationStatus -AppId $created.applicationId
      Full pipeline: upload, create, wait for creation, then watch workflow to completion.
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
        [ValidateRange(10, 3600)]
        [int]$IntervalSeconds = 300,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 1440)]
        [int]$TimeoutMinutes = 240,

        [Parameter(Mandatory = $false)]
        [switch]$Quiet
    )

    $conn = Get-JuribaAppRConnection -Instance $Instance -APIKey $APIKey

    $startTime = Get-Date
    $timeoutTime = $startTime.AddMinutes($TimeoutMinutes)
    $pollCount = 0
    $previousStatus = $null

    if (-not $Quiet) {
        Write-Host "Watching application $AppId workflow status" -ForegroundColor Cyan
        Write-Host "Polling every $IntervalSeconds seconds (timeout: $TimeoutMinutes minutes)" -ForegroundColor Cyan
    }

    while ((Get-Date) -lt $timeoutTime) {
        $pollCount++
        $elapsed = [Math]::Round(((Get-Date) - $startTime).TotalMinutes, 1)
        $timestamp = (Get-Date).ToString('HH:mm:ss')

        # Get the full tracker
        try {
            $tracker = Invoke-JuribaAppRRestMethod -Instance $conn.Instance -APIKey $conn.APIKey `
                -Uri "api/apm/application/$AppId/tracker/full" -Method GET
        }
        catch {
            if (-not $Quiet) {
                Write-Warning "[$timestamp] Poll #$pollCount: Failed to get tracker - $($_.Exception.Message)"
            }
            Start-Sleep -Seconds $IntervalSeconds
            continue
        }

        $currentStatus = $tracker | ConvertTo-Json -Compress -Depth 5

        # Only log when status changes (or first poll)
        if ($currentStatus -ne $previousStatus) {
            if (-not $Quiet) {
                Write-Host "[$timestamp] Poll #$pollCount ($elapsed min): Status changed" -ForegroundColor Yellow
                Write-Host ($tracker | ConvertTo-Json -Depth 3) -ForegroundColor Gray
            }
            $previousStatus = $currentStatus
        }
        else {
            if (-not $Quiet) {
                Write-Host "[$timestamp] Poll #$pollCount ($elapsed min): No change" -ForegroundColor DarkGray
            }
        }

        # Write progress
        if (-not $Quiet) {
            Write-Progress -Activity "Watching application $AppId" `
                -Status "Poll #$pollCount - Elapsed: $elapsed min" `
                -PercentComplete ([Math]::Min(($elapsed / $TimeoutMinutes) * 100, 99))
        }

        Start-Sleep -Seconds $IntervalSeconds
    }

    # Timeout
    if (-not $Quiet) {
        Write-Progress -Activity "Watching application $AppId" -Completed
        Write-Warning "Timeout reached after $TimeoutMinutes minutes ($pollCount polls)."
        Write-Warning "Check manually: Get-JuribaAppRApplicationStatus -AppId $AppId"
    }

    # Return the last known tracker state
    return [PSCustomObject]@{
        Status    = 'Timeout'
        AppId     = $AppId
        Elapsed   = "$TimeoutMinutes minutes"
        PollCount = $pollCount
        LastTracker = $tracker
    }
}
