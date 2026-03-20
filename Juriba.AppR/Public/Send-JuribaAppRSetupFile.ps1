function Send-JuribaAppRSetupFile {
    <#
      .SYNOPSIS
      Uploads a setup file to Juriba App Readiness using chunked upload.
      .DESCRIPTION
      Uploads a local setup file (MSI, EXE, ZIP, etc.) to App Readiness for
      automated processing. The file is split into chunks, uploaded individually,
      and then combined server-side. Returns an upload identifier (UUID) that can
      be passed to New-JuribaAppRApplication to create the application.

      Large files are handled automatically by splitting into configurable chunk
      sizes (default 2MB). Progress is reported via Write-Progress.
      .PARAMETER Instance
      The URL of the App Readiness instance. Not required if connected via Connect-JuribaAppR.
      .PARAMETER APIKey
      The API key for authentication. Not required if connected via Connect-JuribaAppR.
      .PARAMETER FilePath
      The full path to the setup file to upload.
      .PARAMETER ChunkSizeMB
      The size of each upload chunk in megabytes. Default is 2MB.
      Increase for faster uploads on high-bandwidth connections.
      .PARAMETER Protected
      When specified, uploads the file to the protected upload endpoint.
      Use this for files that require additional security handling.
      .EXAMPLE
      $upload = Send-JuribaAppRSetupFile -FilePath "C:\Installers\Firefox-Setup-115.0.exe"
      $upload.Uuid
      Uploads a setup file and returns the upload identifier.
      .EXAMPLE
      $upload = Send-JuribaAppRSetupFile -FilePath "C:\Installers\BigApp.msi" -ChunkSizeMB 5
      Uploads a large file using 5MB chunks.
      .EXAMPLE
      $upload = Send-JuribaAppRSetupFile -FilePath "C:\Installers\App.exe"
      New-JuribaAppRApplication -Uuid $upload.Uuid -FileName $upload.FileName
      Uploads a file and immediately creates an application from it.
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$Instance,

        [Parameter(Mandatory = $false)]
        [string]$APIKey,

        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path $_ -PathType Leaf })]
        [string]$FilePath,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 100)]
        [int]$ChunkSizeMB = 2,

        [Parameter(Mandatory = $false)]
        [switch]$Protected
    )

    $conn = Get-JuribaAppRConnection -Instance $Instance -APIKey $APIKey

    # Resolve the full path and get file info
    $fileInfo = Get-Item $FilePath
    $fileName = $fileInfo.Name
    $fileSize = $fileInfo.Length
    $chunkSize = $ChunkSizeMB * 1024 * 1024
    $totalChunks = [Math]::Ceiling($fileSize / $chunkSize)
    $uuid = [Guid]::NewGuid().ToString()

    Write-Verbose "Uploading '$fileName' ($([Math]::Round($fileSize / 1MB, 2)) MB) in $totalChunks chunk(s)"
    Write-Verbose "Upload UUID: $uuid"

    # Determine the upload endpoint
    $chunkEndpoint = if ($Protected) { "api/uploadChunk/protected" } else { "api/uploadChunk" }
    $combineEndpoint = if ($Protected) { "api/v2/uploadChunk/protected/async" } else { "api/v2/uploadChunk/async" }

    $headers = @{
        "x-api-key" = $conn.APIKey
        "Accept"    = "application/json"
    }

    # Upload each chunk
    $fileStream = [System.IO.File]::OpenRead($fileInfo.FullName)
    try {
        $buffer = New-Object byte[] $chunkSize
        $chunkIndex = 0

        while ($chunkIndex -lt $totalChunks) {
            $bytesRead = $fileStream.Read($buffer, 0, $chunkSize)

            # Create a temp file for the chunk
            $chunkTempPath = [System.IO.Path]::GetTempFileName()
            try {
                [System.IO.File]::WriteAllBytes($chunkTempPath, $buffer[0..($bytesRead - 1)])

                # Build multipart form data
                $chunkUri = "{0}/{1}" -f $conn.Instance, $chunkEndpoint

                # Use Invoke-WebRequest with form for multipart upload
                $form = @{
                    dzUuid      = $uuid
                    dzChunkIndex = $chunkIndex.ToString()
                    dzTotalChunks = $totalChunks.ToString()
                    dzTotalFileSize = $fileSize.ToString()
                    dzFilename  = $fileName
                    file        = Get-Item $chunkTempPath
                }

                $percentComplete = [Math]::Round(($chunkIndex + 1) / $totalChunks * 100)
                Write-Progress -Activity "Uploading $fileName" `
                    -Status "Chunk $($chunkIndex + 1) of $totalChunks" `
                    -PercentComplete $percentComplete

                Write-Verbose "Uploading chunk $($chunkIndex + 1)/$totalChunks ($bytesRead bytes)"

                $null = Invoke-WebRequest -Uri $chunkUri -Method POST `
                    -Headers $headers -Form $form

            }
            finally {
                if (Test-Path $chunkTempPath) {
                    Remove-Item $chunkTempPath -Force -ErrorAction SilentlyContinue
                }
            }

            $chunkIndex++
        }
    }
    finally {
        $fileStream.Close()
        $fileStream.Dispose()
    }

    Write-Progress -Activity "Uploading $fileName" -Completed

    # Combine the chunks on the server
    Write-Verbose "Combining chunks on server..."
    $combineBody = @{
        uuid         = $uuid
        fileName     = $fileName
        totalChunks  = $totalChunks
        expectedBytes = $fileSize
    }

    $combineUri = "{0}/{1}" -f $conn.Instance, $combineEndpoint
    $combineResult = Invoke-RestMethod -Uri $combineUri -Method PUT `
        -Headers $headers -ContentType 'application/json' `
        -Body ($combineBody | ConvertTo-Json)

    Write-Verbose "Upload complete. UUID: $uuid"

    # Return an object with the upload details needed for New-JuribaAppRApplication
    [PSCustomObject]@{
        Uuid         = $uuid
        FileName     = $fileName
        FileSize     = $fileSize
        TotalChunks  = $totalChunks
        CombineResult = $combineResult
    }
}
