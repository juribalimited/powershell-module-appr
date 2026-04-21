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
      When specified, suppresses progress output. Only returns the final status object.
      .EXAMPLE
      Watch-JuribaAppRApplicationCreation -UploadId "abc-123-def"
      Polls every 5 minutes until the application is created or 2 hours elapse.
      .EXAMPLE
      Watch-JuribaAppRApplicationCreation -UploadId "abc-123-def" -IntervalSeconds 60 -TimeoutMinutes 30
      Polls every 60 seconds with a 30-minute timeout.
      .EXAMPLE
      $upload = Send-JuribaAppRSetupFile -FilePath "C:\Installers\App.exe"
      $app = New-JuribaAppRApplication -Uuid $upload.Uuid -FileName $upload.FileName -RunImmediately
      $result = Watch-JuribaAppRApplicationCreation -UploadId $upload.Uuid
      if ($result.Status -eq 'Completed') { Write-Host "App ID: $($result.ApplicationId)" }
      Full end-to-end workflow: upload, create, and poll until complete.
    #>

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'Long-running interactive watcher - emits user-facing progress updates (not diagnostic logging) so CLI users can see polling activity.')]
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

    $startTime = Get-Date
    $timeoutTime = $startTime.AddMinutes($TimeoutMinutes)
    $pollCount = 0

    if (-not $Quiet) {
        Write-Host "Watching application creation for upload $UploadId" -ForegroundColor Cyan
        Write-Host "Polling every $IntervalSeconds seconds (timeout: $TimeoutMinutes minutes)" -ForegroundColor Cyan
    }

    while ((Get-Date) -lt $timeoutTime) {
        $pollCount++
        $elapsed = [Math]::Round(((Get-Date) - $startTime).TotalMinutes, 1)

        # Check the creation state
        try {
            $state = Invoke-JuribaAppRRestMethod -Instance $conn.Instance -APIKey $conn.APIKey `
                -Uri "api/apm/application/creation/$UploadId/state" -Method GET
        }
        catch {
            if (-not $Quiet) {
                Write-Warning "Poll #$pollCount ($elapsed min): Failed to get status - $($_.Exception.Message)"
            }
            Start-Sleep -Seconds $IntervalSeconds
            continue
        }

        # Log the current state
        $statusText = if ($state -is [string]) { $state } else { $state | ConvertTo-Json -Compress -Depth 3 }

        if (-not $Quiet) {
            $timestamp = (Get-Date).ToString('HH:mm:ss')
            Write-Host "[$timestamp] Poll #$pollCount ($elapsed min): $statusText" -ForegroundColor Gray
        }

        # Check for completion states
        # The exact field names depend on the API response - we check common patterns
        $isComplete = $false
        $isFailed = $false

        if ($state -is [PSCustomObject] -or $state -is [hashtable]) {
            # Check various possible status field names
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

            # Also check for an applicationId being present (indicates completion)
            $appId = $state.applicationId ?? $state.ApplicationId ?? $state.appId ?? $null
            if ($appId -and $appId -gt 0) {
                $isComplete = $true
            }
        }

        if ($isComplete) {
            if (-not $Quiet) {
                Write-Host "`nApplication creation completed successfully!" -ForegroundColor Green
                $appId = $state.applicationId ?? $state.ApplicationId ?? $state.appId ?? 'Unknown'
                Write-Host "Application ID: $appId" -ForegroundColor Green
                Write-Host "Total time: $elapsed minutes ($pollCount polls)" -ForegroundColor Green
            }
            return $state
        }

        if ($isFailed) {
            if (-not $Quiet) {
                Write-Host "`nApplication creation failed!" -ForegroundColor Red
                Write-Host "Status: $statusText" -ForegroundColor Red
                Write-Host "Total time: $elapsed minutes ($pollCount polls)" -ForegroundColor Red
            }
            return $state
        }

        # Wait for next poll
        if (-not $Quiet) {
            Write-Progress -Activity "Watching application creation" `
                -Status "Poll #$pollCount - Elapsed: $elapsed min - Next check in $IntervalSeconds sec" `
                -PercentComplete (($elapsed / $TimeoutMinutes) * 100)
        }

        Start-Sleep -Seconds $IntervalSeconds
    }

    # Timeout reached
    if (-not $Quiet) {
        Write-Progress -Activity "Watching application creation" -Completed
        Write-Warning "Timeout reached after $TimeoutMinutes minutes ($pollCount polls). Application may still be processing."
        Write-Warning "You can continue checking manually: Get-JuribaAppRApplicationCreationState -UploadId '$UploadId'"
    }

    return [PSCustomObject]@{
        Status    = 'Timeout'
        UploadId  = $UploadId
        Elapsed   = "$TimeoutMinutes minutes"
        PollCount = $pollCount
        Message   = "Polling timed out. The application may still be processing."
    }
}
