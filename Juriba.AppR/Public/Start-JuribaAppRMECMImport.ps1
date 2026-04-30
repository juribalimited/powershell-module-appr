function Start-JuribaAppRMECMImport {
    <#
      .SYNOPSIS
      Triggers an import of applications from Microsoft Endpoint Configuration Manager (MECM/SCCM) into App Readiness.
      .DESCRIPTION
      Kicks off the AppR-side MECM import job. The import pulls the customer's
      MECM application catalogue into App Readiness so the apps are visible
      for analysis, packaging coverage, and republish workflows.

      This is the inbound counterpart to Invoke-JuribaAppRPublishMECM (which
      pushes packaged apps OUT to MECM). Use Get-JuribaAppRMECMImportAvailability
      first to confirm the connector is configured before starting an import.
      .PARAMETER Instance
      The URL of the App Readiness instance. Not required if connected via Connect-JuribaAppR.
      .PARAMETER APIKey
      The API key for authentication. Not required if connected via Connect-JuribaAppR.
      .PARAMETER FilteringObjects
      Optional. An array of MECM filter objects scoping which applications /
      collections / folders to import. When omitted, the server's default
      filter set is used (typically: import everything available).
      Maps to the SccmRunJobModel.filteringObjects field on the underlying
      POST /api/admin/sccm/import endpoint.
      .PARAMETER Body
      Optional. Full request body, escape hatch for callers who already have
      a hashtable or who need to pass a property the FilteringObjects
      parameter doesn't surface. Mutually exclusive with -FilteringObjects.
      .EXAMPLE
      Start-JuribaAppRMECMImport
      Starts a MECM import using the connector's default filter set.
      .EXAMPLE
      Start-JuribaAppRMECMImport -FilteringObjects @(
          @{ type = 'Collection'; id = 'SMS00001' }
      )
      Starts an import scoped to a specific MECM collection.
      .EXAMPLE
      Start-JuribaAppRMECMImport -Body @{ filteringObjects = @() }
      Equivalent to passing no filter — full hashtable form for callers who
      compose the body elsewhere.
    #>

    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'FilterArray')]
    param (
        [Parameter(Mandatory = $false)]
        [string]$Instance,

        [Parameter(Mandatory = $false)]
        [string]$APIKey,

        [Parameter(Mandatory = $false, ParameterSetName = 'FilterArray')]
        [object[]]$FilteringObjects,

        [Parameter(Mandatory = $true, ParameterSetName = 'BodyHash')]
        [hashtable]$Body
    )

    $conn = Get-JuribaAppRConnection -Instance $Instance -APIKey $APIKey

    if ($PSCmdlet.ParameterSetName -eq 'BodyHash') {
        $payload = $Body
    }
    else {
        # Always send a body (even when empty) — the server expects an
        # SccmRunJobModel JSON object on POST and a missing body would
        # be rejected by the OData / model-binder pipeline.
        $payload = @{ filteringObjects = @($FilteringObjects) }
    }

    if ($PSCmdlet.ShouldProcess($conn.Instance, 'Start MECM import')) {
        Invoke-JuribaAppRRestMethod -Instance $conn.Instance -APIKey $conn.APIKey `
            -Uri 'api/admin/sccm/import' -Method POST -Body $payload
    }
}
