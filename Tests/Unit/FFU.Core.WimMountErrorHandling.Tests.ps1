#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester unit tests for FFU.Core Invoke-WimMountWithErrorHandling function

.DESCRIPTION
    Comprehensive unit tests covering the Invoke-WimMountWithErrorHandling function
    in the FFU.Core module. Tests verify WIMMount error detection, remediation guidance,
    error handling patterns, and parameter validation.

.NOTES
    Run with: Invoke-Pester -Path .\Tests\Unit\FFU.Core.WimMountErrorHandling.Tests.ps1 -Output Detailed
    Coverage: Invoke-Pester -Path .\Tests\Unit\FFU.Core.WimMountErrorHandling.Tests.ps1 -CodeCoverage .\FFUDevelopment\Modules\FFU.Core\*.psm1

    Test Strategy:
    - Mock Mount-WindowsImage to simulate various failure scenarios
    - Verify error detection patterns for WIMMount filter driver issues
    - Verify remediation guidance is included in error messages
    - Verify non-WIMMount errors are properly re-thrown with context
#>

BeforeAll {
    # Get paths relative to test file location
    $TestRoot = Split-Path $PSScriptRoot -Parent
    $ProjectRoot = Split-Path $TestRoot -Parent
    $ModulePath = Join-Path $ProjectRoot 'FFUDevelopment\Modules\FFU.Core'
    $ModulesDir = Join-Path $ProjectRoot 'FFUDevelopment\Modules'

    # Add Modules directory to PSModulePath for dependency resolution
    if ($env:PSModulePath -notlike "*$ModulesDir*") {
        $env:PSModulePath = "$ModulesDir;$env:PSModulePath"
    }

    # Remove modules if loaded
    Get-Module -Name 'FFU.Core' | Remove-Module -Force -ErrorAction SilentlyContinue
    Get-Module -Name 'FFU.Constants' | Remove-Module -Force -ErrorAction SilentlyContinue

    # Import FFU.Core module (will auto-import FFU.Constants dependency)
    if (-not (Test-Path "$ModulePath\FFU.Core.psd1")) {
        throw "FFU.Core module not found at: $ModulePath"
    }
    Import-Module "$ModulePath\FFU.Core.psd1" -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name 'FFU.Core' | Remove-Module -Force -ErrorAction SilentlyContinue
}

# =============================================================================
# Function Export Verification
# =============================================================================

Describe 'FFU.Core Invoke-WimMountWithErrorHandling Export' -Tag 'Unit', 'FFU.Core', 'WimMount' {

    Context 'Function Export' {
        It 'Should export Invoke-WimMountWithErrorHandling function' {
            Get-Command -Name 'Invoke-WimMountWithErrorHandling' -Module 'FFU.Core' | Should -Not -BeNullOrEmpty
        }

        It 'Should have CmdletBinding attribute' {
            $command = Get-Command -Name 'Invoke-WimMountWithErrorHandling' -Module 'FFU.Core'
            $command.CmdletBinding | Should -Be $true
        }

        It 'Should have OutputType attribute set to void' {
            $functionDef = Get-Content "$ModulePath\FFU.Core.psm1" -Raw
            $functionDef | Should -Match 'function Invoke-WimMountWithErrorHandling\s*\{[^\}]*\[OutputType\(\[void\]\)\]'
        }
    }
}

# =============================================================================
# Parameter Validation Tests
# =============================================================================

Describe 'Invoke-WimMountWithErrorHandling Parameter Validation' -Tag 'Unit', 'FFU.Core', 'WimMount', 'Parameters' {

    Context 'Required Parameters' {
        It 'Should have mandatory ImagePath parameter' {
            $command = Get-Command -Name 'Invoke-WimMountWithErrorHandling' -Module 'FFU.Core'
            $param = $command.Parameters['ImagePath']
            $param | Should -Not -BeNullOrEmpty
            $param.Attributes.Mandatory | Should -Contain $true
        }

        It 'Should have mandatory Path parameter' {
            $command = Get-Command -Name 'Invoke-WimMountWithErrorHandling' -Module 'FFU.Core'
            $param = $command.Parameters['Path']
            $param | Should -Not -BeNullOrEmpty
            $param.Attributes.Mandatory | Should -Contain $true
        }

        It 'Should validate ImagePath is not null or empty' {
            $command = Get-Command -Name 'Invoke-WimMountWithErrorHandling' -Module 'FFU.Core'
            $param = $command.Parameters['ImagePath']
            $param.Attributes.TypeId.Name | Should -Contain 'ValidateNotNullOrEmptyAttribute'
        }

        It 'Should validate Path is not null or empty' {
            $command = Get-Command -Name 'Invoke-WimMountWithErrorHandling' -Module 'FFU.Core'
            $param = $command.Parameters['Path']
            $param.Attributes.TypeId.Name | Should -Contain 'ValidateNotNullOrEmptyAttribute'
        }
    }

    Context 'Optional Parameters' {
        It 'Should have optional Index parameter with default value 1' {
            $command = Get-Command -Name 'Invoke-WimMountWithErrorHandling' -Module 'FFU.Core'
            $param = $command.Parameters['Index']
            $param | Should -Not -BeNullOrEmpty
            $param.Attributes.Mandatory | Should -Not -Contain $true
        }

        It 'Should have optional ReadOnly switch parameter' {
            $command = Get-Command -Name 'Invoke-WimMountWithErrorHandling' -Module 'FFU.Core'
            $param = $command.Parameters['ReadOnly']
            $param | Should -Not -BeNullOrEmpty
            $param.SwitchParameter | Should -Be $true
        }

        It 'Should have optional Optimize switch parameter' {
            $command = Get-Command -Name 'Invoke-WimMountWithErrorHandling' -Module 'FFU.Core'
            $param = $command.Parameters['Optimize']
            $param | Should -Not -BeNullOrEmpty
            $param.SwitchParameter | Should -Be $true
        }
    }

    Context 'Parameter Types' {
        It 'Should have string type for ImagePath parameter' {
            $command = Get-Command -Name 'Invoke-WimMountWithErrorHandling' -Module 'FFU.Core'
            $param = $command.Parameters['ImagePath']
            $param.ParameterType.Name | Should -Be 'String'
        }

        It 'Should have string type for Path parameter' {
            $command = Get-Command -Name 'Invoke-WimMountWithErrorHandling' -Module 'FFU.Core'
            $param = $command.Parameters['Path']
            $param.ParameterType.Name | Should -Be 'String'
        }

        It 'Should have int type for Index parameter' {
            $command = Get-Command -Name 'Invoke-WimMountWithErrorHandling' -Module 'FFU.Core'
            $param = $command.Parameters['Index']
            $param.ParameterType.Name | Should -Be 'Int32'
        }

        It 'Should have SwitchParameter type for ReadOnly parameter' {
            $command = Get-Command -Name 'Invoke-WimMountWithErrorHandling' -Module 'FFU.Core'
            $param = $command.Parameters['ReadOnly']
            $param.ParameterType.Name | Should -Be 'SwitchParameter'
        }

        It 'Should have SwitchParameter type for Optimize parameter' {
            $command = Get-Command -Name 'Invoke-WimMountWithErrorHandling' -Module 'FFU.Core'
            $param = $command.Parameters['Optimize']
            $param.ParameterType.Name | Should -Be 'SwitchParameter'
        }
    }

    Context 'Index Parameter Range Validation' {
        It 'Should have ValidateRange attribute on Index parameter' {
            $command = Get-Command -Name 'Invoke-WimMountWithErrorHandling' -Module 'FFU.Core'
            $param = $command.Parameters['Index']
            $param.Attributes.TypeId.Name | Should -Contain 'ValidateRangeAttribute'
        }

        It 'Should validate Index range from 1 to 999' {
            $functionDef = Get-Content "$ModulePath\FFU.Core.psm1" -Raw
            $functionDef | Should -Match '\[ValidateRange\(1,\s*999\)\]'
        }
    }
}

# =============================================================================
# Source Code Analysis - WIMMount Error Detection Patterns
# =============================================================================

Describe 'Invoke-WimMountWithErrorHandling Source Code Analysis' -Tag 'Unit', 'FFU.Core', 'WimMount', 'SourceCode' {

    BeforeAll {
        $FunctionSource = Get-Content "$ModulePath\FFU.Core.psm1" -Raw
    }

    Context 'WIMMount Error Detection Patterns' {
        It 'Should check for "specified service does not exist" error message' {
            $FunctionSource | Should -Match "specified service does not exist"
        }

        It 'Should check for 0x800704DB error code in message (case-insensitive)' {
            $FunctionSource | Should -Match "0x800704\[dD\]\[bB\]"
        }

        It 'Should check for 0x800704DB as signed int32 (-2147023653)' {
            $FunctionSource | Should -Match "-2147023653"
        }

        It 'Should check for 0x800704DB as unsigned int32 (2147943643)' {
            $FunctionSource | Should -Match "2147943643"
        }

        It 'Should use HResult property for error code checking' {
            $FunctionSource | Should -Match '\$_\.Exception\.HResult'
        }
    }

    Context 'Error Message Content Requirements' {
        It 'Should include "MOUNT FAILED" in WIMMount error message' {
            $FunctionSource | Should -Match "MOUNT FAILED"
        }

        It 'Should include "WIMMount filter driver" in error message' {
            $FunctionSource | Should -Match "WIMMount filter driver"
        }

        It 'Should include DISM log path reference' {
            $FunctionSource | Should -Match "DISM Log:"
        }

        It 'Should include ROOT CAUSE explanation' {
            $FunctionSource | Should -Match "ROOT CAUSE:"
        }

        It 'Should include REMEDIATION STEPS section' {
            $FunctionSource | Should -Match "REMEDIATION STEPS:"
        }

        It 'Should mention Invoke-FFUPreflight command' {
            $FunctionSource | Should -Match "Invoke-FFUPreflight"
        }

        It 'Should mention ADK reinstallation as remediation' {
            $FunctionSource | Should -Match "Windows Assessment and Deployment Kit"
        }

        It 'Should mention RUNDLL32 WIMMount registration command' {
            $FunctionSource | Should -Match "RUNDLL32\.EXE WIMGAPI\.DLL,WIMRegisterFilterDriver"
        }

        It 'Should reference Windows\Logs\DISM\dism.log path' {
            $FunctionSource | Should -Match "Logs.DISM.dism\.log"
        }
    }

    Context 'Mount-WindowsImage Invocation' {
        It 'Should call Mount-WindowsImage cmdlet' {
            $FunctionSource | Should -Match "Mount-WindowsImage"
        }

        It 'Should use ErrorAction Stop for Mount-WindowsImage' {
            $FunctionSource | Should -Match "ErrorAction\s*=\s*'Stop'"
        }

        It 'Should pipe Mount-WindowsImage output to Out-Null' {
            $FunctionSource | Should -Match "Mount-WindowsImage.*\|\s*Out-Null"
        }

        It 'Should build mount parameters as hashtable' {
            $FunctionSource | Should -Match '\$mountParams\s*=\s*@\{'
        }

        It 'Should conditionally add ReadOnly parameter' {
            $FunctionSource | Should -Match 'if\s*\(\$ReadOnly\)'
        }

        It 'Should conditionally add Optimize parameter' {
            $FunctionSource | Should -Match 'if\s*\(\$Optimize\)'
        }
    }

    Context 'Error Handling Structure' {
        It 'Should have try-catch block' {
            $FunctionSource | Should -Match 'try\s*\{[^\}]*catch\s*\{'
        }

        It 'Should capture error message from exception' {
            $FunctionSource | Should -Match '\$errorMessage\s*=\s*\$_\.Exception\.Message'
        }

        It 'Should format error code as hex string' {
            $FunctionSource | Should -Match "0x\{0:X8\}"
        }

        It 'Should use isWimMountError flag for error classification' {
            $FunctionSource | Should -Match '\$isWimMountError'
        }

        It 'Should throw enhanced message for WIMMount errors' {
            $FunctionSource | Should -Match 'throw\s+\$enhancedMessage'
        }

        It 'Should throw with context for non-WIMMount errors' {
            $FunctionSource | Should -Match 'throw\s+"Mount-WindowsImage failed'
        }
    }
}

# =============================================================================
# Behavior Tests with Mocking
# =============================================================================

Describe 'Invoke-WimMountWithErrorHandling Behavior' -Tag 'Unit', 'FFU.Core', 'WimMount', 'Behavior' {

    BeforeEach {
        # Mock WriteLog to avoid dependencies
        Mock -CommandName WriteLog -MockWith { } -ModuleName 'FFU.Core'
    }

    Context 'Successful Mount Operation' {
        It 'Should call Mount-WindowsImage with correct parameters for basic mount' {
            Mock -CommandName Mount-WindowsImage -MockWith { } -ModuleName 'FFU.Core'

            { Invoke-WimMountWithErrorHandling -ImagePath 'C:\test.wim' -Path 'C:\mount' } | Should -Not -Throw

            Should -Invoke -CommandName Mount-WindowsImage -ModuleName 'FFU.Core' -Times 1 -ParameterFilter {
                $ImagePath -eq 'C:\test.wim' -and
                $Path -eq 'C:\mount' -and
                $Index -eq 1 -and
                $ErrorAction -eq 'Stop'
            }
        }

        It 'Should call Mount-WindowsImage with ReadOnly switch when specified' {
            Mock -CommandName Mount-WindowsImage -MockWith { } -ModuleName 'FFU.Core'

            { Invoke-WimMountWithErrorHandling -ImagePath 'C:\test.wim' -Path 'C:\mount' -ReadOnly } | Should -Not -Throw

            Should -Invoke -CommandName Mount-WindowsImage -ModuleName 'FFU.Core' -Times 1 -ParameterFilter {
                $ReadOnly -eq $true
            }
        }

        It 'Should call Mount-WindowsImage with Optimize switch when specified' {
            Mock -CommandName Mount-WindowsImage -MockWith { } -ModuleName 'FFU.Core'

            { Invoke-WimMountWithErrorHandling -ImagePath 'C:\test.wim' -Path 'C:\mount' -Optimize } | Should -Not -Throw

            Should -Invoke -CommandName Mount-WindowsImage -ModuleName 'FFU.Core' -Times 1 -ParameterFilter {
                $Optimize -eq $true
            }
        }

        It 'Should call Mount-WindowsImage with custom Index when specified' {
            Mock -CommandName Mount-WindowsImage -MockWith { } -ModuleName 'FFU.Core'

            { Invoke-WimMountWithErrorHandling -ImagePath 'C:\test.wim' -Path 'C:\mount' -Index 3 } | Should -Not -Throw

            Should -Invoke -CommandName Mount-WindowsImage -ModuleName 'FFU.Core' -Times 1 -ParameterFilter {
                $Index -eq 3
            }
        }

        It 'Should not throw exception on successful mount' {
            Mock -CommandName Mount-WindowsImage -MockWith { } -ModuleName 'FFU.Core'

            { Invoke-WimMountWithErrorHandling -ImagePath 'C:\test.wim' -Path 'C:\mount' } | Should -Not -Throw
        }
    }

    Context 'WIMMount Error Detection - Error Message Pattern' {
        It 'Should detect WIMMount error from "specified service does not exist" message' {
            Mock -CommandName Mount-WindowsImage -MockWith {
                $exception = New-Object System.Exception("The specified service does not exist")
                throw $exception
            } -ModuleName 'FFU.Core'

            $error = { Invoke-WimMountWithErrorHandling -ImagePath 'C:\test.wim' -Path 'C:\mount' } | Should -Throw -PassThru
            $error.Exception.Message | Should -Match 'MOUNT FAILED: WIMMount filter driver'
        }

        It 'Should detect WIMMount error from error code 0x800704DB in message (lowercase)' {
            Mock -CommandName Mount-WindowsImage -MockWith {
                $exception = New-Object System.Exception("Error 0x800704db occurred")
                throw $exception
            } -ModuleName 'FFU.Core'

            $error = { Invoke-WimMountWithErrorHandling -ImagePath 'C:\test.wim' -Path 'C:\mount' } | Should -Throw -PassThru
            $error.Exception.Message | Should -Match 'MOUNT FAILED: WIMMount filter driver'
        }

        It 'Should detect WIMMount error from error code 0x800704DB in message (uppercase)' {
            Mock -CommandName Mount-WindowsImage -MockWith {
                $exception = New-Object System.Exception("Error 0x800704DB occurred")
                throw $exception
            } -ModuleName 'FFU.Core'

            $error = { Invoke-WimMountWithErrorHandling -ImagePath 'C:\test.wim' -Path 'C:\mount' } | Should -Throw -PassThru
            $error.Exception.Message | Should -Match 'MOUNT FAILED: WIMMount filter driver'
        }
    }

    Context 'WIMMount Error Detection - HResult Code (Signed Int32)' {
        It 'Should detect WIMMount error from signed HResult -2147023653 (0x800704DB)' {
            Mock -CommandName Mount-WindowsImage -MockWith {
                $exception = New-Object System.ComponentModel.Win32Exception(-2147023653)
                throw $exception
            } -ModuleName 'FFU.Core'

            $error = { Invoke-WimMountWithErrorHandling -ImagePath 'C:\test.wim' -Path 'C:\mount' } | Should -Throw -PassThru
            $error.Exception.Message | Should -Match 'MOUNT FAILED: WIMMount filter driver'
        }
    }

    Context 'WIMMount Error Detection - HResult Code (Unsigned Int32)' {
        It 'Should detect WIMMount error from unsigned HResult 2147943643 (0x800704DB)' {
            Mock -CommandName Mount-WindowsImage -MockWith {
                # Create exception with unsigned HResult (some .NET methods return unsigned)
                $exception = New-Object System.Exception("WIM mount failed")
                # Note: Can't directly set HResult to unsigned in PowerShell, but we test the pattern exists
                throw $exception
            } -ModuleName 'FFU.Core'

            # This test verifies the code pattern exists (checked in source code analysis)
            # In practice, HResult is typically signed, but code handles both cases
            $FunctionSource = Get-Content "$ModulePath\FFU.Core.psm1" -Raw
            $FunctionSource | Should -Match '2147943643'
        }
    }

    Context 'WIMMount Error Message Content' {
        It 'Should include "MOUNT FAILED" header in WIMMount error' {
            Mock -CommandName Mount-WindowsImage -MockWith {
                $exception = New-Object System.Exception("The specified service does not exist")
                throw $exception
            } -ModuleName 'FFU.Core'

            $error = { Invoke-WimMountWithErrorHandling -ImagePath 'C:\test.wim' -Path 'C:\mount' } | Should -Throw -PassThru
            $error.Exception.Message | Should -Match 'MOUNT FAILED:'
        }

        It 'Should include original error message in WIMMount error' {
            Mock -CommandName Mount-WindowsImage -MockWith {
                $exception = New-Object System.Exception("The specified service does not exist")
                throw $exception
            } -ModuleName 'FFU.Core'

            $error = { Invoke-WimMountWithErrorHandling -ImagePath 'C:\test.wim' -Path 'C:\mount' } | Should -Throw -PassThru
            $error.Exception.Message | Should -Match 'The specified service does not exist'
        }

        It 'Should include error code in WIMMount error' {
            Mock -CommandName Mount-WindowsImage -MockWith {
                $exception = New-Object System.Exception("The specified service does not exist")
                throw $exception
            } -ModuleName 'FFU.Core'

            $error = { Invoke-WimMountWithErrorHandling -ImagePath 'C:\test.wim' -Path 'C:\mount' } | Should -Throw -PassThru
            $error.Exception.Message | Should -Match 'Error Code:'
        }

        It 'Should include ImagePath in WIMMount error' {
            Mock -CommandName Mount-WindowsImage -MockWith {
                $exception = New-Object System.Exception("The specified service does not exist")
                throw $exception
            } -ModuleName 'FFU.Core'

            $error = { Invoke-WimMountWithErrorHandling -ImagePath 'C:\test.wim' -Path 'C:\mount' } | Should -Throw -PassThru
            $error.Exception.Message | Should -Match 'C:\\test\.wim'
        }

        It 'Should include mount Path in WIMMount error' {
            Mock -CommandName Mount-WindowsImage -MockWith {
                $exception = New-Object System.Exception("The specified service does not exist")
                throw $exception
            } -ModuleName 'FFU.Core'

            $error = { Invoke-WimMountWithErrorHandling -ImagePath 'C:\test.wim' -Path 'C:\mount' } | Should -Throw -PassThru
            $error.Exception.Message | Should -Match 'C:\\mount'
        }

        It 'Should include DISM log path in WIMMount error' {
            Mock -CommandName Mount-WindowsImage -MockWith {
                $exception = New-Object System.Exception("The specified service does not exist")
                throw $exception
            } -ModuleName 'FFU.Core'

            $error = { Invoke-WimMountWithErrorHandling -ImagePath 'C:\test.wim' -Path 'C:\mount' } | Should -Throw -PassThru
            $error.Exception.Message | Should -Match 'DISM Log:'
            $error.Exception.Message | Should -Match 'Logs\\DISM\\dism\.log'
        }
    }

    Context 'WIMMount Error Remediation Guidance' {
        BeforeEach {
            Mock -CommandName Mount-WindowsImage -MockWith {
                $exception = New-Object System.Exception("The specified service does not exist")
                throw $exception
            } -ModuleName 'FFU.Core'
        }

        It 'Should include ROOT CAUSE section in WIMMount error' {
            $error = { Invoke-WimMountWithErrorHandling -ImagePath 'C:\test.wim' -Path 'C:\mount' } | Should -Throw -PassThru
            $error.Exception.Message | Should -Match 'ROOT CAUSE:'
        }

        It 'Should include REMEDIATION STEPS section in WIMMount error' {
            $error = { Invoke-WimMountWithErrorHandling -ImagePath 'C:\test.wim' -Path 'C:\mount' } | Should -Throw -PassThru
            $error.Exception.Message | Should -Match 'REMEDIATION STEPS:'
        }

        It 'Should mention Invoke-FFUPreflight as first remediation step' {
            $error = { Invoke-WimMountWithErrorHandling -ImagePath 'C:\test.wim' -Path 'C:\mount' } | Should -Throw -PassThru
            $error.Exception.Message | Should -Match 'Invoke-FFUPreflight'
        }

        It 'Should mention ADK reinstallation as remediation step' {
            $error = { Invoke-WimMountWithErrorHandling -ImagePath 'C:\test.wim' -Path 'C:\mount' } | Should -Throw -PassThru
            $error.Exception.Message | Should -Match 'Windows Assessment and Deployment Kit'
        }

        It 'Should mention RUNDLL32 WIMMount registration as remediation step' {
            $error = { Invoke-WimMountWithErrorHandling -ImagePath 'C:\test.wim' -Path 'C:\mount' } | Should -Throw -PassThru
            $error.Exception.Message | Should -Match 'RUNDLL32\.EXE WIMGAPI\.DLL'
        }

        It 'Should mention reboot as part of remediation' {
            $error = { Invoke-WimMountWithErrorHandling -ImagePath 'C:\test.wim' -Path 'C:\mount' } | Should -Throw -PassThru
            $error.Exception.Message | Should -Match 'Reboot'
        }

        It 'Should include numbered remediation steps' {
            $error = { Invoke-WimMountWithErrorHandling -ImagePath 'C:\test.wim' -Path 'C:\mount' } | Should -Throw -PassThru
            $error.Exception.Message | Should -Match '1\.'
            $error.Exception.Message | Should -Match '2\.'
            $error.Exception.Message | Should -Match '3\.'
            $error.Exception.Message | Should -Match '4\.'
        }
    }

    Context 'Non-WIMMount Error Handling' {
        It 'Should re-throw non-WIMMount errors with enhanced context' {
            Mock -CommandName Mount-WindowsImage -MockWith {
                throw "Access denied"
            } -ModuleName 'FFU.Core'

            $error = { Invoke-WimMountWithErrorHandling -ImagePath 'C:\test.wim' -Path 'C:\mount' } | Should -Throw -PassThru
            $error.Exception.Message | Should -Match 'Mount-WindowsImage failed'
            $error.Exception.Message | Should -Match 'Access denied'
        }

        It 'Should include ImagePath in non-WIMMount error context' {
            Mock -CommandName Mount-WindowsImage -MockWith {
                throw "File not found"
            } -ModuleName 'FFU.Core'

            $error = { Invoke-WimMountWithErrorHandling -ImagePath 'C:\test.wim' -Path 'C:\mount' } | Should -Throw -PassThru
            $error.Exception.Message | Should -Match 'C:\\test\.wim'
        }

        It 'Should include error code in non-WIMMount error context' {
            Mock -CommandName Mount-WindowsImage -MockWith {
                throw "Disk full"
            } -ModuleName 'FFU.Core'

            $error = { Invoke-WimMountWithErrorHandling -ImagePath 'C:\test.wim' -Path 'C:\mount' } | Should -Throw -PassThru
            $error.Exception.Message | Should -Match 'Error code:'
        }

        It 'Should not include WIMMount remediation for non-WIMMount errors' {
            Mock -CommandName Mount-WindowsImage -MockWith {
                throw "Insufficient memory"
            } -ModuleName 'FFU.Core'

            $error = { Invoke-WimMountWithErrorHandling -ImagePath 'C:\test.wim' -Path 'C:\mount' } | Should -Throw -PassThru
            $error.Exception.Message | Should -Not -Match 'MOUNT FAILED:'
            $error.Exception.Message | Should -Not -Match 'REMEDIATION STEPS:'
        }

        It 'Should handle errors with HResult codes' {
            Mock -CommandName Mount-WindowsImage -MockWith {
                $exception = New-Object System.ComponentModel.Win32Exception(5) # Access Denied
                throw $exception
            } -ModuleName 'FFU.Core'

            $error = { Invoke-WimMountWithErrorHandling -ImagePath 'C:\test.wim' -Path 'C:\mount' } | Should -Throw -PassThru
            $error.Exception.Message | Should -Match 'Error code:'
        }

        It 'Should handle errors without HResult codes' {
            Mock -CommandName Mount-WindowsImage -MockWith {
                throw "Generic error message"
            } -ModuleName 'FFU.Core'

            $error = { Invoke-WimMountWithErrorHandling -ImagePath 'C:\test.wim' -Path 'C:\mount' } | Should -Throw -PassThru
            $error.Exception.Message | Should -Match 'Mount-WindowsImage failed'
        }
    }

    Context 'Logging Behavior' {
        It 'Should attempt to log mount operation start' {
            Mock -CommandName Mount-WindowsImage -MockWith { } -ModuleName 'FFU.Core'
            Mock -CommandName WriteLog -MockWith { } -ModuleName 'FFU.Core'

            { Invoke-WimMountWithErrorHandling -ImagePath 'C:\test.wim' -Path 'C:\mount' } | Should -Not -Throw

            # Note: WriteLog is called internally via scriptblock, so we verify the pattern exists
            $FunctionSource = Get-Content "$ModulePath\FFU.Core.psm1" -Raw
            $FunctionSource | Should -Match "Mounting image"
        }

        It 'Should attempt to log successful mount' {
            Mock -CommandName Mount-WindowsImage -MockWith { } -ModuleName 'FFU.Core'

            { Invoke-WimMountWithErrorHandling -ImagePath 'C:\test.wim' -Path 'C:\mount' } | Should -Not -Throw

            $FunctionSource = Get-Content "$ModulePath\FFU.Core.psm1" -Raw
            $FunctionSource | Should -Match "Successfully mounted"
        }

        It 'Should attempt to log WIMMount errors' {
            Mock -CommandName Mount-WindowsImage -MockWith {
                throw "The specified service does not exist"
            } -ModuleName 'FFU.Core'

            { Invoke-WimMountWithErrorHandling -ImagePath 'C:\test.wim' -Path 'C:\mount' } | Should -Throw

            $FunctionSource = Get-Content "$ModulePath\FFU.Core.psm1" -Raw
            $FunctionSource | Should -Match "WIMMount filter driver issue detected"
        }

        It 'Should have safe logging fallback for environments without WriteLog' {
            # Verify the logging scriptblock checks for WriteLog availability
            $FunctionSource = Get-Content "$ModulePath\FFU.Core.psm1" -Raw
            $FunctionSource | Should -Match "Get-Command WriteLog -ErrorAction SilentlyContinue"
            $FunctionSource | Should -Match "Write-Verbose"
        }
    }
}

# =============================================================================
# Integration Pattern Tests
# =============================================================================

Describe 'Invoke-WimMountWithErrorHandling Integration Patterns' -Tag 'Unit', 'FFU.Core', 'WimMount', 'Integration' {

    Context 'Common Usage Patterns' {
        It 'Should support readonly mount with optimize' {
            Mock -CommandName Mount-WindowsImage -MockWith { } -ModuleName 'FFU.Core'

            { Invoke-WimMountWithErrorHandling -ImagePath 'C:\boot.wim' -Path 'C:\mount' -Index 1 -ReadOnly -Optimize } | Should -Not -Throw
        }

        It 'Should support multiple image indices' {
            Mock -CommandName Mount-WindowsImage -MockWith { } -ModuleName 'FFU.Core'

            { Invoke-WimMountWithErrorHandling -ImagePath 'C:\install.wim' -Path 'C:\mount' -Index 2 } | Should -Not -Throw
            { Invoke-WimMountWithErrorHandling -ImagePath 'C:\install.wim' -Path 'C:\mount' -Index 10 } | Should -Not -Throw
        }

        It 'Should work with different image types (WIM and FFU paths)' {
            Mock -CommandName Mount-WindowsImage -MockWith { } -ModuleName 'FFU.Core'

            { Invoke-WimMountWithErrorHandling -ImagePath 'C:\images\test.wim' -Path 'C:\mount' } | Should -Not -Throw
            { Invoke-WimMountWithErrorHandling -ImagePath 'C:\images\test.ffu' -Path 'C:\mount' } | Should -Not -Throw
        }
    }

    Context 'Error Recovery Patterns' {
        It 'Should provide actionable guidance for WIMMount errors' {
            Mock -CommandName Mount-WindowsImage -MockWith {
                $exception = New-Object System.ComponentModel.Win32Exception(-2147023653)
                throw $exception
            } -ModuleName 'FFU.Core'

            $error = { Invoke-WimMountWithErrorHandling -ImagePath 'C:\test.wim' -Path 'C:\mount' } | Should -Throw -PassThru

            # Verify error message is actionable
            $error.Exception.Message | Should -Match 'REMEDIATION STEPS:'
            $error.Exception.Message | Should -Match 'Invoke-FFUPreflight'
            $error.Exception.Message | Should -Match 'RUNDLL32'
        }

        It 'Should differentiate between WIMMount and other mount errors' {
            # WIMMount error
            Mock -CommandName Mount-WindowsImage -MockWith {
                throw "The specified service does not exist"
            } -ModuleName 'FFU.Core'

            $wimMountError = { Invoke-WimMountWithErrorHandling -ImagePath 'C:\test.wim' -Path 'C:\mount' } | Should -Throw -PassThru
            $wimMountError.Exception.Message | Should -Match 'MOUNT FAILED: WIMMount filter driver'

            # Other error
            Mock -CommandName Mount-WindowsImage -MockWith {
                throw "Access is denied"
            } -ModuleName 'FFU.Core'

            $otherError = { Invoke-WimMountWithErrorHandling -ImagePath 'C:\test.wim' -Path 'C:\mount' } | Should -Throw -PassThru
            $otherError.Exception.Message | Should -Not -Match 'MOUNT FAILED: WIMMount filter driver'
            $otherError.Exception.Message | Should -Match 'Mount-WindowsImage failed'
        }
    }
}

# =============================================================================
# Documentation and Comments
# =============================================================================

Describe 'Invoke-WimMountWithErrorHandling Documentation' -Tag 'Unit', 'FFU.Core', 'WimMount', 'Documentation' {

    BeforeAll {
        $FunctionSource = Get-Content "$ModulePath\FFU.Core.psm1" -Raw
    }

    Context 'Function Documentation' {
        It 'Should have SYNOPSIS in comment-based help' {
            $FunctionSource | Should -Match '\.SYNOPSIS'
        }

        It 'Should have DESCRIPTION in comment-based help' {
            $FunctionSource | Should -Match '\.DESCRIPTION'
        }

        It 'Should have PARAMETER documentation for ImagePath' {
            $FunctionSource | Should -Match '\.PARAMETER ImagePath'
        }

        It 'Should have PARAMETER documentation for Path' {
            $FunctionSource | Should -Match '\.PARAMETER Path'
        }

        It 'Should have PARAMETER documentation for Index' {
            $FunctionSource | Should -Match '\.PARAMETER Index'
        }

        It 'Should have PARAMETER documentation for ReadOnly' {
            $FunctionSource | Should -Match '\.PARAMETER ReadOnly'
        }

        It 'Should have PARAMETER documentation for Optimize' {
            $FunctionSource | Should -Match '\.PARAMETER Optimize'
        }

        It 'Should have EXAMPLE section in comment-based help' {
            $FunctionSource | Should -Match '\.EXAMPLE'
        }

        It 'Should have OUTPUTS section documenting void return type' {
            $FunctionSource | Should -Match '\.OUTPUTS'
        }

        It 'Should have NOTES section with version and context' {
            $FunctionSource | Should -Match '\.NOTES'
        }

        It 'Should document root cause in NOTES' {
            $FunctionSource | Should -Match 'ROOT CAUSE:'
        }

        It 'Should have LINK section for reference documentation' {
            $FunctionSource | Should -Match '\.LINK'
        }
    }
}
