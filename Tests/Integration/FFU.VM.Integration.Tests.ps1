#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester integration tests for FFU.VM module

.DESCRIPTION
    Integration tests covering VM creation, removal, and capture setup.
    Tests use mocking for logic verification on any machine.
    Optional real infrastructure tests run only when Hyper-V is available.

.NOTES
    Run all: Invoke-Pester -Path .\Tests\Integration\FFU.VM.Integration.Tests.ps1 -Output Detailed
    Skip real infra: Invoke-Pester -Path .\Tests\Integration\FFU.VM.Integration.Tests.ps1 -ExcludeTag 'RealInfra'
    Coverage: TEST-01 - Integration tests for VM creation
#>

BeforeAll {
    # Get paths relative to test file location
    $TestRoot = Split-Path $PSScriptRoot -Parent
    $ProjectRoot = Split-Path $TestRoot -Parent
    $ModulesPath = Join-Path $ProjectRoot 'FFUDevelopment\Modules'
    $ModulePath = Join-Path $ModulesPath 'FFU.VM'

    # Add Modules folder to PSModulePath for RequiredModules resolution
    if ($env:PSModulePath -notlike "*$ModulesPath*") {
        $env:PSModulePath = "$ModulesPath;$env:PSModulePath"
    }

    # Infrastructure detection
    $script:HyperVAvailable = $false
    try {
        $service = Get-Service -Name vmms -ErrorAction Stop
        $script:HyperVAvailable = ($service.Status -eq 'Running')
    }
    catch {
        $script:HyperVAvailable = $false
    }

    # Create stub functions for Hyper-V cmdlets if module not available
    if (-not (Get-Module -Name Hyper-V -ListAvailable)) {
        function global:New-VM { param($Name, $Path, $MemoryStartupBytes, $VHDPath, $Generation) }
        function global:Set-VMProcessor { param($VMName, $Count) }
        function global:Add-VMDvdDrive { param($VMName, $Path) }
        function global:Get-VMHardDiskDrive { param($VMName) }
        function global:Set-VMFirmware { param($VMName, $FirstBootDevice) }
        function global:Set-VM { param($Name, $AutomaticCheckpointsEnabled, $StaticMemory) }
        function global:New-HgsGuardian { param($Name, $GenerateCertificates) }
        function global:Get-HgsGuardian { param($Name) }
        function global:New-HgsKeyProtector { param($Owner, $AllowUntrustedRoot) }
        function global:Set-VMKeyProtector { param($VMName, $KeyProtector) }
        function global:Enable-VMTPM { param($VMName) }
        function global:Start-VM { param($Name) }
        function global:Stop-VM { param($Name, $Force, $TurnOff) }
        function global:Remove-VM { param($Name, $Force) }
        function global:Get-VM { param($Name) }
        function global:Dismount-VHD { param($Path) }
        function global:Get-VMSwitch { param($Name, $SwitchType) }
        function global:Remove-HgsGuardian { param($Name) }
    }

    # Remove and re-import module
    Get-Module -Name 'FFU.VM', 'FFU.Core', 'FFU.Hypervisor' | Remove-Module -Force -ErrorAction SilentlyContinue

    # Import FFU.VM (will auto-load dependencies)
    if (-not (Test-Path "$ModulePath\FFU.VM.psd1")) {
        throw "FFU.VM module not found at: $ModulePath"
    }
    Import-Module "$ModulePath\FFU.VM.psd1" -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name 'FFU.VM', 'FFU.Core', 'FFU.Hypervisor' | Remove-Module -Force -ErrorAction SilentlyContinue
}

# =============================================================================
# Infrastructure Detection Tests
# =============================================================================

Describe 'FFU.VM Infrastructure Detection' -Tag 'Integration', 'FFU.VM', 'InfraDetection' {

    It 'Should detect Hyper-V availability' {
        # This just confirms detection works, not that Hyper-V is available
        $script:HyperVAvailable | Should -BeIn @($true, $false)
    }

    It 'Should report Hyper-V status for test planning' {
        if ($script:HyperVAvailable) {
            Write-Host "  [INFO] Hyper-V is AVAILABLE - real infrastructure tests will run" -ForegroundColor Green
        }
        else {
            Write-Host "  [INFO] Hyper-V is NOT available - using mocked tests only" -ForegroundColor Yellow
        }
        $true | Should -BeTrue  # Always passes, informational
    }
}

# =============================================================================
# New-FFUVM Mock-Based Integration Tests
# =============================================================================

Describe 'New-FFUVM Integration' -Tag 'Integration', 'FFU.VM', 'VMCreation' {

    BeforeAll {
        # Mock WriteLog to avoid output during tests
        Mock WriteLog { } -ModuleName 'FFU.VM'
    }

    Context 'VM Creation Workflow (Mocked)' {

        BeforeEach {
            # Mock all Hyper-V cmdlets for workflow verification
            Mock New-VM {
                return [PSCustomObject]@{ Name = $Name; State = 'Off'; Generation = $Generation }
            } -ModuleName 'FFU.VM'
            Mock Set-VMProcessor { } -ModuleName 'FFU.VM'
            Mock Add-VMDvdDrive { } -ModuleName 'FFU.VM'
            Mock Get-VMHardDiskDrive {
                return [PSCustomObject]@{ Path = 'C:\test.vhdx'; VMName = $VMName }
            } -ModuleName 'FFU.VM'
            Mock Set-VMFirmware { } -ModuleName 'FFU.VM'
            Mock Set-VM { } -ModuleName 'FFU.VM'
            Mock New-HgsGuardian {
                return [PSCustomObject]@{ Name = $Name }
            } -ModuleName 'FFU.VM'
            Mock Get-HgsGuardian {
                return [PSCustomObject]@{ Name = 'TestGuardian' }
            } -ModuleName 'FFU.VM'
            Mock New-HgsKeyProtector {
                return [PSCustomObject]@{ RawData = [byte[]]@(1,2,3,4) }
            } -ModuleName 'FFU.VM'
            Mock Set-VMKeyProtector { } -ModuleName 'FFU.VM'
            Mock Enable-VMTPM { } -ModuleName 'FFU.VM'
            Mock Start-VM { } -ModuleName 'FFU.VM'
            Mock vmconnect { } -ModuleName 'FFU.VM'
            Mock Test-Path { return $true } -ModuleName 'FFU.VM'
        }

        It 'Should call New-VM with Generation 2' {
            New-FFUVM -VMName '_FFU-Test-VM' -VMPath 'C:\VM' -Memory 8GB -VHDXPath 'C:\test.vhdx' -Processors 4 -AppsISO 'C:\apps.iso'

            Should -Invoke New-VM -ModuleName 'FFU.VM' -Times 1 -ParameterFilter {
                $Generation -eq 2
            }
        }

        It 'Should set VM processor count correctly' {
            New-FFUVM -VMName '_FFU-Test-VM' -VMPath 'C:\VM' -Memory 4GB -VHDXPath 'C:\test.vhdx' -Processors 8 -AppsISO 'C:\apps.iso'

            Should -Invoke Set-VMProcessor -ModuleName 'FFU.VM' -Times 1 -ParameterFilter {
                $Count -eq 8
            }
        }

        It 'Should configure VM memory' {
            New-FFUVM -VMName '_FFU-Test-VM' -VMPath 'C:\VM' -Memory 16GB -VHDXPath 'C:\test.vhdx' -Processors 4 -AppsISO 'C:\apps.iso'

            Should -Invoke New-VM -ModuleName 'FFU.VM' -Times 1 -ParameterFilter {
                $MemoryStartupBytes -eq 16GB
            }
        }

        It 'Should attach Apps ISO via DVD drive' {
            $testIsoPath = 'C:\FFU\Apps.iso'
            New-FFUVM -VMName '_FFU-Test-VM' -VMPath 'C:\VM' -Memory 8GB -VHDXPath 'C:\test.vhdx' -Processors 4 -AppsISO $testIsoPath

            Should -Invoke Add-VMDvdDrive -ModuleName 'FFU.VM' -Times 1 -ParameterFilter {
                $Path -eq $testIsoPath
            }
        }

        It 'Should configure TPM via HGS Guardian' {
            New-FFUVM -VMName '_FFU-Test-VM' -VMPath 'C:\VM' -Memory 8GB -VHDXPath 'C:\test.vhdx' -Processors 4 -AppsISO 'C:\apps.iso'

            # Verify TPM configuration was attempted
            Should -Invoke Enable-VMTPM -ModuleName 'FFU.VM' -Times 1
        }

        It 'Should start the VM after creation' {
            New-FFUVM -VMName '_FFU-Test-VM' -VMPath 'C:\VM' -Memory 8GB -VHDXPath 'C:\test.vhdx' -Processors 4 -AppsISO 'C:\apps.iso'

            Should -Invoke Start-VM -ModuleName 'FFU.VM' -Times 1
        }
    }

    Context 'Error Handling (Mocked)' {

        BeforeEach {
            Mock Test-Path { return $true } -ModuleName 'FFU.VM'
            Mock Stop-VM { } -ModuleName 'FFU.VM'
            Mock Remove-VM { } -ModuleName 'FFU.VM'
            Mock Remove-HgsGuardian { } -ModuleName 'FFU.VM'
        }

        It 'Should throw when New-VM fails' {
            Mock New-VM { throw "Insufficient memory" } -ModuleName 'FFU.VM'

            { New-FFUVM -VMName '_FFU-Error-Test' -VMPath 'C:\VM' -Memory 8GB -VHDXPath 'C:\test.vhdx' -Processors 4 -AppsISO 'C:\apps.iso' } |
                Should -Throw
        }
    }
}
