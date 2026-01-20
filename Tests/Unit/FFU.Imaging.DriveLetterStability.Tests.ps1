#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester unit tests for Set-OSPartitionDriveLetter function

.DESCRIPTION
    Unit tests covering the Set-OSPartitionDriveLetter function in the FFU.Imaging module.
    Tests verify function export, parameter validation, and code patterns.

.NOTES
    Run with: Invoke-Pester -Path .\Tests\Unit\FFU.Imaging.DriveLetterStability.Tests.ps1 -Output Detailed
#>

BeforeAll {
    $TestRoot = Split-Path $PSScriptRoot -Parent
    $ProjectRoot = Split-Path $TestRoot -Parent
    $ModulesPath = Join-Path $ProjectRoot 'FFUDevelopment\Modules'
    $ModulePath = Join-Path $ModulesPath 'FFU.Imaging'

    # Store module path for content tests
    $script:ModuleFile = Join-Path $ModulePath 'FFU.Imaging.psm1'
    $script:ManifestFile = Join-Path $ModulePath 'FFU.Imaging.psd1'

    # Add modules path to PSModulePath so RequiredModules can resolve
    if ($env:PSModulePath -notlike "*$ModulesPath*") {
        $env:PSModulePath = "$ModulesPath;$env:PSModulePath"
    }

    # Remove any previously loaded modules
    Get-Module -Name 'FFU.Imaging', 'FFU.Core', 'FFU.Constants', 'FFU.Common' | Remove-Module -Force -ErrorAction SilentlyContinue

    # Define WriteLog stub before importing module (required by FFU.Imaging)
    function global:WriteLog { param($Message) }

    # Import the module under test (will auto-import dependencies via RequiredModules)
    if (-not (Test-Path "$ModulePath\FFU.Imaging.psd1")) {
        throw "FFU.Imaging module not found at: $ModulePath"
    }
    Import-Module "$ModulePath\FFU.Imaging.psd1" -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name 'FFU.Imaging', 'FFU.Core', 'FFU.Constants' | Remove-Module -Force -ErrorAction SilentlyContinue
    Remove-Item Function:\WriteLog -ErrorAction SilentlyContinue
}

# =============================================================================
# Set-OSPartitionDriveLetter Tests
# =============================================================================

Describe 'Set-OSPartitionDriveLetter' -Tag 'Unit', 'FFU.Imaging', 'DriveLetterStability' {

    Context 'Function Export Verification' {

        It 'Should be exported from FFU.Imaging module' {
            Get-Command -Name 'Set-OSPartitionDriveLetter' -Module 'FFU.Imaging' | Should -Not -BeNullOrEmpty
        }

        It 'Should have OutputType of [char]' {
            $command = Get-Command -Name 'Set-OSPartitionDriveLetter' -Module 'FFU.Imaging'
            $command.OutputType.Type.Name | Should -Contain 'Char'
        }

        It 'Should be included in module manifest FunctionsToExport' {
            $manifest = Import-PowerShellDataFile $script:ManifestFile
            $manifest.FunctionsToExport | Should -Contain 'Set-OSPartitionDriveLetter'
        }
    }

    Context 'Parameter Validation' {

        It 'Should have mandatory Disk parameter' {
            $command = Get-Command -Name 'Set-OSPartitionDriveLetter' -Module 'FFU.Imaging'
            $command.Parameters['Disk'] | Should -Not -BeNullOrEmpty
            $command.Parameters['Disk'].Attributes.Mandatory | Should -Contain $true
        }

        It 'Should have optional PreferredLetter parameter' {
            $command = Get-Command -Name 'Set-OSPartitionDriveLetter' -Module 'FFU.Imaging'
            $command.Parameters['PreferredLetter'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have optional RetryCount parameter' {
            $command = Get-Command -Name 'Set-OSPartitionDriveLetter' -Module 'FFU.Imaging'
            $command.Parameters['RetryCount'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have char type for PreferredLetter' {
            $command = Get-Command -Name 'Set-OSPartitionDriveLetter' -Module 'FFU.Imaging'
            $command.Parameters['PreferredLetter'].ParameterType.Name | Should -Be 'Char'
        }

        It 'Should have int type for RetryCount' {
            $command = Get-Command -Name 'Set-OSPartitionDriveLetter' -Module 'FFU.Imaging'
            $command.Parameters['RetryCount'].ParameterType.Name | Should -Be 'Int32'
        }
    }

    Context 'Function Implementation' {

        It 'Should contain GPT type for OS partition detection' {
            $content = Get-Content $script:ModuleFile -Raw
            $content | Should -Match 'ebd0a0a2-b9e5-4433-87c0-68b6b72699c7'
        }

        It 'Should use Get-Partition for partition retrieval' {
            $content = Get-Content $script:ModuleFile -Raw
            # Function should call Get-Partition
            $content | Should -Match 'Get-Partition'
        }

        It 'Should use Set-Partition for drive letter assignment' {
            $content = Get-Content $script:ModuleFile -Raw
            $content | Should -Match 'Set-Partition.*-NewDriveLetter'
        }

        It 'Should use Get-Volume for available letter detection' {
            $content = Get-Content $script:ModuleFile -Raw
            $content | Should -Match 'Get-Volume'
        }

        It 'Should implement retry logic' {
            $content = Get-Content $script:ModuleFile -Raw
            $content | Should -Match 'RetryCount'
            $content | Should -Match 'for.*\$attempt'
        }

        It 'Should have comprehensive logging' {
            $content = Get-Content $script:ModuleFile -Raw
            # Should have multiple WriteLog calls for key operations
            $logMatches = [regex]::Matches($content, 'WriteLog.*Set-OSPartitionDriveLetter')
            $logMatches.Count | Should -BeGreaterOrEqual 1
        }

        It 'Should handle both DiskNumber and Number properties for disk compatibility' {
            $content = Get-Content $script:ModuleFile -Raw
            $content | Should -Match '\$Disk\.DiskNumber'
            $content | Should -Match '\$Disk\.Number'
        }
    }

    Context 'Module Manifest' {

        It 'Should have module version 1.0.12 or higher' {
            $manifest = Import-PowerShellDataFile $script:ManifestFile
            [version]$manifest.ModuleVersion | Should -BeGreaterOrEqual ([version]'1.0.12')
        }

        It 'Should include VHDX-01 in release notes' {
            $manifest = Import-PowerShellDataFile $script:ManifestFile
            $manifest.PrivateData.PSData.ReleaseNotes | Should -Match 'VHDX-01'
        }
    }
}
