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

      Progress is surfaced via Write-Progress, which renders a progress bar in
      interactive hosts and emits a progress record on CI runners. Per-poll detail
      lines are emitted via Write-Verbose (enable with -Verbose).
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
      When specified, suppresses the Write-Progress bar. Only returns the final status object.
      Verbose logging is still controlled independently via -Verbose.
      .EXAMPLE
      Watch-JuribaAppRApplicationStatus -AppId 42
      Polls application 42 every 5 minutes until the workflow completes or 4 hours elapse.
      .EXAMPLE
      Watch-JuribaAppRApplicationStatus -AppId 42 -IntervalSeconds 60 -TimeoutMinutes 60 -Verbose
      Polls every 60 seconds with a 1-hour timeout; emits per-poll detail via Write-Verbose.
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

    $startTime     = Get-Date
    $timeoutTime   = $startTime.AddMinutes($TimeoutMinutes)
    $pollCount     = 0
    $previousStatus = $null
    $activity      = "Watching application $AppId (timeout $TimeoutMinutes min, poll every $IntervalSeconds s)"
    $statusText    = $null
    $progressPct   = 0
    $appDetail     = $null

    Write-Verbose "$activity — started at $startTime"

    # Terminal states — packaging complete or failed
    $terminalStates = @(
        'ReadyForQualityReview', 'QualityReview', 'ReadyForUat', 'Uat',
        'ReadyForPublishing',    'Published',
        'Failed',                'FailedPackaging', 'FailedToPackage', 'Cancelled'
    )

    while ((Get-Date) -lt $timeoutTime) {
        $pollCount++
        $elapsed   = [Math]::Round(((Get-Date) - $startTime).TotalMinutes, 1)
        $timestamp = (Get-Date).ToString('HH:mm:ss')

        # Get app detail — the ext.status field is the authoritative packaging status.
        # The tracker/full endpoint shows "None" even after failures.
        try {
            $appDetail = Invoke-JuribaAppRRestMethod -Instance $conn.Instance -APIKey $conn.APIKey `
                -Uri "api/apm/application/$AppId" -Method GET
        }
        catch {
            Write-Verbose "[$timestamp] Poll #${pollCount}: failed to get app detail — $($_.Exception.Message)"
            Start-Sleep -Seconds $IntervalSeconds
            continue
        }

        $statusText  = $appDetail.ext.status
        $progressPct = $appDetail.ext.progressPercent
        $currentKey  = "$statusText|$progressPct"
        $changed     = $currentKey -ne $previousStatus
        $previousStatus = $currentKey

        # Emit per-poll detail via Write-Verbose (enable with -Verbose)
        $delta = if ($changed) { 'changed' } else { 'no change' }
        Write-Verbose "[$timestamp] Poll #$pollCount ($elapsed min): $statusText ($progressPct%) — $delta"

        # Check for terminal state
        if ($statusText -and $terminalStates -contains $statusText) {
            if (-not $Quiet) {
                Write-Progress -Activity $activity -Completed
            }
            Write-Verbose "[$timestamp] Workflow reached terminal state: $statusText ($progressPct%)"
            return [PSCustomObject]@{
                Status    = $statusText
                AppId     = $AppId
                Progress  = $progressPct
                Elapsed   = "$elapsed minutes"
                PollCount = $pollCount
                AppDetail = $appDetail
            }
        }

        # Update the progress bar. Percent reflects elapsed time against the timeout budget,
        # capped at 99 so the bar only hits 100 when we hit a terminal state above.
        if (-not $Quiet) {
            Write-Progress -Activity $activity `
                -Status  "Poll #$pollCount — $statusText ($progressPct%) — elapsed $elapsed min" `
                -PercentComplete ([Math]::Min(($elapsed / $TimeoutMinutes) * 100, 99))
        }

        Start-Sleep -Seconds $IntervalSeconds
    }

    # Timeout
    if (-not $Quiet) {
        Write-Progress -Activity $activity -Completed
    }
    Write-Warning "Watch-JuribaAppRApplicationStatus: timeout after $TimeoutMinutes minutes ($pollCount polls). Last status: $statusText ($progressPct%)."

    return [PSCustomObject]@{
        Status    = 'Timeout'
        AppId     = $AppId
        Progress  = $progressPct
        Elapsed   = "$TimeoutMinutes minutes"
        PollCount = $pollCount
        AppDetail = $appDetail
    }
}
