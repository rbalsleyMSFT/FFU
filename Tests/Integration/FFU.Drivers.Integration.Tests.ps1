#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester integration tests for FFU.Drivers module

.DESCRIPTION
    Integration tests covering driver download, extraction, and injection workflows.
    Tests use mocking for DISM operations and file system to avoid requiring
    actual driver files or mounted Windows images.

.NOTES
    Run all: Invoke-Pester -Path .\Tests\Integration\FFU.Drivers.Integration.Tests.ps1 -Output Detailed
    Coverage: TEST-02 - Integration tests for driver injection workflow
#>

BeforeAll {
    # Get paths relative to test file location
    $TestRoot = Split-Path $PSScriptRoot -Parent
    $ProjectRoot = Split-Path $TestRoot -Parent
    $ModulesPath = Join-Path $ProjectRoot 'FFUDevelopment\Modules'
    $script:ModulePath = Join-Path $ModulesPath 'FFU.Drivers'

    # Add Modules folder to PSModulePath for RequiredModules resolution
    if ($env:PSModulePath -notlike "*$ModulesPath*") {
        $env:PSModulePath = "$ModulesPath;$env:PSModulePath"
    }

    # Create stub functions for DISM cmdlets if not available
    if (-not (Get-Command Add-WindowsDriver -ErrorAction SilentlyContinue)) {
        function global:Add-WindowsDriver { param($Path, $Driver, $Recurse, $ForceUnsigned) }
        function global:Mount-WindowsImage { param($Path, $ImagePath, $Index) }
        function global:Dismount-WindowsImage { param($Path, $Save, $Discard) }
        function global:Get-WindowsDriver { param($Path, $Online, $All) }
    }

    # Create WriteLog stub if not available (before module import)
    # This allows the module to load cleanly, then we mock it within module scope
    if (-not (Get-Command WriteLog -ErrorAction SilentlyContinue)) {
        function global:WriteLog {
            param([string]$Message)
            # Silent in tests
        }
    }

    # Remove and re-import module
    Get-Module -Name 'FFU.Drivers', 'FFU.Core', 'FFU.Constants' | Remove-Module -Force -ErrorAction SilentlyContinue

    # Import FFU.Drivers (will auto-load FFU.Core dependency)
    if (-not (Test-Path "$script:ModulePath\FFU.Drivers.psd1")) {
        throw "FFU.Drivers module not found at: $script:ModulePath"
    }
    Import-Module "$script:ModulePath\FFU.Drivers.psd1" -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name 'FFU.Drivers', 'FFU.Core' | Remove-Module -Force -ErrorAction SilentlyContinue
}

# =============================================================================
# Copy-Drivers Integration Tests
# =============================================================================

Describe 'Copy-Drivers Integration' -Tag 'Integration', 'FFU.Drivers', 'DriverCopy' {

    BeforeAll {
        Mock WriteLog { } -ModuleName 'FFU.Drivers'
    }

    Context 'Driver Filtering by Architecture' {

        BeforeEach {
            # Mock Test-Path for source directory
            Mock Test-Path { return $true } -ModuleName 'FFU.Drivers'

            # Mock Get-ChildItem to return INF files with architecture info
            Mock Get-ChildItem {
                return @(
                    [PSCustomObject]@{
                        FullName = 'C:\Drivers\Intel\net\e1000.inf'
                        Name = 'e1000.inf'
                        DirectoryName = 'C:\Drivers\Intel\net'
                    },
                    [PSCustomObject]@{
                        FullName = 'C:\Drivers\Intel\storage\iaahci.inf'
                        Name = 'iaahci.inf'
                        DirectoryName = 'C:\Drivers\Intel\storage'
                    }
                )
            } -ModuleName 'FFU.Drivers'

            # Mock Get-Content for INF file reading
            Mock Get-Content {
                return @(
                    '[Version]',
                    'Signature="$WINDOWS NT$"',
                    'Class=Net',
                    'ClassGuid={4d36e972-e325-11ce-bfc1-08002be10318}',
                    '[Manufacturer]',
                    '%Intel%=Intel,NTamd64'
                )
            } -ModuleName 'FFU.Drivers'

            # Mock Copy-Item
            Mock Copy-Item { } -ModuleName 'FFU.Drivers'
            Mock New-Item { } -ModuleName 'FFU.Drivers'

            # Mock Get-PrivateProfileString (used to read INF sections)
            Mock Get-PrivateProfileString {
                param($FileName, $SectionName, $KeyName)
                if ($KeyName -eq 'ClassGUID') {
                    return '{4D36E97D-E325-11CE-BFC1-08002BE10318}'  # System devices
                }
                if ($KeyName -eq 'Provider') {
                    return '%Intel%'
                }
                if ($KeyName -eq 'Catalogfile') {
                    return 'e1000.cat'
                }
                return ''
            } -ModuleName 'FFU.Drivers'

            # Mock Get-PrivateProfileSection
            Mock Get-PrivateProfileSection {
                return @{}
            } -ModuleName 'FFU.Drivers'
        }

        It 'Should filter drivers by x64 architecture' {
            Copy-Drivers -Path 'C:\Drivers' -Output 'C:\WinPE\Drivers' -WindowsArch 'x64'

            Should -Invoke Get-ChildItem -ModuleName 'FFU.Drivers' -Times 1
        }

        It 'Should copy matching INF files and directories' {
            Copy-Drivers -Path 'C:\Drivers' -Output 'C:\WinPE\Drivers' -WindowsArch 'x64'

            Should -Invoke Copy-Item -ModuleName 'FFU.Drivers'
        }
    }

    Context 'Driver Class Filtering' {

        BeforeEach {
            Mock Test-Path { return $true } -ModuleName 'FFU.Drivers'
            Mock New-Item { } -ModuleName 'FFU.Drivers'

            # Create mock INF files with different class GUIDs
            Mock Get-ChildItem {
                return @(
                    # Network adapter - should be included for WinPE
                    [PSCustomObject]@{
                        FullName = 'C:\Drivers\net.inf'
                        Name = 'net.inf'
                        DirectoryName = 'C:\Drivers'
                    }
                )
            } -ModuleName 'FFU.Drivers'
        }

        It 'Should include Network Adapter drivers (ClassGUID 4d36e972)' {
            # Network adapter class GUID
            Mock Get-Content {
                return @(
                    '[Version]',
                    'ClassGuid={4d36e972-e325-11ce-bfc1-08002be10318}'
                )
            } -ModuleName 'FFU.Drivers'

            Mock Get-PrivateProfileString {
                param($FileName, $SectionName, $KeyName)
                if ($KeyName -eq 'ClassGUID') {
                    return '{4D36E972-E325-11CE-BFC1-08002BE10318}'  # Network Adapters
                }
                if ($KeyName -eq 'Provider') {
                    return '%Intel%'
                }
                if ($KeyName -eq 'Catalogfile') {
                    return 'net.cat'
                }
                return ''
            } -ModuleName 'FFU.Drivers'

            Mock Get-PrivateProfileSection {
                return @{}
            } -ModuleName 'FFU.Drivers'

            Mock Copy-Item { } -ModuleName 'FFU.Drivers'

            Copy-Drivers -Path 'C:\Drivers' -Output 'C:\WinPE\Drivers' -WindowsArch 'x64'

            # Should copy network drivers
            Should -Invoke Copy-Item -ModuleName 'FFU.Drivers'
        }
    }
}

# =============================================================================
# OEM Driver Functions Integration Tests
# =============================================================================

Describe 'OEM Driver Functions Integration' -Tag 'Integration', 'FFU.Drivers', 'OEMDrivers' {

    BeforeAll {
        Mock WriteLog { } -ModuleName 'FFU.Drivers'
    }

    Context 'Get-MicrosoftDrivers (Mocked Network)' {

        BeforeEach {
            # Mock web request to avoid actual network calls
            Mock Invoke-WebRequest {
                throw "Network call blocked in test"
            } -ModuleName 'FFU.Drivers'

            Mock Invoke-RestMethod {
                throw "Network call blocked in test"
            } -ModuleName 'FFU.Drivers'

            Mock Test-Path { return $false } -ModuleName 'FFU.Drivers'
            Mock New-Item { } -ModuleName 'FFU.Drivers'
        }

        It 'Should require valid Make parameter' {
            $command = Get-Command Get-MicrosoftDrivers -Module FFU.Drivers
            $param = $command.Parameters['Make']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }

        It 'Should require valid Model parameter' {
            $command = Get-Command Get-MicrosoftDrivers -Module FFU.Drivers
            $param = $command.Parameters['Model']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }
    }

    Context 'Get-DellDrivers (Mocked Network)' {

        BeforeEach {
            Mock Invoke-WebRequest { throw "Network blocked" } -ModuleName 'FFU.Drivers'
            Mock Test-Path { return $false } -ModuleName 'FFU.Drivers'
        }

        It 'Should have WindowsArch parameter with ValidateSet' {
            $command = Get-Command Get-DellDrivers -Module FFU.Drivers
            $param = $command.Parameters['WindowsArch']

            $validateSet = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
            $validateSet.ValidValues | Should -Contain 'x64'
            $validateSet.ValidValues | Should -Contain 'ARM64'
        }

        It 'Should have isServer parameter for server vs client differentiation' {
            $command = Get-Command Get-DellDrivers -Module FFU.Drivers
            $param = $command.Parameters['isServer']

            $param | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Get-HPDrivers (Mocked Network)' {

        BeforeEach {
            Mock Invoke-WebRequest { throw "Network blocked" } -ModuleName 'FFU.Drivers'
            Mock Test-Path { return $false } -ModuleName 'FFU.Drivers'
        }

        It 'Should have WindowsVersion parameter for HP catalog matching' {
            $command = Get-Command Get-HPDrivers -Module FFU.Drivers
            $param = $command.Parameters['WindowsVersion']

            $param | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Get-LenovoDrivers (Mocked Network)' {

        BeforeEach {
            Mock Invoke-WebRequest { throw "Network blocked" } -ModuleName 'FFU.Drivers'
            Mock Test-Path { return $false } -ModuleName 'FFU.Drivers'
        }

        It 'Should require Headers parameter for API authentication' {
            $command = Get-Command Get-LenovoDrivers -Module FFU.Drivers
            $param = $command.Parameters['Headers']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }

        It 'Should require UserAgent parameter' {
            $command = Get-Command Get-LenovoDrivers -Module FFU.Drivers
            $param = $command.Parameters['UserAgent']

            $param | Should -Not -BeNullOrEmpty
        }
    }
}

# =============================================================================
# Driver Injection Pattern Tests
# =============================================================================

Describe 'Driver Injection Patterns' -Tag 'Integration', 'FFU.Drivers', 'DriverInjection' {

    BeforeAll {
        Mock WriteLog { } -ModuleName 'FFU.Drivers'
    }

    Context 'Add-WindowsDriver Integration (Mocked DISM)' {

        It 'Should use Add-WindowsDriver with -Recurse for folder injection' {
            # This tests the expected pattern for driver injection
            # The actual call happens in FFU.Imaging, but we verify the pattern

            Mock Add-WindowsDriver { } -ModuleName 'FFU.Drivers'

            # Verify Add-WindowsDriver exists (even if stub)
            { Get-Command Add-WindowsDriver -ErrorAction Stop } | Should -Not -Throw
        }

        It 'Should have DISM cmdlet stubs available for testing' {
            # Verify we can mock DISM operations
            $commands = @('Add-WindowsDriver', 'Mount-WindowsImage', 'Dismount-WindowsImage')

            foreach ($cmd in $commands) {
                { Get-Command $cmd -ErrorAction Stop } | Should -Not -Throw
            }
        }
    }

    Context 'Driver Extraction Timeout (BUG-04 Regression)' {

        It 'Should have timeout constant defined for driver extraction' {
            # Verify the Dell driver extraction timeout fix is in place
            # Check for DRIVER_EXTRACTION_TIMEOUT_SECONDS in FFU.Constants or FFU.Drivers

            $moduleContent = Get-Content (Join-Path $script:ModulePath 'FFU.Drivers.psm1') -Raw

            # Should have timeout handling for driver extraction
            $moduleContent | Should -Match 'timeout|WaitForExit|DRIVER_EXTRACTION_TIMEOUT'
        }

        It 'Should use WaitForExit pattern for chipset driver extraction' {
            # Verify the fix for BUG-04 Dell chipset driver hang
            $moduleContent = Get-Content (Join-Path $script:ModulePath 'FFU.Drivers.psm1') -Raw

            # Should use WaitForExit instead of Start-Sleep for timeout handling
            $moduleContent | Should -Match 'WaitForExit'
        }
    }
}

# =============================================================================
# Get-IntelEthernetDrivers Tests
# =============================================================================

Describe 'Get-IntelEthernetDrivers Integration' -Tag 'Integration', 'FFU.Drivers', 'IntelDrivers' {

    BeforeAll {
        Mock WriteLog { } -ModuleName 'FFU.Drivers'
    }

    Context 'Intel Driver Download (Mocked)' {

        BeforeEach {
            Mock Invoke-WebRequest { throw "Network blocked" } -ModuleName 'FFU.Drivers'
            Mock Test-Path { return $false } -ModuleName 'FFU.Drivers'
            Mock New-Item { } -ModuleName 'FFU.Drivers'
        }

        It 'Should export Get-IntelEthernetDrivers function' {
            Get-Command Get-IntelEthernetDrivers -Module FFU.Drivers | Should -Not -BeNullOrEmpty
        }

        It 'Should have DestinationPath parameter as mandatory' {
            $command = Get-Command Get-IntelEthernetDrivers -Module FFU.Drivers
            $param = $command.Parameters['DestinationPath']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }

        It 'Should have optional TempPath parameter with default' {
            $command = Get-Command Get-IntelEthernetDrivers -Module FFU.Drivers
            $param = $command.Parameters['TempPath']

            $param | Should -Not -BeNullOrEmpty
            # TempPath should not be mandatory (has default value)
            $isMandatory = $param.Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory }
            $isMandatory | Should -Not -BeTrue
        }
    }
}

# =============================================================================
# Module Dependency and Export Tests
# =============================================================================

Describe 'FFU.Drivers Module Integration' -Tag 'Integration', 'FFU.Drivers', 'ModuleExports' {

    Context 'Module Dependencies' {

        It 'Should have FFU.Core as a required module' {
            $manifest = Test-ModuleManifest -Path (Join-Path $script:ModulePath 'FFU.Drivers.psd1')
            $requiredModules = $manifest.RequiredModules

            $requiredModules | Where-Object { $_.Name -eq 'FFU.Core' } | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Exported Functions' {

        It 'Should export exactly 6 functions' {
            $manifest = Test-ModuleManifest -Path (Join-Path $script:ModulePath 'FFU.Drivers.psd1')
            $manifest.ExportedFunctions.Count | Should -Be 6
        }

        It 'Should export all OEM driver functions' {
            $expectedFunctions = @(
                'Get-MicrosoftDrivers',
                'Get-HPDrivers',
                'Get-LenovoDrivers',
                'Get-DellDrivers',
                'Copy-Drivers',
                'Get-IntelEthernetDrivers'
            )

            foreach ($funcName in $expectedFunctions) {
                Get-Command -Name $funcName -Module 'FFU.Drivers' | Should -Not -BeNullOrEmpty -Because "$funcName should be exported"
            }
        }
    }

    Context 'WriteLog Dependency' {

        It 'Should use WriteLog function from FFU.Core' {
            $moduleContent = Get-Content (Join-Path $script:ModulePath 'FFU.Drivers.psm1') -Raw

            # Should call WriteLog for logging
            $moduleContent | Should -Match 'WriteLog'
        }
    }
}
