function Watch-JuribaAppRApplicationCreation {
    <#
      .SYNOPSIS
      Polls the creation status of an application until it completes or times out.
      .DESCRIPTION
      After creating an application with New-JuribaAppRApplication, use this cmdlet
      to poll for the creation status at a defined interval. The cmdlet will continue
      polling until the application creation completes (successfully or with failure),
      or until the specified timeout is reached.

      Returns the final status object which includes success/failure information
      and the application ID if creation succeeded.

      Progress is surfaced via Write-Progress (progress bar in interactive hosts,
      progress record on CI runners). Per-poll detail is emitted via Write-Verbose
      (enable with -Verbose).
      .PARAMETER Instance
      The URL of the App Readiness instance. Not required if connected via Connect-JuribaAppR.
      .PARAMETER APIKey
      The API key for authentication. Not required if connected via Connect-JuribaAppR.
      .PARAMETER UploadId
      The upload UUID returned by Send-JuribaAppRSetupFile or New-JuribaAppRApplication.
      .PARAMETER IntervalSeconds
      The number of seconds to wait between status checks. Default is 300 (5 minutes).
      .PARAMETER TimeoutMinutes
      The maximum number of minutes to poll before giving up. Default is 120 (2 hours).
      .PARAMETER Quiet
      When specified, suppresses the Write-Progress bar. Only returns the final status object.
      Verbose logging is still controlled independently via -Verbose.
      .EXAMPLE
      Watch-JuribaAppRApplicationCreation -UploadId "abc-123-def"
      Polls every 5 minutes until the application is created or 2 hours elapse.
      .EXAMPLE
      Watch-JuribaAppRApplicationCreation -UploadId "abc-123-def" -IntervalSeconds 60 -TimeoutMinutes 30 -Verbose
      Polls every 60 seconds with a 30-minute timeout; emits per-poll detail via Write-Verbose.
      .EXAMPLE
      $upload = Send-JuribaAppRSetupFile -FilePath "C:\Installers\App.exe"
      $app = New-JuribaAppRApplication -Uuid $upload.Uuid -FileName $upload.FileName -RunImmediately
      $result = Watch-JuribaAppRApplicationCreation -UploadId $upload.Uuid
      Full end-to-end workflow: upload, create, and poll until complete.
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$Instance,

        [Parameter(Mandatory = $false)]
        [string]$APIKey,

        [Parameter(Mandatory = $true)]
        [string]$UploadId,

        [Parameter(Mandatory = $false)]
        [ValidateRange(10, 3600)]
        [int]$IntervalSeconds = 300,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 1440)]
        [int]$TimeoutMinutes = 120,

        [Parameter(Mandatory = $false)]
        [switch]$Quiet
    )

    $conn = Get-JuribaAppRConnection -Instance $Instance -APIKey $APIKey

    $startTime   = Get-Date
    $timeoutTime = $startTime.AddMinutes($TimeoutMinutes)
    $pollCount   = 0
    $activity    = "Watching creation for upload $UploadId (timeout $TimeoutMinutes min, poll every $IntervalSeconds s)"

    Write-Verbose "$activity — started at $startTime"

    while ((Get-Date) -lt $timeoutTime) {
        $pollCount++
        $elapsed   = [Math]::Round(((Get-Date) - $startTime).TotalMinutes, 1)
        $timestamp = (Get-Date).ToString('HH:mm:ss')

        # Check the creation state
        try {
            $state = Invoke-JuribaAppRRestMethod -Instance $conn.Instance -APIKey $conn.APIKey `
                -Uri "api/apm/application/creation/$UploadId/state" -Method GET
        }
        catch {
            Write-Verbose "[$timestamp] Poll #${pollCount}: failed to get status — $($_.Exception.Message)"
            Start-Sleep -Seconds $IntervalSeconds
            continue
        }

        # Render state as a short string for logging
        $statusText = if ($state -is [string]) { $state } else { $state | ConvertTo-Json -Compress -Depth 3 }
        Write-Verbose "[$timestamp] Poll #$pollCount ($elapsed min): $statusText"

        # Check for completion states. Field names vary — check common patterns.
        $isComplete = $false
        $isFailed   = $false

        if ($state -is [PSCustomObject] -or $state -is [hashtable]) {
            $statusValue = $state.status ?? $state.state ?? $state.Status ?? $state.State ?? ''

            if ($statusValue -is [string]) {
                $statusLower = $statusValue.ToLower()
                if ($statusLower -in @('completed', 'complete', 'done', 'success', 'succeeded', 'finished')) {
                    $isComplete = $true
                }
                elseif ($statusLower -in @('failed', 'error', 'cancelled', 'canceled', 'faulted')) {
                    $isFailed = $true
                }
            }

            # An applicationId being present also indicates completion
            $appId = $state.applicationId ?? $state.ApplicationId ?? $state.appId ?? $null
            if ($appId -and $appId -gt 0) { $isComplete = $true }
        }

        if ($isComplete) {
            if (-not $Quiet) { Write-Progress -Activity $activity -Completed }
            $appId = $state.applicationId ?? $state.ApplicationId ?? $state.appId ?? 'Unknown'
            Write-Verbose "[$timestamp] Creation completed — ApplicationId=$appId, elapsed=$elapsed min, polls=$pollCount"
            return $state
        }

        if ($isFailed) {
            if (-not $Quiet) { Write-Progress -Activity $activity -Completed }
            Write-Warning "Application creation failed: $statusText"
            return $state
        }

        if (-not $Quiet) {
            Write-Progress -Activity $activity `
                -Status "Poll #$pollCount — elapsed $elapsed min — next check in $IntervalSeconds s" `
                -PercentComplete ([Math]::Min(($elapsed / $TimeoutMinutes) * 100, 99))
        }

        Start-Sleep -Seconds $IntervalSeconds
    }

    # Timeout
    if (-not $Quiet) { Write-Progress -Activity $activity -Completed }
    Write-Warning "Watch-JuribaAppRApplicationCreation: timeout after $TimeoutMinutes minutes ($pollCount polls). Check with: Get-JuribaAppRApplicationCreationState -UploadId '$UploadId'"

    return [PSCustomObject]@{
        Status    = 'Timeout'
        UploadId  = $UploadId
        Elapsed   = "$TimeoutMinutes minutes"
        PollCount = $pollCount
        Message   = "Polling timed out. The application may still be processing."
    }
}
