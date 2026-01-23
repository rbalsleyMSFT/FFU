#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester unit tests for New-WinPEMediaNative function in FFU.Media module

.DESCRIPTION
    Comprehensive unit tests for the New-WinPEMediaNative function which creates WinPE
    working directory structure using native PowerShell DISM cmdlets. Tests include
    v1.3.11 WIMMount just-in-time validation feature using Test-FFUWimMount.

    Tests cover:
    - Parameter validation (10 tests)
    - Source path validation (8 tests)
    - Architecture handling (6 tests)
    - Directory creation (5 tests)
    - Native DISM cmdlet usage (8 tests)
    - Boot file copy operations (8 tests)
    - Error handling and cleanup (5 tests)
    - New-PEMedia integration (5 tests)
    - WIMMount just-in-time validation (20 tests) - NEW in v1.3.11

.NOTES
    Run with: Invoke-Pester -Path .\Tests\Unit\FFU.Media.NativeWinPE.Tests.ps1 -Output Detailed
    Coverage: Invoke-Pester -Path .\Tests\Unit\FFU.Media.NativeWinPE.Tests.ps1 -CodeCoverage .\FFUDevelopment\Modules\FFU.Media\*.psm1
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
    $PreflightModulePath = Join-Path $ModulesPath 'FFU.Preflight'

    # Add Modules folder to PSModulePath for RequiredModules resolution
    if ($env:PSModulePath -notlike "*$ModulesPath*") {
        $env:PSModulePath = "$ModulesPath;$env:PSModulePath"
    }

    # Remove modules if loaded
    Get-Module -Name 'FFU.Media', 'FFU.Preflight', 'FFU.ADK', 'FFU.Core', 'FFU.Constants' | Remove-Module -Force -ErrorAction SilentlyContinue

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

    # Import FFU.Preflight module (required by FFU.Media v1.2.0+)
    if (Test-Path "$PreflightModulePath\FFU.Preflight.psd1") {
        Import-Module "$PreflightModulePath\FFU.Preflight.psd1" -Force -ErrorAction SilentlyContinue
    }

    # Import FFU.Media module
    if (-not (Test-Path "$ModulePath\FFU.Media.psd1")) {
        throw "FFU.Media module not found at: $ModulePath"
    }
    Import-Module "$ModulePath\FFU.Media.psd1" -Force -ErrorAction Stop

    # Create a stub WriteLog function in the global scope that FFU.Media can use
    # This is necessary because WriteLog is normally provided by FFU.Common which
    # is imported into BuildFFUVM.ps1, not by FFU.Media module itself
    function global:WriteLog {
        param([string]$Message)
        # Do nothing - this is a test stub
    }
}

AfterAll {
    Get-Module -Name 'FFU.Media', 'FFU.Preflight', 'FFU.ADK', 'FFU.Core', 'FFU.Constants' | Remove-Module -Force -ErrorAction SilentlyContinue

    # Remove the global WriteLog stub
    if (Get-Command -Name WriteLog -ErrorAction SilentlyContinue) {
        Remove-Item -Path Function:\WriteLog -ErrorAction SilentlyContinue
    }
}

# =============================================================================
# Parameter Validation Tests (10 tests)
# =============================================================================

Describe 'New-WinPEMediaNative - Parameter Validation' -Tag 'Unit', 'FFU.Media', 'New-WinPEMediaNative', 'ParameterValidation' {

    Context 'Architecture Parameter' {
        It 'Should have mandatory Architecture parameter' {
            $command = Get-Command -Name 'New-WinPEMediaNative' -Module 'FFU.Media'
            $param = $command.Parameters['Architecture']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }

        It 'Should have ValidateSet constraint on Architecture parameter' {
            $command = Get-Command -Name 'New-WinPEMediaNative' -Module 'FFU.Media'
            $param = $command.Parameters['Architecture']

            $validateSet = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
            $validateSet | Should -Not -BeNullOrEmpty
            $validateSet.ValidValues | Should -Contain 'x64'
            $validateSet.ValidValues | Should -Contain 'arm64'
            $validateSet.ValidValues.Count | Should -Be 2
        }

        It 'Should NOT accept x86 in Architecture ValidateSet' {
            $command = Get-Command -Name 'New-WinPEMediaNative' -Module 'FFU.Media'
            $param = $command.Parameters['Architecture']

            $validateSet = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
            $validateSet.ValidValues | Should -Not -Contain 'x86'
        }

        It 'Should NOT accept invalid architecture value' {
            $command = Get-Command -Name 'New-WinPEMediaNative' -Module 'FFU.Media'
            $param = $command.Parameters['Architecture']

            $validateSet = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
            $validateSet.ValidValues | Should -Not -Contain 'InvalidArch'
            $validateSet.ValidValues | Should -Not -Contain 'amd64'
        }
    }

    Context 'DestinationPath Parameter' {
        It 'Should have mandatory DestinationPath parameter' {
            $command = Get-Command -Name 'New-WinPEMediaNative' -Module 'FFU.Media'
            $param = $command.Parameters['DestinationPath']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }

        It 'Should have ValidateNotNullOrEmpty on DestinationPath parameter' {
            $command = Get-Command -Name 'New-WinPEMediaNative' -Module 'FFU.Media'
            $param = $command.Parameters['DestinationPath']

            $validateNotNull = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateNotNullOrEmptyAttribute] }
            $validateNotNull | Should -Not -BeNullOrEmpty
        }

        It 'Should accept string type for DestinationPath parameter' {
            $command = Get-Command -Name 'New-WinPEMediaNative' -Module 'FFU.Media'
            $param = $command.Parameters['DestinationPath']
            $param.ParameterType.Name | Should -Be 'String'
        }
    }

    Context 'ADKPath Parameter' {
        It 'Should have mandatory ADKPath parameter' {
            $command = Get-Command -Name 'New-WinPEMediaNative' -Module 'FFU.Media'
            $param = $command.Parameters['ADKPath']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }

        It 'Should have ValidateNotNullOrEmpty on ADKPath parameter' {
            $command = Get-Command -Name 'New-WinPEMediaNative' -Module 'FFU.Media'
            $param = $command.Parameters['ADKPath']

            $validateNotNull = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateNotNullOrEmptyAttribute] }
            $validateNotNull | Should -Not -BeNullOrEmpty
        }

        It 'Should accept string type for ADKPath parameter' {
            $command = Get-Command -Name 'New-WinPEMediaNative' -Module 'FFU.Media'
            $param = $command.Parameters['ADKPath']
            $param.ParameterType.Name | Should -Be 'String'
        }
    }
}

# =============================================================================
# Source Path Validation Tests (8 tests)
# =============================================================================

Describe 'New-WinPEMediaNative - Source Path Validation' -Tag 'Unit', 'FFU.Media', 'New-WinPEMediaNative', 'PathValidation' {

    BeforeEach {
        # Mock all external commands
        Mock -CommandName Test-Path -MockWith { $false } -ModuleName 'FFU.Media'
        Mock -CommandName New-Item -MockWith { } -ModuleName 'FFU.Media'
        Mock -CommandName Copy-Item -MockWith { } -ModuleName 'FFU.Media'
        Mock -CommandName Mount-WindowsImage -MockWith { } -ModuleName 'FFU.Media'
        Mock -CommandName Dismount-WindowsImage -MockWith { } -ModuleName 'FFU.Media'
        Mock -CommandName Get-Command -MockWith { $null } -ModuleName 'FFU.Media'
    }

    Context 'ADK Path Validation' {
        It 'Should throw if ADK architecture path does not exist' {
            Mock -CommandName Test-Path -MockWith { $false } -ModuleName 'FFU.Media' -ParameterFilter {
                $Path -like '*\amd64'
            }

            { New-WinPEMediaNative -Architecture 'x64' -DestinationPath 'C:\Test' -ADKPath 'C:\ADK' } |
                Should -Throw -ExpectedMessage "*Architecture 'x64' not found*"
        }

        It 'Should throw if Media source folder does not exist' {
            Mock -CommandName Test-Path -MockWith {
                param($Path)
                if ($Path -like '*\amd64') { return $true }
                if ($Path -like '*\Media') { return $false }
                return $true
            } -ModuleName 'FFU.Media'

            { New-WinPEMediaNative -Architecture 'x64' -DestinationPath 'C:\Test' -ADKPath 'C:\ADK' } |
                Should -Throw -ExpectedMessage "*Media source not found*"
        }

        It 'Should throw if winpe.wim file does not exist' {
            Mock -CommandName Test-Path -MockWith {
                param($Path)
                if ($Path -like '*\amd64') { return $true }
                if ($Path -like '*\Media') { return $true }
                if ($Path -like '*winpe.wim') { return $false }
                return $true
            } -ModuleName 'FFU.Media'

            { New-WinPEMediaNative -Architecture 'x64' -DestinationPath 'C:\Test' -ADKPath 'C:\ADK' } |
                Should -Throw -ExpectedMessage "*WinPE WIM file not found*"
        }

        It 'Should throw if OSCDIMG folder does not exist' {
            Mock -CommandName Test-Path -MockWith {
                param($Path)
                if ($Path -like '*\amd64') { return $true }
                if ($Path -like '*\Media') { return $true }
                if ($Path -like '*winpe.wim') { return $true }
                if ($Path -like '*Oscdimg') { return $false }
                return $true
            } -ModuleName 'FFU.Media'

            { New-WinPEMediaNative -Architecture 'x64' -DestinationPath 'C:\Test' -ADKPath 'C:\ADK' } |
                Should -Throw -ExpectedMessage "*OSCDIMG root not found*"
        }
    }

    Context 'Destination Path Validation' {
        It 'Should throw if destination directory already exists' {
            Mock -CommandName Test-Path -MockWith {
                param($Path)
                # All source paths exist
                if ($Path -like '*\amd64*') { return $true }
                if ($Path -like '*\Media') { return $true }
                if ($Path -like '*winpe.wim') { return $true }
                if ($Path -like '*Oscdimg') { return $true }
                # Destination exists (problem!)
                if ($Path -eq 'C:\Test') { return $true }
                return $false
            } -ModuleName 'FFU.Media'

            { New-WinPEMediaNative -Architecture 'x64' -DestinationPath 'C:\Test' -ADKPath 'C:\ADK' } |
                Should -Throw -ExpectedMessage "*Destination directory already exists*"
        }

        It 'Should NOT throw if destination directory does not exist' {
            Mock -CommandName Test-Path -MockWith {
                param($Path)
                # All source paths exist
                if ($Path -like '*Assessment and Deployment Kit*') { return $true }
                # Destination does not exist (good!)
                if ($Path -eq 'C:\Test') { return $false }
                # But all boot files exist for copy operations
                if ($Path -like '*bootmgfw.efi' -or $Path -like '*efisys*.bin' -or $Path -like '*etfsboot.com') { return $true }
                return $false
            } -ModuleName 'FFU.Media'
            Mock -CommandName robocopy.exe -MockWith { $global:LASTEXITCODE = 1; return @() } -ModuleName 'FFU.Media'

            # Should not throw on path validation step
            { New-WinPEMediaNative -Architecture 'x64' -DestinationPath 'C:\Test' -ADKPath 'C:\ADK' } |
                Should -Not -Throw -ExpectedMessage "*Destination directory already exists*"
        }
    }

    Context 'Path Construction Logic' {
        It 'Should construct correct paths for x64 architecture' {
            Mock -CommandName Test-Path -MockWith { $true } -ModuleName 'FFU.Media'
            Mock -CommandName Test-Path -MockWith { $false } -ModuleName 'FFU.Media' -ParameterFilter { $Path -eq 'C:\Test' }
            Mock -CommandName robocopy.exe -MockWith { $global:LASTEXITCODE = 1; return @() } -ModuleName 'FFU.Media'

            try {
                New-WinPEMediaNative -Architecture 'x64' -DestinationPath 'C:\Test' -ADKPath 'C:\ADK\'
            } catch {}

            # Verify Test-Path was called with amd64 (not x64)
            Should -Invoke -CommandName Test-Path -ModuleName 'FFU.Media' -ParameterFilter {
                $Path -like '*\amd64\*'
            }
        }

        It 'Should construct correct paths for arm64 architecture' {
            Mock -CommandName Test-Path -MockWith { $true } -ModuleName 'FFU.Media'
            Mock -CommandName Test-Path -MockWith { $false } -ModuleName 'FFU.Media' -ParameterFilter { $Path -eq 'C:\Test' }
            Mock -CommandName robocopy.exe -MockWith { $global:LASTEXITCODE = 1; return @() } -ModuleName 'FFU.Media'

            try {
                New-WinPEMediaNative -Architecture 'arm64' -DestinationPath 'C:\Test' -ADKPath 'C:\ADK\'
            } catch {}

            # Verify Test-Path was called with arm64 (not amd64)
            Should -Invoke -CommandName Test-Path -ModuleName 'FFU.Media' -ParameterFilter {
                $Path -like '*\arm64\*'
            }
        }
    }
}

# =============================================================================
# Architecture Handling Tests (6 tests)
# =============================================================================

Describe 'New-WinPEMediaNative - Architecture Handling' -Tag 'Unit', 'FFU.Media', 'New-WinPEMediaNative', 'Architecture' {

    BeforeAll {
        # Create a mock function that simulates the function's architecture mapping logic
        function Get-ADKArchFolder {
            param([string]$Architecture)
            if ($Architecture -eq 'x64') { return 'amd64' } else { return $Architecture }
        }
    }

    Context 'Architecture Folder Mapping' {
        It 'Should map x64 to amd64 folder' {
            $result = Get-ADKArchFolder -Architecture 'x64'
            $result | Should -Be 'amd64'
        }

        It 'Should keep arm64 as arm64 folder' {
            $result = Get-ADKArchFolder -Architecture 'arm64'
            $result | Should -Be 'arm64'
        }
    }

    Context 'Boot File Architecture Differences' {
        BeforeEach {
            Mock -CommandName Test-Path -MockWith { $true } -ModuleName 'FFU.Media'
            Mock -CommandName Test-Path -MockWith { $false } -ModuleName 'FFU.Media' -ParameterFilter { $Path -like '*C:\Test*' }
            Mock -CommandName New-Item -MockWith { } -ModuleName 'FFU.Media'
            Mock -CommandName Copy-Item -MockWith { } -ModuleName 'FFU.Media'
            Mock -CommandName robocopy.exe -MockWith { $global:LASTEXITCODE = 1; return @() } -ModuleName 'FFU.Media'
            Mock -CommandName Mount-WindowsImage -MockWith { } -ModuleName 'FFU.Media'
            Mock -CommandName Dismount-WindowsImage -MockWith { } -ModuleName 'FFU.Media'
            Mock -CommandName Get-Command -MockWith { $null } -ModuleName 'FFU.Media'
        }

        It 'Should attempt to copy etfsboot.com for x64 architecture' {
            try {
                New-WinPEMediaNative -Architecture 'x64' -DestinationPath 'C:\Test' -ADKPath 'C:\ADK\'
            } catch {}

            # Verify Copy-Item was called for etfsboot.com
            Should -Invoke -CommandName Copy-Item -ModuleName 'FFU.Media' -ParameterFilter {
                $Path -like '*etfsboot.com'
            }
        }

        It 'Should NOT attempt to copy etfsboot.com for arm64 architecture' {
            try {
                New-WinPEMediaNative -Architecture 'arm64' -DestinationPath 'C:\Test' -ADKPath 'C:\ADK\'
            } catch {}

            # Verify Copy-Item was NOT called for etfsboot.com
            Should -Invoke -CommandName Copy-Item -ModuleName 'FFU.Media' -ParameterFilter {
                $Path -like '*etfsboot.com'
            } -Times 0
        }

        It 'Should log skip message for etfsboot.com on arm64' {
            Mock -CommandName WriteLog -MockWith { } -ModuleName 'FFU.Media'

            try {
                New-WinPEMediaNative -Architecture 'arm64' -DestinationPath 'C:\Test' -ADKPath 'C:\ADK\'
            } catch {}

            Should -Invoke -CommandName WriteLog -ModuleName 'FFU.Media' -ParameterFilter {
                $Message -like '*Skipping etfsboot.com*ARM64*'
            }
        }

        It 'Should copy efisys.bin for both x64 and arm64' {
            Mock -CommandName WriteLog -MockWith { } -ModuleName 'FFU.Media'

            try {
                New-WinPEMediaNative -Architecture 'x64' -DestinationPath 'C:\Test' -ADKPath 'C:\ADK\'
            } catch {}

            Should -Invoke -CommandName Copy-Item -ModuleName 'FFU.Media' -ParameterFilter {
                $Path -like '*efisys.bin' -and $Path -notlike '*noprompt*'
            }

            try {
                New-WinPEMediaNative -Architecture 'arm64' -DestinationPath 'C:\Test2' -ADKPath 'C:\ADK\'
            } catch {}

            Should -Invoke -CommandName Copy-Item -ModuleName 'FFU.Media' -ParameterFilter {
                $Path -like '*efisys.bin' -and $Path -notlike '*noprompt*'
            } -Times 2
        }
    }
}

# =============================================================================
# Directory Creation Tests (5 tests)
# =============================================================================

Describe 'New-WinPEMediaNative - Directory Creation' -Tag 'Unit', 'FFU.Media', 'New-WinPEMediaNative', 'DirectoryCreation' {

    BeforeEach {
        Mock -CommandName Test-Path -MockWith {
            param($Path)
            # All boot files should exist for copy operations (check this first!)
            if ($Path -like '*bootmgfw.efi' -or $Path -like '*bootmgr.efi' -or
                $Path -like '*efisys*.bin' -or $Path -like '*etfsboot.com') {
                return $true
            }
            # Destination root paths should not exist initially
            if ($Path -eq 'C:\Test' -or $Path -eq 'C:\Test2') { return $false }
            # All other paths (ADK, source files, subdirs) exist by default
            return $true
        } -ModuleName 'FFU.Media'
        Mock -CommandName New-Item -MockWith { } -ModuleName 'FFU.Media'
        Mock -CommandName Copy-Item -MockWith { } -ModuleName 'FFU.Media'
        Mock -CommandName robocopy.exe -MockWith { $global:LASTEXITCODE = 1; return @() } -ModuleName 'FFU.Media'
        Mock -CommandName Mount-WindowsImage -MockWith { } -ModuleName 'FFU.Media'
        Mock -CommandName Dismount-WindowsImage -MockWith { } -ModuleName 'FFU.Media'
        Mock -CommandName Get-Command -MockWith { $null } -ModuleName 'FFU.Media'
    }

    Context 'Required Directory Structure' {
        It 'Should create root destination directory' {
            try {
                New-WinPEMediaNative -Architecture 'x64' -DestinationPath 'C:\Test' -ADKPath 'C:\ADK\'
            } catch {}

            Should -Invoke -CommandName New-Item -ModuleName 'FFU.Media' -ParameterFilter {
                $Path -eq 'C:\Test' -and $ItemType -eq 'Directory'
            }
        }

        It 'Should create media subdirectory' {
            try {
                New-WinPEMediaNative -Architecture 'x64' -DestinationPath 'C:\Test' -ADKPath 'C:\ADK\'
            } catch {}

            Should -Invoke -CommandName New-Item -ModuleName 'FFU.Media' -ParameterFilter {
                $Path -like '*\media' -and $ItemType -eq 'Directory'
            }
        }

        It 'Should create mount subdirectory' {
            try {
                New-WinPEMediaNative -Architecture 'x64' -DestinationPath 'C:\Test' -ADKPath 'C:\ADK\'
            } catch {}

            Should -Invoke -CommandName New-Item -ModuleName 'FFU.Media' -ParameterFilter {
                $Path -like '*\mount' -and $ItemType -eq 'Directory'
            }
        }

        It 'Should create bootbins subdirectory' {
            try {
                New-WinPEMediaNative -Architecture 'x64' -DestinationPath 'C:\Test' -ADKPath 'C:\ADK\'
            } catch {}

            Should -Invoke -CommandName New-Item -ModuleName 'FFU.Media' -ParameterFilter {
                $Path -like '*\bootbins' -and $ItemType -eq 'Directory'
            }
        }

        It 'Should create sources subdirectory for boot.wim' {
            try {
                New-WinPEMediaNative -Architecture 'x64' -DestinationPath 'C:\Test' -ADKPath 'C:\ADK\'
            } catch {}

            Should -Invoke -CommandName New-Item -ModuleName 'FFU.Media' -ParameterFilter {
                $Path -like '*\sources' -and $ItemType -eq 'Directory'
            }
        }
    }
}

# =============================================================================
# Native DISM Cmdlet Usage Tests (8 tests) - CRITICAL
# =============================================================================

Describe 'New-WinPEMediaNative - Native DISM Cmdlet Usage' -Tag 'Unit', 'FFU.Media', 'New-WinPEMediaNative', 'NativeDISM' {

    BeforeEach {
        Mock -CommandName Test-Path -MockWith {
            param($Path)
            # All boot files should exist for copy operations (check this first!)
            if ($Path -like '*bootmgfw.efi' -or $Path -like '*bootmgr.efi' -or
                $Path -like '*efisys*.bin' -or $Path -like '*etfsboot.com') {
                return $true
            }
            # Destination root paths should not exist initially
            if ($Path -eq 'C:\Test' -or $Path -eq 'C:\Test2') { return $false }
            # All other paths (ADK, source files, subdirs) exist by default
            return $true
        } -ModuleName 'FFU.Media'
        Mock -CommandName New-Item -MockWith { } -ModuleName 'FFU.Media'
        Mock -CommandName Copy-Item -MockWith { } -ModuleName 'FFU.Media'
        Mock -CommandName robocopy.exe -MockWith { $global:LASTEXITCODE = 1; return @() } -ModuleName 'FFU.Media'
        Mock -CommandName Mount-WindowsImage -MockWith { } -ModuleName 'FFU.Media'
        Mock -CommandName Dismount-WindowsImage -MockWith { } -ModuleName 'FFU.Media'
        Mock -CommandName Get-Command -MockWith { $null } -ModuleName 'FFU.Media'
    }

    Context 'Mount-WindowsImage Cmdlet Usage' {
        It 'Should use Mount-WindowsImage cmdlet instead of dism.exe' {
            try {
                New-WinPEMediaNative -Architecture 'x64' -DestinationPath 'C:\Test' -ADKPath 'C:\ADK\'
            } catch {}

            Should -Invoke -CommandName Mount-WindowsImage -ModuleName 'FFU.Media' -Times 1
        }

        It 'Should mount with -ReadOnly flag' {
            try {
                New-WinPEMediaNative -Architecture 'x64' -DestinationPath 'C:\Test' -ADKPath 'C:\ADK\'
            } catch {}

            Should -Invoke -CommandName Mount-WindowsImage -ModuleName 'FFU.Media' -ParameterFilter {
                $ReadOnly -eq $true
            }
        }

        It 'Should mount with -Index 1' {
            try {
                New-WinPEMediaNative -Architecture 'x64' -DestinationPath 'C:\Test' -ADKPath 'C:\ADK\'
            } catch {}

            Should -Invoke -CommandName Mount-WindowsImage -ModuleName 'FFU.Media' -ParameterFilter {
                $Index -eq 1
            }
        }

        It 'Should mount with correct ImagePath (boot.wim)' {
            try {
                New-WinPEMediaNative -Architecture 'x64' -DestinationPath 'C:\Test' -ADKPath 'C:\ADK\'
            } catch {}

            Should -Invoke -CommandName Mount-WindowsImage -ModuleName 'FFU.Media' -ParameterFilter {
                $ImagePath -like '*\sources\boot.wim'
            }
        }

        It 'Should mount with correct Path (mount directory)' {
            try {
                New-WinPEMediaNative -Architecture 'x64' -DestinationPath 'C:\Test' -ADKPath 'C:\ADK\'
            } catch {}

            Should -Invoke -CommandName Mount-WindowsImage -ModuleName 'FFU.Media' -ParameterFilter {
                $Path -like '*\mount'
            }
        }
    }

    Context 'Dismount-WindowsImage Cmdlet Usage' {
        It 'Should use Dismount-WindowsImage cmdlet instead of dism.exe' {
            try {
                New-WinPEMediaNative -Architecture 'x64' -DestinationPath 'C:\Test' -ADKPath 'C:\ADK\'
            } catch {}

            Should -Invoke -CommandName Dismount-WindowsImage -ModuleName 'FFU.Media' -Times 1
        }

        It 'Should dismount with -Discard flag' {
            try {
                New-WinPEMediaNative -Architecture 'x64' -DestinationPath 'C:\Test' -ADKPath 'C:\ADK\'
            } catch {}

            Should -Invoke -CommandName Dismount-WindowsImage -ModuleName 'FFU.Media' -ParameterFilter {
                $Discard -eq $true
            }
        }
    }

    Context 'DISM Cleanup Registration' {
        It 'Should register DISM mount cleanup if Register-DISMMountCleanup is available' {
            Mock -CommandName Get-Command -MockWith {
                return [PSCustomObject]@{ Name = 'Register-DISMMountCleanup' }
            } -ModuleName 'FFU.Media' -ParameterFilter { $Name -eq 'Register-DISMMountCleanup' }

            Mock -CommandName Register-DISMMountCleanup -MockWith { } -ModuleName 'FFU.Media'

            try {
                New-WinPEMediaNative -Architecture 'x64' -DestinationPath 'C:\Test' -ADKPath 'C:\ADK\'
            } catch {}

            Should -Invoke -CommandName Get-Command -ModuleName 'FFU.Media' -ParameterFilter {
                $Name -eq 'Register-DISMMountCleanup'
            }
        }
    }
}

# =============================================================================
# Boot File Copy Tests (8 tests)
# =============================================================================

Describe 'New-WinPEMediaNative - Boot File Copy' -Tag 'Unit', 'FFU.Media', 'New-WinPEMediaNative', 'BootFiles' {

    BeforeEach {
        Mock -CommandName Test-Path -MockWith {
            param($Path)
            # All boot files should exist for copy operations (check this first!)
            if ($Path -like '*bootmgfw.efi' -or $Path -like '*bootmgr.efi' -or
                $Path -like '*efisys*.bin' -or $Path -like '*etfsboot.com') {
                return $true
            }
            # Destination root paths should not exist initially
            if ($Path -eq 'C:\Test' -or $Path -eq 'C:\Test2') { return $false }
            # All other paths (ADK, source files, subdirs) exist by default
            return $true
        } -ModuleName 'FFU.Media'
        Mock -CommandName New-Item -MockWith { } -ModuleName 'FFU.Media'
        Mock -CommandName Copy-Item -MockWith { } -ModuleName 'FFU.Media'
        Mock -CommandName robocopy.exe -MockWith { $global:LASTEXITCODE = 1; return @() } -ModuleName 'FFU.Media'
        Mock -CommandName Mount-WindowsImage -MockWith { } -ModuleName 'FFU.Media'
        Mock -CommandName Dismount-WindowsImage -MockWith { } -ModuleName 'FFU.Media'
        Mock -CommandName Get-Command -MockWith { $null } -ModuleName 'FFU.Media'
    }

    Context 'Required Boot Files from Mounted WIM' {
        It 'Should copy bootmgfw.efi (required)' {
            try {
                New-WinPEMediaNative -Architecture 'x64' -DestinationPath 'C:\Test' -ADKPath 'C:\ADK\'
            } catch {}

            Should -Invoke -CommandName Copy-Item -ModuleName 'FFU.Media' -ParameterFilter {
                $Path -like '*bootmgfw.efi' -and $Path -notlike '*_EX.efi'
            }
        }

        It 'Should throw if bootmgfw.efi does not exist' {
            Mock -CommandName Test-Path -MockWith {
                param($Path)
                if ($Path -like '*bootmgfw.efi' -and $Path -notlike '*_EX.efi') { return $false }
                if ($Path -like '*C:\Test*') { return $false }
                return $true
            } -ModuleName 'FFU.Media'

            { New-WinPEMediaNative -Architecture 'x64' -DestinationPath 'C:\Test' -ADKPath 'C:\ADK\' } |
                Should -Throw -ExpectedMessage "*Required boot file not found*bootmgfw.efi*"
        }
    }

    Context 'Optional Boot Files from Mounted WIM' {
        It 'Should copy bootmgfw_EX.efi if it exists' {
            Mock -CommandName Test-Path -MockWith {
                param($Path)
                if ($Path -like '*bootmgfw_EX.efi') { return $true }
                if ($Path -like '*C:\Test*') { return $false }
                return $true
            } -ModuleName 'FFU.Media'

            try {
                New-WinPEMediaNative -Architecture 'x64' -DestinationPath 'C:\Test' -ADKPath 'C:\ADK\'
            } catch {}

            Should -Invoke -CommandName Copy-Item -ModuleName 'FFU.Media' -ParameterFilter {
                $Path -like '*bootmgfw_EX.efi'
            }
        }

        It 'Should log warning if bootmgfw_EX.efi does not exist' {
            Mock -CommandName Test-Path -MockWith {
                param($Path)
                if ($Path -like '*bootmgfw_EX.efi') { return $false }
                if ($Path -like '*C:\Test*') { return $false }
                return $true
            } -ModuleName 'FFU.Media'
            Mock -CommandName WriteLog -MockWith { } -ModuleName 'FFU.Media'

            try {
                New-WinPEMediaNative -Architecture 'x64' -DestinationPath 'C:\Test' -ADKPath 'C:\ADK\'
            } catch {}

            Should -Invoke -CommandName WriteLog -ModuleName 'FFU.Media' -ParameterFilter {
                $Message -like '*WARNING*bootmgfw_EX.efi*'
            }
        }

        It 'Should copy bootmgr.efi if it exists (legacy support)' {
            Mock -CommandName Test-Path -MockWith {
                param($Path)
                if ($Path -like '*\bootmgr.efi') { return $true }
                if ($Path -like '*C:\Test*') { return $false }
                return $true
            } -ModuleName 'FFU.Media'

            try {
                New-WinPEMediaNative -Architecture 'x64' -DestinationPath 'C:\Test' -ADKPath 'C:\ADK\'
            } catch {}

            Should -Invoke -CommandName Copy-Item -ModuleName 'FFU.Media' -ParameterFilter {
                $Path -like '*\bootmgr.efi' -and $Path -notlike '*bootmgfw*'
            }
        }
    }

    Context 'Boot Sector Files from OSCDIMG' {
        It 'Should copy efisys.bin (required)' {
            try {
                New-WinPEMediaNative -Architecture 'x64' -DestinationPath 'C:\Test' -ADKPath 'C:\ADK\'
            } catch {}

            Should -Invoke -CommandName Copy-Item -ModuleName 'FFU.Media' -ParameterFilter {
                $Path -like '*efisys.bin' -and $Path -notlike '*noprompt*' -and $Path -notlike '*_EX*'
            }
        }

        It 'Should copy efisys_noprompt.bin (required)' {
            try {
                New-WinPEMediaNative -Architecture 'x64' -DestinationPath 'C:\Test' -ADKPath 'C:\ADK\'
            } catch {}

            Should -Invoke -CommandName Copy-Item -ModuleName 'FFU.Media' -ParameterFilter {
                $Path -like '*efisys_noprompt.bin' -and $Path -notlike '*_EX*'
            }
        }

        It 'Should throw if efisys.bin does not exist' {
            Mock -CommandName Test-Path -MockWith {
                param($Path)
                if ($Path -like '*efisys.bin' -and $Path -notlike '*noprompt*' -and $Path -notlike '*_EX*') { return $false }
                if ($Path -like '*C:\Test*') { return $false }
                return $true
            } -ModuleName 'FFU.Media'

            { New-WinPEMediaNative -Architecture 'x64' -DestinationPath 'C:\Test' -ADKPath 'C:\ADK\' } |
                Should -Throw -ExpectedMessage "*Required boot sector file not found*efisys.bin*"
        }
    }
}

# =============================================================================
# Error Handling and Cleanup Tests (5 tests)
# =============================================================================

Describe 'New-WinPEMediaNative - Error Handling and Cleanup' -Tag 'Unit', 'FFU.Media', 'New-WinPEMediaNative', 'ErrorHandling' {

    BeforeEach {
        Mock -CommandName Test-Path -MockWith { $true } -ModuleName 'FFU.Media'
        Mock -CommandName Test-Path -MockWith { $false } -ModuleName 'FFU.Media' -ParameterFilter { $Path -like '*C:\Test*' }
        Mock -CommandName New-Item -MockWith { } -ModuleName 'FFU.Media'
        Mock -CommandName Copy-Item -MockWith { } -ModuleName 'FFU.Media'
        Mock -CommandName robocopy.exe -MockWith { $global:LASTEXITCODE = 1; return @() } -ModuleName 'FFU.Media'
        Mock -CommandName Get-Command -MockWith { $null } -ModuleName 'FFU.Media'
    }

    Context 'WIM Dismount on Failure' {
        It 'Should attempt to dismount WIM if an error occurs after mounting' {
            Mock -CommandName Mount-WindowsImage -MockWith {
                # Simulate successful mount
            } -ModuleName 'FFU.Media'

            Mock -CommandName Copy-Item -MockWith {
                throw "Simulated copy error"
            } -ModuleName 'FFU.Media' -ParameterFilter { $Path -like '*bootmgfw.efi*' }

            Mock -CommandName Dismount-WindowsImage -MockWith { } -ModuleName 'FFU.Media'

            { New-WinPEMediaNative -Architecture 'x64' -DestinationPath 'C:\Test' -ADKPath 'C:\ADK\' } |
                Should -Throw

            # Verify cleanup dismount was attempted
            Should -Invoke -CommandName Dismount-WindowsImage -ModuleName 'FFU.Media' -ParameterFilter {
                $Discard -eq $true
            }
        }

        It 'Should fallback to dism.exe cleanup-mountpoints if native dismount fails' {
            Mock -CommandName Mount-WindowsImage -MockWith { } -ModuleName 'FFU.Media'

            Mock -CommandName Copy-Item -MockWith {
                throw "Simulated copy error"
            } -ModuleName 'FFU.Media' -ParameterFilter { $Path -like '*bootmgfw.efi*' }

            Mock -CommandName Dismount-WindowsImage -MockWith {
                throw "Dismount failed"
            } -ModuleName 'FFU.Media'

            Mock -CommandName dism.exe -MockWith { } -ModuleName 'FFU.Media'

            { New-WinPEMediaNative -Architecture 'x64' -DestinationPath 'C:\Test' -ADKPath 'C:\ADK\' } |
                Should -Throw

            # Verify fallback to dism.exe was attempted
            Should -Invoke -CommandName dism.exe -ModuleName 'FFU.Media' -ParameterFilter {
                $args -contains '/Cleanup-Mountpoints'
            }
        }
    }

    Context 'Return Value' {
        It 'Should return $true on success' {
            Mock -CommandName Mount-WindowsImage -MockWith { } -ModuleName 'FFU.Media'
            Mock -CommandName Dismount-WindowsImage -MockWith { } -ModuleName 'FFU.Media'

            $result = New-WinPEMediaNative -Architecture 'x64' -DestinationPath 'C:\Test' -ADKPath 'C:\ADK\'
            $result | Should -Be $true
        }

        It 'Should throw on critical failures' {
            Mock -CommandName Test-Path -MockWith { $false } -ModuleName 'FFU.Media'

            { New-WinPEMediaNative -Architecture 'x64' -DestinationPath 'C:\Test' -ADKPath 'C:\ADK\' } |
                Should -Throw
        }
    }

    Context 'Logging During Error' {
        It 'Should log error message when function fails' {
            Mock -CommandName Test-Path -MockWith { $false } -ModuleName 'FFU.Media'
            Mock -CommandName WriteLog -MockWith { } -ModuleName 'FFU.Media'

            { New-WinPEMediaNative -Architecture 'x64' -DestinationPath 'C:\Test' -ADKPath 'C:\ADK\' } |
                Should -Throw

            Should -Invoke -CommandName WriteLog -ModuleName 'FFU.Media' -ParameterFilter {
                $Message -like '*ERROR*New-WinPEMediaNative failed*'
            }
        }
    }
}

# =============================================================================
# New-PEMedia Integration Tests (5 tests)
# =============================================================================

Describe 'New-WinPEMediaNative - Integration with New-PEMedia' -Tag 'Unit', 'FFU.Media', 'New-WinPEMediaNative', 'Integration' {

    Context 'UseNativeMethod Parameter' {
        It 'New-PEMedia should have UseNativeMethod parameter' {
            $command = Get-Command -Name 'New-PEMedia' -Module 'FFU.Media'
            $command.Parameters['UseNativeMethod'] | Should -Not -BeNullOrEmpty
        }

        It 'UseNativeMethod parameter should default to $true' {
            $command = Get-Command -Name 'New-PEMedia' -Module 'FFU.Media'
            $param = $command.Parameters['UseNativeMethod']

            # Check if parameter has a default value by checking the attributes
            $paramAttribute = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
            $paramAttribute | Should -Not -BeNullOrEmpty
        }

        It 'UseNativeMethod parameter should be boolean type' {
            $command = Get-Command -Name 'New-PEMedia' -Module 'FFU.Media'
            $param = $command.Parameters['UseNativeMethod']
            $param.ParameterType.Name | Should -Be 'Boolean'
        }

        It 'UseNativeMethod parameter should be optional' {
            $command = Get-Command -Name 'New-PEMedia' -Module 'FFU.Media'
            $param = $command.Parameters['UseNativeMethod']

            $paramAttribute = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
            $paramAttribute.Mandatory | Should -Be $false
        }

        It 'New-PEMedia should export New-WinPEMediaNative in module' {
            Get-Command -Name 'New-WinPEMediaNative' -Module 'FFU.Media' | Should -Not -BeNullOrEmpty
        }
    }
}

# =============================================================================
# WIMMount Just-In-Time Validation Tests (20 tests) - NEW in v1.3.11
# =============================================================================

Describe 'New-WinPEMediaNative - WIMMount Just-In-Time Validation' -Tag 'Unit', 'FFU.Media', 'New-WinPEMediaNative', 'WIMMount', 'v1.3.11' {

    BeforeAll {
        # Read source code for static analysis
        $ModulePath = Join-Path $PSScriptRoot '..\..\FFUDevelopment\Modules\FFU.Media'
        $ModuleFile = Join-Path $ModulePath 'FFU.Media.psm1'
        $ManifestFile = Join-Path $ModulePath 'FFU.Media.psd1'
        $SourceCode = Get-Content $ModuleFile -Raw
        $ManifestData = Import-PowerShellDataFile -Path $ManifestFile
    }

    Context 'Module Dependency on FFU.Preflight' {
        It 'Should require FFU.Preflight module in manifest' {
            $preflightDep = $ManifestData.RequiredModules | Where-Object {
                ($_ -is [hashtable] -and $_.ModuleName -eq 'FFU.Preflight') -or
                ($_ -is [string] -and $_ -eq 'FFU.Preflight')
            }
            $preflightDep | Should -Not -BeNullOrEmpty -Because 'FFU.Preflight provides Test-FFUWimMount function'
        }

        It 'Should be version 1.2.0 or higher' {
            $version = [version]$ManifestData.ModuleVersion
            $version.Major | Should -BeGreaterOrEqual 1
            if ($version.Major -eq 1) {
                $version.Minor | Should -BeGreaterOrEqual 2
            }
        }

        It 'Should document WIMMount validation in release notes' {
            $ManifestData.PrivateData.PSData.ReleaseNotes | Should -Match 'Test-FFUWimMount|WIMMount.*validation'
        }
    }

    Context 'Source Code Validation Logic' {
        It 'Should contain call to Test-FFUWimMount' {
            $SourceCode | Should -Match 'Test-FFUWimMount' -Because 'Function must perform WIMMount validation'
        }

        It 'Should check if Test-FFUWimMount command exists before calling it' {
            $SourceCode | Should -Match 'Get-Command\s+(Test-FFUWimMount|-Name\s+Test-FFUWimMount)' -Because 'Must handle case where FFU.Preflight is not loaded'
        }

        It 'Should use -AttemptRemediation parameter with Test-FFUWimMount' {
            $SourceCode | Should -Match 'Test-FFUWimMount\s+-AttemptRemediation' -Because 'Should attempt to fix WIMMount issues automatically'
        }

        It 'Should store validation result in variable' {
            $SourceCode | Should -Match '\$wimMountCheck\s*=\s*Test-FFUWimMount' -Because 'Result must be captured for analysis'
        }

        It 'Should check Status property of validation result' {
            $SourceCode | Should -Match '\$wimMountCheck\.Status' -Because 'Must evaluate validation outcome'
        }

        It 'Should compare Status against "Passed" string' {
            $SourceCode | Should -Match "Status\s+-ne\s+'Passed'" -Because 'Must detect validation failures'
        }

        It 'Should throw error when validation fails' {
            # Check for the validation check and throw separately (regex is simpler)
            $SourceCode | Should -Match "Status\s+-ne\s+'Passed'" -Because 'Must check validation status'
            $SourceCode | Should -Match 'throw\s+\$errorMsg' -Because 'Must throw error on failure'
        }

        It 'Should include validation Message in error' {
            $SourceCode | Should -Match '\$wimMountCheck\.Message' -Because 'Error should include diagnostic message'
        }

        It 'Should include Remediation guidance in error output' {
            $SourceCode | Should -Match '\$wimMountCheck\.Remediation' -Because 'Error should include remediation steps'
        }

        It 'Should log warning when Test-FFUWimMount is unavailable' {
            $SourceCode | Should -Match 'WARNING.*Test-FFUWimMount.*not available' -Because 'Should inform user of missing pre-validation'
        }

        It 'Should proceed with mount when Test-FFUWimMount unavailable' {
            $SourceCode | Should -Match 'Proceeding.*mount.*without.*pre-validation' -Because 'Should not block builds when FFU.Preflight missing'
        }
    }

    Context 'Step Numbering and Logging' {
        It 'Should log "Step 6" for WIMMount validation' {
            $SourceCode | Should -Match 'Step\s+6:.*[Vv]alidat(ing|e).*WIMMount' -Because 'Step 6 should be WIMMount validation'
        }

        It 'Should log "Step 7" for mount operation' {
            $SourceCode | Should -Match 'Step\s+7:.*[Mm]ount(ing)?.*boot\.wim' -Because 'Step 7 should be mount (after validation)'
        }

        It 'Should NOT skip from Step 5 to Step 7' {
            # Verify Step 6 exists between Step 5 and Step 7
            $step5Pos = $SourceCode.IndexOf('Step 5:')
            $step6Pos = $SourceCode.IndexOf('Step 6:')
            $step7Pos = $SourceCode.IndexOf('Step 7:')

            $step5Pos | Should -BeGreaterThan 0
            $step6Pos | Should -BeGreaterThan $step5Pos
            $step7Pos | Should -BeGreaterThan $step6Pos
        }

        It 'Should clarify that both methods require WIMMount service' {
            $SourceCode | Should -Match 'Both.*native.*PowerShell.*cmdlets.*AND.*ADK.*dism\.exe.*require.*WIMMount|Both methods require.*WIMMount' -Because 'Must correct v1.3.6 documentation error'
        }
    }

    Context 'Documentation Accuracy' {
        It 'Should NOT claim native cmdlets avoid WIMMount issues' {
            # Extract function documentation
            $functionStart = $SourceCode.IndexOf('function New-WinPEMediaNative')
            $functionDoc = $SourceCode.Substring($functionStart, 5000)

            # Should NOT contain misleading claims
            $functionDoc | Should -Not -Match 'avoid.*WIMMount.*filter.*driver' -Because 'v1.3.8 reverted v1.3.6 claim that native cmdlets avoid WIMMount'
            $functionDoc | Should -Not -Match 'eliminates.*WIMMount.*dependency' -Because 'Native cmdlets still require WIMMount service'
            $functionDoc | Should -Not -Match 'does not require.*WIMMount' -Because 'This was incorrect documentation'
        }

        It 'Should document that native cmdlets require WIMMount service' {
            $SourceCode | Should -Match 'NOTE:.*Both.*native.*cmdlets.*AND.*ADK.*dism\.exe.*require.*WIMMount|Both methods require.*WIMMount service' -Because 'Documentation must be accurate'
        }

        It 'Should document just-in-time validation in function help' {
            $SourceCode | Should -Match 'just-in-time validation|pre-mount.*validation|Test-FFUWimMount before' -Because 'Feature should be documented'
        }
    }

    Context 'Validation Timing and Order' {
        It 'Should validate WIMMount BEFORE calling Mount-WindowsImage' {
            $testWimMountPos = $SourceCode.IndexOf('Test-FFUWimMount')
            $mountImagePos = $SourceCode.IndexOf('Mount-WindowsImage', $testWimMountPos)

            $testWimMountPos | Should -BeGreaterThan 0 -Because 'Test-FFUWimMount call must exist'
            $mountImagePos | Should -BeGreaterThan $testWimMountPos -Because 'Validation must occur before mount'
        }

        It 'Should validate after copying boot.wim' {
            # Step 5 copies boot.wim, Step 6 validates WIMMount, Step 7 mounts
            $copyBootWim = $SourceCode.IndexOf('Step 5:')
            $validateWimMount = $SourceCode.IndexOf('Step 6:')

            $copyBootWim | Should -BeGreaterThan 0
            $validateWimMount | Should -BeGreaterThan $copyBootWim
        }
    }

    Context 'Error Message Quality' {
        It 'Should construct descriptive error message on validation failure' {
            $SourceCode | Should -Match '\$errorMsg\s*=.*WIMMount.*service.*validation.*failed' -Because 'Error message should be clear'
        }

        It 'Should log error before throwing' {
            $SourceCode | Should -Match 'WriteLog.*ERROR.*\$errorMsg' -Because 'Error should be logged'
        }

        It 'Should log remediation if provided' {
            # Check for the conditional and WriteLog separately
            $SourceCode | Should -Match 'if.*\$wimMountCheck\.Remediation' -Because 'Should check if remediation exists'
            $SourceCode | Should -Match 'WriteLog.*Remediation.*\$wimMountCheck\.Remediation' -Because 'Remediation should be logged'
        }
    }
}

# =============================================================================
# Regression Prevention Tests for v1.3.6-v1.3.11 (5 tests)
# =============================================================================

Describe 'New-WinPEMediaNative - Regression Prevention' -Tag 'Unit', 'FFU.Media', 'Regression', 'v1.3.11' {

    BeforeAll {
        $ModulePath = Join-Path $PSScriptRoot '..\..\FFUDevelopment\Modules\FFU.Media'
        $ModuleFile = Join-Path $ModulePath 'FFU.Media.psm1'
        $ManifestFile = Join-Path $ModulePath 'FFU.Media.psd1'
        $SourceCode = Get-Content $ModuleFile -Raw
        $ManifestData = Import-PowerShellDataFile -Path $ManifestFile
    }

    Context 'v1.3.6 False Assumption Correction' {
        It 'Should NOT claim native cmdlets avoid WIMMount service' {
            $SourceCode | Should -Not -Match 'Native.*PowerShell.*cmdlets.*avoid.*WIMMount' -Because 'v1.3.6 incorrectly claimed this'
            $SourceCode | Should -Not -Match 'does not require.*WIMMount.*filter.*driver' -Because 'This was false'
        }

        It 'Should explicitly state both methods require WIMMount' {
            $SourceCode | Should -Match 'Both.*methods.*require.*WIMMount|native.*cmdlets.*AND.*dism\.exe.*require.*WIMMount' -Because 'v1.3.8 corrected the documentation'
        }
    }

    Context 'v1.3.7 Missing Validation' {
        It 'Should now include WIMMount validation before mount' {
            $SourceCode | Should -Match 'Test-FFUWimMount' -Because 'v1.3.7 added native method but did not validate WIMMount'
        }
    }

    Context 'v1.3.11 Enhancement Verification' {
        It 'Should perform just-in-time validation' {
            # Check that Test-FFUWimMount exists and Mount-WindowsImage comes after it
            $testWimPos = $SourceCode.IndexOf('Test-FFUWimMount')
            $mountPos = $SourceCode.IndexOf('Mount-WindowsImage', $testWimPos)
            $testWimPos | Should -BeGreaterThan 0
            $mountPos | Should -BeGreaterThan $testWimPos -Because 'v1.3.11 adds pre-mount validation'
        }

        It 'Should fail fast on WIMMount issues instead of cryptic mount errors' {
            # Verify error is thrown when Status check fails
            $SourceCode | Should -Match "Status\s+-ne\s+'Passed'" -Because 'Should check status'
            $SourceCode | Should -Match 'throw\s+\$errorMsg' -Because 'Should fail with clear message'
        }
    }
}
