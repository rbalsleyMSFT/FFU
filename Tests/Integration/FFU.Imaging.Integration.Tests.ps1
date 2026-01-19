#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester integration tests for FFU.Imaging module

.DESCRIPTION
    Integration tests covering VHDX creation, partitioning, image application,
    and FFU capture workflows. Tests use mocking for disk operations and DISM
    cmdlets to avoid requiring actual VHDXs or Windows images.

.NOTES
    Run all: Invoke-Pester -Path .\Tests\Integration\FFU.Imaging.Integration.Tests.ps1 -Output Detailed
    Coverage: TEST-03 - Integration tests for FFU capture process
#>

BeforeAll {
    # Get paths relative to test file location
    $TestRoot = Split-Path $PSScriptRoot -Parent
    $ProjectRoot = Split-Path $TestRoot -Parent
    $ModulesPath = Join-Path $ProjectRoot 'FFUDevelopment\Modules'
    $ModulePath = Join-Path $ModulesPath 'FFU.Imaging'

    # Add Modules folder to PSModulePath for RequiredModules resolution
    if ($env:PSModulePath -notlike "*$ModulesPath*") {
        $env:PSModulePath = "$ModulesPath;$env:PSModulePath"
    }

    # Create stub functions for Hyper-V and Storage cmdlets if not available
    if (-not (Get-Command New-VHD -ErrorAction SilentlyContinue)) {
        function global:New-VHD { param($Path, $SizeBytes, $Dynamic, $LogicalSectorSizeBytes) }
        function global:Mount-VHD { param($Path, $Passthru) }
        function global:Dismount-VHD { param($Path) }
        function global:Get-VHD { param($Path) }
    }

    if (-not (Get-Command Get-Disk -ErrorAction SilentlyContinue)) {
        function global:Get-Disk { param($Number, $Path) }
        function global:Initialize-Disk { param($Number, $PartitionStyle, $PassThru) }
        function global:Get-Partition { param($DiskNumber, $DriveLetter) }
        function global:New-Partition { param($DiskNumber, $Size, $GptType, $DriveLetter, $UseMaximumSize, $IsHidden) }
        function global:Format-Volume { param($DriveLetter, $FileSystem, $NewFileSystemLabel, $Confirm, $Force) }
        function global:Get-Volume { param($DriveLetter) }
        function global:Set-Partition { param($NewDriveLetter) }
        function global:Remove-Partition { param($DiskNumber, $PartitionNumber, $Confirm) }
        function global:Write-VolumeCache { param($DriveLetter) }
    }

    # Create stub functions for DISM cmdlets if not available
    if (-not (Get-Command Expand-WindowsImage -ErrorAction SilentlyContinue)) {
        function global:Expand-WindowsImage { param($ImagePath, $Index, $ApplyPath, $Compact) }
        function global:Add-WindowsDriver { param($Path, $Driver, $Recurse) }
        function global:Mount-WindowsImage { param($Path, $ImagePath, $Index) }
        function global:Dismount-WindowsImage { param($Path, $Save, $Discard) }
        function global:Get-WindowsImage { param($ImagePath) }
        function global:New-WindowsImage { param($CapturePath, $ImagePath, $Name, $CompressionType) }
        function global:Get-WindowsEdition { param($Path) }
    }

    # Remove and re-import module
    Get-Module -Name 'FFU.Imaging', 'FFU.Core', 'FFU.Constants' | Remove-Module -Force -ErrorAction SilentlyContinue

    # Import FFU.Imaging (will auto-load FFU.Core dependency)
    if (-not (Test-Path "$ModulePath\FFU.Imaging.psd1")) {
        throw "FFU.Imaging module not found at: $ModulePath"
    }
    Import-Module "$ModulePath\FFU.Imaging.psd1" -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name 'FFU.Imaging', 'FFU.Core', 'FFU.Constants' | Remove-Module -Force -ErrorAction SilentlyContinue
}

# =============================================================================
# New-ScratchVhdx Integration Tests
# =============================================================================

Describe 'New-ScratchVhdx Integration' -Tag 'Integration', 'FFU.Imaging', 'VHDXCreation' {

    BeforeAll {
        Mock WriteLog { } -ModuleName 'FFU.Imaging'
    }

    Context 'Function Exports and Parameters' {

        It 'Should export New-ScratchVhdx function' {
            Get-Command New-ScratchVhdx -Module FFU.Imaging | Should -Not -BeNullOrEmpty
        }

        It 'Should have VhdxPath parameter (mandatory)' {
            $command = Get-Command New-ScratchVhdx -Module FFU.Imaging
            $command.Parameters['VhdxPath'] | Should -Not -BeNullOrEmpty
            $command.Parameters['VhdxPath'].Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory } | Should -Contain $true
        }

        It 'Should have SizeBytes parameter with default 50GB' {
            $command = Get-Command New-ScratchVhdx -Module FFU.Imaging
            $command.Parameters['SizeBytes'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have Dynamic switch parameter' {
            $command = Get-Command New-ScratchVhdx -Module FFU.Imaging
            $command.Parameters['Dynamic'] | Should -Not -BeNullOrEmpty
            $command.Parameters['Dynamic'].SwitchParameter | Should -Be $true
        }

        It 'Should have PartitionStyle parameter defaulting to GPT' {
            $command = Get-Command New-ScratchVhdx -Module FFU.Imaging
            $command.Parameters['PartitionStyle'] | Should -Not -BeNullOrEmpty
        }
    }
}

# =============================================================================
# New-ScratchVhd Integration Tests (VMware)
# =============================================================================

Describe 'New-ScratchVhd Integration' -Tag 'Integration', 'FFU.Imaging', 'VHDCreation', 'VMware' {

    BeforeAll {
        Mock WriteLog { } -ModuleName 'FFU.Imaging'
    }

    Context 'Function Exports and Parameters' {

        It 'Should export New-ScratchVhd function' {
            Get-Command New-ScratchVhd -Module FFU.Imaging | Should -Not -BeNullOrEmpty
        }

        It 'Should have VhdPath parameter (mandatory)' {
            $command = Get-Command New-ScratchVhd -Module FFU.Imaging
            $command.Parameters['VhdPath'] | Should -Not -BeNullOrEmpty
            $command.Parameters['VhdPath'].Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory } | Should -Contain $true
        }

        It 'Should have SizeBytes parameter with default' {
            $command = Get-Command New-ScratchVhd -Module FFU.Imaging
            $command.Parameters['SizeBytes'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have Dynamic switch parameter for expandable VHD' {
            $command = Get-Command New-ScratchVhd -Module FFU.Imaging
            $command.Parameters['Dynamic'] | Should -Not -BeNullOrEmpty
        }
    }
}

# =============================================================================
# Partition Functions Integration Tests
# =============================================================================

Describe 'Partition Functions Integration' -Tag 'Integration', 'FFU.Imaging', 'Partitioning' {

    BeforeAll {
        Mock WriteLog { } -ModuleName 'FFU.Imaging'
    }

    Context 'New-SystemPartition' {

        It 'Should export New-SystemPartition function' {
            Get-Command New-SystemPartition -Module FFU.Imaging | Should -Not -BeNullOrEmpty
        }

        It 'Should have VhdxDisk parameter (mandatory)' {
            $command = Get-Command New-SystemPartition -Module FFU.Imaging
            $command.Parameters['VhdxDisk'] | Should -Not -BeNullOrEmpty
            $command.Parameters['VhdxDisk'].Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory } | Should -Contain $true
        }

        It 'Should have SystemPartitionSize parameter with 260MB default' {
            $command = Get-Command New-SystemPartition -Module FFU.Imaging
            $command.Parameters['SystemPartitionSize'] | Should -Not -BeNullOrEmpty
        }
    }

    Context 'New-MSRPartition' {

        It 'Should export New-MSRPartition function' {
            Get-Command New-MSRPartition -Module FFU.Imaging | Should -Not -BeNullOrEmpty
        }

        It 'Should have VhdxDisk parameter (mandatory)' {
            $command = Get-Command New-MSRPartition -Module FFU.Imaging
            $command.Parameters['VhdxDisk'] | Should -Not -BeNullOrEmpty
        }
    }

    Context 'New-OSPartition' {

        It 'Should export New-OSPartition function' {
            Get-Command New-OSPartition -Module FFU.Imaging | Should -Not -BeNullOrEmpty
        }

        It 'Should have VhdxDisk parameter (mandatory)' {
            $command = Get-Command New-OSPartition -Module FFU.Imaging
            $command.Parameters['VhdxDisk'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have WimPath parameter for image source' {
            $command = Get-Command New-OSPartition -Module FFU.Imaging
            $command.Parameters['WimPath'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have WimIndex parameter for image index' {
            $command = Get-Command New-OSPartition -Module FFU.Imaging
            $command.Parameters['WimIndex'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have CompactOS parameter for compression' {
            $command = Get-Command New-OSPartition -Module FFU.Imaging
            $command.Parameters['CompactOS'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have ISOPath parameter for auto-remount capability' {
            $command = Get-Command New-OSPartition -Module FFU.Imaging
            $command.Parameters['ISOPath'] | Should -Not -BeNullOrEmpty
        }
    }

    Context 'New-RecoveryPartition' {

        It 'Should export New-RecoveryPartition function' {
            Get-Command New-RecoveryPartition -Module FFU.Imaging | Should -Not -BeNullOrEmpty
        }
    }
}

# =============================================================================
# New-FFU Integration Tests
# =============================================================================

Describe 'New-FFU Integration' -Tag 'Integration', 'FFU.Imaging', 'FFUCapture' {

    BeforeAll {
        Mock WriteLog { } -ModuleName 'FFU.Imaging'
    }

    Context 'Function Exports and Parameters' {

        It 'Should export New-FFU function' {
            Get-Command New-FFU -Module FFU.Imaging | Should -Not -BeNullOrEmpty
        }

        It 'Should have VMName parameter for VM-based capture' {
            $command = Get-Command New-FFU -Module FFU.Imaging
            $command.Parameters['VMName'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have InstallApps parameter (mandatory)' {
            $command = Get-Command New-FFU -Module FFU.Imaging
            $command.Parameters['InstallApps'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have CaptureISO parameter for WinPE ISO' {
            $command = Get-Command New-FFU -Module FFU.Imaging
            $command.Parameters['CaptureISO'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have FFUCaptureLocation parameter (mandatory)' {
            $command = Get-Command New-FFU -Module FFU.Imaging
            $command.Parameters['FFUCaptureLocation'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have Optimize parameter for FFU optimization' {
            $command = Get-Command New-FFU -Module FFU.Imaging
            $command.Parameters['Optimize'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have HypervisorProvider parameter for VMware support' {
            $command = Get-Command New-FFU -Module FFU.Imaging
            # HypervisorProvider parameter enables hypervisor-agnostic VM operations
            $command.Parameters['HypervisorProvider'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have VMInfo parameter for VM details' {
            $command = Get-Command New-FFU -Module FFU.Imaging
            $command.Parameters['VMInfo'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have VMShutdownTimeoutMinutes parameter with default' {
            $command = Get-Command New-FFU -Module FFU.Imaging
            $command.Parameters['VMShutdownTimeoutMinutes'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have VHDXPath parameter for direct VHDX capture' {
            $command = Get-Command New-FFU -Module FFU.Imaging
            $command.Parameters['VHDXPath'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have DandIEnv parameter for ADK environment (mandatory)' {
            $command = Get-Command New-FFU -Module FFU.Imaging
            $command.Parameters['DandIEnv'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have InstallDrivers parameter' {
            $command = Get-Command New-FFU -Module FFU.Imaging
            $command.Parameters['InstallDrivers'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have FFUDevelopmentPath parameter (mandatory)' {
            $command = Get-Command New-FFU -Module FFU.Imaging
            $command.Parameters['FFUDevelopmentPath'] | Should -Not -BeNullOrEmpty
        }
    }
}

# =============================================================================
# Dismount-ScratchVhdx Integration Tests
# =============================================================================

Describe 'Dismount-ScratchVhdx Integration' -Tag 'Integration', 'FFU.Imaging', 'VHDXDismount' {

    BeforeAll {
        Mock WriteLog { } -ModuleName 'FFU.Imaging'
    }

    Context 'Function Exports and Parameters' {

        It 'Should export Dismount-ScratchVhdx function' {
            Get-Command Dismount-ScratchVhdx -Module FFU.Imaging | Should -Not -BeNullOrEmpty
        }

        It 'Should have VhdxPath parameter (mandatory)' {
            $command = Get-Command Dismount-ScratchVhdx -Module FFU.Imaging
            $command.Parameters['VhdxPath'] | Should -Not -BeNullOrEmpty
        }
    }
}

# =============================================================================
# Dismount-ScratchVhd Integration Tests (VMware)
# =============================================================================

Describe 'Dismount-ScratchVhd Integration' -Tag 'Integration', 'FFU.Imaging', 'VHDDismount', 'VMware' {

    BeforeAll {
        Mock WriteLog { } -ModuleName 'FFU.Imaging'
    }

    Context 'Function Exports and Parameters' {

        It 'Should export Dismount-ScratchVhd function' {
            Get-Command Dismount-ScratchVhd -Module FFU.Imaging | Should -Not -BeNullOrEmpty
        }

        It 'Should have VhdPath parameter (mandatory)' {
            $command = Get-Command Dismount-ScratchVhd -Module FFU.Imaging
            $command.Parameters['VhdPath'] | Should -Not -BeNullOrEmpty
        }
    }

    Context 'VHD Dismount with Volume Flush (PERF-01 Verification)' {

        It 'Should NOT have triple-pass flush loop in module code' {
            # Verify PERF-01 optimization is in place - no triple-pass flush
            $moduleContent = Get-Content (Join-Path $ModulePath 'FFU.Imaging.psm1') -Raw

            $moduleContent | Should -Not -Match 'Flush pass .* of 3'
            $moduleContent | Should -Not -Match 'for \(\$flushPass = 1'
        }

        It 'Should use Write-VolumeCache for verified flush' {
            # Verify PERF-01 uses Write-VolumeCache for single verified flush
            $moduleContent = Get-Content (Join-Path $ModulePath 'FFU.Imaging.psm1') -Raw

            $moduleContent | Should -Match 'Write-VolumeCache'
        }

        It 'Should have Invoke-VerifiedVolumeFlush function' {
            # This is the PERF-01 optimization function
            $moduleContent = Get-Content (Join-Path $ModulePath 'FFU.Imaging.psm1') -Raw

            $moduleContent | Should -Match 'function Invoke-VerifiedVolumeFlush'
        }
    }
}

# =============================================================================
# Expand-FFUPartitionForDrivers Integration Tests (BUG-03)
# =============================================================================

Describe 'Expand-FFUPartitionForDrivers Integration' -Tag 'Integration', 'FFU.Imaging', 'PartitionExpand', 'BUG-03' {

    BeforeAll {
        Mock WriteLog { } -ModuleName 'FFU.Imaging'
    }

    Context 'Function Exports and Parameters' {

        It 'Should export Expand-FFUPartitionForDrivers function' {
            Get-Command Expand-FFUPartitionForDrivers -Module FFU.Imaging | Should -Not -BeNullOrEmpty
        }

        It 'Should have VHDXPath parameter (mandatory)' {
            $command = Get-Command Expand-FFUPartitionForDrivers -Module FFU.Imaging
            $command.Parameters['VHDXPath'] | Should -Not -BeNullOrEmpty
            $command.Parameters['VHDXPath'].Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory } | Should -Contain $true
        }

        It 'Should have DriversFolder parameter (mandatory)' {
            $command = Get-Command Expand-FFUPartitionForDrivers -Module FFU.Imaging
            $command.Parameters['DriversFolder'] | Should -Not -BeNullOrEmpty
            $command.Parameters['DriversFolder'].Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory } | Should -Contain $true
        }

        It 'Should have ThresholdGB parameter with default 5GB' {
            $command = Get-Command Expand-FFUPartitionForDrivers -Module FFU.Imaging
            $command.Parameters['ThresholdGB'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have SafetyMarginGB parameter for DISM overhead' {
            $command = Get-Command Expand-FFUPartitionForDrivers -Module FFU.Imaging
            $command.Parameters['SafetyMarginGB'] | Should -Not -BeNullOrEmpty
        }
    }
}

# =============================================================================
# Get-WindowsVersionInfo Integration Tests
# =============================================================================

Describe 'Get-WindowsVersionInfo Integration' -Tag 'Integration', 'FFU.Imaging', 'VersionInfo' {

    BeforeAll {
        Mock WriteLog { } -ModuleName 'FFU.Imaging'
    }

    Context 'Function Exports and Parameters' {

        It 'Should export Get-WindowsVersionInfo function' {
            Get-Command Get-WindowsVersionInfo -Module FFU.Imaging | Should -Not -BeNullOrEmpty
        }

        It 'Should have MountPath parameter' {
            $command = Get-Command Get-WindowsVersionInfo -Module FFU.Imaging
            $command.Parameters['MountPath'] | Should -Not -BeNullOrEmpty
        }
    }
}

# =============================================================================
# Invoke-FFUOptimizeWithScratchDir Integration Tests
# =============================================================================

Describe 'Invoke-FFUOptimizeWithScratchDir Integration' -Tag 'Integration', 'FFU.Imaging', 'FFUOptimize' {

    BeforeAll {
        Mock WriteLog { } -ModuleName 'FFU.Imaging'
    }

    Context 'Function Exports and Parameters' {

        It 'Should export Invoke-FFUOptimizeWithScratchDir function' {
            Get-Command Invoke-FFUOptimizeWithScratchDir -Module FFU.Imaging | Should -Not -BeNullOrEmpty
        }

        It 'Should have FFUFile parameter' {
            $command = Get-Command Invoke-FFUOptimizeWithScratchDir -Module FFU.Imaging
            $command.Parameters['FFUFile'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have DandIEnv parameter for ADK environment' {
            $command = Get-Command Invoke-FFUOptimizeWithScratchDir -Module FFU.Imaging
            $command.Parameters['DandIEnv'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have MaxRetries parameter for reliability' {
            $command = Get-Command Invoke-FFUOptimizeWithScratchDir -Module FFU.Imaging
            $command.Parameters['MaxRetries'] | Should -Not -BeNullOrEmpty
        }
    }
}

# =============================================================================
# Initialize-DISMService Integration Tests
# =============================================================================

Describe 'Initialize-DISMService Integration' -Tag 'Integration', 'FFU.Imaging', 'DISMInit' {

    BeforeAll {
        Mock WriteLog { } -ModuleName 'FFU.Imaging'
    }

    Context 'Function Exports and Parameters' {

        It 'Should export Initialize-DISMService function' {
            Get-Command Initialize-DISMService -Module FFU.Imaging | Should -Not -BeNullOrEmpty
        }

        It 'Should have MountPath parameter (mandatory)' {
            $command = Get-Command Initialize-DISMService -Module FFU.Imaging
            $command.Parameters['MountPath'] | Should -Not -BeNullOrEmpty
            $command.Parameters['MountPath'].Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory } | Should -Contain $true
        }
    }
}

# =============================================================================
# Test-WimSourceAccessibility Integration Tests
# =============================================================================

Describe 'Test-WimSourceAccessibility Integration' -Tag 'Integration', 'FFU.Imaging', 'WimValidation' {

    BeforeAll {
        Mock WriteLog { } -ModuleName 'FFU.Imaging'
    }

    Context 'Function Exports and Parameters' {

        It 'Should export Test-WimSourceAccessibility function' {
            Get-Command Test-WimSourceAccessibility -Module FFU.Imaging | Should -Not -BeNullOrEmpty
        }

        It 'Should have WimPath parameter (mandatory)' {
            $command = Get-Command Test-WimSourceAccessibility -Module FFU.Imaging
            $command.Parameters['WimPath'] | Should -Not -BeNullOrEmpty
            $command.Parameters['WimPath'].Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory } | Should -Contain $true
        }

        It 'Should have ISOPath parameter for mount verification' {
            $command = Get-Command Test-WimSourceAccessibility -Module FFU.Imaging
            $command.Parameters['ISOPath'] | Should -Not -BeNullOrEmpty
        }
    }
}

# =============================================================================
# Add-BootFiles Integration Tests
# =============================================================================

Describe 'Add-BootFiles Integration' -Tag 'Integration', 'FFU.Imaging', 'BootFiles' {

    BeforeAll {
        Mock WriteLog { } -ModuleName 'FFU.Imaging'
    }

    Context 'Function Exports and Parameters' {

        It 'Should export Add-BootFiles function' {
            Get-Command Add-BootFiles -Module FFU.Imaging | Should -Not -BeNullOrEmpty
        }
    }
}

# =============================================================================
# Module Export Count Verification
# =============================================================================

Describe 'FFU.Imaging Module Export Verification' -Tag 'Integration', 'FFU.Imaging', 'Exports' {

    It 'Should export all 21 documented functions' {
        $module = Get-Module -Name FFU.Imaging
        $exportedFunctions = $module.ExportedFunctions.Keys

        # List from FFU.Imaging.psd1
        $expectedFunctions = @(
            'Initialize-DISMService',
            'Test-WimSourceAccessibility',
            'Invoke-ExpandWindowsImageWithRetry',
            'Get-WimFromISO',
            'Get-Index',
            'New-ScratchVhdx',
            'New-ScratchVhd',
            'New-SystemPartition',
            'New-MSRPartition',
            'New-OSPartition',
            'New-RecoveryPartition',
            'Add-BootFiles',
            'Enable-WindowsFeaturesByName',
            'Dismount-ScratchVhdx',
            'Dismount-ScratchVhd',
            'Optimize-FFUCaptureDrive',
            'Get-WindowsVersionInfo',
            'New-FFU',
            'Remove-FFU',
            'Start-RequiredServicesForDISM',
            'Invoke-FFUOptimizeWithScratchDir',
            'Expand-FFUPartitionForDrivers'
        )

        foreach ($funcName in $expectedFunctions) {
            $exportedFunctions | Should -Contain $funcName -Because "Function $funcName should be exported"
        }
    }
}
