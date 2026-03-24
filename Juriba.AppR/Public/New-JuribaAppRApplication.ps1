function New-JuribaAppRApplication {
    <#
      .SYNOPSIS
      Creates a new application in Juriba App Readiness.
      .DESCRIPTION
      Creates a new application record in App Readiness from a previously uploaded
      setup file. The application is created asynchronously. Use
      Get-JuribaAppRApplicationCreationState or Watch-JuribaAppRApplicationCreation
      to monitor progress.

      This cmdlet reads Default Settings from the instance to resolve:
        - VM groups for repackaging and testing
        - Output format bitmask (which package types to produce)

      It also calls the server-side metadata extraction API to detect the
      application name, manufacturer, and version from the uploaded binary.

      It also calls the command suggestion API to detect the best install
      and uninstall command lines for the uploaded binary.

      Typical workflow:
        1. Send-JuribaAppRSetupFile to upload the installer
        2. New-JuribaAppRApplication to start processing
        3. Watch-JuribaAppRApplicationStatus to poll until complete
      .PARAMETER Instance
      The URL of the App Readiness instance. Not required if connected via Connect-JuribaAppR.
      .PARAMETER APIKey
      The API key for authentication. Not required if connected via Connect-JuribaAppR.
      .PARAMETER Uuid
      The upload UUID returned by Send-JuribaAppRSetupFile. This identifies the
      uploaded file on the server.
      .PARAMETER FileName
      The original file name of the uploaded setup file. Returned by Send-JuribaAppRSetupFile.
      .PARAMETER FileSize
      The size in bytes of the uploaded file. Returned by Send-JuribaAppRSetupFile.
      .PARAMETER TotalChunks
      The number of chunks the file was split into during upload. Returned by Send-JuribaAppRSetupFile.
      .PARAMETER Name
      Optional override name for the application. If not specified, the server-side
      metadata extraction API is called, falling back to the file name.
      .PARAMETER CommandLine
      Optional override install command line. If not specified, the command suggestion
      API is called to auto-detect the best install command.
      .PARAMETER Manufacturer
      Optional manufacturer/vendor name override.
      .PARAMETER Version
      Optional application version override.
      .PARAMETER RunImmediately
      When specified, immediately begins automated packaging after creation.
      This is the default behavior for most automation scenarios.
      .PARAMETER VMGroupId
      Optional. The VM group to use for packaging. If not specified, reads from
      the instance's Default Settings.
      .PARAMETER VMGroupForTestingId
      Optional. The VM group to use for smoke testing. If not specified, reads from
      the instance's Default Settings.
      .PARAMETER PrePackaged
      When specified, indicates the uploaded file is already in a final package
      format (e.g. an MSI or IntuneWin that does not need repackaging).
      .PARAMETER SkipMetadataExtraction
      When specified, skips the server-side metadata extraction API call.
      Use this if you are providing Name, Manufacturer, and Version explicitly.
      .PARAMETER SkipCommandSuggestion
      When specified, skips the command suggestion API call.
      Use this if you are providing CommandLine explicitly.
      .EXAMPLE
      $upload = Send-JuribaAppRSetupFile -FilePath "C:\Installers\Firefox-Setup.exe"
      New-JuribaAppRApplication -Uuid $upload.Uuid -FileName $upload.FileName `
          -FileSize $upload.FileSize -TotalChunks $upload.TotalChunks -RunImmediately
      Uploads a file and creates an application using default settings and auto-detection.
      .EXAMPLE
      $upload = Send-JuribaAppRSetupFile -FilePath "C:\Installers\App.exe"
      New-JuribaAppRApplication -Uuid $upload.Uuid -FileName $upload.FileName `
          -FileSize $upload.FileSize -TotalChunks $upload.TotalChunks `
          -Name "My App 2.0" -Manufacturer "Contoso" -Version "2.0" -RunImmediately
      Creates an application with explicit metadata overrides.
      .EXAMPLE
      $upload = Send-JuribaAppRSetupFile -FilePath "C:\Packages\App.msi"
      $app = New-JuribaAppRApplication -Uuid $upload.Uuid -FileName $upload.FileName `
          -FileSize $upload.FileSize -TotalChunks $upload.TotalChunks -PrePackaged
      Creates a pre-packaged application (no repackaging needed).
    #>

    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory = $false)]
        [string]$Instance,

        [Parameter(Mandatory = $false)]
        [string]$APIKey,

        [Parameter(Mandatory = $true)]
        [string]$Uuid,

        [Parameter(Mandatory = $true)]
        [string]$FileName,

        [Parameter(Mandatory = $true)]
        [long]$FileSize,

        [Parameter(Mandatory = $true)]
        [int]$TotalChunks,

        [Parameter(Mandatory = $false)]
        [string]$Name,

        [Parameter(Mandatory = $false)]
        [string]$CommandLine,

        [Parameter(Mandatory = $false)]
        [string]$Manufacturer,

        [Parameter(Mandatory = $false)]
        [string]$Version,

        [Parameter(Mandatory = $false)]
        [switch]$RunImmediately,

        [Parameter(Mandatory = $false)]
        [int]$VMGroupId,

        [Parameter(Mandatory = $false)]
        [int]$VMGroupForTestingId,

        [Parameter(Mandatory = $false)]
        [switch]$PrePackaged,

        [Parameter(Mandatory = $false)]
        [switch]$SkipMetadataExtraction,

        [Parameter(Mandatory = $false)]
        [switch]$SkipCommandSuggestion
    )

    $conn = Get-JuribaAppRConnection -Instance $Instance -APIKey $APIKey

    # ── Step 1: Read Default Settings for VM groups and output format bitmask ──
    # This matches the UI's GET /api/default-settings call before creating an app.
    $defaults = $null
    try {
        $defaults = Get-JuribaAppRDefaultSettings -Instance $conn.Instance -APIKey $conn.APIKey
        Write-Verbose "Default Settings: VMGroup=$($defaults.VMGroupForRepackaging), TestGroup=$($defaults.VMGroupForTesting), OutputBitmask=$($defaults.OutputFormatBitmask)"
    }
    catch {
        Write-Warning "Could not read Default Settings: $($_.Exception.Message). Using fallback values."
    }

    # Resolve VM groups: explicit parameter > default settings
    $resolvedVMGroupId = if ($VMGroupId) { $VMGroupId }
                         elseif ($defaults -and $defaults.VMGroupForRepackaging) { $defaults.VMGroupForRepackaging }
                         else { 0 }

    $resolvedVMGroupForTestingId = if ($VMGroupForTestingId) { $VMGroupForTestingId }
                                   elseif ($defaults -and $defaults.VMGroupForTesting) { $defaults.VMGroupForTesting }
                                   else { 0 }

    # Resolve output format bitmask from default settings
    $outputBitmask = if ($defaults -and $defaults.OutputFormatBitmask) { $defaults.OutputFormatBitmask }
                     else { 0 }

    # ── Step 2: Server-side metadata extraction ──
    # Matches the UI's PUT /api/apm/application/setupFile/getMetadata/{uuid}
    $serverMeta = $null
    if (-not $SkipMetadataExtraction -and (-not $Name -or -not $Manufacturer -or -not $Version)) {
        try {
            Write-Verbose "Extracting metadata from server for upload $Uuid..."
            $serverMeta = Invoke-JuribaAppRRestMethod -Instance $conn.Instance -APIKey $conn.APIKey `
                -Uri "api/apm/application/setupFile/getMetadata/$Uuid" -Method PUT
            Write-Verbose "Server metadata: Name=$($serverMeta.applicationName), Mfg=$($serverMeta.applicationManufacturer), Ver=$($serverMeta.applicationVersion)"
        }
        catch {
            Write-Warning "Server-side metadata extraction failed: $($_.Exception.Message)"
        }
    }

    # Resolve name/manufacturer/version: explicit param > server metadata > fallback
    $appName = if ($Name)         { $Name }
               elseif ($serverMeta -and $serverMeta.applicationName) { $serverMeta.applicationName }
               else { [System.IO.Path]::GetFileNameWithoutExtension($FileName) }

    $appMfg  = if ($Manufacturer) { $Manufacturer }
               elseif ($serverMeta -and $serverMeta.applicationManufacturer) { $serverMeta.applicationManufacturer }
               else { "Unknown" }

    $appVer  = if ($Version)      { $Version }
               elseif ($serverMeta -and $serverMeta.applicationVersion) { $serverMeta.applicationVersion }
               else { "1.0" }

    # ── Step 3: Command suggestion API ──
    # Matches the UI's POST /api/application/temp/commands/suggestion
    $suggestedCmd = $null
    if (-not $SkipCommandSuggestion -and -not $CommandLine) {
        try {
            Write-Verbose "Getting command suggestions for $FileName..."
            $suggestedCmd = Get-JuribaAppRCommandSuggestion `
                -Instance $conn.Instance -APIKey $conn.APIKey `
                -UploadId $Uuid -FileName $FileName `
                -Name $appName -Manufacturer $appMfg -Version $appVer
            if ($suggestedCmd) {
                Write-Verbose "Suggested command: $($suggestedCmd | ConvertTo-Json -Compress)"
            }
        }
        catch {
            Write-Warning "Command suggestion failed: $($_.Exception.Message)"
        }
    }

    # Parse command suggestions — the API returns a commands array with source priority:
    #   source 3 = Juriba KB, source 1 = programmatic, source 2 = AI
    # Within each source, prefer: lastResult > 0 (previously successful), then highest
    # successRate, then first in array (API returns best-ranked first).
    $suggestedInstallCmd = $null
    if ($suggestedCmd) {
        $cmds = $null
        if ($suggestedCmd.PSObject.Properties['commands']) {
            $cmds = $suggestedCmd.commands
        }
        if ($cmds -and $cmds.Count -gt 0) {
            $installCmds = @($cmds | Where-Object { $_.type -eq 1 })
            Write-Verbose "Install command candidates: $($installCmds.Count)"
            foreach ($c in $installCmds) {
                $srcLabel = switch ($c.source) { 3 { 'JuribaKB' } 1 { 'Programmatic' } 2 { 'AI' } default { "Unknown($($c.source))" } }
                Write-Verbose "  [$srcLabel] $($c.command)  (success=$($c.successRate) failure=$($c.failureRate) lastResult=$($c.lastResult))"
            }

            # Source priority: Juriba KB (3), programmatic (1), AI (2)
            foreach ($sourcePriority in @(3, 1, 2)) {
                $candidates = @($installCmds | Where-Object { $_.source -eq $sourcePriority })
                if ($candidates.Count -gt 0) {
                    # Within a source: prefer last-used successful (lastResult > 0),
                    # then highest successRate, then first (API's own ranking)
                    $pick = $candidates |
                        Sort-Object -Property @{ Expression = { if ($_.lastResult -gt 0) { 0 } else { 1 } } },
                                              @{ Expression = { $_.successRate }; Descending = $true } |
                        Select-Object -First 1
                    $suggestedInstallCmd = $pick.command
                    $srcLabel = switch ($sourcePriority) { 3 { 'JuribaKB' } 1 { 'Programmatic' } 2 { 'AI' } }
                    Write-Verbose "Selected install command [$srcLabel]: $suggestedInstallCmd"
                    break
                }
            }
        }
        else {
            Write-Verbose "Command suggestion response had no commands array"
        }
    }

    # Resolve install command: explicit param > suggestion API > empty
    # Uninstall is intentionally left blank — the product handles it during packaging
    $installCmd = if ($CommandLine) { $CommandLine }
                  elseif ($suggestedInstallCmd) { $suggestedInstallCmd }
                  else { "" }

    # ── Step 4: Build the request body ──

    # applicationInfo — matches the UI's AddApplicationViewModel
    $applicationInfo = @{
        appVer                 = $appVer
        manufacturer           = $appMfg
        name                   = $appName
        pkgVer                 = "1.0"
        siteCode               = "GLOBAL"
        isDiscovery            = $false
        preReqIds              = @()
        upgradeAppIds          = @()
        existingAppId          = -1
        fullPreReqInfo         = @()
        source                 = 0
        sourceFileName         = $FileName
        sendUda                = $true
        operatingSystemType    = 0
        isAutomatedRepackaging = $false
    }

    # Add install command line if we have one
    if ($installCmd) {
        $applicationInfo['cmdLine'] = $installCmd
    }
    # Explicitly set uninstall to empty — without this, the server copies
    # the install command to uninstall, which hangs the VM
    $applicationInfo['uninstall'] = ""

    # uploadChunkModel — tells the server which uploaded chunks to use
    $uploadChunkModel = @{
        dzIdentifier  = $Uuid
        fileName      = $FileName
        expectedBytes = $FileSize
        totalChunks   = $TotalChunks
    }

    # packageTypeMatrixModel — output format bitmask from default settings
    # UI sends { from: 0, to: <bitmask> } with NO sourceAction field
    $packageTypeMatrixModel = @{
        from = 0
        to   = $outputBitmask
    }

    # Main request body (AddApplicationParentViewModel)
    $body = @{
        applicationId          = -1
        applicationInfo        = $applicationInfo
        preReqs                = @()
        fullPreReqInfo         = @()
        upgradeAppIds          = @()
        setAsMainSource        = $true
        uploadChunkModel       = $uploadChunkModel
        packageTypeMatrixModel = $packageTypeMatrixModel
        runImmediately         = [bool]$RunImmediately
        runEvAsAnotherUser     = $null
    }

    # VM groups from default settings or explicit parameters
    if ($resolvedVMGroupId -gt 0) {
        $body['vmGroupId'] = $resolvedVMGroupId
    }
    if ($resolvedVMGroupForTestingId -gt 0) {
        $body['vmGroupForTestingId'] = $resolvedVMGroupForTestingId
    }

    $Target = if ($appName -ne [System.IO.Path]::GetFileNameWithoutExtension($FileName)) { $appName } else { $FileName }

    if ($PSCmdlet.ShouldProcess($Target, "Create Application")) {
        if ($PrePackaged) {
            $uri = "api/apm/application/prePackaged/async"
        }
        else {
            $uri = "api/apm/application/async"
        }

        Write-Verbose "Submitting create request to $uri..."
        Write-Verbose "Body: $($body | ConvertTo-Json -Depth 5 -Compress)"

        $result = Invoke-JuribaAppRRestMethod -Instance $conn.Instance -APIKey $conn.APIKey `
            -Uri $uri -Method POST -Body $body

        # Return a useful object with the UUID for tracking
        if ($result) {
            $result | Add-Member -NotePropertyName 'Uuid' -NotePropertyValue $Uuid -Force -PassThru
        }
        else {
            # API returned success but empty body — return tracking object
            [PSCustomObject]@{
                Uuid     = $Uuid
                FileName = $FileName
                Status   = 'Submitted'
            }
        }
    }
}
