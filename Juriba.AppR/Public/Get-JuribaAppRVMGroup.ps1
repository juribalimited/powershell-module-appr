function Get-JuribaAppRVMGroup {
    <#
      .SYNOPSIS
      Gets available virtual machine groups (VM pools) from Juriba App Readiness.
      .DESCRIPTION
      Retrieves the list of available VM groups (pools) that can be used for
      smoke testing. Each VM group represents a configured testing environment.
      Use this to identify which VM pool to target for testing.
      .PARAMETER Instance
      The URL of the App Readiness instance. Not required if connected via Connect-JuribaAppR.
      .PARAMETER APIKey
      The API key for authentication. Not required if connected via Connect-JuribaAppR.
      .PARAMETER VMGroupId
      Optional. The unique identifier of a specific VM group to retrieve.
      .EXAMPLE
      Get-JuribaAppRVMGroup
      Returns all available VM groups.
      .EXAMPLE
      Get-JuribaAppRVMGroup -VMGroupId 1
      Returns details for VM group 1.
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$Instance,

        [Parameter(Mandatory = $false)]
        [string]$APIKey,

        [Parameter(Mandatory = $false)]
        [int]$VMGroupId
    )

    $conn = Get-JuribaAppRConnection -Instance $Instance -APIKey $APIKey

    if ($VMGroupId) {
        $uri = "api/virtual-machine/group/$VMGroupId"
    }
    else {
        $uri = "api/virtual-machine/group/list"
    }

    Invoke-JuribaAppRRestMethod -Instance $conn.Instance -APIKey $conn.APIKey `
        -Uri $uri -Method GET
}
