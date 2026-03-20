# Juriba App Readiness PowerShell Module

PowerShell module to interact with [Juriba App Readiness](https://www.juriba.com) (AppR). Provides cmdlets for managing applications, packaging, smoke testing, quality review, and publishing to distribution systems such as Microsoft Intune and MECM.

## Available Modules

| Module | Description |
|--------|-------------|
| Juriba.AppR | Core App Readiness module with 36 cmdlets covering application lifecycle management |

## Installation

### PowerShell Gallery (coming soon)

```powershell
Install-Module Juriba.AppR
```

### Manual Installation

Clone this repository and import the module directly:

```powershell
git clone https://github.com/juribalimited/powershell-module-appr.git
Import-Module ./powershell-module-appr/Juriba.AppR/Juriba.AppR.psd1
```

## Requirements

- PowerShell 7.0 or later (PowerShell Core)
- A Juriba App Readiness instance
- An API key (generated from your user profile in the App Readiness web interface)

## Configuration

### Instance URL

Your App Readiness instance URL is the address you use to access the web interface, for example `https://appr.yourcompany.com`.

### API Key

An API key can be generated from your user profile within the App Readiness web interface. It is recommended to store your API key securely using the [SecretManagement](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.secretmanagement/) module:

```powershell
# Store your API key securely (one time)
Install-Module Microsoft.PowerShell.SecretManagement
Install-Module Microsoft.PowerShell.SecretStore
Set-Secret -Name "AppR-APIKey" -Secret "your-api-key-here"

# Retrieve and use in scripts
$apiKey = Get-Secret -Name "AppR-APIKey" -AsPlainText
Connect-JuribaAppR -Instance "https://appr.example.com" -APIKey $apiKey
```

## Getting Started

### Connect to App Readiness

```powershell
# Option 1: Connect once, use for all subsequent calls
Connect-JuribaAppR -Instance "https://appr.example.com" -APIKey "your-api-key"

# Option 2: Pass credentials explicitly to each cmdlet
Get-JuribaAppRApplication -Instance "https://appr.example.com" -APIKey "your-api-key"
```

### List Applications

```powershell
# Get all applications
Get-JuribaAppRApplicationList -AllUsers

# Search for a specific application
Get-JuribaAppRApplicationList -Query "Chrome"

# Get full details for an application
Get-JuribaAppRApplication -AppId 42
```

### Check Application Status

```powershell
# Get the full workflow tracker (packaging, testing, QR, publishing)
Get-JuribaAppRApplicationStatus -AppId 42

# Get event history
Get-JuribaAppRApplicationEvent -AppId 42

# Get package information
Get-JuribaAppRApplicationPackage -AppId 42
```

### Create an Application

```powershell
# Create a new application from an uploaded file
$result = New-JuribaAppRApplication -UploadId "upload-guid-here"

# Check creation progress
Get-JuribaAppRApplicationCreationState -UploadId "upload-guid-here"

# Assign an owner
Set-JuribaAppRApplicationOwner -AppId 42 -UserId 5

# Set a custom command line
Set-JuribaAppRApplicationCommandLine -AppId 42 -CommandLine "/S /v/qn"
```

### Smoke Testing

```powershell
# List available VM pools
Get-JuribaAppRVMGroup

# Start a smoke test
Start-JuribaAppRSmokeTest -AppId 42 -PackageType Msi

# Check test results
Get-JuribaAppRTestResult -AppId 42

# Get testing statistics
Get-JuribaAppRTestStats -AppId 42
```

### Publishing

```powershell
# See available integration connectors
Get-JuribaAppRIntegrationConnector

# Publish to Intune
Invoke-JuribaAppRPublishIntune -Body @{
    applicationId = 42
    packageType   = "IntuneWin"
}

# Publish to MECM
Invoke-JuribaAppRPublishMECM -Body @{
    applicationId = 42
    packageType   = "Msi"
}
```

### Search Juriba Knowledge Base

```powershell
# Search for known applications
Search-JuribaAppRKnowledgeBase -Search "Firefox"
```

## Cmdlet Reference

### Connection

| Cmdlet | Description |
|--------|-------------|
| `Connect-JuribaAppR` | Establish a persistent connection to an App Readiness instance |
| `Disconnect-JuribaAppR` | Clear the stored connection |
| `Get-JuribaAppRAboutInfo` | Get instance version and configuration information |

### Applications

| Cmdlet | Description |
|--------|-------------|
| `Get-JuribaAppRApplication` | Get application details by ID, or list all applications |
| `Get-JuribaAppRApplicationList` | Search and filter applications |
| `Get-JuribaAppRApplicationStatus` | Get the full workflow tracker for an application |
| `Get-JuribaAppRApplicationPackage` | Get package information for an application |
| `Get-JuribaAppRApplicationPackageDetail` | Get detailed package info by type (v1 API) |
| `Get-JuribaAppRApplicationEvent` | Get event history for an application |
| `New-JuribaAppRApplication` | Create a new application |
| `Get-JuribaAppRApplicationCreationState` | Check async application creation progress |
| `Set-JuribaAppRApplication` | Update application properties |
| `Set-JuribaAppRApplicationOwner` | Assign an owner to an application |
| `Set-JuribaAppRApplicationCommandLine` | Set a custom command line |
| `Remove-JuribaAppRApplication` | Delete an application |

### Users

| Cmdlet | Description |
|--------|-------------|
| `Get-JuribaAppRUser` | Get user information (current user, by ID, or all users) |

### Testing

| Cmdlet | Description |
|--------|-------------|
| `Get-JuribaAppRVMGroup` | List available VM pools for testing |
| `Get-JuribaAppRTestApplication` | Get applications available for testing |
| `Start-JuribaAppRSmokeTest` | Initiate a smoke test |
| `Stop-JuribaAppRSmokeTest` | Cancel a running smoke test |
| `Get-JuribaAppRTestResult` | Get smoke test results |
| `Get-JuribaAppRTestStats` | Get aggregate testing statistics |

### Quality Review

| Cmdlet | Description |
|--------|-------------|
| `Get-JuribaAppRQualityReview` | Get QR results, optionally with screenshots |

### Publishing

| Cmdlet | Description |
|--------|-------------|
| `Get-JuribaAppRIntegrationConnector` | List configured integration connectors |
| `Get-JuribaAppRPublishingProperty` | Get publishing configuration properties |
| `Invoke-JuribaAppRPublishIntune` | Publish a package to Microsoft Intune |
| `Invoke-JuribaAppRPublishMECM` | Publish a package to MECM |
| `Invoke-JuribaAppRPublishGeneric` | Publish a package to a generic integration |

### Knowledge Base

| Cmdlet | Description |
|--------|-------------|
| `Search-JuribaAppRKnowledgeBase` | Search the Juriba KB for known applications |

### Generic Integration (v1 API)

| Cmdlet | Description |
|--------|-------------|
| `Get-JuribaAppRGenericIntegration` | List generic integrations |
| `Get-JuribaAppRGenericIntegrationPublishing` | Get publishing records for an integration |
| `Get-JuribaAppRGenericIntegrationPrerequisite` | Get prerequisites for a publishing |
| `Get-JuribaAppRGenericIntegrationProperty` | Get properties for a publishing |
| `Get-JuribaAppRGenericIntegrationSource` | Download the source package |
| `Add-JuribaAppRGenericIntegrationLog` | Add a log entry for a publishing |
| `Update-JuribaAppRGenericIntegrationPublishingState` | Update publishing state (Succeeded/Failed) |

## Use Case Coverage

This module addresses the key customer automation scenarios identified in the API Use Cases document:

| Priority | Use Case | Cmdlets |
|----------|----------|---------|
| Need | Get list of applications and package status | `Get-JuribaAppRApplicationList`, `Get-JuribaAppRApplicationPackage` |
| Need | Add an application with uploaded file | `New-JuribaAppRApplication` |
| Need | Assign to requester | `Set-JuribaAppRApplicationOwner` |
| Need | Specify override name | `Set-JuribaAppRApplication` |
| Need | Request a smoke test | `Start-JuribaAppRSmokeTest` |
| Need | Interrogate VM pools | `Get-JuribaAppRVMGroup` |
| Need | Pull back test results/warnings/failures | `Get-JuribaAppRTestResult`, `Get-JuribaAppRTestStats` |
| Need | Interrogate integration options | `Get-JuribaAppRIntegrationConnector` |
| Need | Publish to Intune | `Invoke-JuribaAppRPublishIntune` |
| Need | Pull back publishing status | `Get-JuribaAppRApplicationStatus` |
| Need | Pull back application status | `Get-JuribaAppRApplicationStatus` |
| Need | Pull back QR/UAT results | `Get-JuribaAppRQualityReview` |
| Need | Pull back assignment info | `Get-JuribaAppRApplication` |
| Want | Specify override command line | `Set-JuribaAppRApplicationCommandLine` |
| When Possible | Search Juriba KB | `Search-JuribaAppRKnowledgeBase` |

## Examples

See the [Examples](Examples/) folder for complete workflow scripts.

## Contributing

This module is under active development. For feature requests or bug reports, please open an issue on GitHub.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
