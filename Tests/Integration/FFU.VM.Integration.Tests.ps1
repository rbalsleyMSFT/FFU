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

    # Create stub function for WriteLog (defined in FFU.Common, called by FFU.VM)
    # This allows mocking WriteLog without having FFU.Common loaded
    function global:WriteLog { param($LogText) }

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

    # Create stub functions for DISM cmdlets if not available
    if (-not (Get-Command Get-WindowsImage -ErrorAction SilentlyContinue)) {
        function global:Get-WindowsImage { param($Mounted) }
        function global:Dismount-WindowsImage { param($Path, $Discard, $Save) }
        function global:Clear-WindowsCorruptMountPoint { }
    }

    # Create stub functions for other cmdlets used by FFU.VM
    if (-not (Get-Command Invoke-Process -ErrorAction SilentlyContinue)) {
        function global:Invoke-Process { param($FilePath, $ArgumentList) return @{ ExitCode = 0 } }
    }
    if (-not (Get-Command Remove-InProgressItems -ErrorAction SilentlyContinue)) {
        function global:Remove-InProgressItems { param($FFUDevelopmentPath, $DriversFolder, $OfficePath) }
    }
    if (-not (Get-Command Clear-CurrentRunDownloads -ErrorAction SilentlyContinue)) {
        function global:Clear-CurrentRunDownloads { param($FFUDevelopmentPath, $AppsPath, $DefenderPath, $MSRTPath, $OneDrivePath, $EdgePath, $KBPath, $DriversFolder, $orchestrationPath, $OfficePath) }
    }
    if (-not (Get-Command Restore-RunJsonBackups -ErrorAction SilentlyContinue)) {
        function global:Restore-RunJsonBackups { param($FFUDevelopmentPath, $DriversFolder, $orchestrationPath) }
    }
    if (-not (Get-Command Dismount-ScratchVhdx -ErrorAction SilentlyContinue)) {
        function global:Dismount-ScratchVhdx { param($VhdxPath) }
    }
    if (-not (Get-Command Remove-Apps -ErrorAction SilentlyContinue)) {
        function global:Remove-Apps { }
    }
    if (-not (Get-Command Test-VMStateRunning -ErrorAction SilentlyContinue)) {
        function global:Test-VMStateRunning { param($State) return $State -eq 'Running' }
    }
    if (-not (Get-Command New-SecureRandomPassword -ErrorAction SilentlyContinue)) {
        function global:New-SecureRandomPassword { param($Length, $IncludeSpecialChars) return (ConvertTo-SecureString 'MockP@ss123!' -AsPlainText -Force) }
    }
    if (-not (Get-Command Register-UserAccountCleanup -ErrorAction SilentlyContinue)) {
        function global:Register-UserAccountCleanup { param($Username) }
    }
    if (-not (Get-Command Register-NetworkShareCleanup -ErrorAction SilentlyContinue)) {
        function global:Register-NetworkShareCleanup { param($ShareName) }
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
            # Note: Hyper-V cmdlets have strong type validation, so we mock to return
            # types that won't cause type errors downstream. For Set-VMFirmware,
            # we need to mock the entire function to skip type checking.
            Mock New-VM {
                return [PSCustomObject]@{ Name = $Name; State = 'Off'; Generation = $Generation }
            } -ModuleName 'FFU.VM'
            Mock Set-VMProcessor { } -ModuleName 'FFU.VM'
            Mock Add-VMDvdDrive { } -ModuleName 'FFU.VM'
            # Return null to avoid type issues with Set-VMFirmware FirstBootDevice parameter
            Mock Get-VMHardDiskDrive { return $null } -ModuleName 'FFU.VM'
            # Skip Set-VMFirmware since it has strict type requirements
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

        It 'Should attempt TPM configuration (non-critical)' {
            New-FFUVM -VMName '_FFU-Test-VM' -VMPath 'C:\VM' -Memory 8GB -VHDXPath 'C:\test.vhdx' -Processors 4 -AppsISO 'C:\apps.iso'

            # Verify HGS Guardian creation was attempted
            # TPM config is in try/catch and continues on failure (non-critical)
            # We verify the Guardian was created, which triggers the TPM chain
            Should -Invoke New-HgsGuardian -ModuleName 'FFU.VM' -Times 1
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

# =============================================================================
# Remove-FFUVM Mock-Based Integration Tests
# =============================================================================

Describe 'Remove-FFUVM Integration' -Tag 'Integration', 'FFU.VM', 'VMCleanup' {

    BeforeAll {
        Mock WriteLog { } -ModuleName 'FFU.VM'
    }

    Context 'VM Removal Workflow (Mocked)' {

        BeforeEach {
            Mock Get-VM {
                return [PSCustomObject]@{ Name = $Name; State = 'Off' }
            } -ModuleName 'FFU.VM'
            Mock Stop-VM { } -ModuleName 'FFU.VM'
            Mock Remove-VM { } -ModuleName 'FFU.VM'
            Mock Dismount-VHD { } -ModuleName 'FFU.VM'
            Mock Remove-Item { } -ModuleName 'FFU.VM'
            Mock Get-SmbShare { return $null } -ModuleName 'FFU.VM'
            Mock Test-Path { return $true } -ModuleName 'FFU.VM'
            Mock Remove-HgsGuardian { } -ModuleName 'FFU.VM'
            Mock Get-ChildItem { return @() } -ModuleName 'FFU.VM'
            Mock Get-WindowsImage { return $null } -ModuleName 'FFU.VM'
            Mock Invoke-Process { return @{ ExitCode = 0 } } -ModuleName 'FFU.VM'
        }

        It 'Should call Remove-VM for existing VM' {
            Remove-FFUVM -VMName '_FFU-Test-VM' -VMPath 'C:\VM' -InstallApps $true -FFUDevelopmentPath 'C:\FFU' -Username 'ffu_user' -ShareName 'FFUCaptureShare'

            Should -Invoke Remove-VM -ModuleName 'FFU.VM' -Times 1 -ParameterFilter {
                $Name -eq '_FFU-Test-VM'
            }
        }

        It 'Should attempt HGS Guardian cleanup' {
            Remove-FFUVM -VMName '_FFU-Test-VM' -VMPath 'C:\VM' -InstallApps $true -FFUDevelopmentPath 'C:\FFU' -Username 'ffu_user' -ShareName 'FFUCaptureShare'

            Should -Invoke Remove-HgsGuardian -ModuleName 'FFU.VM' -Times 1
        }

        It 'Should handle VM not found gracefully' {
            Mock Get-VM { return $null } -ModuleName 'FFU.VM'

            # Should not throw when VM doesn't exist
            { Remove-FFUVM -VMName '_FFU-NonExistent' -VMPath 'C:\VM' -InstallApps $true -FFUDevelopmentPath 'C:\FFU' -Username 'ffu_user' -ShareName 'FFUCaptureShare' } |
                Should -Not -Throw
        }
    }

    Context 'Cleanup Operations (Mocked)' {

        BeforeEach {
            Mock Get-VM { return $null } -ModuleName 'FFU.VM'
            Mock Remove-SmbShare { } -ModuleName 'FFU.VM'
            Mock Remove-Item { } -ModuleName 'FFU.VM'
            Mock Test-Path { return $true } -ModuleName 'FFU.VM'
            Mock Get-WindowsImage { return $null } -ModuleName 'FFU.VM'
            Mock Invoke-Process { return @{ ExitCode = 0 } } -ModuleName 'FFU.VM'
        }

        It 'Should attempt mounted image cleanup' {
            Remove-FFUVM -VMName '_FFU-Test' -VMPath 'C:\VM' -InstallApps $true -FFUDevelopmentPath 'C:\FFU' -Username 'ffu_user' -ShareName 'FFUCaptureShare'

            # Get-WindowsImage should be called to check for mounted images
            Should -Invoke Get-WindowsImage -ModuleName 'FFU.VM' -Times 1
        }
    }
}

# =============================================================================
# Set-CaptureFFU Mock-Based Integration Tests
# =============================================================================

Describe 'Set-CaptureFFU Integration' -Tag 'Integration', 'FFU.VM', 'CaptureSetup' {

    BeforeAll {
        Mock WriteLog { } -ModuleName 'FFU.VM'
    }

    Context 'Capture Setup Workflow (Mocked)' {

        BeforeEach {
            # Mock SMB share operations
            Mock Get-SmbShare { return $null } -ModuleName 'FFU.VM'
            Mock New-SmbShare { } -ModuleName 'FFU.VM'
            Mock Grant-SmbShareAccess { } -ModuleName 'FFU.VM'
            Mock New-Item { return [PSCustomObject]@{ FullName = $Path } } -ModuleName 'FFU.VM'
            Mock Test-Path { return $true } -ModuleName 'FFU.VM'

            # Mock local user functions within module scope
            Mock Get-LocalUserAccount { return $null } -ModuleName 'FFU.VM'
            Mock New-LocalUserAccount { return $true } -ModuleName 'FFU.VM'
            Mock Set-LocalUserAccountExpiry { return (Get-Date).AddHours(12) } -ModuleName 'FFU.VM'

            # Mock New-SecureRandomPassword (from FFU.Core)
            Mock New-SecureRandomPassword {
                return (ConvertTo-SecureString 'MockP@ssword123!' -AsPlainText -Force)
            } -ModuleName 'FFU.VM'

            # Mock cleanup registration
            Mock Register-UserAccountCleanup { } -ModuleName 'FFU.VM'
            Mock Register-NetworkShareCleanup { } -ModuleName 'FFU.VM'
        }

        It 'Should create local user for capture' {
            $password = ConvertTo-SecureString 'TestP@ss123!' -AsPlainText -Force

            Set-CaptureFFU -Username 'ffu_user' -ShareName 'FFUCaptureShare' -FFUCaptureLocation 'C:\FFU' -Password $password

            Should -Invoke New-LocalUserAccount -ModuleName 'FFU.VM' -Times 1 -ParameterFilter {
                $Username -eq 'ffu_user'
            }
        }

        It 'Should create SMB share for FFU capture location' {
            $password = ConvertTo-SecureString 'TestP@ss123!' -AsPlainText -Force

            Set-CaptureFFU -Username 'ffu_user' -ShareName 'FFUCaptureShare' -FFUCaptureLocation 'C:\FFU' -Password $password

            Should -Invoke New-SmbShare -ModuleName 'FFU.VM' -Times 1 -ParameterFilter {
                $Name -eq 'FFUCaptureShare' -and $Path -eq 'C:\FFU'
            }
        }

        It 'Should grant share access to capture user' {
            $password = ConvertTo-SecureString 'TestP@ss123!' -AsPlainText -Force

            Set-CaptureFFU -Username 'ffu_user' -ShareName 'FFUCaptureShare' -FFUCaptureLocation 'C:\FFU' -Password $password

            Should -Invoke Grant-SmbShareAccess -ModuleName 'FFU.VM' -Times 1 -ParameterFilter {
                $AccountName -eq 'ffu_user'
            }
        }

        It 'Should set user account expiry' {
            $password = ConvertTo-SecureString 'TestP@ss123!' -AsPlainText -Force

            Set-CaptureFFU -Username 'ffu_user' -ShareName 'FFUCaptureShare' -FFUCaptureLocation 'C:\FFU' -Password $password

            Should -Invoke Set-LocalUserAccountExpiry -ModuleName 'FFU.VM' -Times 1
        }
    }

    Context 'Share Already Exists (Mocked)' {

        It 'Should skip share creation when share exists' {
            Mock Get-SmbShare { return [PSCustomObject]@{ Name = 'FFUCaptureShare' } } -ModuleName 'FFU.VM'
            Mock New-SmbShare { } -ModuleName 'FFU.VM'
            Mock Grant-SmbShareAccess { } -ModuleName 'FFU.VM'
            Mock Test-Path { return $true } -ModuleName 'FFU.VM'
            # Return a mock user object with Dispose method (Add-Member ScriptMethod)
            Mock Get-LocalUserAccount {
                $mockUser = [PSCustomObject]@{ Name = 'ffu_user' }
                $mockUser | Add-Member -MemberType ScriptMethod -Name 'Dispose' -Value { } -Force
                return $mockUser
            } -ModuleName 'FFU.VM'
            Mock Set-LocalUserPassword { return $true } -ModuleName 'FFU.VM'
            Mock Set-LocalUserAccountExpiry { return (Get-Date).AddHours(12) } -ModuleName 'FFU.VM'

            $password = ConvertTo-SecureString 'TestP@ss123!' -AsPlainText -Force

            Set-CaptureFFU -Username 'ffu_user' -ShareName 'FFUCaptureShare' -FFUCaptureLocation 'C:\FFU' -Password $password

            Should -Invoke New-SmbShare -ModuleName 'FFU.VM' -Times 0
        }
    }
}

# =============================================================================
# Get-FFUEnvironment Mock-Based Integration Tests
# =============================================================================

Describe 'Get-FFUEnvironment Integration' -Tag 'Integration', 'FFU.VM', 'Environment' {

    BeforeAll {
        Mock WriteLog { } -ModuleName 'FFU.VM'
    }

    Context 'Environment Detection (Mocked)' {

        BeforeEach {
            Mock Get-VM {
                return @(
                    [PSCustomObject]@{ Name = '_FFU-Build-VM'; State = 'Running' },
                    [PSCustomObject]@{ Name = '_FFU-Test-VM'; State = 'Off' }
                )
            } -ModuleName 'FFU.VM'
            Mock Get-ChildItem { return @() } -ModuleName 'FFU.VM'
            Mock Test-Path { return $true } -ModuleName 'FFU.VM'
            Mock Stop-VM { } -ModuleName 'FFU.VM'
            Mock Remove-FFUVM { } -ModuleName 'FFU.VM'
            Mock Remove-InProgressItems { } -ModuleName 'FFU.VM'
            Mock Get-Disk { return @() } -ModuleName 'FFU.VM'
            Mock Get-Volume { return @() } -ModuleName 'FFU.VM'
            Mock Get-WindowsImage { return $null } -ModuleName 'FFU.VM'
            Mock Invoke-Process { return @{ ExitCode = 0 } } -ModuleName 'FFU.VM'
            Mock Clear-WindowsCorruptMountPoint { } -ModuleName 'FFU.VM'
            Mock Get-LocalUserAccount { return $null } -ModuleName 'FFU.VM'
            Mock Remove-Item { } -ModuleName 'FFU.VM'
        }

        It 'Should find FFU VMs by name pattern' {
            Get-FFUEnvironment -FFUDevelopmentPath 'C:\FFUDevelopment' -CleanupCurrentRunDownloads $false `
                -UserName 'ffu_user' -RemoveApps $false -AppsPath 'C:\FFU\Apps' `
                -RemoveUpdates $false -KBPath 'C:\FFU\KB' -AppsISO 'C:\FFU\Apps.iso'

            # Verify Get-VM was called
            Should -Invoke Get-VM -ModuleName 'FFU.VM'
        }

        It 'Should stop running FFU VMs' {
            Get-FFUEnvironment -FFUDevelopmentPath 'C:\FFUDevelopment' -CleanupCurrentRunDownloads $false `
                -UserName 'ffu_user' -RemoveApps $false -AppsPath 'C:\FFU\Apps' `
                -RemoveUpdates $false -KBPath 'C:\FFU\KB' -AppsISO 'C:\FFU\Apps.iso'

            # Stop-VM should be called for running VMs starting with _FFU-
            Should -Invoke Stop-VM -ModuleName 'FFU.VM'
        }
    }
}

# =============================================================================
# Real Infrastructure Tests (Conditional)
# =============================================================================

Describe 'FFU.VM Real Infrastructure Tests' -Tag 'Integration', 'FFU.VM', 'RealInfra' {

    BeforeAll {
        Mock WriteLog { } -ModuleName 'FFU.VM'
    }

    It 'Should query actual VMs when Hyper-V available' -Skip:(-not $script:HyperVAvailable) {
        # Real test - only runs when Hyper-V is available
        $vms = Get-VM -ErrorAction SilentlyContinue

        # Just verify we can query without error
        { Get-VM -ErrorAction Stop } | Should -Not -Throw
    }

    It 'Should detect Hyper-V service status' -Skip:(-not $script:HyperVAvailable) {
        $service = Get-Service -Name vmms
        $service.Status | Should -Be 'Running'
    }
}
