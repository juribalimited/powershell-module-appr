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
    $totalChunks = [int][Math]::Ceiling($fileSize / $chunkSize)
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

            # Create a temp file for the chunk, using the original filename
            # so the multipart Content-Disposition has the correct extension.
            # The server validates the filename and rejects .tmp files.
            $chunkTempDir = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), $uuid)
            if (-not (Test-Path $chunkTempDir)) { $null = New-Item -Path $chunkTempDir -ItemType Directory }
            $chunkTempPath = [System.IO.Path]::Combine($chunkTempDir, $fileName)
            try {
                [System.IO.File]::WriteAllBytes($chunkTempPath, $buffer[0..($bytesRead - 1)])

                # Build multipart form data using HttpClient for full control over
                # headers. PowerShell's Invoke-WebRequest -Form may not reliably
                # pass custom headers (x-api-key) with multipart uploads.
                $chunkUri = "{0}/{1}" -f $conn.Instance, $chunkEndpoint
                $chunkByteOffset = $chunkIndex * $chunkSize

                $percentComplete = [Math]::Round(($chunkIndex + 1) / $totalChunks * 100)
                Write-Progress -Activity "Uploading $fileName" `
                    -Status "Chunk $($chunkIndex + 1) of $totalChunks" `
                    -PercentComplete $percentComplete

                Write-Verbose "Uploading chunk $($chunkIndex + 1)/$totalChunks ($bytesRead bytes)"

                try {
                    $httpClient = [System.Net.Http.HttpClient]::new()
                    $httpClient.DefaultRequestHeaders.Add("x-api-key", $conn.APIKey)
                    $httpClient.DefaultRequestHeaders.Add("Authorization", "Bearer $($conn.APIKey)")
                    $httpClient.DefaultRequestHeaders.Add("Accept", "application/json")

                    $multipartContent = [System.Net.Http.MultipartFormDataContent]::new()

                    # Add Dropzone.js 5.9.3 chunked upload fields
                    $multipartContent.Add([System.Net.Http.StringContent]::new($uuid), "dzUuid")
                    $multipartContent.Add([System.Net.Http.StringContent]::new($chunkIndex.ToString()), "dzChunkIndex")
                    $multipartContent.Add([System.Net.Http.StringContent]::new($fileSize.ToString()), "dzTotalFileSize")
                    $multipartContent.Add([System.Net.Http.StringContent]::new($bytesRead.ToString()), "dzCurrentChunkSize")
                    $multipartContent.Add([System.Net.Http.StringContent]::new($totalChunks.ToString()), "dzTotalChunkCount")
                    $multipartContent.Add([System.Net.Http.StringContent]::new($chunkByteOffset.ToString()), "dzChunkByteOffset")
                    $multipartContent.Add([System.Net.Http.StringContent]::new($chunkSize.ToString()), "dzChunkSize")
                    $multipartContent.Add([System.Net.Http.StringContent]::new($fileName), "dzFilename")
                    $multipartContent.Add([System.Net.Http.StringContent]::new("1"), "userId")

                    # Add the file content
                    $chunkBytes = [System.IO.File]::ReadAllBytes($chunkTempPath)
                    $fileContent = [System.Net.Http.ByteArrayContent]::new($chunkBytes)
                    $fileContent.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::new("application/octet-stream")
                    $multipartContent.Add($fileContent, "file", $fileName)

                    $uploadResponse = $httpClient.PostAsync($chunkUri, $multipartContent).GetAwaiter().GetResult()
                    if (-not $uploadResponse.IsSuccessStatusCode) {
                        $respBody = $uploadResponse.Content.ReadAsStringAsync().GetAwaiter().GetResult()
                        throw "HTTP $([int]$uploadResponse.StatusCode) $($uploadResponse.ReasonPhrase): $respBody"
                    }
                }
                catch {
                    $fileStream.Close()
                    $fileStream.Dispose()
                    Write-Progress -Activity "Uploading $fileName" -Completed
                    throw "Chunk $($chunkIndex + 1)/$totalChunks upload failed: $($_.Exception.Message)"
                }
                finally {
                    if ($multipartContent) { $multipartContent.Dispose() }
                    if ($httpClient)        { $httpClient.Dispose() }
                }

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
        # Clean up the temp chunk directory
        if ($chunkTempDir -and (Test-Path $chunkTempDir)) {
            Remove-Item $chunkTempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Write-Progress -Activity "Uploading $fileName" -Completed

    # Combine the chunks on the server
    # Field names must match the CombineFilesModel expected by the API
    Write-Verbose "Combining chunks on server..."
    $combineBody = @{
        dzIdentifier  = $uuid
        fileName      = $fileName
        totalChunks   = $totalChunks
        expectedBytes = $fileSize
        uploadType    = 0
    }

    $combineUri = "{0}/{1}" -f $conn.Instance, $combineEndpoint
    $jsonBody = $combineBody | ConvertTo-Json -Compress
    Write-Verbose "Combine URI: $combineUri"
    Write-Verbose "Combine body: $jsonBody"

    try {
        $combineSplat = @{
            Uri         = $combineUri
            Method      = 'PUT'
            Headers     = $headers
            ContentType = 'application/json'
            Body        = $jsonBody
        }
        if ($conn.WebSession) {
            $combineSplat['WebSession'] = $conn.WebSession
        }
        $combineResult = Invoke-RestMethod @combineSplat
    }
    catch {
        $errDetail = $_.Exception.Message
        if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
            $errDetail = $_.ErrorDetails.Message
        }
        throw "Combine failed: $errDetail"
    }

    Write-Verbose "Upload complete. UUID: $uuid"

    # Extract FileVersionInfo metadata (ProductName, CompanyName, etc.)
    # This is the same data the Angular UI reads client-side before posting.
    $productName  = $null
    $companyName  = $null
    $productVersion = $null
    try {
        $versionInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($fileInfo.FullName)
        if ($versionInfo.ProductName)      { $productName    = $versionInfo.ProductName.Trim() }
        if ($versionInfo.CompanyName)       { $companyName    = $versionInfo.CompanyName.Trim() }
        if ($versionInfo.ProductVersion)    { $productVersion = $versionInfo.ProductVersion.Trim() }
        elseif ($versionInfo.FileVersion)   { $productVersion = $versionInfo.FileVersion.Trim() }
        Write-Verbose "File metadata: Name='$productName', Manufacturer='$companyName', Version='$productVersion'"
    }
    catch {
        Write-Verbose "Could not read FileVersionInfo: $($_.Exception.Message)"
    }

    # Return an object with the upload details needed for New-JuribaAppRApplication
    [PSCustomObject]@{
        Uuid            = $uuid
        FileName        = $fileName
        FileSize        = $fileSize
        TotalChunks     = $totalChunks
        CombineResult   = $combineResult
        ProductName     = $productName
        CompanyName     = $companyName
        ProductVersion  = $productVersion
    }
}
