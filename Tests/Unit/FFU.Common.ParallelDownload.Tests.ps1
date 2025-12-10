#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester unit tests for FFU.Common.ParallelDownload module

.DESCRIPTION
    Comprehensive unit tests covering the parallel download functions including:
    - Factory functions for creating download items and configs
    - Download result summary calculations
    - Parallel download execution (with mocking)

.NOTES
    Run with: Invoke-Pester -Path .\Tests\Unit\FFU.Common.ParallelDownload.Tests.ps1 -Output Detailed
#>

BeforeAll {
    # Get paths relative to test file location
    $TestRoot = Split-Path $PSScriptRoot -Parent
    $ProjectRoot = Split-Path $TestRoot -Parent
    $ModulePath = Join-Path $ProjectRoot 'FFUDevelopment\FFU.Common'

    # Remove module if loaded
    Get-Module -Name 'FFU.Common' | Remove-Module -Force -ErrorAction SilentlyContinue

    # Import FFU.Common module
    if (-not (Test-Path "$ModulePath\FFU.Common.psd1")) {
        throw "FFU.Common module not found at: $ModulePath"
    }
    Import-Module "$ModulePath\FFU.Common.psd1" -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name 'FFU.Common' | Remove-Module -Force -ErrorAction SilentlyContinue
}

# =============================================================================
# Module Export Verification
# =============================================================================

Describe 'FFU.Common.ParallelDownload Module Exports' -Tag 'Unit', 'FFU.Common', 'ParallelDownload', 'Module' {

    Context 'Expected Functions Are Exported' {
        It 'Should export Start-ParallelDownloads' {
            Get-Command -Name 'Start-ParallelDownloads' -Module 'FFU.Common' | Should -Not -BeNullOrEmpty
        }

        It 'Should export New-DownloadItem' {
            Get-Command -Name 'New-DownloadItem' -Module 'FFU.Common' | Should -Not -BeNullOrEmpty
        }

        It 'Should export New-ParallelDownloadConfig' {
            Get-Command -Name 'New-ParallelDownloadConfig' -Module 'FFU.Common' | Should -Not -BeNullOrEmpty
        }

        It 'Should export New-KBDownloadItems' {
            Get-Command -Name 'New-KBDownloadItems' -Module 'FFU.Common' | Should -Not -BeNullOrEmpty
        }

        It 'Should export New-GenericDownloadItem' {
            Get-Command -Name 'New-GenericDownloadItem' -Module 'FFU.Common' | Should -Not -BeNullOrEmpty
        }

        It 'Should export Get-ParallelDownloadSummary' {
            Get-Command -Name 'Get-ParallelDownloadSummary' -Module 'FFU.Common' | Should -Not -BeNullOrEmpty
        }
    }
}

# =============================================================================
# New-DownloadItem Tests
# =============================================================================

Describe 'New-DownloadItem' -Tag 'Unit', 'FFU.Common', 'ParallelDownload', 'New-DownloadItem' {

    Context 'Parameter Validation' {
        It 'Should have mandatory Id parameter' {
            $command = Get-Command -Name 'New-DownloadItem' -Module 'FFU.Common'
            $param = $command.Parameters['Id']
            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }

        It 'Should have mandatory Source parameter' {
            $command = Get-Command -Name 'New-DownloadItem' -Module 'FFU.Common'
            $param = $command.Parameters['Source']
            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }

        It 'Should have mandatory Destination parameter' {
            $command = Get-Command -Name 'New-DownloadItem' -Module 'FFU.Common'
            $param = $command.Parameters['Destination']
            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }

        It 'Should have optional DisplayName parameter' {
            $command = Get-Command -Name 'New-DownloadItem' -Module 'FFU.Common'
            $command.Parameters['DisplayName'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have optional Category parameter' {
            $command = Get-Command -Name 'New-DownloadItem' -Module 'FFU.Common'
            $command.Parameters['Category'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have optional Metadata parameter' {
            $command = Get-Command -Name 'New-DownloadItem' -Module 'FFU.Common'
            $command.Parameters['Metadata'] | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Object Creation' {
        It 'Should create a download item with all required properties' {
            $item = New-DownloadItem -Id 'KB123456' `
                                     -Source 'https://example.com/test.msu' `
                                     -Destination 'C:\temp\test.msu'

            $item.Id | Should -Be 'KB123456'
            $item.Source | Should -Be 'https://example.com/test.msu'
            $item.Destination | Should -Be 'C:\temp\test.msu'
        }

        It 'Should create a download item with optional properties' {
            $item = New-DownloadItem -Id 'KB123456' `
                                     -Source 'https://example.com/test.msu' `
                                     -Destination 'C:\temp\test.msu' `
                                     -DisplayName 'Security Update' `
                                     -Category 'WindowsUpdate'

            $item.DisplayName | Should -Be 'Security Update'
            $item.Category | Should -Be 'WindowsUpdate'
        }

        It 'Should use Id as DisplayName when not specified' {
            $item = New-DownloadItem -Id 'KB123456' `
                                     -Source 'https://example.com/test.msu' `
                                     -Destination 'C:\temp\test.msu'

            $item.DisplayName | Should -Be 'KB123456'
        }

        It 'Should use default Category of General when not specified' {
            $item = New-DownloadItem -Id 'KB123456' `
                                     -Source 'https://example.com/test.msu' `
                                     -Destination 'C:\temp\test.msu'

            $item.Category | Should -Be 'General'
        }

        It 'Should support Metadata hashtable' {
            $metadata = @{
                KBArticleId = 'KB5001234'
                UpdateType = 'CumulativeUpdate'
            }
            $item = New-DownloadItem -Id 'KB123456' `
                                     -Source 'https://example.com/test.msu' `
                                     -Destination 'C:\temp\test.msu' `
                                     -Metadata $metadata

            $item.Metadata.KBArticleId | Should -Be 'KB5001234'
            $item.Metadata.UpdateType | Should -Be 'CumulativeUpdate'
        }
    }
}

# =============================================================================
# New-ParallelDownloadConfig Tests
# =============================================================================

Describe 'New-ParallelDownloadConfig' -Tag 'Unit', 'FFU.Common', 'ParallelDownload', 'New-ParallelDownloadConfig' {

    Context 'Default Values' {
        It 'Should create config with default MaxConcurrentDownloads of 5' {
            $config = New-ParallelDownloadConfig
            $config.MaxConcurrentDownloads | Should -Be 5
        }

        It 'Should create config with default RetryCount of 3' {
            $config = New-ParallelDownloadConfig
            $config.RetryCount | Should -Be 3
        }

        It 'Should create config with default ContinueOnError of true' {
            $config = New-ParallelDownloadConfig
            $config.ContinueOnError | Should -BeTrue
        }
    }

    Context 'Custom Values' {
        It 'Should accept custom MaxConcurrentDownloads' {
            $config = New-ParallelDownloadConfig -MaxConcurrentDownloads 10
            $config.MaxConcurrentDownloads | Should -Be 10
        }

        It 'Should accept custom RetryCount' {
            $config = New-ParallelDownloadConfig -RetryCount 5
            $config.RetryCount | Should -Be 5
        }

        It 'Should accept custom LogPath' {
            $config = New-ParallelDownloadConfig -LogPath 'C:\logs\download.log'
            $config.LogPath | Should -Be 'C:\logs\download.log'
        }

        It 'Should accept custom ContinueOnError' {
            $config = New-ParallelDownloadConfig -ContinueOnError $false
            $config.ContinueOnError | Should -BeFalse
        }
    }
}

# =============================================================================
# Get-ParallelDownloadSummary Tests
# =============================================================================

Describe 'Get-ParallelDownloadSummary' -Tag 'Unit', 'FFU.Common', 'ParallelDownload', 'Get-ParallelDownloadSummary' {

    Context 'Summary Calculations' {
        BeforeAll {
            $script:mockResults = @(
                [PSCustomObject]@{ Id = 'KB1'; Success = $true; BytesDownloaded = 1000000; DurationSeconds = 10; ErrorMessage = $null; Source = 'https://url1' }
                [PSCustomObject]@{ Id = 'KB2'; Success = $true; BytesDownloaded = 2000000; DurationSeconds = 15; ErrorMessage = $null; Source = 'https://url2' }
                [PSCustomObject]@{ Id = 'KB3'; Success = $true; BytesDownloaded = 1500000; DurationSeconds = 12; ErrorMessage = $null; Source = 'https://url3' }
                [PSCustomObject]@{ Id = 'KB4'; Success = $false; BytesDownloaded = 0; DurationSeconds = 5; ErrorMessage = 'Connection timeout'; Source = 'https://url4' }
                [PSCustomObject]@{ Id = 'KB5'; Success = $false; BytesDownloaded = 0; DurationSeconds = 3; ErrorMessage = '404 Not Found'; Source = 'https://url5' }
            )
        }

        It 'Should calculate TotalCount correctly' {
            $summary = Get-ParallelDownloadSummary -Results $mockResults
            $summary.TotalCount | Should -Be 5
        }

        It 'Should calculate SuccessCount correctly' {
            $summary = Get-ParallelDownloadSummary -Results $mockResults
            $summary.SuccessCount | Should -Be 3
        }

        It 'Should calculate FailedCount correctly' {
            $summary = Get-ParallelDownloadSummary -Results $mockResults
            $summary.FailedCount | Should -Be 2
        }

        It 'Should calculate TotalBytesDownloaded correctly' {
            $summary = Get-ParallelDownloadSummary -Results $mockResults
            $summary.TotalBytesDownloaded | Should -Be 4500000  # 1M + 2M + 1.5M
        }

        It 'Should calculate TotalDurationSeconds correctly' {
            $summary = Get-ParallelDownloadSummary -Results $mockResults
            $summary.TotalDurationSeconds | Should -Be 45  # 10 + 15 + 12 + 5 + 3
        }

        It 'Should calculate SuccessRate correctly' {
            $summary = Get-ParallelDownloadSummary -Results $mockResults
            $summary.SuccessRate | Should -Be 60  # 3/5 * 100
        }

        It 'Should include failed downloads with error messages' {
            $summary = Get-ParallelDownloadSummary -Results $mockResults
            $summary.FailedDownloads.Count | Should -Be 2
            $summary.FailedDownloads[0].ErrorMessage | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Edge Cases' {
        It 'Should reject empty results array with parameter validation' {
            { Get-ParallelDownloadSummary -Results @() } | Should -Throw -ErrorId 'ParameterArgumentValidationError*'
        }

        It 'Should handle all successful results' {
            $allSuccess = @(
                [PSCustomObject]@{ Id = 'KB1'; Success = $true; BytesDownloaded = 1000; DurationSeconds = 1; ErrorMessage = $null }
                [PSCustomObject]@{ Id = 'KB2'; Success = $true; BytesDownloaded = 2000; DurationSeconds = 2; ErrorMessage = $null }
            )
            $summary = Get-ParallelDownloadSummary -Results $allSuccess
            $summary.SuccessRate | Should -Be 100
            $summary.FailedDownloads.Count | Should -Be 0
        }

        It 'Should handle all failed results' {
            $allFailed = @(
                [PSCustomObject]@{ Id = 'KB1'; Success = $false; BytesDownloaded = 0; DurationSeconds = 1; ErrorMessage = 'Error 1' }
                [PSCustomObject]@{ Id = 'KB2'; Success = $false; BytesDownloaded = 0; DurationSeconds = 2; ErrorMessage = 'Error 2' }
            )
            $summary = Get-ParallelDownloadSummary -Results $allFailed
            $summary.SuccessRate | Should -Be 0
            $summary.FailedDownloads.Count | Should -Be 2
        }
    }
}

# =============================================================================
# New-KBDownloadItems Tests
# =============================================================================

Describe 'New-KBDownloadItems' -Tag 'Unit', 'FFU.Common', 'ParallelDownload', 'New-KBDownloadItems' {

    Context 'Parameter Validation' {
        It 'Should have mandatory Updates parameter' {
            $command = Get-Command -Name 'New-KBDownloadItems' -Module 'FFU.Common'
            $param = $command.Parameters['Updates']
            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }

        It 'Should have mandatory KBPath parameter' {
            $command = Get-Command -Name 'New-KBDownloadItems' -Module 'FFU.Common'
            $param = $command.Parameters['KBPath']
            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }
    }

    Context 'Download Items Creation' {
        BeforeAll {
            $script:mockUpdates = @(
                [PSCustomObject]@{ Name = 'SSU Update'; Url = 'https://example.com/ssu.msu' }
                [PSCustomObject]@{ Name = 'CU Update'; Url = 'https://example.com/cu.msu' }
            )
        }

        It 'Should create download items from updates array' {
            $items = New-KBDownloadItems -Updates $mockUpdates -KBPath 'C:\KB'
            $items.Count | Should -Be 2
        }

        It 'Should set correct destination paths' {
            $items = New-KBDownloadItems -Updates $mockUpdates -KBPath 'C:\KB'
            $items[0].Destination | Should -BeLike 'C:\KB\*'
        }

        It 'Should use update Name as Id' {
            $items = New-KBDownloadItems -Updates $mockUpdates -KBPath 'C:\KB'
            $items[0].Id | Should -Be 'SSU Update'
        }

        It 'Should set WindowsUpdate category by default' {
            $items = New-KBDownloadItems -Updates $mockUpdates -KBPath 'C:\KB'
            $items[0].Category | Should -Be 'WindowsUpdate'
        }

        It 'Should skip updates without URL' {
            $updatesWithMissing = @(
                [PSCustomObject]@{ Name = 'Good Update'; Url = 'https://example.com/good.msu' }
                [PSCustomObject]@{ Name = 'Bad Update'; Url = $null }
                [PSCustomObject]@{ Name = 'Another Good'; Url = 'https://example.com/another.msu' }
            )
            $items = New-KBDownloadItems -Updates $updatesWithMissing -KBPath 'C:\KB'
            $items.Count | Should -Be 2
        }
    }
}

# =============================================================================
# Start-ParallelDownloads Parameter Tests
# =============================================================================

Describe 'Start-ParallelDownloads' -Tag 'Unit', 'FFU.Common', 'ParallelDownload', 'Start-ParallelDownloads' {

    Context 'Parameter Validation' {
        It 'Should have mandatory Downloads parameter' {
            $command = Get-Command -Name 'Start-ParallelDownloads' -Module 'FFU.Common'
            $param = $command.Parameters['Downloads']
            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory | Should -BeTrue }
        }

        It 'Should have optional Config parameter' {
            $command = Get-Command -Name 'Start-ParallelDownloads' -Module 'FFU.Common'
            $command.Parameters['Config'] | Should -Not -BeNullOrEmpty
        }

        It 'Should have optional WaitForCompletion parameter' {
            $command = Get-Command -Name 'Start-ParallelDownloads' -Module 'FFU.Common'
            $command.Parameters['WaitForCompletion'] | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Empty Downloads Handling' {
        It 'Should reject empty downloads array with parameter validation' {
            { Start-ParallelDownloads -Downloads @() } | Should -Throw -ErrorId 'ParameterArgumentValidationError*'
        }
    }
}

# =============================================================================
# Integration with Fallback Download Methods
# =============================================================================

Describe 'Parallel Download Fallback Integration' -Tag 'Unit', 'FFU.Common', 'ParallelDownload', 'Integration' {

    Context 'Fallback Method Availability' {
        It 'Should have Start-ResilientDownload function available' {
            Get-Command -Name 'Start-ResilientDownload' -Module 'FFU.Common' | Should -Not -BeNullOrEmpty
        }

        It 'Should have Invoke-BITSDownload function available' {
            Get-Command -Name 'Invoke-BITSDownload' -Module 'FFU.Common' | Should -Not -BeNullOrEmpty
        }

        It 'Should have Invoke-WebRequestDownload function available' {
            Get-Command -Name 'Invoke-WebRequestDownload' -Module 'FFU.Common' | Should -Not -BeNullOrEmpty
        }

        It 'Should have Invoke-WebClientDownload function available' {
            Get-Command -Name 'Invoke-WebClientDownload' -Module 'FFU.Common' | Should -Not -BeNullOrEmpty
        }

        It 'Should have Invoke-CurlDownload function available' {
            Get-Command -Name 'Invoke-CurlDownload' -Module 'FFU.Common' | Should -Not -BeNullOrEmpty
        }
    }
}

# =============================================================================
# BuildFFUVM.ps1 Integration Tests
# =============================================================================

Describe 'BuildFFUVM.ps1 Parallel Download Integration' -Tag 'Unit', 'FFU.Common', 'ParallelDownload', 'BuildFFUVM', 'Integration' {

    BeforeAll {
        $BuildScriptPath = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'FFUDevelopment\BuildFFUVM.ps1'
        $script:BuildScriptContent = Get-Content -Path $BuildScriptPath -Raw
    }

    Context 'Parallel Download Implementation' {
        It 'Should use New-DownloadItem factory function' {
            $BuildScriptContent | Should -Match 'New-DownloadItem'
        }

        It 'Should use New-ParallelDownloadConfig factory function' {
            $BuildScriptContent | Should -Match 'New-ParallelDownloadConfig'
        }

        It 'Should call Start-ParallelDownloads for KB updates' {
            $BuildScriptContent | Should -Match 'Start-ParallelDownloads\s*-Downloads'
        }

        It 'Should use Get-ParallelDownloadSummary for results' {
            $BuildScriptContent | Should -Match 'Get-ParallelDownloadSummary'
        }

        It 'Should check for failed downloads and throw on failure' {
            $BuildScriptContent | Should -Match 'FailedCount\s*-gt\s*0'
        }
    }
}
