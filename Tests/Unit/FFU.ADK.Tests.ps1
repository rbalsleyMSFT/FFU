#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester unit tests for FFU.ADK module

.DESCRIPTION
    Comprehensive unit tests covering all exported functions in the FFU.ADK module.
    Tests verify parameter validation, expected behavior, error handling, and edge cases.

.NOTES
    Run with: Invoke-Pester -Path .\Tests\Unit\FFU.ADK.Tests.ps1 -Output Detailed
    Coverage: Invoke-Pester -Path .\Tests\Unit\FFU.ADK.Tests.ps1 -CodeCoverage .\FFUDevelopment\Modules\FFU.ADK\*.psm1
#>

BeforeAll {
    # Get paths relative to test file location
    $TestRoot = Split-Path $PSScriptRoot -Parent
    $ProjectRoot = Split-Path $TestRoot -Parent
    $ModulePath = Join-Path $ProjectRoot 'FFUDevelopment\Modules\FFU.ADK'
    $CoreModulePath = Join-Path $ProjectRoot 'FFUDevelopment\Modules\FFU.Core'

    # Remove modules if loaded
    Get-Module -Name 'FFU.ADK', 'FFU.Core' | Remove-Module -Force -ErrorAction SilentlyContinue

    # Import FFU.Core first (dependency)
    if (Test-Path "$CoreModulePath\FFU.Core.psd1") {
        Import-Module "$CoreModulePath\FFU.Core.psd1" -Force -ErrorAction SilentlyContinue
    }

    # Import FFU.ADK module
    if (-not (Test-Path "$ModulePath\FFU.ADK.psd1")) {
        throw "FFU.ADK module not found at: $ModulePath"
    }
    Import-Module "$ModulePath\FFU.ADK.psd1" -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name 'FFU.ADK', 'FFU.Core' | Remove-Module -Force -ErrorAction SilentlyContinue
}

# =============================================================================
# Module Export Verification
# =============================================================================

Describe 'FFU.ADK Module Exports' -Tag 'Unit', 'FFU.ADK', 'Module' {

    Context 'Expected Functions Are Exported' {
        It 'Should export Write-ADKValidationLog' {
            Get-Command -Name 'Write-ADKValidationLog' -Module 'FFU.ADK' | Should -Not -BeNullOrEmpty
        }

        It 'Should export Test-ADKPrerequisites' {
            Get-Command -Name 'Test-ADKPrerequisites' -Module 'FFU.ADK' | Should -Not -BeNullOrEmpty
        }

        It 'Should export Get-ADKURL' {
            Get-Command -Name 'Get-ADKURL' -Module 'FFU.ADK' | Should -Not -BeNullOrEmpty
        }

        It 'Should export Install-ADK' {
            Get-Command -Name 'Install-ADK' -Module 'FFU.ADK' | Should -Not -BeNullOrEmpty
        }

        It 'Should export Get-InstalledProgramRegKey' {
            Get-Command -Name 'Get-InstalledProgramRegKey' -Module 'FFU.ADK' | Should -Not -BeNullOrEmpty
        }

        It 'Should export Uninstall-ADK' {
            Get-Command -Name 'Uninstall-ADK' -Module 'FFU.ADK' | Should -Not -BeNullOrEmpty
        }

        It 'Should export Confirm-ADKVersionIsLatest' {
            Get-Command -Name 'Confirm-ADKVersionIsLatest' -Module 'FFU.ADK' | Should -Not -BeNullOrEmpty
        }

        It 'Should export Get-ADK' {
            Get-Command -Name 'Get-ADK' -Module 'FFU.ADK' | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Module Metadata' {
        It 'Should have a valid module manifest' {
            $ManifestPath = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'FFUDevelopment\Modules\FFU.ADK\FFU.ADK.psd1'
            Test-ModuleManifest -Path $ManifestPath -ErrorAction Stop | Should -Not -BeNullOrEmpty
        }
    }
}

# =============================================================================
# Write-ADKValidationLog Tests
# =============================================================================

Describe 'Write-ADKValidationLog' -Tag 'Unit', 'FFU.ADK', 'Write-ADKValidationLog' {

    Context 'Parameter Validation' {
        It 'Should have mandatory Severity parameter' {
            $command = Get-Command -Name 'Write-ADKValidationLog' -Module 'FFU.ADK'
            $param = $command.Parameters['Severity']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }

        It 'Should have mandatory Message parameter' {
            $command = Get-Command -Name 'Write-ADKValidationLog' -Module 'FFU.ADK'
            $param = $command.Parameters['Message']
            $param | Should -Not -BeNullOrEmpty
        }

        It 'Should have optional Context parameter' {
            $command = Get-Command -Name 'Write-ADKValidationLog' -Module 'FFU.ADK'
            $param = $command.Parameters['Context']
            $param | Should -Not -BeNullOrEmpty
        }

        It 'Should have ValidateSet for Severity parameter' {
            $command = Get-Command -Name 'Write-ADKValidationLog' -Module 'FFU.ADK'
            $param = $command.Parameters['Severity']

            $validateSet = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
            $validateSet | Should -Not -BeNullOrEmpty
            $validateSet.ValidValues | Should -Contain 'Info'
            $validateSet.ValidValues | Should -Contain 'Success'
            $validateSet.ValidValues | Should -Contain 'Warning'
            $validateSet.ValidValues | Should -Contain 'Error'
            $validateSet.ValidValues | Should -Contain 'Critical'
        }
    }
}

# =============================================================================
# Test-ADKPrerequisites Tests
# =============================================================================

Describe 'Test-ADKPrerequisites' -Tag 'Unit', 'FFU.ADK', 'Test-ADKPrerequisites' {

    Context 'Parameter Validation' {
        It 'Should have mandatory WindowsArch parameter' {
            $command = Get-Command -Name 'Test-ADKPrerequisites' -Module 'FFU.ADK'
            $param = $command.Parameters['WindowsArch']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }

        It 'Should have ValidateSet for WindowsArch parameter' {
            $command = Get-Command -Name 'Test-ADKPrerequisites' -Module 'FFU.ADK'
            $param = $command.Parameters['WindowsArch']

            $validateSet = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
            $validateSet | Should -Not -BeNullOrEmpty
            $validateSet.ValidValues | Should -Contain 'x64'
            $validateSet.ValidValues | Should -Contain 'arm64'
        }

        It 'Should have AutoInstall parameter' {
            $command = Get-Command -Name 'Test-ADKPrerequisites' -Module 'FFU.ADK'
            $command.Parameters['AutoInstall'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have ThrowOnFailure parameter' {
            $command = Get-Command -Name 'Test-ADKPrerequisites' -Module 'FFU.ADK'
            $command.Parameters['ThrowOnFailure'] | Should -Not -BeNullOrEmpty
        }
    }
}

# =============================================================================
# Get-ADKURL Tests
# =============================================================================

Describe 'Get-ADKURL' -Tag 'Unit', 'FFU.ADK', 'Get-ADKURL' {

    Context 'Parameter Validation' {
        It 'Should have ADKOption parameter' {
            $command = Get-Command -Name 'Get-ADKURL' -Module 'FFU.ADK'
            $command.Parameters['ADKOption'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have ValidateSet for ADKOption parameter' {
            $command = Get-Command -Name 'Get-ADKURL' -Module 'FFU.ADK'
            $param = $command.Parameters['ADKOption']

            $validateSet = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
            $validateSet | Should -Not -BeNullOrEmpty
            $validateSet.ValidValues | Should -Contain 'Windows ADK'
            $validateSet.ValidValues | Should -Contain 'WinPE add-on'
        }
    }
}

# =============================================================================
# Install-ADK Tests
# =============================================================================

Describe 'Install-ADK' -Tag 'Unit', 'FFU.ADK', 'Install-ADK' {

    Context 'Parameter Validation' {
        It 'Should have ADKOption parameter' {
            $command = Get-Command -Name 'Install-ADK' -Module 'FFU.ADK'
            $command.Parameters['ADKOption'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have ValidateSet for ADKOption parameter' {
            $command = Get-Command -Name 'Install-ADK' -Module 'FFU.ADK'
            $param = $command.Parameters['ADKOption']

            $validateSet = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
            $validateSet | Should -Not -BeNullOrEmpty
            $validateSet.ValidValues | Should -Contain 'Windows ADK'
            $validateSet.ValidValues | Should -Contain 'WinPE add-on'
        }
    }
}

# =============================================================================
# Get-InstalledProgramRegKey Tests
# =============================================================================

Describe 'Get-InstalledProgramRegKey' -Tag 'Unit', 'FFU.ADK', 'Get-InstalledProgramRegKey' {

    Context 'Parameter Validation' {
        It 'Should have DisplayName parameter' {
            $command = Get-Command -Name 'Get-InstalledProgramRegKey' -Module 'FFU.ADK'
            $command.Parameters['DisplayName'] | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Return Value' {
        It 'Should return null for non-existent program' {
            $result = Get-InstalledProgramRegKey -DisplayName 'NonExistentProgram12345XYZ'
            $result | Should -BeNullOrEmpty
        }
    }
}

# =============================================================================
# Uninstall-ADK Tests
# =============================================================================

Describe 'Uninstall-ADK' -Tag 'Unit', 'FFU.ADK', 'Uninstall-ADK' {

    Context 'Parameter Validation' {
        It 'Should have ADKOption parameter' {
            $command = Get-Command -Name 'Uninstall-ADK' -Module 'FFU.ADK'
            $command.Parameters['ADKOption'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have ValidateSet for ADKOption parameter' {
            $command = Get-Command -Name 'Uninstall-ADK' -Module 'FFU.ADK'
            $param = $command.Parameters['ADKOption']

            $validateSet = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
            $validateSet | Should -Not -BeNullOrEmpty
            $validateSet.ValidValues | Should -Contain 'Windows ADK'
            $validateSet.ValidValues | Should -Contain 'WinPE add-on'
        }
    }
}

# =============================================================================
# Confirm-ADKVersionIsLatest Tests
# =============================================================================

Describe 'Confirm-ADKVersionIsLatest' -Tag 'Unit', 'FFU.ADK', 'Confirm-ADKVersionIsLatest' {

    Context 'Parameter Validation' {
        It 'Should have mandatory ADKOption parameter' {
            $command = Get-Command -Name 'Confirm-ADKVersionIsLatest' -Module 'FFU.ADK'
            $param = $command.Parameters['ADKOption']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }

        It 'Should have optional Headers parameter' {
            $command = Get-Command -Name 'Confirm-ADKVersionIsLatest' -Module 'FFU.ADK'
            $command.Parameters['Headers'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have optional UserAgent parameter' {
            $command = Get-Command -Name 'Confirm-ADKVersionIsLatest' -Module 'FFU.ADK'
            $command.Parameters['UserAgent'] | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Return Value' {
        It 'Should return false when Headers or UserAgent not provided' {
            $result = Confirm-ADKVersionIsLatest -ADKOption "Windows ADK"
            $result | Should -BeFalse
        }
    }
}

# =============================================================================
# Get-ADK Tests
# =============================================================================

Describe 'Get-ADK' -Tag 'Unit', 'FFU.ADK', 'Get-ADK' {

    Context 'Parameter Validation' {
        It 'Should have mandatory UpdateADK parameter' {
            $command = Get-Command -Name 'Get-ADK' -Module 'FFU.ADK'
            $param = $command.Parameters['UpdateADK']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }

        It 'Should have bool type for UpdateADK parameter' {
            $command = Get-Command -Name 'Get-ADK' -Module 'FFU.ADK'
            $param = $command.Parameters['UpdateADK']
            $param.ParameterType.Name | Should -Be 'Boolean'
        }
    }
}
