# Pester tests for Export-MSIXAppAttachToShare.ps1
# Mocks all module cmdlets to test script logic without a live instance.

$ScriptPath = Join-Path $PSScriptRoot 'Export-MSIXAppAttachToShare.ps1'

# We need to define stub functions for the module cmdlets so Mock can intercept them.
# Pester Mock requires the stub's param signature to match the real cmdlet.
# The `$null = $paramList` lines consume the params so PSScriptAnalyzer's
# PSReviewUnusedParameter rule doesn't fire on what are, by design, unused in stubs.
function Connect-JuribaAppR { param($Instance, $APIKey, $SecretName) $null = $Instance, $APIKey, $SecretName }
function Disconnect-JuribaAppR { }
function Get-JuribaAppRGenericIntegration { }
function Get-JuribaAppRGenericIntegrationPublishing { param($IntegrationId, $Limit, $PackageTypes) $null = $IntegrationId, $Limit, $PackageTypes }
function Get-JuribaAppRGenericIntegrationProperty { param($IntegrationId, $PublishingId) $null = $IntegrationId, $PublishingId }
function Get-JuribaAppRGenericIntegrationSource { param($IntegrationId, $PublishingId, $SourcePath) $null = $IntegrationId, $PublishingId, $SourcePath }
function Add-JuribaAppRGenericIntegrationLog { param($IntegrationId, $PublishingId, $Message, $Level, $Date) $null = $IntegrationId, $PublishingId, $Message, $Level, $Date }
function Update-JuribaAppRGenericIntegrationPublishingState {
    [CmdletBinding(SupportsShouldProcess)]
    param($IntegrationId, $PublishingId, $PublishingState)
    $null = $IntegrationId, $PublishingId, $PublishingState
    # Pester intercepts this stub via Mock; satisfy PSShouldProcess without a real side-effect.
    if ($PSCmdlet.ShouldProcess('stub', 'noop')) { }
}

Describe 'Export-MSIXAppAttachToShare' {

    $testShare = Join-Path $TestDrive 'msix-share'
    $testStaging = Join-Path $TestDrive 'staging'
    New-Item -Path $testShare -ItemType Directory -Force | Out-Null

    Mock Import-Module { }
    Mock Connect-JuribaAppR { }
    Mock Disconnect-JuribaAppR { }

    Context 'Single integration, single package — happy path' {

        Mock Get-JuribaAppRGenericIntegration {
            @([pscustomobject]@{ id = 3; name = 'MSIX Export' })
        }

        # API returns array of publishing IDs
        Mock Get-JuribaAppRGenericIntegrationPublishing { @(101) }

        Mock Get-JuribaAppRGenericIntegrationProperty {
            @(
                [pscustomobject]@{ propertyName = 'AppName'; propertyValue = 'TestApp' },
                [pscustomobject]@{ propertyName = 'ApplicationPackageSourceUrl'; propertyValue = 'api/v1/integration/generic/3/published-app/101/source' }
            )
        }

        Mock Get-JuribaAppRGenericIntegrationSource {
            $file = 'TestApp_1.0.0.vhdx'
            $stagingDir = (Get-Variable -Name SourcePath -ErrorAction SilentlyContinue).Value
            if (-not $stagingDir) { $stagingDir = $testStaging }
            New-Item -Path (Join-Path $stagingDir $file) -ItemType File -Force | Out-Null
            Set-Content -Path (Join-Path $stagingDir $file) -Value 'fake-vhdx-content'
            return $file
        }

        Mock Add-JuribaAppRGenericIntegrationLog { }
        Mock Update-JuribaAppRGenericIntegrationPublishingState { }

        It 'completes without error' {
            {
                & $ScriptPath `
                    -InstanceUrl 'https://test.appr.example.com' `
                    -APIKey 'test-key' `
                    -SMBSharePath $testShare `
                    -StagingPath $testStaging
            } | Should Not Throw
        }

        It 'called Connect with correct instance' {
            Assert-MockCalled Connect-JuribaAppR -Times 1 -ParameterFilter {
                $Instance -eq 'https://test.appr.example.com'
            }
        }

        It 'auto-selected the single integration' {
            Assert-MockCalled Get-JuribaAppRGenericIntegrationPublishing -Times 1 -ParameterFilter {
                $IntegrationId -eq 3
            }
        }

        It 'fetched publishing properties' {
            Assert-MockCalled Get-JuribaAppRGenericIntegrationProperty -Times 1 -ParameterFilter {
                $PublishingId -eq 101
            }
        }

        It 'downloaded the package source' {
            Assert-MockCalled Get-JuribaAppRGenericIntegrationSource -Times 1 -ParameterFilter {
                $PublishingId -eq 101
            }
        }

        It 'logged success' {
            Assert-MockCalled Add-JuribaAppRGenericIntegrationLog -Times 1 -ParameterFilter {
                $Level -eq 'Information'
            }
        }

        It 'marked publishing as Succeeded' {
            Assert-MockCalled Update-JuribaAppRGenericIntegrationPublishingState -Times 1 -ParameterFilter {
                $PublishingState -eq 'Succeeded' -and $PublishingId -eq 101
            }
        }

        It 'copied the file to the share' {
            Test-Path (Join-Path $testShare 'TestApp_1.0.0.vhdx') | Should Be $true
        }

        It 'called Disconnect' {
            Assert-MockCalled Disconnect-JuribaAppR -Times 1
        }
    }

    Context 'No packages found — early exit' {

        Mock Get-JuribaAppRGenericIntegration {
            @([pscustomobject]@{ id = 5; name = 'Empty Integration' })
        }

        Mock Get-JuribaAppRGenericIntegrationPublishing { @() }
        Mock Get-JuribaAppRGenericIntegrationProperty { }
        Mock Get-JuribaAppRGenericIntegrationSource { }
        Mock Add-JuribaAppRGenericIntegrationLog { }
        Mock Update-JuribaAppRGenericIntegrationPublishingState { }

        It 'completes without error when no packages found' {
            {
                & $ScriptPath `
                    -InstanceUrl 'https://test.appr.example.com' `
                    -APIKey 'test-key' `
                    -SMBSharePath $testShare `
                    -StagingPath (Join-Path $TestDrive 'staging2')
            } | Should Not Throw
        }

        It 'did not attempt any downloads' {
            Assert-MockCalled Get-JuribaAppRGenericIntegrationSource -Times 0
        }
    }

    Context 'Explicit IntegrationId skips listing' {

        Mock Get-JuribaAppRGenericIntegration { }
        Mock Get-JuribaAppRGenericIntegrationPublishing { @() }
        Mock Get-JuribaAppRGenericIntegrationProperty { }
        Mock Get-JuribaAppRGenericIntegrationSource { }
        Mock Add-JuribaAppRGenericIntegrationLog { }
        Mock Update-JuribaAppRGenericIntegrationPublishingState { }

        It 'does not call Get-JuribaAppRGenericIntegration when IntegrationId is given' {
            & $ScriptPath `
                -InstanceUrl 'https://test.appr.example.com' `
                -APIKey 'test-key' `
                -IntegrationId 7 `
                -SMBSharePath $testShare `
                -StagingPath (Join-Path $TestDrive 'staging3')

            Assert-MockCalled Get-JuribaAppRGenericIntegration -Times 0
        }
    }

    Context 'Download failure — marks publishing as Failed' {

        Mock Get-JuribaAppRGenericIntegration {
            @([pscustomobject]@{ id = 3; name = 'MSIX Export' })
        }

        # API returns array of publishing IDs
        Mock Get-JuribaAppRGenericIntegrationPublishing { @(202) }

        Mock Get-JuribaAppRGenericIntegrationProperty {
            @(
                [pscustomobject]@{ propertyName = 'AppName'; propertyValue = 'FailApp' }
            )
        }

        Mock Get-JuribaAppRGenericIntegrationSource { throw 'Network timeout' }
        Mock Add-JuribaAppRGenericIntegrationLog { }
        Mock Update-JuribaAppRGenericIntegrationPublishingState { }

        It 'does not throw (error is caught)' {
            {
                & $ScriptPath `
                    -InstanceUrl 'https://test.appr.example.com' `
                    -APIKey 'test-key' `
                    -SMBSharePath $testShare `
                    -StagingPath (Join-Path $TestDrive 'staging4')
            } | Should Not Throw
        }

        It 'logged the error' {
            Assert-MockCalled Add-JuribaAppRGenericIntegrationLog -Times 1 -ParameterFilter {
                $Level -eq 'Error'
            }
        }

        It 'marked publishing as Failed' {
            Assert-MockCalled Update-JuribaAppRGenericIntegrationPublishingState -Times 1 -ParameterFilter {
                $PublishingState -eq 'Failed' -and $PublishingId -eq 202
            }
        }
    }
}
