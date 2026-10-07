# Juriba App Readiness PowerShell Module

PowerShell module and automation examples for [Juriba App Readiness](https://www.juriba.com) (AppR). Provides 51 cmdlets covering the full application lifecycle — connect, upload, package, test, publish, and import from MECM/SCCM — plus ready-to-run example scripts for common automation patterns.

## Compatibility

Tested against App Readiness v5.2 and v6.0 RC. All cmdlets work on both versions.

## Installation

### PowerShell Gallery

The module is published on [PowerShell Gallery](https://www.powershellgallery.com/packages/Juriba.AppR/). Installing the module is as simple as:

```powershell
Install-Module Juriba.AppR
```

If you are updating from a previous version of the module simply run:

```powershell
Update-Module Juriba.AppR
```

## Requirements

- PowerShell 7.1 or later (PowerShell Core)
- A Juriba App Readiness instance (v5.2+)
- An API key

### Getting an API key

1. Sign in to the App Readiness web interface.
2. Open your user profile (top-right menu) and select **API Keys**.
3. Click **Generate New Key**, add a description, and copy the key — it is shown only once at creation time.
4. Store it securely (see [API Key Security](#api-key-security)).

## Quick Start

```powershell
Install-Module Juriba.AppR

# Connect
Connect-JuribaAppR -Instance "https://appr.example.com" -APIKey "your-api-key"

# Upload and package an application
$upload = Send-JuribaAppRSetupFile -FilePath "C:\Installers\7z2407-x64.exe"
$app = New-JuribaAppRApplication -Uuid $upload.Uuid -FileName $upload.FileName `
    -FileSize $upload.FileSize -TotalChunks $upload.TotalChunks -RunImmediately

# Watch until packaging completes
$result = Watch-JuribaAppRApplicationStatus -AppId $app.AppId -IntervalSeconds 60
```

## API Key Security

It is recommended to store your API key securely using [SecretManagement](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.secretmanagement/):

```powershell
# One-time setup
Install-Module Microsoft.PowerShell.SecretManagement, Microsoft.PowerShell.SecretStore
Set-Secret -Name "AppR-APIKey" -Secret "your-api-key-here"

# Use in scripts
Connect-JuribaAppR -Instance "https://appr.example.com" -SecretName "AppR-APIKey"
```

The module also supports `-APIKey` (plain text) and `-SecureAPIKey` (SecureString) for backward compatibility and interactive use.

## Examples

The [Examples](Juriba.AppR/Examples/) folder contains ready-to-run automation scripts. Each script has full comment-based help — run `Get-Help ./Examples/<Script>.ps1 -Full` for parameter details and sample invocations.

| Script | Description |
|--------|-------------|
| `Test-QuickStart.ps1` | Exercises every read-only cmdlet, then optionally runs upload-and-create. Use to validate a new install. |
| `Test-UploadAndWatch.ps1` | Upload a local installer, create the app, watch packaging to completion. |
| `Test-KBSearchAndPackage.ps1` | Search the Juriba Knowledge Base, pick a version, download, upload, and package. |
| `Test-WatchAndPublishIntune.ps1` | Poll for apps with passed smoke tests, auto-publish to Intune. |
| `Invoke-JuribaAppRSelfService.ps1` | Interactive self-service packaging — KB search or local file upload. |
| `Invoke-JuribaAppRSelfServiceWithTesting.ps1` | Same, plus live smoke-test visibility after packaging completes. |
| `Import-MECMAppAndSmokeTest.ps1` | Import a CM (MECM/SCCM) application via the configured connector and run a smoke test against the resulting AppR app. |
| `Export-MSIXAppAttachToShare.ps1` | Download MSIX App Attach packages from a generic integration to an SMB share. |

## Cmdlet Reference

Every cmdlet ships with full comment-based help. Use PowerShell's built-in `Get-Help` for parameters, examples, and behavior details:

```powershell
Get-Help Connect-JuribaAppR -Full           # complete documentation
Get-Help New-JuribaAppRApplication -Examples # examples only
Get-Help Watch-JuribaAppRApplicationStatus -Online 2>$null
```

The tables below summarize what's available.

### Connection

| Cmdlet | Description |
|--------|-------------|
| `Connect-JuribaAppR` | Establish a persistent connection to an App Readiness instance |
| `Disconnect-JuribaAppR` | Clear the stored connection |
| `Get-JuribaAppRSession` | Return the active session (instance URL, connected-at timestamp); `$null` if not connected |
| `Set-JuribaAppRAPIKey` | Store an API key in a SecretManagement vault |

### Instance Configuration

| Cmdlet | Description |
|--------|-------------|
| `Get-JuribaAppRAboutInfo` | Get instance version and configuration |
| `Get-JuribaAppRDefaultSetting` | Get default settings (VM groups, output formats, automation flags) |
| `Get-JuribaAppRUser` | Get user information (current user, by ID, or all users) |
| `Get-JuribaAppRVMGroup` | List available VM groups for packaging and testing |

### Applications

| Cmdlet | Description |
|--------|-------------|
| `Get-JuribaAppRApplication` | Get application details by ID (full or basic) |
| `Get-JuribaAppRApplicationList` | Search and filter applications (by query, user, or all) |
| `Get-JuribaAppRApplicationStatus` | Get the full workflow tracker for an application |
| `Get-JuribaAppRApplicationEvent` | Get event history for an application |
| `New-JuribaAppRApplication` | Create a new application from an uploaded file |
| `Get-JuribaAppRApplicationCreationState` | Check async creation progress |
| `Set-JuribaAppRApplication` | Update application properties (name, manufacturer, etc.) |
| `Set-JuribaAppRApplicationOwner` | Assign an owner to an application |
| `Set-JuribaAppRApplicationCommandLine` | Set a custom install command line |
| `Remove-JuribaAppRApplication` | Delete an application |
| `Watch-JuribaAppRApplicationCreation` | Poll until creation resolves to an application ID |
| `Watch-JuribaAppRApplicationStatus` | Poll until packaging reaches a terminal state |

### Upload

| Cmdlet | Description |
|--------|-------------|
| `Send-JuribaAppRSetupFile` | Upload an installer using chunked upload |

### Knowledge Base

| Cmdlet | Description | v6 Status |
|--------|-------------|-----------|
| `Search-JuribaAppRKnowledgeBase` | Search the Juriba KB by name (v6 OData contract with v5 fallback), or get versions by ID; `-UseUDA` as explicit opt-in | OK |
| `Get-JuribaAppRCommandSuggestion` | Get install command suggestions (KB, Programmatic, AI) | OK |

### Packages

| Cmdlet | Description |
|--------|-------------|
| `Get-JuribaAppRApplicationPackage` | Get all packages or by type for an application |
| `Get-JuribaAppRApplicationPackageDetail` | Get detailed package info (v1 API) |

### Testing

| Cmdlet | Description |
|--------|-------------|
| `Get-JuribaAppRTestApplication` | Get applications available for testing |
| `Start-JuribaAppRSmokeTest` | Initiate a smoke test for a package type |
| `Stop-JuribaAppRSmokeTest` | Cancel a running smoke test |
| `Get-JuribaAppRTestResult` | Get smoke test results with pass/fail details |
| `Get-JuribaAppRTestStat` | Get aggregate testing statistics |

### Quality Review

| Cmdlet | Description |
|--------|-------------|
| `Get-JuribaAppRQualityReview` | Get QR checklist results and screenshots |

### Publishing

| Cmdlet | Description | v6 Status |
|--------|-------------|-----------|
| `Get-JuribaAppRIntegrationConnector` | List configured integration connectors | OK |
| `Get-JuribaAppRPublishingProperty` | Get publishing configuration properties | OK |
| `Invoke-JuribaAppRPublishIntune` | Publish a package to Microsoft Intune | OK |
| `Invoke-JuribaAppRPublishMECM` | Publish a package to MECM/SCCM | OK |
| `Invoke-JuribaAppRPublishGeneric` | Publish to a generic integration (auto-populates required fields) | OK |

### MECM (SCCM) Import

These cmdlets pull a customer's MECM application catalogue **into** App Readiness — the inbound counterpart to `Invoke-JuribaAppRPublishMECM`. The import body shape (CM-side `originalApplicationId` + `model`) is derived from the scan-list cmdlet so callers don't need to know the wire format.

| Cmdlet | Description |
|--------|-------------|
| `Get-JuribaAppRMECMProvider` | List configured integration providers (MECM + Intune) or get a single provider by `-Id` |
| `Get-JuribaAppRMECMImportAvailability` | Preflight check — returns `1` when a connector is configured and ready, `0` otherwise |
| `Get-JuribaAppRMECMScanList` | List applications discovered by an integration scan (the table the AppR UI's Scan Import page binds to) |
| `Start-JuribaAppRMECMImport` | Trigger the import — accepts pipeline input from `Get-JuribaAppRMECMScanList` and derives the body fields automatically |
| `Get-JuribaAppRMECMImportEvent` | Get the import event log |
| `Set-JuribaAppRMECMProviderUniqueness` | Toggle uniqueness on a single provider |
| `Start-JuribaAppRMECMScan` | Trigger an integration scan so newly-created CM applications appear in the scan list without waiting for the autoscheduler |
| `Remove-JuribaAppRMECMProvider` | Delete a single (`-Id`) or every (`-All`) provider configuration |

```powershell
# Recommended pattern — pick one row from the scan list and import it
Get-JuribaAppRMECMScanList -ProviderId 7 |
    Where-Object { $_.applicationName -eq 'Notepad++' } |
    Start-JuribaAppRMECMImport
```

### Generic Integration (v1 API)

These cmdlets support custom third-party integrations built on the Generic Integration framework.

| Cmdlet | Description |
|--------|-------------|
| `Get-JuribaAppRGenericIntegration` | List configured generic integrations |
| `Get-JuribaAppRGenericIntegrationPublishing` | Get publishing records for an integration |
| `Get-JuribaAppRGenericIntegrationProperty` | Get properties for a specific publishing |
| `Get-JuribaAppRGenericIntegrationPrerequisite` | Get prerequisites for a publishing |
| `Get-JuribaAppRGenericIntegrationSource` | Download the package source file |
| `Add-JuribaAppRGenericIntegrationLog` | Add a log entry for a publishing |
| `Update-JuribaAppRGenericIntegrationPublishingState` | Update publishing state (Succeeded/Failed) |

## Key Behaviors

### Wrapping vs Repackaging

The module automatically detects whether the instance requires VM-based repackaging or direct wrapping based on the configured output formats:

- **MSI, MSIX, MSIX App Attach** in output formats: triggers VM-based repackaging (`from=0`, uses configured VM group)
- **IntuneWin, PSADT only** in output formats: triggers direct wrapping (`from=4`, `vmGroupId=-1`, no VM needed)

### Command Suggestion Priority

When creating an application, install commands are selected with this priority:

1. **Juriba Knowledge Base** (source 3) — curated commands from the KB
2. **Programmatic** (source 1) — detected from installer type/flags
3. **AI** (source 2) — AI-generated suggestions

Within each source, previously successful commands (by `lastResult` and `successRate`) are preferred.

### Metadata Extraction

Application name, manufacturer, and version are resolved in order:

1. Server-side PE header extraction API
2. Client-side `FileVersionInfo` (PowerShell) or proxy-based extraction (HTML portal)
3. Knowledge Base metadata (when using the KB workflow)
4. Filename fallback

## Use Case Coverage

| Use Case | Cmdlets |
|----------|---------|
| Get list of applications and package status | `Get-JuribaAppRApplicationList`, `Get-JuribaAppRApplicationPackage` |
| Add an application with uploaded file | `Send-JuribaAppRSetupFile`, `New-JuribaAppRApplication` |
| Assign to requester | `Set-JuribaAppRApplicationOwner` |
| Specify override name | `Set-JuribaAppRApplication` |
| Specify override command line | `Set-JuribaAppRApplicationCommandLine` |
| Request a smoke test | `Start-JuribaAppRSmokeTest` |
| Interrogate VM pools | `Get-JuribaAppRVMGroup` |
| Pull back test results/warnings/failures | `Get-JuribaAppRTestResult`, `Get-JuribaAppRTestStat` |
| Interrogate integration options | `Get-JuribaAppRIntegrationConnector` |
| Publish to Intune | `Invoke-JuribaAppRPublishIntune` |
| Pull back publishing status | `Get-JuribaAppRApplicationStatus` |
| Pull back application status | `Get-JuribaAppRApplicationStatus` |
| Pull back QR/UAT results | `Get-JuribaAppRQualityReview` |
| Pull back assignment info | `Get-JuribaAppRApplication` |
| Search Juriba KB | `Search-JuribaAppRKnowledgeBase` |
| List MECM/SCCM provider config | `Get-JuribaAppRMECMProvider` |
| List CM applications discovered by a scan | `Get-JuribaAppRMECMScanList` |
| Import a CM application into AppR | `Start-JuribaAppRMECMImport` |
| Diagnose MECM import progress / errors | `Get-JuribaAppRMECMImportEvent` |

## Contributing

This module is under active development. For feature requests or bug reports, please open an issue on GitHub.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
