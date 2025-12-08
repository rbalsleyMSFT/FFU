#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester unit tests for FFU.Core credential security functions

.DESCRIPTION
    Comprehensive unit tests covering credential security functions in the FFU.Core module.
    Tests verify secure password generation, SecureString handling, memory cleanup,
    and sensitive media cleanup functionality.

.NOTES
    Run with: Invoke-Pester -Path .\Tests\Unit\FFU.Core.CredentialSecurity.Tests.ps1 -Output Detailed
    Coverage: Invoke-Pester -Path .\Tests\Unit\FFU.Core.CredentialSecurity.Tests.ps1 -CodeCoverage .\FFUDevelopment\Modules\FFU.Core\*.psm1
#>

BeforeAll {
    # Get paths relative to test file location
    $TestRoot = Split-Path $PSScriptRoot -Parent
    $ProjectRoot = Split-Path $TestRoot -Parent
    $ModulePath = Join-Path $ProjectRoot 'FFUDevelopment\Modules\FFU.Core'

    # Remove module if loaded
    Get-Module -Name 'FFU.Core' | Remove-Module -Force -ErrorAction SilentlyContinue

    # Import FFU.Core module
    if (-not (Test-Path "$ModulePath\FFU.Core.psd1")) {
        throw "FFU.Core module not found at: $ModulePath"
    }
    Import-Module "$ModulePath\FFU.Core.psd1" -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name 'FFU.Core' | Remove-Module -Force -ErrorAction SilentlyContinue
}

# =============================================================================
# Credential Security Function Exports
# =============================================================================

Describe 'FFU.Core Credential Security Function Exports' -Tag 'Unit', 'FFU.Core', 'Security' {

    Context 'Credential Security Functions Are Exported' {
        It 'Should export New-SecureRandomPassword' {
            Get-Command -Name 'New-SecureRandomPassword' -Module 'FFU.Core' | Should -Not -BeNullOrEmpty
        }

        It 'Should export ConvertFrom-SecureStringToPlainText' {
            Get-Command -Name 'ConvertFrom-SecureStringToPlainText' -Module 'FFU.Core' | Should -Not -BeNullOrEmpty
        }

        It 'Should export Clear-PlainTextPassword' {
            Get-Command -Name 'Clear-PlainTextPassword' -Module 'FFU.Core' | Should -Not -BeNullOrEmpty
        }

        It 'Should export Remove-SecureStringFromMemory' {
            Get-Command -Name 'Remove-SecureStringFromMemory' -Module 'FFU.Core' | Should -Not -BeNullOrEmpty
        }

        It 'Should export Register-SensitiveMediaCleanup' {
            Get-Command -Name 'Register-SensitiveMediaCleanup' -Module 'FFU.Core' | Should -Not -BeNullOrEmpty
        }
    }
}

# =============================================================================
# New-SecureRandomPassword Tests
# =============================================================================

Describe 'New-SecureRandomPassword' -Tag 'Unit', 'FFU.Core', 'Security', 'New-SecureRandomPassword' {

    Context 'Parameter Validation' {
        It 'Should have optional Length parameter' {
            $command = Get-Command -Name 'New-SecureRandomPassword' -Module 'FFU.Core'
            $command.Parameters['Length'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have int type for Length parameter' {
            $command = Get-Command -Name 'New-SecureRandomPassword' -Module 'FFU.Core'
            $param = $command.Parameters['Length']
            $param.ParameterType.Name | Should -Be 'Int32'
        }

        It 'Should have optional IncludeSpecialChars parameter' {
            $command = Get-Command -Name 'New-SecureRandomPassword' -Module 'FFU.Core'
            $command.Parameters['IncludeSpecialChars'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have bool type for IncludeSpecialChars parameter' {
            $command = Get-Command -Name 'New-SecureRandomPassword' -Module 'FFU.Core'
            $param = $command.Parameters['IncludeSpecialChars']
            $param.ParameterType.Name | Should -Be 'Boolean'
        }
    }

    Context 'Return Type and Basic Behavior' {
        It 'Should return a SecureString object' {
            $result = New-SecureRandomPassword
            $result | Should -BeOfType [System.Security.SecureString]
            $result.Dispose()
        }

        It 'Should return a non-empty SecureString' {
            $result = New-SecureRandomPassword
            $result.Length | Should -BeGreaterThan 0
            $result.Dispose()
        }

        It 'Should generate password with default length of 32' {
            $result = New-SecureRandomPassword
            $result.Length | Should -Be 32
            $result.Dispose()
        }

        It 'Should generate password with specified length' {
            $result = New-SecureRandomPassword -Length 16
            $result.Length | Should -Be 16
            $result.Dispose()
        }
    }

    Context 'Password Randomness' {
        It 'Should generate different passwords on consecutive calls' {
            $pass1 = New-SecureRandomPassword
            $pass2 = New-SecureRandomPassword

            # Convert to plain text for comparison (then clean up)
            $ptr1 = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($pass1)
            $ptr2 = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($pass2)
            try {
                $plain1 = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr1)
                $plain2 = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr2)
                $plain1 | Should -Not -Be $plain2
            }
            finally {
                [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr1)
                [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr2)
                $pass1.Dispose()
                $pass2.Dispose()
            }
        }
    }
}

# =============================================================================
# ConvertFrom-SecureStringToPlainText Tests
# =============================================================================

Describe 'ConvertFrom-SecureStringToPlainText' -Tag 'Unit', 'FFU.Core', 'Security', 'ConvertFrom-SecureStringToPlainText' {

    Context 'Parameter Validation' {
        It 'Should have mandatory SecureString parameter' {
            $command = Get-Command -Name 'ConvertFrom-SecureStringToPlainText' -Module 'FFU.Core'
            $param = $command.Parameters['SecureString']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }

        It 'Should have SecureString type for SecureString parameter' {
            $command = Get-Command -Name 'ConvertFrom-SecureStringToPlainText' -Module 'FFU.Core'
            $param = $command.Parameters['SecureString']
            $param.ParameterType.Name | Should -Be 'SecureString'
        }
    }

    Context 'Conversion Behavior' {
        It 'Should convert SecureString to plain text correctly' {
            $testPassword = "TestP@ssw0rd123"
            $secureString = ConvertTo-SecureString -String $testPassword -AsPlainText -Force

            $result = ConvertFrom-SecureStringToPlainText -SecureString $secureString
            $result | Should -Be $testPassword

            $secureString.Dispose()
        }

        It 'Should handle empty SecureString' {
            $secureString = [System.Security.SecureString]::new()
            $result = ConvertFrom-SecureStringToPlainText -SecureString $secureString
            $result | Should -Be ""
            $secureString.Dispose()
        }
    }
}

# =============================================================================
# Remove-SecureStringFromMemory Tests
# =============================================================================

Describe 'Remove-SecureStringFromMemory' -Tag 'Unit', 'FFU.Core', 'Security', 'Remove-SecureStringFromMemory' {

    Context 'Parameter Validation' {
        It 'Should have mandatory SecureStringVariable parameter' {
            $command = Get-Command -Name 'Remove-SecureStringFromMemory' -Module 'FFU.Core'
            $param = $command.Parameters['SecureStringVariable']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }
    }

    Context 'Disposal Behavior' {
        It 'Should dispose SecureString and set variable to null' {
            $secureString = New-SecureRandomPassword
            $secureString | Should -Not -BeNullOrEmpty

            Remove-SecureStringFromMemory -SecureStringVariable ([ref]$secureString)
            $secureString | Should -BeNullOrEmpty
        }

        It 'Should not throw when given null SecureString' {
            $nullSecure = $null
            { Remove-SecureStringFromMemory -SecureStringVariable ([ref]$nullSecure) } | Should -Not -Throw
        }
    }
}

# =============================================================================
# Clear-PlainTextPassword Tests
# =============================================================================

Describe 'Clear-PlainTextPassword' -Tag 'Unit', 'FFU.Core', 'Security', 'Clear-PlainTextPassword' {

    Context 'Parameter Validation' {
        It 'Should have mandatory PasswordVariable parameter' {
            $command = Get-Command -Name 'Clear-PlainTextPassword' -Module 'FFU.Core'
            $param = $command.Parameters['PasswordVariable']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }
    }

    Context 'Clearing Behavior' {
        It 'Should clear password string and set variable to null' {
            $password = "SensitivePassword123!"
            $password | Should -Not -BeNullOrEmpty

            Clear-PlainTextPassword -PasswordVariable ([ref]$password)
            $password | Should -BeNullOrEmpty
        }

        It 'Should not throw when given null password' {
            $nullPassword = $null
            { Clear-PlainTextPassword -PasswordVariable ([ref]$nullPassword) } | Should -Not -Throw
        }
    }
}

# =============================================================================
# Register-SensitiveMediaCleanup Tests
# =============================================================================

Describe 'Register-SensitiveMediaCleanup' -Tag 'Unit', 'FFU.Core', 'Security', 'Register-SensitiveMediaCleanup' {

    BeforeEach {
        # Clear cleanup registry before each test
        Clear-CleanupRegistry
    }

    Context 'Parameter Validation' {
        It 'Should have mandatory FFUDevelopmentPath parameter' {
            $command = Get-Command -Name 'Register-SensitiveMediaCleanup' -Module 'FFU.Core'
            $param = $command.Parameters['FFUDevelopmentPath']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }

        It 'Should have string type for FFUDevelopmentPath parameter' {
            $command = Get-Command -Name 'Register-SensitiveMediaCleanup' -Module 'FFU.Core'
            $param = $command.Parameters['FFUDevelopmentPath']
            $param.ParameterType.Name | Should -Be 'String'
        }
    }

    Context 'Cleanup Registration' {
        It 'Should register a cleanup action in the registry' {
            $beforeCount = (Get-CleanupRegistry).Count

            Register-SensitiveMediaCleanup -FFUDevelopmentPath "C:\TestFFU"

            $afterCount = (Get-CleanupRegistry).Count
            $afterCount | Should -Be ($beforeCount + 1)
        }

        It 'Should register with TempFile resource type' {
            Register-SensitiveMediaCleanup -FFUDevelopmentPath "C:\TestFFU"

            $registry = Get-CleanupRegistry
            $entry = $registry | Where-Object { $_.Name -eq "Remove sensitive capture media backups" }

            $entry | Should -Not -BeNullOrEmpty
            $entry.ResourceType | Should -Be 'TempFile'
        }

        It 'Should register with correct resource ID' {
            Register-SensitiveMediaCleanup -FFUDevelopmentPath "C:\TestFFU"

            $registry = Get-CleanupRegistry
            $entry = $registry | Where-Object { $_.Name -eq "Remove sensitive capture media backups" }

            $entry.ResourceId | Should -Be 'CaptureFFU-Backups'
        }
    }

    AfterEach {
        # Clean up registry after each test
        Clear-CleanupRegistry
    }
}

# =============================================================================
# Security Best Practices Tests
# =============================================================================

Describe 'Credential Security Best Practices' -Tag 'Unit', 'FFU.Core', 'Security', 'BestPractices' {

    Context 'Cryptographic Security' {
        It 'Should use cryptographic random generator (RNGCryptoServiceProvider)' {
            # Verify by checking the function definition mentions RNGCryptoServiceProvider
            $moduleContent = Get-Content -Path (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'FFUDevelopment\Modules\FFU.Core\FFU.Core.psm1') -Raw
            $moduleContent | Should -Match 'RNGCryptoServiceProvider'
        }

        It 'Should not use Get-Random for password generation (actual implementation)' {
            # Get-Random is not cryptographically secure
            $moduleContent = Get-Content -Path (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'FFUDevelopment\Modules\FFU.Core\FFU.Core.psm1') -Raw

            # Check that New-SecureRandomPassword function doesn't use Get-Random in actual code (not comments)
            # Extract function body after param block where actual implementation lives
            if ($moduleContent -match 'function\s+New-SecureRandomPassword[\s\S]*?param\s*\([\s\S]*?\)\s*([\s\S]*?)(?=\s*function\s+|\s*Export-ModuleMember|\z)') {
                $functionImplementation = $Matches[1]
                # Remove comment lines and check remaining code
                $codeOnly = ($functionImplementation -split "`n" | Where-Object { $_ -notmatch '^\s*#' -and $_ -notmatch '^\s*\.NOTES' }) -join "`n"
                # Should not have Get-Random as actual command usage
                $codeOnly | Should -Not -Match '\bGet-Random\s*(-|\||\z)'
            }
        }
    }

    Context 'BSTR Memory Handling' {
        It 'Should use BSTR for SecureString conversion' {
            $moduleContent = Get-Content -Path (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'FFUDevelopment\Modules\FFU.Core\FFU.Core.psm1') -Raw
            $moduleContent | Should -Match 'SecureStringToBSTR'
        }

        It 'Should free BSTR memory after use' {
            $moduleContent = Get-Content -Path (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'FFUDevelopment\Modules\FFU.Core\FFU.Core.psm1') -Raw
            $moduleContent | Should -Match 'ZeroFreeBSTR'
        }
    }

    Context 'No Insecure Patterns' {
        It 'FFU.VM module should not use GUID-based password generation' {
            $vmModulePath = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'FFUDevelopment\Modules\FFU.VM\FFU.VM.psm1'
            $vmModuleContent = Get-Content -Path $vmModulePath -Raw

            # GUID-based password is insecure: [guid]::NewGuid().ToString()
            # Should not be used for password generation
            $vmModuleContent | Should -Not -Match '\[guid\]::NewGuid\(\)\.ToString\(\).*\$.*password'
        }

        It 'Update-CaptureFFUScript help should show SecureString usage' {
            $vmModulePath = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'FFUDevelopment\Modules\FFU.VM\FFU.VM.psm1'
            $vmModuleContent = Get-Content -Path $vmModulePath -Raw

            # The help examples should reference SecureString and SecureRandomPassword
            # Pattern accounts for multiline - looks for examples that mention both secure password generation
            $vmModuleContent | Should -Match 'New-SecureRandomPassword'
            # Also verify the function is there with proper password handling
            $vmModuleContent | Should -Match 'function Update-CaptureFFUScript'
        }
    }
}

# =============================================================================
# BuildFFUVM.ps1 Security Integration Tests
# =============================================================================

Describe 'BuildFFUVM.ps1 Credential Security Integration' -Tag 'Unit', 'FFU.Core', 'Security', 'Integration' {

    BeforeAll {
        $BuildScriptPath = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'FFUDevelopment\BuildFFUVM.ps1'
        $script:BuildScriptContent = Get-Content -Path $BuildScriptPath -Raw
    }

    Context 'Secure Password Generation Usage' {
        It 'Should use New-SecureRandomPassword for FFU capture user' {
            $BuildScriptContent | Should -Match 'New-SecureRandomPassword'
        }

        It 'Should generate password with cryptographic RNG' {
            $BuildScriptContent | Should -Match '\$capturePasswordSecure\s*=\s*New-SecureRandomPassword'
        }
    }

    Context 'Sensitive Media Cleanup Registration' {
        It 'Should register sensitive media cleanup after Update-CaptureFFUScript' {
            $BuildScriptContent | Should -Match 'Register-SensitiveMediaCleanup'
        }

        It 'Should pass FFUDevelopmentPath to Register-SensitiveMediaCleanup' {
            $BuildScriptContent | Should -Match 'Register-SensitiveMediaCleanup\s+-FFUDevelopmentPath\s+\$FFUDevelopmentPath'
        }
    }

    Context 'SecureString Disposal' {
        It 'Should dispose SecureString credentials after use' {
            $BuildScriptContent | Should -Match '\$capturePasswordSecure\.Dispose\(\)'
        }

        It 'Should have Remove-SecureStringFromMemory call for cleanup' {
            $BuildScriptContent | Should -Match 'Remove-SecureStringFromMemory'
        }
    }

    Context 'No Legacy Backup File' {
        It 'Should not have BuildFFUVM.ps1.backup-before-modularization in repository' {
            $backupPath = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'FFUDevelopment\BuildFFUVM.ps1.backup-before-modularization'
            Test-Path $backupPath | Should -BeFalse
        }
    }
}
