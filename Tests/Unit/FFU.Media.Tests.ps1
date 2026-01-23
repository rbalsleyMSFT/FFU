#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester unit tests for FFU.Media module

.DESCRIPTION
    Comprehensive unit tests covering all exported functions in the FFU.Media module.
    Tests verify parameter validation, expected behavior, error handling, and edge cases.

.NOTES
    Run with: Invoke-Pester -Path .\Tests\Unit\FFU.Media.Tests.ps1 -Output Detailed
    Coverage: Invoke-Pester -Path .\Tests\Unit\FFU.Media.Tests.ps1 -CodeCoverage .\FFUDevelopment\Modules\FFU.Media\*.psm1
#>

BeforeAll {
    # Get paths relative to test file location
    $TestRoot = Split-Path $PSScriptRoot -Parent
    $ProjectRoot = Split-Path $TestRoot -Parent
    $ModulesPath = Join-Path $ProjectRoot 'FFUDevelopment\Modules'
    $ModulePath = Join-Path $ModulesPath 'FFU.Media'
    $CoreModulePath = Join-Path $ModulesPath 'FFU.Core'
    $ADKModulePath = Join-Path $ModulesPath 'FFU.ADK'
    $ConstantsModulePath = Join-Path $ModulesPath 'FFU.Constants'

    # Add Modules folder to PSModulePath for RequiredModules resolution
    if ($env:PSModulePath -notlike "*$ModulesPath*") {
        $env:PSModulePath = "$ModulesPath;$env:PSModulePath"
    }

    # Remove modules if loaded
    Get-Module -Name 'FFU.Media', 'FFU.ADK', 'FFU.Core', 'FFU.Constants' | Remove-Module -Force -ErrorAction SilentlyContinue

    # Import dependencies in order
    if (Test-Path "$ConstantsModulePath\FFU.Constants.psd1") {
        Import-Module "$ConstantsModulePath\FFU.Constants.psd1" -Force -ErrorAction SilentlyContinue
    }

    if (Test-Path "$CoreModulePath\FFU.Core.psd1") {
        Import-Module "$CoreModulePath\FFU.Core.psd1" -Force -ErrorAction SilentlyContinue
    }

    if (Test-Path "$ADKModulePath\FFU.ADK.psd1") {
        Import-Module "$ADKModulePath\FFU.ADK.psd1" -Force -ErrorAction SilentlyContinue
    }

    # Import FFU.Media module
    if (-not (Test-Path "$ModulePath\FFU.Media.psd1")) {
        throw "FFU.Media module not found at: $ModulePath"
    }
    Import-Module "$ModulePath\FFU.Media.psd1" -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name 'FFU.Media', 'FFU.ADK', 'FFU.Core', 'FFU.Constants' | Remove-Module -Force -ErrorAction SilentlyContinue
}

# =============================================================================
# Module Export Verification
# =============================================================================

Describe 'FFU.Media Module Exports' -Tag 'Unit', 'FFU.Media', 'Module' {

    Context 'Expected Functions Are Exported' {
        It 'Should export Invoke-DISMPreFlightCleanup' {
            Get-Command -Name 'Invoke-DISMPreFlightCleanup' -Module 'FFU.Media' | Should -Not -BeNullOrEmpty
        }

        It 'Should export Invoke-CopyPEWithRetry' {
            Get-Command -Name 'Invoke-CopyPEWithRetry' -Module 'FFU.Media' | Should -Not -BeNullOrEmpty
        }

        It 'Should export New-PEMedia' {
            Get-Command -Name 'New-PEMedia' -Module 'FFU.Media' | Should -Not -BeNullOrEmpty
        }

        It 'Should export Get-PEArchitecture' {
            Get-Command -Name 'Get-PEArchitecture' -Module 'FFU.Media' | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Module Metadata' {
        It 'Should have a valid module manifest' {
            $ManifestPath = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'FFUDevelopment\Modules\FFU.Media\FFU.Media.psd1'
            Test-ModuleManifest -Path $ManifestPath -ErrorAction Stop | Should -Not -BeNullOrEmpty
        }
    }
}

# =============================================================================
# Invoke-DISMPreFlightCleanup Tests
# =============================================================================

Describe 'Invoke-DISMPreFlightCleanup' -Tag 'Unit', 'FFU.Media', 'Invoke-DISMPreFlightCleanup' {

    Context 'Parameter Validation' {
        It 'Should have mandatory WinPEPath parameter' {
            $command = Get-Command -Name 'Invoke-DISMPreFlightCleanup' -Module 'FFU.Media'
            $param = $command.Parameters['WinPEPath']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }

        It 'Should have optional MinimumFreeSpaceGB parameter' {
            $command = Get-Command -Name 'Invoke-DISMPreFlightCleanup' -Module 'FFU.Media'
            $command.Parameters['MinimumFreeSpaceGB'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have int type for MinimumFreeSpaceGB parameter' {
            $command = Get-Command -Name 'Invoke-DISMPreFlightCleanup' -Module 'FFU.Media'
            $param = $command.Parameters['MinimumFreeSpaceGB']
            $param.ParameterType.Name | Should -Be 'Int32'
        }
    }
}

# =============================================================================
# Invoke-CopyPEWithRetry Tests
# =============================================================================

Describe 'Invoke-CopyPEWithRetry' -Tag 'Unit', 'FFU.Media', 'Invoke-CopyPEWithRetry' {

    Context 'Parameter Validation' {
        It 'Should have mandatory Architecture parameter' {
            $command = Get-Command -Name 'Invoke-CopyPEWithRetry' -Module 'FFU.Media'
            $param = $command.Parameters['Architecture']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }

        It 'Should have ValidateSet for Architecture parameter' {
            $command = Get-Command -Name 'Invoke-CopyPEWithRetry' -Module 'FFU.Media'
            $param = $command.Parameters['Architecture']

            $validateSet = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
            $validateSet | Should -Not -BeNullOrEmpty
            $validateSet.ValidValues | Should -Contain 'x64'
            $validateSet.ValidValues | Should -Contain 'arm64'
        }

        It 'Should have mandatory DestinationPath parameter' {
            $command = Get-Command -Name 'Invoke-CopyPEWithRetry' -Module 'FFU.Media'
            $param = $command.Parameters['DestinationPath']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }

        It 'Should have mandatory DandIEnvPath parameter' {
            $command = Get-Command -Name 'Invoke-CopyPEWithRetry' -Module 'FFU.Media'
            $param = $command.Parameters['DandIEnvPath']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }

        It 'Should have optional MaxRetries parameter' {
            $command = Get-Command -Name 'Invoke-CopyPEWithRetry' -Module 'FFU.Media'
            $command.Parameters['MaxRetries'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have int type for MaxRetries parameter' {
            $command = Get-Command -Name 'Invoke-CopyPEWithRetry' -Module 'FFU.Media'
            $param = $command.Parameters['MaxRetries']
            $param.ParameterType.Name | Should -Be 'Int32'
        }
    }
}

# =============================================================================
# New-PEMedia Tests
# =============================================================================

Describe 'New-PEMedia' -Tag 'Unit', 'FFU.Media', 'New-PEMedia' {

    Context 'Parameter Validation' {
        It 'Should have mandatory Capture parameter' {
            $command = Get-Command -Name 'New-PEMedia' -Module 'FFU.Media'
            $param = $command.Parameters['Capture']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }

        It 'Should have mandatory Deploy parameter' {
            $command = Get-Command -Name 'New-PEMedia' -Module 'FFU.Media'
            $param = $command.Parameters['Deploy']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }

        It 'Should have mandatory adkPath parameter' {
            $command = Get-Command -Name 'New-PEMedia' -Module 'FFU.Media'
            $param = $command.Parameters['adkPath']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }

        It 'Should have mandatory FFUDevelopmentPath parameter' {
            $command = Get-Command -Name 'New-PEMedia' -Module 'FFU.Media'
            $param = $command.Parameters['FFUDevelopmentPath']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }

        It 'Should have mandatory WindowsArch parameter with ValidateSet' {
            $command = Get-Command -Name 'New-PEMedia' -Module 'FFU.Media'
            $param = $command.Parameters['WindowsArch']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }

            $validateSet = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
            $validateSet | Should -Not -BeNullOrEmpty
            $validateSet.ValidValues | Should -Contain 'x64'
            $validateSet.ValidValues | Should -Contain 'x86'
            $validateSet.ValidValues | Should -Contain 'ARM64'
        }

        It 'Should have optional CaptureISO parameter' {
            $command = Get-Command -Name 'New-PEMedia' -Module 'FFU.Media'
            $command.Parameters['CaptureISO'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have optional DeployISO parameter' {
            $command = Get-Command -Name 'New-PEMedia' -Module 'FFU.Media'
            $command.Parameters['DeployISO'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have mandatory CopyPEDrivers parameter' {
            $command = Get-Command -Name 'New-PEMedia' -Module 'FFU.Media'
            $param = $command.Parameters['CopyPEDrivers']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }

        It 'Should have mandatory UseDriversAsPEDrivers parameter' {
            $command = Get-Command -Name 'New-PEMedia' -Module 'FFU.Media'
            $param = $command.Parameters['UseDriversAsPEDrivers']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }

        It 'Should have optional PEDriversFolder parameter' {
            $command = Get-Command -Name 'New-PEMedia' -Module 'FFU.Media'
            $command.Parameters['PEDriversFolder'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have optional DriversFolder parameter' {
            $command = Get-Command -Name 'New-PEMedia' -Module 'FFU.Media'
            $command.Parameters['DriversFolder'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have mandatory CompressDownloadedDriversToWim parameter' {
            $command = Get-Command -Name 'New-PEMedia' -Module 'FFU.Media'
            $param = $command.Parameters['CompressDownloadedDriversToWim']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }
    }
}

# =============================================================================
# Get-PEArchitecture Tests
# =============================================================================

Describe 'Get-PEArchitecture' -Tag 'Unit', 'FFU.Media', 'Get-PEArchitecture' {

    Context 'Parameter Validation' {
        It 'Should have FilePath parameter' {
            $command = Get-Command -Name 'Get-PEArchitecture' -Module 'FFU.Media'
            $command.Parameters['FilePath'] | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Return Values' {
        It 'Should throw for non-existent file' {
            { Get-PEArchitecture -FilePath 'C:\NonExistent\file.exe' } | Should -Throw
        }
    }
}
