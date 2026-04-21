function Invoke-JuribaAppRPublishGeneric {
    <#
      .SYNOPSIS
      Publishes a package to a generic integration.
      .DESCRIPTION
      Triggers the publishing of a completed package to a configured generic
      integration endpoint. Automatically populates the required request body
      by fetching application details, command lines, and integration properties.

      The user only needs to provide the application ID, integration ID, and
      package type — everything else is resolved automatically.
      .PARAMETER Instance
      The URL of the App Readiness instance. Not required if connected via Connect-JuribaAppR.
      .PARAMETER APIKey
      The API key for authentication. Not required if connected via Connect-JuribaAppR.
      .PARAMETER ApplicationId
      The ID of the application to publish.
      .PARAMETER IntegrationId
      The ID of the generic integration to publish to.
      .PARAMETER PackageType
      The package type to publish. Valid values: Msi, IntuneWin, Psadt, AppAttach.
      .PARAMETER Properties
      Optional. A hashtable of publishing template property values, keyed by
      property ID. If omitted, non-required properties are sent with empty values.
      .PARAMETER Prerequisites
      Optional. An array of prerequisite objects. Defaults to empty.
      .PARAMETER Body
      Optional. A complete request body hashtable. When provided, skips all
      auto-population and sends this body directly (legacy/advanced usage).
      .EXAMPLE
      Invoke-JuribaAppRPublishGeneric -ApplicationId 1941 -IntegrationId 4 -PackageType Msi
      Publishes the MSI package for application 1941 to generic integration 4.
      .EXAMPLE
      Invoke-JuribaAppRPublishGeneric -ApplicationId 1941 -IntegrationId 4 -PackageType Msi -Properties @{ 3 = "English" }
      Publishes with a custom value for publishing property ID 3.
    #>

    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Simple')]
    param (
        [Parameter(Mandatory = $false)]
        [string]$Instance,

        [Parameter(Mandatory = $false)]
        [string]$APIKey,

        [Parameter(Mandatory = $true, ParameterSetName = 'Simple')]
        [int]$ApplicationId,

        [Parameter(Mandatory = $true, ParameterSetName = 'Simple')]
        [int]$IntegrationId,

        [Parameter(Mandatory = $true, ParameterSetName = 'Simple')]
        [ValidateSet('Msi', 'IntuneWin', 'Psadt', 'AppAttach')]
        [string]$PackageType,

        [Parameter(Mandatory = $false, ParameterSetName = 'Simple')]
        [hashtable]$Properties,

        [Parameter(Mandatory = $false, ParameterSetName = 'Simple')]
        [array]$Prerequisites = @(),

        [Parameter(Mandatory = $true, ParameterSetName = 'RawBody')]
        [hashtable]$Body
    )

    $conn = Get-JuribaAppRConnection -Instance $Instance -APIKey $APIKey

    if ($PSCmdlet.ParameterSetName -eq 'RawBody') {
        # Legacy: send the body as-is
        $Target = "App {0} ({1})" -f $Body['applicationId'], $Body['packageType']
        if ($PSCmdlet.ShouldProcess($Target, "Publish to generic integration")) {
            Invoke-JuribaAppRRestMethod -Instance $conn.Instance -APIKey $conn.APIKey `
                -Uri "api/publishing/generic" -Method POST -Body $Body
        }
        return
    }

    # Map friendly name to integer
    $packageTypeMap = @{
        'Msi'        = 0
        'IntuneWin'  = 4
        'AppAttach'  = 5
        'Psadt'      = 6
    }
    $packageTypeInt = $packageTypeMap[$PackageType]

    # Fetch app details for name and command lines
    $app = Get-JuribaAppRApplication -AppId $ApplicationId
    $appName = $app.basic.name
    if (-not $appName) {
        Write-Error "Could not resolve application name for app $ApplicationId."
        return
    }

    # Find install/uninstall commands for this package type
    $cmdEntry = $app.ext.allCommandLines | Where-Object { $_.packageType -eq $packageTypeInt } | Select-Object -First 1
    $installCmd   = if ($cmdEntry) { $cmdEntry.commandLine } else { '' }
    $uninstallCmd = if ($cmdEntry) { $cmdEntry.uninstall }   else { '' }

    # Fetch integration publishing properties and build the properties array
    $intProps = Get-JuribaAppRPublishingProperty -ProviderId $IntegrationId
    $propsArray = @()
    foreach ($pkg in $intProps) {
        if ($pkg.packageType -ne $packageTypeInt) { continue }
        foreach ($p in $pkg.properties) {
            $value = ''
            if ($Properties -and $Properties.ContainsKey($p.id)) {
                $value = $Properties[$p.id]
            }
            $propsArray += @{ id = $p.id; value = $value }
        }
    }

    # Build the request body
    $body = @{
        applicationId          = $ApplicationId.ToString()
        integrationId          = $IntegrationId
        applicationName        = $appName
        installationProgram    = $installCmd
        uninstallationProgram  = $uninstallCmd
        properties             = $propsArray
        packageType            = $packageTypeInt
        prerequisites          = $Prerequisites
    }

    $Target = "$appName (App $ApplicationId, $PackageType) to integration $IntegrationId"

    if ($PSCmdlet.ShouldProcess($Target, "Publish to generic integration")) {
        Invoke-JuribaAppRRestMethod -Instance $conn.Instance -APIKey $conn.APIKey `
            -Uri "api/publishing/generic" -Method POST -Body $body
    }
}
