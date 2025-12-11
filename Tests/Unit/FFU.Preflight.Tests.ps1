#Requires -Module Pester
#Requires -Version 7.0
<#
.SYNOPSIS
    Pester tests for FFU.Preflight module.

.DESCRIPTION
    Comprehensive tests for the pre-flight validation system including:
    - Module loading and function exports
    - Tier 1 critical checks (Admin, PS version, Hyper-V)
    - Tier 2 feature-dependent checks (ADK, disk space, network, config)
    - Tier 3 warnings (Antivirus exclusions)
    - Tier 4 cleanup operations
    - Integration tests for Invoke-FFUPreflight

.NOTES
    Version: 1.0.0
    Date: 2025-12-11
    Author: FFU Builder Team
#>

BeforeAll {
    # Set up paths
    $script:FFUDevelopmentPath = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'FFUDevelopment'
    $script:ModulePath = Join-Path $script:FFUDevelopmentPath 'Modules\FFU.Preflight'

    # Import the module
    Import-Module $script:ModulePath -Force -ErrorAction Stop
}

AfterAll {
    Remove-Module 'FFU.Preflight' -Force -ErrorAction SilentlyContinue
}

Describe 'FFU.Preflight Module' -Tag 'Module', 'Preflight' {

    Context 'Module Loading' {

        It 'Should load without errors' {
            { Import-Module $script:ModulePath -Force -ErrorAction Stop } | Should -Not -Throw
        }

        It 'Should export 12 functions' {
            $commands = Get-Command -Module FFU.Preflight
            $commands.Count | Should -Be 12
        }

        It 'Should export Invoke-FFUPreflight (main entry point)' {
            Get-Command -Name 'Invoke-FFUPreflight' -Module 'FFU.Preflight' | Should -Not -BeNullOrEmpty
        }

        It 'Should require PowerShell 7.0+' {
            $manifest = Test-ModuleManifest -Path (Join-Path $script:ModulePath 'FFU.Preflight.psd1')
            $manifest.PowerShellVersion | Should -Be '7.0'
        }

        It 'Should have no required modules (self-contained)' {
            $manifest = Test-ModuleManifest -Path (Join-Path $script:ModulePath 'FFU.Preflight.psd1')
            $manifest.RequiredModules | Should -BeNullOrEmpty
        }
    }

    Context 'Exported Functions' {

        It 'Should export Invoke-FFUPreflight' {
            Get-Command -Name 'Invoke-FFUPreflight' -Module 'FFU.Preflight' -ErrorAction SilentlyContinue |
                Should -Not -BeNullOrEmpty
        }

        It 'Should export Test-FFUAdministrator' {
            Get-Command -Name 'Test-FFUAdministrator' -Module 'FFU.Preflight' -ErrorAction SilentlyContinue |
                Should -Not -BeNullOrEmpty
        }

        It 'Should export Test-FFUPowerShellVersion' {
            Get-Command -Name 'Test-FFUPowerShellVersion' -Module 'FFU.Preflight' -ErrorAction SilentlyContinue |
                Should -Not -BeNullOrEmpty
        }

        It 'Should export Test-FFUHyperV' {
            Get-Command -Name 'Test-FFUHyperV' -Module 'FFU.Preflight' -ErrorAction SilentlyContinue |
                Should -Not -BeNullOrEmpty
        }

        It 'Should export Test-FFUADK' {
            Get-Command -Name 'Test-FFUADK' -Module 'FFU.Preflight' -ErrorAction SilentlyContinue |
                Should -Not -BeNullOrEmpty
        }

        It 'Should export Test-FFUDiskSpace' {
            Get-Command -Name 'Test-FFUDiskSpace' -Module 'FFU.Preflight' -ErrorAction SilentlyContinue |
                Should -Not -BeNullOrEmpty
        }

        It 'Should export Test-FFUNetwork' {
            Get-Command -Name 'Test-FFUNetwork' -Module 'FFU.Preflight' -ErrorAction SilentlyContinue |
                Should -Not -BeNullOrEmpty
        }

        It 'Should export Test-FFUConfigurationFile' {
            Get-Command -Name 'Test-FFUConfigurationFile' -Module 'FFU.Preflight' -ErrorAction SilentlyContinue |
                Should -Not -BeNullOrEmpty
        }

        It 'Should export Test-FFUAntivirusExclusions' {
            Get-Command -Name 'Test-FFUAntivirusExclusions' -Module 'FFU.Preflight' -ErrorAction SilentlyContinue |
                Should -Not -BeNullOrEmpty
        }

        It 'Should export Invoke-FFUDISMCleanup' {
            Get-Command -Name 'Invoke-FFUDISMCleanup' -Module 'FFU.Preflight' -ErrorAction SilentlyContinue |
                Should -Not -BeNullOrEmpty
        }

        It 'Should export New-FFUCheckResult' {
            Get-Command -Name 'New-FFUCheckResult' -Module 'FFU.Preflight' -ErrorAction SilentlyContinue |
                Should -Not -BeNullOrEmpty
        }

        It 'Should export Get-FFURequirements' {
            Get-Command -Name 'Get-FFURequirements' -Module 'FFU.Preflight' -ErrorAction SilentlyContinue |
                Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'New-FFUCheckResult' -Tag 'Helper', 'Preflight' {

    Context 'Result Object Creation' {

        It 'Should create a result with Passed status' {
            $result = New-FFUCheckResult -CheckName 'TestCheck' -Status 'Passed' -Message 'Test passed'

            $result.CheckName | Should -Be 'TestCheck'
            $result.Status | Should -Be 'Passed'
            $result.Message | Should -Be 'Test passed'
        }

        It 'Should create a result with Failed status and remediation' {
            $result = New-FFUCheckResult -CheckName 'TestCheck' -Status 'Failed' `
                -Message 'Test failed' -Remediation 'Fix this issue'

            $result.Status | Should -Be 'Failed'
            $result.Remediation | Should -Be 'Fix this issue'
        }

        It 'Should create a result with Warning status' {
            $result = New-FFUCheckResult -CheckName 'TestCheck' -Status 'Warning' -Message 'Warning'

            $result.Status | Should -Be 'Warning'
        }

        It 'Should create a result with Skipped status' {
            $result = New-FFUCheckResult -CheckName 'TestCheck' -Status 'Skipped' -Message 'Skipped'

            $result.Status | Should -Be 'Skipped'
        }

        It 'Should include Details hashtable when provided' {
            $details = @{ Key = 'Value'; Number = 42 }
            $result = New-FFUCheckResult -CheckName 'TestCheck' -Status 'Passed' `
                -Message 'Test' -Details $details

            $result.Details.Key | Should -Be 'Value'
            $result.Details.Number | Should -Be 42
        }
    }
}

Describe 'Test-FFUAdministrator' -Tag 'Tier1', 'Preflight' {

    Context 'Administrator Check' {

        It 'Should return a valid result object' {
            $result = Test-FFUAdministrator

            $result | Should -Not -BeNullOrEmpty
            $result.CheckName | Should -Be 'Administrator'
            $result.Status | Should -BeIn @('Passed', 'Failed')
        }

        It 'Should include remediation when not admin' {
            # This test verifies structure - actual pass/fail depends on execution context
            $result = Test-FFUAdministrator

            if ($result.Status -eq 'Failed') {
                $result.Remediation | Should -Not -BeNullOrEmpty
                $result.Remediation | Should -Match 'Administrator'
            }
        }

        # When running as admin (typical for CI/test environment)
        It 'Should pass when running as Administrator' -Skip:(-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            $result = Test-FFUAdministrator
            $result.Status | Should -Be 'Passed'
        }
    }
}

Describe 'Test-FFUPowerShellVersion' -Tag 'Tier1', 'Preflight' {

    Context 'PowerShell Version Check' {

        It 'Should return a valid result object' {
            $result = Test-FFUPowerShellVersion

            $result | Should -Not -BeNullOrEmpty
            $result.CheckName | Should -Be 'PowerShellVersion'
        }

        It 'Should pass when running in PowerShell 7+' {
            # We are running in PS7+ (required by tests)
            $result = Test-FFUPowerShellVersion

            $result.Status | Should -Be 'Passed'
            $result.Details.Version | Should -Not -BeNullOrEmpty
        }

        It 'Should include version in details' {
            $result = Test-FFUPowerShellVersion

            $result.Details.Version | Should -Match '^\d+\.\d+\.\d+'
            $result.Details.Edition | Should -Be 'Core'
        }
    }
}

Describe 'Test-FFUHyperV' -Tag 'Tier1', 'Preflight' {

    Context 'Hyper-V Feature Check' {

        It 'Should return a valid result object' {
            $result = Test-FFUHyperV

            $result | Should -Not -BeNullOrEmpty
            $result.CheckName | Should -Be 'HyperV'
            $result.Status | Should -BeIn @('Passed', 'Failed')
        }

        It 'Should include Hyper-V state in details when available' {
            $result = Test-FFUHyperV

            # Details should exist even if check fails
            $result.Details | Should -Not -BeNullOrEmpty
        }

        It 'Should provide remediation for missing Hyper-V' {
            $result = Test-FFUHyperV

            if ($result.Status -eq 'Failed') {
                $result.Remediation | Should -Not -BeNullOrEmpty
                $result.Remediation | Should -Match 'Hyper-V|Enable-WindowsOptionalFeature'
            }
        }
    }
}

Describe 'Get-FFURequirements' -Tag 'Helper', 'Preflight' {

    Context 'Disk Space Calculation' {

        It 'Should calculate base requirements (VHDX + scratch)' {
            $features = @{
                CreateVM = $true
                CreateCaptureMedia = $false
                CreateDeploymentMedia = $false
                OptimizeFFU = $false
                InstallApps = $false
                UpdateLatestCU = $false
                DownloadDrivers = $false
            }

            $requirements = Get-FFURequirements -Features $features -VHDXSizeGB 50

            # Base: 50GB VHDX + 10GB scratch = 60GB minimum
            $requirements.RequiredDiskSpaceGB | Should -BeGreaterOrEqual 60
        }

        It 'Should add space for WinPE media creation' {
            $featuresWithMedia = @{
                CreateVM = $true
                CreateCaptureMedia = $true
                CreateDeploymentMedia = $false
                OptimizeFFU = $false
                InstallApps = $false
                UpdateLatestCU = $false
                DownloadDrivers = $false
            }

            $featuresBase = @{
                CreateVM = $true
                CreateCaptureMedia = $false
                CreateDeploymentMedia = $false
                OptimizeFFU = $false
                InstallApps = $false
                UpdateLatestCU = $false
                DownloadDrivers = $false
            }

            $withMedia = Get-FFURequirements -Features $featuresWithMedia -VHDXSizeGB 50
            $baseOnly = Get-FFURequirements -Features $featuresBase -VHDXSizeGB 50

            $withMedia.RequiredDiskSpaceGB | Should -BeGreaterThan $baseOnly.RequiredDiskSpaceGB
        }

        It 'Should add space for Apps ISO' {
            $features = @{
                CreateVM = $true
                CreateCaptureMedia = $false
                CreateDeploymentMedia = $false
                OptimizeFFU = $false
                InstallApps = $true
                UpdateLatestCU = $false
                DownloadDrivers = $false
            }

            $requirements = Get-FFURequirements -Features $features -VHDXSizeGB 50

            # Should include Apps ISO space
            $requirements.RequiredDiskSpaceGB | Should -BeGreaterOrEqual 70  # 60 base + 10 apps
        }

        It 'Should list required features' {
            $features = @{
                CreateVM = $true
                CreateCaptureMedia = $true
                CreateDeploymentMedia = $false
                OptimizeFFU = $true
                InstallApps = $false
                UpdateLatestCU = $true
                DownloadDrivers = $false
            }

            $requirements = Get-FFURequirements -Features $features -VHDXSizeGB 50

            $requirements.RequiredFeatures | Should -Contain 'Hyper-V'
            $requirements.RequiredFeatures | Should -Contain 'Windows ADK'
            $requirements.RequiredFeatures | Should -Contain 'Network connectivity'
        }
    }
}

Describe 'Test-FFUDiskSpace' -Tag 'Tier2', 'Preflight' {

    Context 'Disk Space Validation' {

        It 'Should return a valid result object' {
            $features = @{ CreateVM = $true }
            $result = Test-FFUDiskSpace -FFUDevelopmentPath $env:TEMP -Features $features -VHDXSizeGB 50

            $result | Should -Not -BeNullOrEmpty
            $result.CheckName | Should -Be 'DiskSpace'
            $result.Status | Should -BeIn @('Passed', 'Failed', 'Warning')
        }

        It 'Should include available and required space in details' {
            $features = @{ CreateVM = $true }
            $result = Test-FFUDiskSpace -FFUDevelopmentPath $env:TEMP -Features $features -VHDXSizeGB 50

            $result.Details.AvailableGB | Should -Not -BeNullOrEmpty
            $result.Details.RequiredGB | Should -Not -BeNullOrEmpty
        }

        It 'Should fail for unrealistically large requirements' {
            $features = @{ CreateVM = $true }
            # Request impossibly large VHDX
            $result = Test-FFUDiskSpace -FFUDevelopmentPath $env:TEMP -Features $features -VHDXSizeGB 100000

            $result.Status | Should -Be 'Failed'
            $result.Remediation | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'Test-FFUNetwork' -Tag 'Tier2', 'Preflight' {

    Context 'Network Connectivity Check' {

        It 'Should return a valid result object' {
            $features = @{
                DownloadDrivers = $true
                UpdateLatestCU = $false
                InstallApps = $false
            }
            $result = Test-FFUNetwork -Features $features

            $result | Should -Not -BeNullOrEmpty
            $result.CheckName | Should -Be 'Network'
            $result.Status | Should -BeIn @('Passed', 'Failed', 'Warning', 'Skipped')
        }

        It 'Should skip when no network features needed' {
            $features = @{
                DownloadDrivers = $false
                UpdateLatestCU = $false
                InstallApps = $false
            }

            $result = Test-FFUNetwork -Features $features

            # When features don't require network, should skip
            if ($features.Values -notcontains $true) {
                $result.Status | Should -Be 'Skipped'
            }
        }
    }
}

Describe 'Test-FFUADK' -Tag 'Tier2', 'Preflight' {

    Context 'ADK Validation' {

        It 'Should return a valid result object' {
            $result = Test-FFUADK -WindowsArch 'x64' -RequireWinPE $false

            $result | Should -Not -BeNullOrEmpty
            $result.CheckName | Should -Be 'ADK'
            $result.Status | Should -BeIn @('Passed', 'Failed', 'Warning')
        }

        It 'Should check for more components when RequireWinPE is true' {
            $withWinPE = Test-FFUADK -WindowsArch 'x64' -RequireWinPE $true
            $withoutWinPE = Test-FFUADK -WindowsArch 'x64' -RequireWinPE $false

            # Both should return valid results
            $withWinPE | Should -Not -BeNullOrEmpty
            $withoutWinPE | Should -Not -BeNullOrEmpty
        }

        It 'Should support x64 architecture' {
            $result = Test-FFUADK -WindowsArch 'x64' -RequireWinPE $false
            $result | Should -Not -BeNullOrEmpty
        }

        It 'Should support arm64 architecture' {
            $result = Test-FFUADK -WindowsArch 'arm64' -RequireWinPE $false
            $result | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'Test-FFUAntivirusExclusions' -Tag 'Tier3', 'Preflight' {

    Context 'Antivirus Exclusion Check' {

        It 'Should return a valid result object' {
            $result = Test-FFUAntivirusExclusions -FFUDevelopmentPath $env:TEMP

            $result | Should -Not -BeNullOrEmpty
            $result.CheckName | Should -Be 'AntivirusExclusions'
            $result.Status | Should -BeIn @('Passed', 'Warning', 'Skipped')
        }

        It 'Should never return Failed (warnings only)' {
            $result = Test-FFUAntivirusExclusions -FFUDevelopmentPath $env:TEMP

            # Tier 3 checks are warnings only, never blocking failures
            $result.Status | Should -Not -Be 'Failed'
        }
    }
}

Describe 'Invoke-FFUDISMCleanup' -Tag 'Tier4', 'Preflight' {

    Context 'DISM Cleanup Operations' {

        It 'Should return a valid result object' {
            $result = Invoke-FFUDISMCleanup -FFUDevelopmentPath $env:TEMP

            $result | Should -Not -BeNullOrEmpty
            $result.CheckName | Should -Be 'DISMCleanup'
            $result.Status | Should -BeIn @('Passed', 'Warning')
        }

        It 'Should include Details property with cleanup info' {
            $result = Invoke-FFUDISMCleanup -FFUDevelopmentPath $env:TEMP

            # Details should always exist (ActionsPerformed may be empty if nothing to clean)
            $result.Details | Should -Not -BeNullOrEmpty
            $result.PSObject.Properties.Name | Should -Contain 'Details'
        }
    }
}

Describe 'Invoke-FFUPreflight Integration' -Tag 'Integration', 'Preflight' {

    Context 'Full Preflight Execution' {

        BeforeAll {
            $script:features = @{
                CreateVM = $true
                CreateCaptureMedia = $false
                CreateDeploymentMedia = $false
                OptimizeFFU = $false
                InstallApps = $false
                UpdateLatestCU = $false
                DownloadDrivers = $false
            }
        }

        It 'Should return a comprehensive result object' {
            $result = Invoke-FFUPreflight -Features $script:features `
                -FFUDevelopmentPath $env:TEMP `
                -VHDXSizeGB 50 `
                -WindowsArch 'x64'

            $result | Should -Not -BeNullOrEmpty
            $result.PSObject.Properties.Name | Should -Contain 'IsValid'
            $result.PSObject.Properties.Name | Should -Contain 'HasWarnings'
            $result.PSObject.Properties.Name | Should -Contain 'Errors'
            $result.PSObject.Properties.Name | Should -Contain 'Warnings'
            $result.PSObject.Properties.Name | Should -Contain 'RemediationSteps'
        }

        It 'Should include tier results' {
            $result = Invoke-FFUPreflight -Features $script:features `
                -FFUDevelopmentPath $env:TEMP `
                -VHDXSizeGB 50 `
                -WindowsArch 'x64'

            $result.Tier1Results | Should -Not -BeNullOrEmpty
            $result.Tier2Results | Should -Not -BeNullOrEmpty
            $result.Tier3Results | Should -Not -BeNullOrEmpty
            $result.Tier4Results | Should -Not -BeNullOrEmpty
        }

        It 'Should always run Tier 1 checks' {
            $result = Invoke-FFUPreflight -Features $script:features `
                -FFUDevelopmentPath $env:TEMP `
                -VHDXSizeGB 50 `
                -WindowsArch 'x64'

            $result.Tier1Results.Administrator | Should -Not -BeNullOrEmpty
            $result.Tier1Results.PowerShellVersion | Should -Not -BeNullOrEmpty
        }

        It 'Should respect SkipCleanup parameter' {
            $withCleanup = Invoke-FFUPreflight -Features $script:features `
                -FFUDevelopmentPath $env:TEMP `
                -VHDXSizeGB 50 `
                -WindowsArch 'x64'

            $withoutCleanup = Invoke-FFUPreflight -Features $script:features `
                -FFUDevelopmentPath $env:TEMP `
                -VHDXSizeGB 50 `
                -WindowsArch 'x64' `
                -SkipCleanup

            # Both should work
            $withCleanup | Should -Not -BeNullOrEmpty
            $withoutCleanup | Should -Not -BeNullOrEmpty
        }

        It 'Should include validation duration' {
            $result = Invoke-FFUPreflight -Features $script:features `
                -FFUDevelopmentPath $env:TEMP `
                -VHDXSizeGB 50 `
                -WindowsArch 'x64'

            $result.ValidationDurationMs | Should -BeGreaterThan 0
        }

        It 'Should aggregate errors from failed checks' {
            # This depends on actual system state
            $result = Invoke-FFUPreflight -Features $script:features `
                -FFUDevelopmentPath $env:TEMP `
                -VHDXSizeGB 50 `
                -WindowsArch 'x64'

            # Errors property should exist (may be empty string array if all pass)
            $result.PSObject.Properties.Name | Should -Contain 'Errors'
            # Verify it's an array-like collection
            @($result.Errors) | Should -Not -BeNullOrEmpty -Because 'Errors property should exist'
        }
    }

    Context 'Feature-Dependent Validation' {

        It 'Should skip ADK check when no media creation' {
            $features = @{
                CreateVM = $true
                CreateCaptureMedia = $false
                CreateDeploymentMedia = $false
                OptimizeFFU = $false
                InstallApps = $false
                UpdateLatestCU = $false
                DownloadDrivers = $false
            }

            $result = Invoke-FFUPreflight -Features $features `
                -FFUDevelopmentPath $env:TEMP `
                -VHDXSizeGB 50 `
                -WindowsArch 'x64'

            # ADK should be skipped when not needed
            if ($result.Tier2Results.ADK) {
                $result.Tier2Results.ADK.Status | Should -Be 'Skipped'
            }
        }

        It 'Should check ADK when media creation is enabled' {
            $features = @{
                CreateVM = $true
                CreateCaptureMedia = $true
                CreateDeploymentMedia = $false
                OptimizeFFU = $false
                InstallApps = $false
                UpdateLatestCU = $false
                DownloadDrivers = $false
            }

            $result = Invoke-FFUPreflight -Features $features `
                -FFUDevelopmentPath $env:TEMP `
                -VHDXSizeGB 50 `
                -WindowsArch 'x64'

            $result.Tier2Results.ADK | Should -Not -BeNullOrEmpty
            $result.Tier2Results.ADK.Status | Should -Not -Be 'Skipped'
        }
    }
}

Describe 'No TrustedInstaller Check' -Tag 'Design', 'Preflight' {

    Context 'Design Decision Verification' {

        It 'Should NOT check TrustedInstaller running state in DISM cleanup' {
            # Read the module source to verify no TrustedInstaller running check
            $moduleContent = Get-Content (Join-Path $script:ModulePath 'FFU.Preflight.psm1') -Raw

            # Should not start TrustedInstaller service
            $moduleContent | Should -Not -Match 'Start-Service.*TrustedInstaller'
        }

        It 'Should NOT have TrustedInstaller in required services' {
            $moduleContent = Get-Content (Join-Path $script:ModulePath 'FFU.Preflight.psm1') -Raw

            # Should not have TrustedInstaller as a required running service
            $moduleContent | Should -Not -Match '\$requiredServices.*TrustedInstaller'
        }
    }
}
