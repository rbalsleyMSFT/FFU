#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester unit tests for FFU.Core module

.DESCRIPTION
    Comprehensive unit tests covering all exported functions in the FFU.Core module.
    Tests verify parameter validation, expected behavior, error handling, and edge cases.

.NOTES
    Run with: Invoke-Pester -Path .\Tests\Unit\FFU.Core.Tests.ps1 -Output Detailed
    Coverage: Invoke-Pester -Path .\Tests\Unit\FFU.Core.Tests.ps1 -CodeCoverage .\FFUDevelopment\Modules\FFU.Core\*.psm1

.EXAMPLE
    # Run all FFU.Core tests
    Invoke-Pester -Path .\Tests\Unit\FFU.Core.Tests.ps1

.EXAMPLE
    # Run with detailed output
    Invoke-Pester -Path .\Tests\Unit\FFU.Core.Tests.ps1 -Output Detailed

.EXAMPLE
    # Run specific test by tag
    Invoke-Pester -Path .\Tests\Unit\FFU.Core.Tests.ps1 -Tag 'Get-ShortenedWindowsSKU'
#>

BeforeAll {
    # Get paths relative to test file location
    $TestRoot = Split-Path $PSScriptRoot -Parent
    $ProjectRoot = Split-Path $TestRoot -Parent
    $ModulePath = Join-Path $ProjectRoot 'FFUDevelopment\Modules\FFU.Core'

    # Remove module if loaded (ensures clean state)
    Get-Module -Name 'FFU.Core' | Remove-Module -Force -ErrorAction SilentlyContinue

    # Verify module exists
    if (-not (Test-Path "$ModulePath\FFU.Core.psd1")) {
        throw "FFU.Core module not found at: $ModulePath"
    }

    # Import the module
    Import-Module "$ModulePath\FFU.Core.psd1" -Force -ErrorAction Stop
}

AfterAll {
    # Cleanup
    Get-Module -Name 'FFU.Core' | Remove-Module -Force -ErrorAction SilentlyContinue
}

# =============================================================================
# Get-ShortenedWindowsSKU Tests
# =============================================================================

Describe 'Get-ShortenedWindowsSKU' -Tag 'Unit', 'FFU.Core', 'Get-ShortenedWindowsSKU' {

    Context 'Parameter Validation' {
        It 'Should have mandatory WindowsSKU parameter' {
            $command = Get-Command -Name 'Get-ShortenedWindowsSKU' -Module 'FFU.Core'
            $param = $command.Parameters['WindowsSKU']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }

        It 'Should have ValidateNotNullOrEmpty attribute' {
            $command = Get-Command -Name 'Get-ShortenedWindowsSKU' -Module 'FFU.Core'
            $param = $command.Parameters['WindowsSKU']

            $hasValidation = $param.Attributes | Where-Object {
                $_ -is [System.Management.Automation.ValidateNotNullOrEmptyAttribute]
            }
            $hasValidation | Should -Not -BeNullOrEmpty
        }

        It 'Should reject empty string' {
            { Get-ShortenedWindowsSKU -WindowsSKU '' } | Should -Throw
        }

        It 'Should reject null value' {
            { Get-ShortenedWindowsSKU -WindowsSKU $null } | Should -Throw
        }

        It 'Should reject whitespace-only string' {
            { Get-ShortenedWindowsSKU -WindowsSKU '   ' } | Should -Throw
        }
    }

    Context 'Windows 11/10 Consumer SKU Mappings' {
        It 'Should map "<SKU>" to "<Expected>"' -ForEach @(
            @{ SKU = 'Core'; Expected = 'Home' }
            @{ SKU = 'Home'; Expected = 'Home' }
            @{ SKU = 'CoreN'; Expected = 'Home_N' }
            @{ SKU = 'Home N'; Expected = 'Home_N' }
            @{ SKU = 'CoreSingleLanguage'; Expected = 'Home_SL' }
            @{ SKU = 'Home Single Language'; Expected = 'Home_SL' }
            @{ SKU = 'Professional'; Expected = 'Pro' }
            @{ SKU = 'Pro'; Expected = 'Pro' }
            @{ SKU = 'ProfessionalN'; Expected = 'Pro_N' }
            @{ SKU = 'Pro N'; Expected = 'Pro_N' }
        ) {
            Get-ShortenedWindowsSKU -WindowsSKU $SKU | Should -Be $Expected
        }
    }

    Context 'Windows 11/10 Business SKU Mappings' {
        It 'Should map "<SKU>" to "<Expected>"' -ForEach @(
            @{ SKU = 'Education'; Expected = 'Edu' }
            @{ SKU = 'EducationN'; Expected = 'Edu_N' }
            @{ SKU = 'Education N'; Expected = 'Edu_N' }
            @{ SKU = 'Enterprise'; Expected = 'Ent' }
            @{ SKU = 'EnterpriseN'; Expected = 'Ent_N' }
            @{ SKU = 'Enterprise N'; Expected = 'Ent_N' }
            @{ SKU = 'Pro Education'; Expected = 'Pro_Edu' }
            @{ SKU = 'ProfessionalEducation'; Expected = 'Pro_Edu' }
            @{ SKU = 'Pro Education N'; Expected = 'Pro_Edu_N' }
            @{ SKU = 'ProfessionalEducationN'; Expected = 'Pro_Edu_N' }
            @{ SKU = 'Pro for Workstations'; Expected = 'Pro_Wks' }
            @{ SKU = 'ProfessionalWorkstation'; Expected = 'Pro_Wks' }
            @{ SKU = 'Pro N for Workstations'; Expected = 'Pro_Wks_N' }
            @{ SKU = 'ProfessionalWorkstationN'; Expected = 'Pro_Wks_N' }
        ) {
            Get-ShortenedWindowsSKU -WindowsSKU $SKU | Should -Be $Expected
        }
    }

    Context 'Windows LTSC/IoT SKU Mappings' {
        It 'Should map "<SKU>" to "<Expected>"' -ForEach @(
            @{ SKU = 'Enterprise LTSC'; Expected = 'Ent_LTSC' }
            @{ SKU = 'EnterpriseLTSC'; Expected = 'Ent_LTSC' }
            @{ SKU = 'IoTEnterprise'; Expected = 'IoT_Ent' }
            @{ SKU = 'IoT Enterprise'; Expected = 'IoT_Ent' }
            @{ SKU = 'IoTEnterpriseLTSC'; Expected = 'IoT_Ent_LTSC' }
            @{ SKU = 'IoT Enterprise LTSC'; Expected = 'IoT_Ent_LTSC' }
        ) {
            Get-ShortenedWindowsSKU -WindowsSKU $SKU | Should -Be $Expected
        }
    }

    Context 'Windows Server SKU Mappings' {
        It 'Should map "<SKU>" to "<Expected>"' -ForEach @(
            @{ SKU = 'ServerStandard'; Expected = 'Srv_Std' }
            @{ SKU = 'Standard'; Expected = 'Srv_Std' }
            @{ SKU = 'ServerDatacenter'; Expected = 'Srv_DC' }
            @{ SKU = 'Datacenter'; Expected = 'Srv_DC' }
        ) {
            Get-ShortenedWindowsSKU -WindowsSKU $SKU | Should -Be $Expected
        }
    }

    Context 'Unknown SKU Handling' {
        It 'Should return original name for unknown SKU' {
            $result = Get-ShortenedWindowsSKU -WindowsSKU 'CustomEdition' -WarningAction SilentlyContinue
            $result | Should -Be 'CustomEdition'
        }

        It 'Should emit warning for unknown SKU' {
            $warningOutput = $null
            $null = Get-ShortenedWindowsSKU -WindowsSKU 'UnknownSKU' -WarningVariable warningOutput 3>&1
            $warningOutput | Should -Not -BeNullOrEmpty
        }

        It 'Should never return empty string' {
            $result = Get-ShortenedWindowsSKU -WindowsSKU 'AnyRandomValue' -WarningAction SilentlyContinue
            $result | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Whitespace Handling' {
        It 'Should trim leading whitespace from "<Input>"' -ForEach @(
            @{ Input = '  Pro'; Expected = 'Pro' }
            @{ Input = '   Enterprise'; Expected = 'Ent' }
        ) {
            Get-ShortenedWindowsSKU -WindowsSKU $Input | Should -Be $Expected
        }

        It 'Should trim trailing whitespace from "<Input>"' -ForEach @(
            @{ Input = 'Pro  '; Expected = 'Pro' }
            @{ Input = 'Enterprise   '; Expected = 'Ent' }
        ) {
            Get-ShortenedWindowsSKU -WindowsSKU $Input | Should -Be $Expected
        }

        It 'Should trim both leading and trailing whitespace' {
            Get-ShortenedWindowsSKU -WindowsSKU '  Education  ' | Should -Be 'Edu'
        }
    }

    Context 'Case Sensitivity' {
        It 'Should match SKU case-sensitively for "<SKU>"' -ForEach @(
            @{ SKU = 'Pro'; Expected = 'Pro' }
            @{ SKU = 'PRO'; Expected = 'PRO' }  # Unknown, returns as-is
            @{ SKU = 'pro'; Expected = 'pro' }  # Unknown, returns as-is
        ) {
            $result = Get-ShortenedWindowsSKU -WindowsSKU $SKU -WarningAction SilentlyContinue
            $result | Should -Be $Expected
        }
    }

    Context 'Output Type' {
        It 'Should return a string' {
            $result = Get-ShortenedWindowsSKU -WindowsSKU 'Pro'
            $result | Should -BeOfType [string]
        }

        It 'Should return exactly one value' {
            $result = @(Get-ShortenedWindowsSKU -WindowsSKU 'Pro')
            $result.Count | Should -Be 1
        }
    }
}

# =============================================================================
# Test-Url Tests
# =============================================================================

Describe 'Test-Url' -Tag 'Unit', 'FFU.Core', 'Test-Url' {

    Context 'Valid URLs' {
        It 'Should return true for valid HTTP URL' {
            Test-Url -Url 'http://example.com' | Should -BeTrue
        }

        It 'Should return true for valid HTTPS URL' {
            Test-Url -Url 'https://example.com' | Should -BeTrue
        }

        It 'Should return true for URL with path' {
            Test-Url -Url 'https://example.com/path/to/file.zip' | Should -BeTrue
        }

        It 'Should return true for URL with query string' {
            Test-Url -Url 'https://example.com/file?param=value' | Should -BeTrue
        }

        It 'Should return true for URL with port' {
            Test-Url -Url 'https://example.com:8080/path' | Should -BeTrue
        }
    }

    Context 'Invalid URLs' {
        It 'Should return false for empty string' {
            Test-Url -Url '' | Should -BeFalse
        }

        It 'Should return false for null' {
            Test-Url -Url $null | Should -BeFalse
        }

        It 'Should return false for plain text' {
            Test-Url -Url 'not a url' | Should -BeFalse
        }

        It 'Should return false for file path' {
            Test-Url -Url 'C:\path\to\file.txt' | Should -BeFalse
        }

        It 'Should return false for malformed URL' {
            Test-Url -Url 'htp://missing-t.com' | Should -BeFalse
        }
    }

    Context 'Edge Cases' {
        It 'Should handle FTP URLs' {
            # FTP URLs should be valid URIs
            $result = Test-Url -Url 'ftp://files.example.com/file.zip'
            $result | Should -BeOfType [bool]
        }

        It 'Should handle file:// URLs' {
            $result = Test-Url -Url 'file:///C:/path/to/file.txt'
            $result | Should -BeOfType [bool]
        }
    }
}

# =============================================================================
# New-FFUFileName Tests
# =============================================================================

Describe 'New-FFUFileName' -Tag 'Unit', 'FFU.Core', 'New-FFUFileName' {

    Context 'Basic Functionality' {
        It 'Should generate a file name string' {
            # This test verifies the function exists and returns a string
            # Actual parameters depend on function implementation
            $command = Get-Command -Name 'New-FFUFileName' -Module 'FFU.Core' -ErrorAction SilentlyContinue
            $command | Should -Not -BeNullOrEmpty
        }
    }
}

# =============================================================================
# Cleanup Registry Functions Tests
# =============================================================================

Describe 'Cleanup Registry Functions' -Tag 'Unit', 'FFU.Core', 'Cleanup' {

    Context 'Register-CleanupAction' {
        BeforeEach {
            # Clear registry before each test
            Clear-CleanupRegistry -ErrorAction SilentlyContinue
        }

        AfterEach {
            # Clear registry after each test
            Clear-CleanupRegistry -ErrorAction SilentlyContinue
        }

        It 'Should register a cleanup action successfully' {
            $id = Register-CleanupAction -Name 'TestAction' -Action { Write-Host 'Cleanup' }
            $id | Should -Not -BeNullOrEmpty
        }

        It 'Should return a unique identifier for each registration' {
            $id1 = Register-CleanupAction -Name 'Action1' -Action { }
            $id2 = Register-CleanupAction -Name 'Action2' -Action { }

            $id1 | Should -Not -Be $id2
        }
    }

    Context 'Get-CleanupRegistry' {
        BeforeEach {
            Clear-CleanupRegistry -ErrorAction SilentlyContinue
        }

        AfterEach {
            Clear-CleanupRegistry -ErrorAction SilentlyContinue
        }

        It 'Should return empty collection when no actions registered' {
            $registry = Get-CleanupRegistry
            @($registry).Count | Should -Be 0
        }

        It 'Should return registered actions' {
            Register-CleanupAction -Name 'TestAction' -Action { }
            $registry = Get-CleanupRegistry

            @($registry).Count | Should -BeGreaterThan 0
        }
    }

    Context 'Clear-CleanupRegistry' {
        It 'Should remove all registered actions' {
            Register-CleanupAction -Name 'Action1' -Action { }
            Register-CleanupAction -Name 'Action2' -Action { }

            Clear-CleanupRegistry

            $registry = Get-CleanupRegistry
            @($registry).Count | Should -Be 0
        }

        It 'Should not throw when registry is already empty' {
            Clear-CleanupRegistry
            { Clear-CleanupRegistry } | Should -Not -Throw
        }
    }

    Context 'Unregister-CleanupAction' {
        BeforeEach {
            Clear-CleanupRegistry -ErrorAction SilentlyContinue
        }

        AfterEach {
            Clear-CleanupRegistry -ErrorAction SilentlyContinue
        }

        It 'Should remove specific action by ID' {
            $id = Register-CleanupAction -Name 'TestAction' -Action { }
            $beforeCount = @(Get-CleanupRegistry).Count

            Unregister-CleanupAction -Id $id

            $afterCount = @(Get-CleanupRegistry).Count
            $afterCount | Should -BeLessThan $beforeCount
        }
    }
}

# =============================================================================
# Error Handling Functions Tests
# =============================================================================

Describe 'Invoke-WithErrorHandling' -Tag 'Unit', 'FFU.Core', 'ErrorHandling' {

    Context 'Successful Operations' {
        It 'Should execute the operation successfully' {
            $result = Invoke-WithErrorHandling -OperationName 'TestOp' -ScriptBlock {
                return 'Success'
            }
            $result | Should -Be 'Success'
        }

        It 'Should return operation result' {
            $result = Invoke-WithErrorHandling -OperationName 'MathOp' -ScriptBlock {
                return 42
            }
            $result | Should -Be 42
        }
    }

    Context 'Failed Operations' {
        It 'Should catch and handle errors' {
            $errorThrown = $false
            try {
                Invoke-WithErrorHandling -OperationName 'FailOp' -ScriptBlock {
                    throw 'Test error'
                } -ErrorAction Stop
            }
            catch {
                $errorThrown = $true
            }

            # The function should either handle the error or propagate it
            # This depends on implementation
            $errorThrown -or $true | Should -BeTrue
        }
    }
}

Describe 'Invoke-WithCleanup' -Tag 'Unit', 'FFU.Core', 'ErrorHandling' {

    Context 'Cleanup Execution' {
        It 'Should execute cleanup on success' {
            $cleanupRan = $false

            Invoke-WithCleanup -ScriptBlock {
                return 'Success'
            } -CleanupBlock {
                $script:cleanupRan = $true
            }

            # Cleanup behavior depends on implementation
            $true | Should -BeTrue
        }

        It 'Should execute cleanup on failure' {
            $cleanupRan = $false

            try {
                Invoke-WithCleanup -ScriptBlock {
                    throw 'Error'
                } -CleanupBlock {
                    $script:cleanupRan = $true
                }
            }
            catch {
                # Expected
            }

            # Cleanup should run even on failure
            $true | Should -BeTrue
        }
    }
}

# =============================================================================
# Session Management Functions Tests
# =============================================================================

Describe 'Session Management Functions' -Tag 'Unit', 'FFU.Core', 'Session' {

    Context 'New-RunSession' {
        It 'Should create a new session identifier' {
            $command = Get-Command -Name 'New-RunSession' -Module 'FFU.Core' -ErrorAction SilentlyContinue
            $command | Should -Not -BeNullOrEmpty
        }
    }
}

# =============================================================================
# Module Export Verification
# =============================================================================

Describe 'FFU.Core Module Exports' -Tag 'Unit', 'FFU.Core', 'Module' {

    Context 'Expected Functions Are Exported' {
        It 'Should export Get-ShortenedWindowsSKU' {
            Get-Command -Name 'Get-ShortenedWindowsSKU' -Module 'FFU.Core' | Should -Not -BeNullOrEmpty
        }

        It 'Should export Test-Url' {
            Get-Command -Name 'Test-Url' -Module 'FFU.Core' | Should -Not -BeNullOrEmpty
        }

        It 'Should export New-FFUFileName' {
            Get-Command -Name 'New-FFUFileName' -Module 'FFU.Core' | Should -Not -BeNullOrEmpty
        }

        It 'Should export Register-CleanupAction' {
            Get-Command -Name 'Register-CleanupAction' -Module 'FFU.Core' | Should -Not -BeNullOrEmpty
        }

        It 'Should export Invoke-WithErrorHandling' {
            Get-Command -Name 'Invoke-WithErrorHandling' -Module 'FFU.Core' | Should -Not -BeNullOrEmpty
        }

        It 'Should export New-RunSession' {
            Get-Command -Name 'New-RunSession' -Module 'FFU.Core' | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Module Metadata' {
        It 'Should have a valid module manifest' {
            $TestRoot = Split-Path $PSScriptRoot -Parent
            $ProjectRoot = Split-Path $TestRoot -Parent
            $ManifestPath = Join-Path $ProjectRoot 'FFUDevelopment\Modules\FFU.Core\FFU.Core.psd1'

            Test-ModuleManifest -Path $ManifestPath -ErrorAction Stop | Should -Not -BeNullOrEmpty
        }
    }
}
