function Start-JuribaAppRMECMImport {
    <#
      .SYNOPSIS
      Triggers an import of applications discovered by an MECM/SCCM (or other integration) scan into App Readiness.
      .DESCRIPTION
      Kicks off the AppR-side import job for one or more CM applications
      previously discovered by the integration's scan (visible via
      Get-JuribaAppRMECMScanList). The import creates AppR Application
      records for each selected scan-list row.

      The underlying call is POST /api/admin/sccm/import with body:

          { "filteringObjects": [
              { "id": "<originalApplicationId>", "model": <int> }, ...
            ] }

      Two important things that are easy to get wrong:

        - "id" must be the CM-side originalApplicationId (a string the
          source-of-truth system assigned to the application), NOT the
          AppR-side numeric id from the scan-list row. Sending the numeric
          id silently no-ops — the server returns 200 with no record
          created.
        - "model" must mirror the model field on the scan-list row (the
          server uses it to dispatch to the right importer). For an MECM
          Application record this is 0.

      The recommended pattern is to let the cmdlet derive both fields from
      a scan-list row, either via pipeline or -InputObject.

      Inbound counterpart to Invoke-JuribaAppRPublishMECM (which pushes
      packaged apps OUT to MECM). Use Get-JuribaAppRMECMImportAvailability
      first to confirm the connector is configured before starting an
      import.
      .PARAMETER Instance
      The URL of the App Readiness instance. Not required if connected via Connect-JuribaAppR.
      .PARAMETER APIKey
      The API key for authentication. Not required if connected via Connect-JuribaAppR.
      .PARAMETER InputObject
      One or more scan-list rows from Get-JuribaAppRMECMScanList. Accepts
      pipeline input. Each row contributes
      { id = $row.originalApplicationId; model = $row.model } to the
      filteringObjects body.
      .PARAMETER FilteringObjects
      Pre-built filteringObjects array — escape hatch for callers
      composing the body manually. Each element must be a hashtable /
      object with `id` (string CM-side id) and `model` (int) properties.
      Mutually exclusive with -InputObject and -Body.
      .PARAMETER Body
      Full request body — escape hatch for callers who already have a
      hashtable or who need to pass a property the other parameters don't
      surface. Mutually exclusive with -InputObject and -FilteringObjects.
      .EXAMPLE
      Get-JuribaAppRMECMScanList -ProviderId 7 |
          Where-Object { $_.applicationName -eq 'Notepad++' } |
          Start-JuribaAppRMECMImport
      The recommended flow — pick one row from the scan list and import
      it. The cmdlet pulls originalApplicationId + model off the row.
      .EXAMPLE
      $rows = Get-JuribaAppRMECMScanList -ProviderId 7 |
              Where-Object { $_.status -eq 1 -and $_.applicationName -like 'Adobe*' }
      Start-JuribaAppRMECMImport -InputObject $rows
      Bulk import — every Adobe app that is currently un-imported.
      .EXAMPLE
      Start-JuribaAppRMECMImport -FilteringObjects @(
          @{ id = 'ScopeId_.../Application_...'; model = 0 }
      )
      Manual form when the originalApplicationId is already in hand.
    #>

    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Pipeline')]
    [OutputType([object])]
    param (
        [Parameter(Mandatory = $false)]
        [string]$Instance,

        [Parameter(Mandatory = $false)]
        [string]$APIKey,

        [Parameter(Mandatory = $false, ValueFromPipeline = $true,
            ParameterSetName = 'Pipeline')]
        [object[]]$InputObject,

        [Parameter(Mandatory = $true, ParameterSetName = 'FilterArray')]
        [object[]]$FilteringObjects,

        [Parameter(Mandatory = $true, ParameterSetName = 'BodyHash')]
        [hashtable]$Body
    )

    begin {
        $conn = Get-JuribaAppRConnection -Instance $Instance -APIKey $APIKey
        $collected = New-Object System.Collections.Generic.List[object]
    }

    process {
        if ($PSCmdlet.ParameterSetName -eq 'Pipeline' -and $InputObject) {
            foreach ($row in $InputObject) {
                if ($null -eq $row.originalApplicationId) {
                    throw "Input row missing 'originalApplicationId'. Pass scan-list rows from Get-JuribaAppRMECMScanList, or use -FilteringObjects to compose the body manually."
                }
                $collected.Add(@{
                    id    = [string]$row.originalApplicationId
                    model = [int]$row.model
                })
            }
        }
    }

    end {
        switch ($PSCmdlet.ParameterSetName) {
            'BodyHash'    { $payload = $Body }
            'FilterArray' { $payload = @{ filteringObjects = @($FilteringObjects) } }
            default       { $payload = @{ filteringObjects = $collected.ToArray() } }
        }

        $count = if ($payload.filteringObjects) { @($payload.filteringObjects).Count } else { 0 }
        $target = "$($conn.Instance) ($count application(s))"

        if ($PSCmdlet.ShouldProcess($target, 'Start MECM import')) {
            Invoke-JuribaAppRRestMethod -Instance $conn.Instance -APIKey $conn.APIKey `
                -Uri 'api/admin/sccm/import' -Method POST -Body $payload
        }
    }
}
