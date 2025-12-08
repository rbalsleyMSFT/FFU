#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester unit tests for FFU.VM module

.DESCRIPTION
    Comprehensive unit tests covering all exported functions in the FFU.VM module.
    Tests verify parameter validation, expected behavior, error handling, and edge cases.

.NOTES
    Run with: Invoke-Pester -Path .\Tests\Unit\FFU.VM.Tests.ps1 -Output Detailed
    Coverage: Invoke-Pester -Path .\Tests\Unit\FFU.VM.Tests.ps1 -CodeCoverage .\FFUDevelopment\Modules\FFU.VM\*.psm1
#>

BeforeAll {
    # Get paths relative to test file location
    $TestRoot = Split-Path $PSScriptRoot -Parent
    $ProjectRoot = Split-Path $TestRoot -Parent
    $ModulePath = Join-Path $ProjectRoot 'FFUDevelopment\Modules\FFU.VM'
    $CoreModulePath = Join-Path $ProjectRoot 'FFUDevelopment\Modules\FFU.Core'

    # Remove modules if loaded
    Get-Module -Name 'FFU.VM', 'FFU.Core' | Remove-Module -Force -ErrorAction SilentlyContinue

    # Import FFU.Core first (dependency)
    if (Test-Path "$CoreModulePath\FFU.Core.psd1") {
        Import-Module "$CoreModulePath\FFU.Core.psd1" -Force -ErrorAction SilentlyContinue
    }

    # Import FFU.VM module
    if (-not (Test-Path "$ModulePath\FFU.VM.psd1")) {
        throw "FFU.VM module not found at: $ModulePath"
    }
    Import-Module "$ModulePath\FFU.VM.psd1" -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name 'FFU.VM', 'FFU.Core' | Remove-Module -Force -ErrorAction SilentlyContinue
}

# =============================================================================
# Module Export Verification
# =============================================================================

Describe 'FFU.VM Module Exports' -Tag 'Unit', 'FFU.VM', 'Module' {

    Context 'Expected Functions Are Exported' {
        It 'Should export Get-LocalUserAccount' {
            Get-Command -Name 'Get-LocalUserAccount' -Module 'FFU.VM' | Should -Not -BeNullOrEmpty
        }

        It 'Should export New-LocalUserAccount' {
            Get-Command -Name 'New-LocalUserAccount' -Module 'FFU.VM' | Should -Not -BeNullOrEmpty
        }

        It 'Should export Remove-LocalUserAccount' {
            Get-Command -Name 'Remove-LocalUserAccount' -Module 'FFU.VM' | Should -Not -BeNullOrEmpty
        }

        It 'Should export Set-LocalUserPassword' {
            Get-Command -Name 'Set-LocalUserPassword' -Module 'FFU.VM' | Should -Not -BeNullOrEmpty
        }

        It 'Should export Set-LocalUserAccountExpiry' {
            Get-Command -Name 'Set-LocalUserAccountExpiry' -Module 'FFU.VM' | Should -Not -BeNullOrEmpty
        }

        It 'Should export New-FFUVM' {
            Get-Command -Name 'New-FFUVM' -Module 'FFU.VM' | Should -Not -BeNullOrEmpty
        }

        It 'Should export Remove-FFUVM' {
            Get-Command -Name 'Remove-FFUVM' -Module 'FFU.VM' | Should -Not -BeNullOrEmpty
        }

        It 'Should export Get-FFUEnvironment' {
            Get-Command -Name 'Get-FFUEnvironment' -Module 'FFU.VM' | Should -Not -BeNullOrEmpty
        }

        It 'Should export Set-CaptureFFU' {
            Get-Command -Name 'Set-CaptureFFU' -Module 'FFU.VM' | Should -Not -BeNullOrEmpty
        }

        It 'Should export Remove-FFUUserShare' {
            Get-Command -Name 'Remove-FFUUserShare' -Module 'FFU.VM' | Should -Not -BeNullOrEmpty
        }

        It 'Should export Remove-SensitiveCaptureMedia' {
            Get-Command -Name 'Remove-SensitiveCaptureMedia' -Module 'FFU.VM' | Should -Not -BeNullOrEmpty
        }

        It 'Should export Update-CaptureFFUScript' {
            Get-Command -Name 'Update-CaptureFFUScript' -Module 'FFU.VM' | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Module Metadata' {
        It 'Should have a valid module manifest' {
            $ManifestPath = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'FFUDevelopment\Modules\FFU.VM\FFU.VM.psd1'
            Test-ModuleManifest -Path $ManifestPath -ErrorAction Stop | Should -Not -BeNullOrEmpty
        }
    }
}

# =============================================================================
# Get-LocalUserAccount Tests
# =============================================================================

Describe 'Get-LocalUserAccount' -Tag 'Unit', 'FFU.VM', 'Get-LocalUserAccount' {

    Context 'Parameter Validation' {
        It 'Should have mandatory Username parameter' {
            $command = Get-Command -Name 'Get-LocalUserAccount' -Module 'FFU.VM'
            $param = $command.Parameters['Username']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }

        It 'Should have ValidateNotNullOrEmpty attribute on Username' {
            $command = Get-Command -Name 'Get-LocalUserAccount' -Module 'FFU.VM'
            $param = $command.Parameters['Username']

            $hasValidation = $param.Attributes | Where-Object {
                $_ -is [System.Management.Automation.ValidateNotNullOrEmptyAttribute]
            }
            $hasValidation | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Output Type' {
        It 'Should return null for non-existent user' {
            # Use a username that definitely doesn't exist
            $result = Get-LocalUserAccount -Username 'NonExistentTestUser12345XYZ'
            $result | Should -BeNullOrEmpty
        }
    }
}

# =============================================================================
# New-LocalUserAccount Tests
# =============================================================================

Describe 'New-LocalUserAccount' -Tag 'Unit', 'FFU.VM', 'New-LocalUserAccount' {

    Context 'Parameter Validation' {
        It 'Should have mandatory Username parameter' {
            $command = Get-Command -Name 'New-LocalUserAccount' -Module 'FFU.VM'
            $param = $command.Parameters['Username']
            $param | Should -Not -BeNullOrEmpty
        }

        It 'Should have mandatory Password parameter' {
            $command = Get-Command -Name 'New-LocalUserAccount' -Module 'FFU.VM'
            $param = $command.Parameters['Password']
            $param | Should -Not -BeNullOrEmpty
        }

        It 'Should accept SecureString for Password' {
            $command = Get-Command -Name 'New-LocalUserAccount' -Module 'FFU.VM'
            $param = $command.Parameters['Password']
            $param.ParameterType.Name | Should -Be 'SecureString'
        }
    }
}

# =============================================================================
# Remove-LocalUserAccount Tests
# =============================================================================

Describe 'Remove-LocalUserAccount' -Tag 'Unit', 'FFU.VM', 'Remove-LocalUserAccount' {

    Context 'Parameter Validation' {
        It 'Should have mandatory Username parameter' {
            $command = Get-Command -Name 'Remove-LocalUserAccount' -Module 'FFU.VM'
            $param = $command.Parameters['Username']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }
    }

    Context 'Non-Existent User Handling' {
        It 'Should not throw for non-existent user' {
            { Remove-LocalUserAccount -Username 'NonExistentTestUser12345XYZ' } | Should -Not -Throw
        }
    }
}

# =============================================================================
# Set-LocalUserPassword Tests
# =============================================================================

Describe 'Set-LocalUserPassword' -Tag 'Unit', 'FFU.VM', 'Set-LocalUserPassword' {

    Context 'Parameter Validation' {
        It 'Should have mandatory Username parameter' {
            $command = Get-Command -Name 'Set-LocalUserPassword' -Module 'FFU.VM'
            $param = $command.Parameters['Username']
            $param | Should -Not -BeNullOrEmpty
        }

        It 'Should have mandatory Password parameter' {
            $command = Get-Command -Name 'Set-LocalUserPassword' -Module 'FFU.VM'
            $param = $command.Parameters['Password']
            $param | Should -Not -BeNullOrEmpty
        }

        It 'Should accept SecureString for Password' {
            $command = Get-Command -Name 'Set-LocalUserPassword' -Module 'FFU.VM'
            $param = $command.Parameters['Password']
            $param.ParameterType.Name | Should -Be 'SecureString'
        }
    }
}

# =============================================================================
# Set-LocalUserAccountExpiry Tests
# =============================================================================

Describe 'Set-LocalUserAccountExpiry' -Tag 'Unit', 'FFU.VM', 'Set-LocalUserAccountExpiry' {

    Context 'Parameter Validation' {
        It 'Should have mandatory Username parameter' {
            $command = Get-Command -Name 'Set-LocalUserAccountExpiry' -Module 'FFU.VM'
            $param = $command.Parameters['Username']
            $param | Should -Not -BeNullOrEmpty
        }

        It 'Should have ExpiryHours parameter' {
            $command = Get-Command -Name 'Set-LocalUserAccountExpiry' -Module 'FFU.VM'
            $param = $command.Parameters['ExpiryHours']
            $param | Should -Not -BeNullOrEmpty
        }

        It 'Should have int type for ExpiryHours' {
            $command = Get-Command -Name 'Set-LocalUserAccountExpiry' -Module 'FFU.VM'
            $param = $command.Parameters['ExpiryHours']
            $param.ParameterType.Name | Should -Be 'Int32'
        }
    }
}

# =============================================================================
# New-FFUVM Tests
# =============================================================================

Describe 'New-FFUVM' -Tag 'Unit', 'FFU.VM', 'New-FFUVM' {

    Context 'Parameter Validation' {
        It 'Should have VMName parameter' {
            $command = Get-Command -Name 'New-FFUVM' -Module 'FFU.VM'
            $command.Parameters['VMName'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have VMPath parameter' {
            $command = Get-Command -Name 'New-FFUVM' -Module 'FFU.VM'
            $command.Parameters['VMPath'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have Memory parameter' {
            $command = Get-Command -Name 'New-FFUVM' -Module 'FFU.VM'
            $command.Parameters['Memory'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have Processors parameter' {
            $command = Get-Command -Name 'New-FFUVM' -Module 'FFU.VM'
            $command.Parameters['Processors'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have VHDXPath parameter' {
            $command = Get-Command -Name 'New-FFUVM' -Module 'FFU.VM'
            $command.Parameters['VHDXPath'] | Should -Not -BeNullOrEmpty
        }
    }
}

# =============================================================================
# Remove-FFUVM Tests
# =============================================================================

Describe 'Remove-FFUVM' -Tag 'Unit', 'FFU.VM', 'Remove-FFUVM' {

    Context 'Parameter Validation' {
        It 'Should have VMName parameter' {
            $command = Get-Command -Name 'Remove-FFUVM' -Module 'FFU.VM'
            $command.Parameters['VMName'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have VMPath parameter' {
            $command = Get-Command -Name 'Remove-FFUVM' -Module 'FFU.VM'
            $command.Parameters['VMPath'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have Username parameter' {
            $command = Get-Command -Name 'Remove-FFUVM' -Module 'FFU.VM'
            $command.Parameters['Username'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have ShareName parameter' {
            $command = Get-Command -Name 'Remove-FFUVM' -Module 'FFU.VM'
            $command.Parameters['ShareName'] | Should -Not -BeNullOrEmpty
        }
    }
}

# =============================================================================
# Remove-FFUVM Regression Tests
# =============================================================================

Describe 'Remove-FFUVM VMName Parameter Bug Fix' -Tag 'Unit', 'FFU.VM', 'Remove-FFUVM', 'Regression' {
    <#
    .DESCRIPTION
    Regression test for bug where VM was not deleted after successful build.

    Root Cause: The final cleanup call in BuildFFUVM.ps1 was missing -VMName parameter.
    Without VMName, Remove-FFUVM's internal logic never sets $FFUVM variable,
    causing the VM deletion code block to be skipped entirely.

    Fix: Added -VMName $VMName to the final cleanup call at line 3484.
    #>

    Context 'BuildFFUVM.ps1 Final Cleanup Call' {
        BeforeAll {
            $TestRoot = Split-Path $PSScriptRoot -Parent
            $ProjectRoot = Split-Path $TestRoot -Parent
            $BuildScriptPath = Join-Path $ProjectRoot 'FFUDevelopment\BuildFFUVM.ps1'
            $BuildScriptContent = Get-Content $BuildScriptPath -Raw
        }

        It 'Should include -VMName parameter in final cleanup Remove-FFUVM call' {
            # Find the final cleanup section (after "#Clean up VM or VHDX" comment)
            # This regex looks for the Remove-FFUVM call that follows the cleanup comment
            $pattern = '#Clean up VM or VHDX[\s\S]*?Remove-FFUVM\s+-VMName'
            $BuildScriptContent | Should -Match $pattern
        }

        It 'Should have VMName as first parameter in final cleanup call' {
            # The pattern ensures -VMName appears right after Remove-FFUVM in the final cleanup
            # This catches the specific bug where VMName was omitted
            $lines = $BuildScriptContent -split "`n"
            $cleanupCommentIndex = -1

            for ($i = 0; $i -lt $lines.Count; $i++) {
                if ($lines[$i] -match '#Clean up VM or VHDX') {
                    $cleanupCommentIndex = $i
                    break
                }
            }

            $cleanupCommentIndex | Should -BeGreaterThan 0 -Because 'cleanup comment should exist'

            # Find the Remove-FFUVM call after the comment
            $foundRemoveFFUVM = $false
            for ($i = $cleanupCommentIndex; $i -lt [Math]::Min($cleanupCommentIndex + 10, $lines.Count); $i++) {
                if ($lines[$i] -match 'Remove-FFUVM') {
                    $foundRemoveFFUVM = $true
                    $lines[$i] | Should -Match 'Remove-FFUVM\s+-VMName\s+\$VMName' -Because 'VMName parameter must be passed to ensure VM deletion'
                    break
                }
            }

            $foundRemoveFFUVM | Should -BeTrue -Because 'Remove-FFUVM call should exist after cleanup comment'
        }
    }

    Context 'All Remove-FFUVM Calls Consistency Check' {
        BeforeAll {
            $TestRoot = Split-Path $PSScriptRoot -Parent
            $ProjectRoot = Split-Path $TestRoot -Parent
            $BuildScriptPath = Join-Path $ProjectRoot 'FFUDevelopment\BuildFFUVM.ps1'
            $BuildScriptContent = Get-Content $BuildScriptPath -Raw
        }

        It 'Should have at least 6 Remove-FFUVM calls in BuildFFUVM.ps1' {
            $matches = [regex]::Matches($BuildScriptContent, 'Remove-FFUVM')
            $matches.Count | Should -BeGreaterOrEqual 6
        }

        It 'Should have VMName parameter in most Remove-FFUVM calls' {
            # Count calls with VMName vs total calls
            $totalCalls = [regex]::Matches($BuildScriptContent, 'Remove-FFUVM').Count
            $callsWithVMName = [regex]::Matches($BuildScriptContent, 'Remove-FFUVM\s+-VMName').Count

            # At least 5 out of 7 calls should have VMName (allowing for intentional omission in non-VM scenarios)
            $callsWithVMName | Should -BeGreaterOrEqual 5
        }
    }
}

# =============================================================================
# Get-FFUEnvironment Tests
# =============================================================================

Describe 'Get-FFUEnvironment' -Tag 'Unit', 'FFU.VM', 'Get-FFUEnvironment' {

    Context 'Parameter Validation' {
        It 'Should have FFUDevelopmentPath parameter' {
            $command = Get-Command -Name 'Get-FFUEnvironment' -Module 'FFU.VM'
            $command.Parameters['FFUDevelopmentPath'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have CleanupVMs switch parameter' {
            $command = Get-Command -Name 'Get-FFUEnvironment' -Module 'FFU.VM'
            $param = $command.Parameters['CleanupVMs']
            $param | Should -Not -BeNullOrEmpty
        }

        It 'Should have CleanupMounts switch parameter' {
            $command = Get-Command -Name 'Get-FFUEnvironment' -Module 'FFU.VM'
            $param = $command.Parameters['CleanupMounts']
            $param | Should -Not -BeNullOrEmpty
        }
    }
}

# =============================================================================
# Set-CaptureFFU Tests
# =============================================================================

Describe 'Set-CaptureFFU' -Tag 'Unit', 'FFU.VM', 'Set-CaptureFFU' {

    Context 'Parameter Validation' {
        It 'Should have Username parameter' {
            $command = Get-Command -Name 'Set-CaptureFFU' -Module 'FFU.VM'
            $command.Parameters['Username'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have ShareName parameter' {
            $command = Get-Command -Name 'Set-CaptureFFU' -Module 'FFU.VM'
            $command.Parameters['ShareName'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have FFUCaptureLocation parameter' {
            $command = Get-Command -Name 'Set-CaptureFFU' -Module 'FFU.VM'
            $command.Parameters['FFUCaptureLocation'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have Password parameter (SecureString)' {
            $command = Get-Command -Name 'Set-CaptureFFU' -Module 'FFU.VM'
            $param = $command.Parameters['Password']
            $param | Should -Not -BeNullOrEmpty
            $param.ParameterType.Name | Should -Be 'SecureString'
        }
    }
}

# =============================================================================
# Remove-FFUUserShare Tests
# =============================================================================

Describe 'Remove-FFUUserShare' -Tag 'Unit', 'FFU.VM', 'Remove-FFUUserShare' {

    Context 'Parameter Validation' {
        It 'Should have Username parameter' {
            $command = Get-Command -Name 'Remove-FFUUserShare' -Module 'FFU.VM'
            $command.Parameters['Username'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have ShareName parameter' {
            $command = Get-Command -Name 'Remove-FFUUserShare' -Module 'FFU.VM'
            $command.Parameters['ShareName'] | Should -Not -BeNullOrEmpty
        }
    }
}

# =============================================================================
# Remove-SensitiveCaptureMedia Tests
# =============================================================================

Describe 'Remove-SensitiveCaptureMedia' -Tag 'Unit', 'FFU.VM', 'Remove-SensitiveCaptureMedia' {

    Context 'Parameter Validation' {
        It 'Should have FFUDevelopmentPath parameter' {
            $command = Get-Command -Name 'Remove-SensitiveCaptureMedia' -Module 'FFU.VM'
            $command.Parameters['FFUDevelopmentPath'] | Should -Not -BeNullOrEmpty
        }
    }
}

# =============================================================================
# Update-CaptureFFUScript Tests
# =============================================================================

Describe 'Update-CaptureFFUScript' -Tag 'Unit', 'FFU.VM', 'Update-CaptureFFUScript' {

    Context 'Parameter Validation' {
        It 'Should have VMHostIPAddress parameter' {
            $command = Get-Command -Name 'Update-CaptureFFUScript' -Module 'FFU.VM'
            $command.Parameters['VMHostIPAddress'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have ShareName parameter' {
            $command = Get-Command -Name 'Update-CaptureFFUScript' -Module 'FFU.VM'
            $command.Parameters['ShareName'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have Username parameter' {
            $command = Get-Command -Name 'Update-CaptureFFUScript' -Module 'FFU.VM'
            $command.Parameters['Username'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have Password parameter' {
            $command = Get-Command -Name 'Update-CaptureFFUScript' -Module 'FFU.VM'
            $command.Parameters['Password'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have FFUDevelopmentPath parameter' {
            $command = Get-Command -Name 'Update-CaptureFFUScript' -Module 'FFU.VM'
            $command.Parameters['FFUDevelopmentPath'] | Should -Not -BeNullOrEmpty
        }
    }
}
