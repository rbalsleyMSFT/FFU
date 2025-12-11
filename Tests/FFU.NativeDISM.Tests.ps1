#Requires -Version 7.0
#Requires -Modules Pester

<#
.SYNOPSIS
    Tests for native DISM (PowerShell cmdlet) usage in FFU Builder.

.DESCRIPTION
    Validates that WIM mount/unmount operations use native PowerShell DISM cmdlets
    (Mount-WindowsImage, Dismount-WindowsImage) instead of ADK dism.exe to avoid
    WIMMount filter driver issues (error 0x800704db "The specified service does not exist").

.NOTES
    Fix: DISM error 0x800704db when WIMMount filter driver is not properly registered
    Root cause: ADK dism.exe relies on WIMMount filter which can be corrupted by newer ADK versions
    Solution: Use native OS DISM infrastructure via PowerShell cmdlets
#>

Describe 'Native DISM Usage in ApplyFFU.ps1' -Tag 'NativeDISM', 'ApplyFFU' {

    BeforeAll {
        $script:applyFFUPath = Join-Path $PSScriptRoot '..\FFUDevelopment\WinPEDeployFFUFiles\ApplyFFU.ps1'
        $script:applyFFUContent = Get-Content $script:applyFFUPath -Raw
    }

    Context 'Mount Operations Use Native PowerShell Cmdlets' {

        It 'Should use Mount-WindowsImage instead of dism.exe /Mount-Image' {
            # Verify Mount-WindowsImage is used
            $script:applyFFUContent | Should -Match 'Mount-WindowsImage\s+-ImagePath'
        }

        It 'Should NOT use dism.exe /Mount-Image for WIM mounting' {
            # Verify dism.exe /Mount-Image is NOT used (except in comments)
            $nonCommentLines = $script:applyFFUContent -split "`n" | Where-Object { $_ -notmatch '^\s*#' }
            $nonCommentContent = $nonCommentLines -join "`n"
            $nonCommentContent | Should -Not -Match 'dism\.exe\s+/Mount-Image'
        }

        It 'Should include -ReadOnly parameter for driver WIM mount' {
            $script:applyFFUContent | Should -Match 'Mount-WindowsImage.*-ReadOnly'
        }

        It 'Should include -Optimize parameter for driver WIM mount' {
            $script:applyFFUContent | Should -Match 'Mount-WindowsImage.*-Optimize'
        }

        It 'Should include -ErrorAction Stop for proper error handling' {
            $script:applyFFUContent | Should -Match 'Mount-WindowsImage.*-ErrorAction\s+Stop'
        }
    }

    Context 'Unmount Operations Use Native PowerShell Cmdlets' {

        It 'Should use Dismount-WindowsImage instead of dism.exe /Unmount-Image' {
            $script:applyFFUContent | Should -Match 'Dismount-WindowsImage\s+-Path'
        }

        It 'Should NOT use dism.exe /Unmount-Image for WIM unmounting' {
            # Find non-comment lines that use /Unmount-Image
            $nonCommentLines = $script:applyFFUContent -split "`n" | Where-Object { $_ -notmatch '^\s*#' }
            $nonCommentContent = $nonCommentLines -join "`n"
            $nonCommentContent | Should -Not -Match 'dism\.exe\s+.*?/Unmount-Image'
            $nonCommentContent | Should -Not -Match 'Invoke-Process.*dism.*Unmount'
        }

        It 'Should include -Discard parameter for cleanup unmount' {
            $script:applyFFUContent | Should -Match 'Dismount-WindowsImage.*-Discard'
        }

        It 'Should have fallback cleanup for unmount failures' {
            $script:applyFFUContent | Should -Match 'dism\.exe\s+/Cleanup-Mountpoints'
        }
    }

    Context 'Error Handling for Mount Operations' {

        It 'Should wrap mount operation in try-catch block' {
            # Verify the mount is in a try block
            $script:applyFFUContent | Should -Match 'try\s*\{[^}]*Mount-WindowsImage'
        }

        It 'Should have catch block for mount errors' {
            # Verify there's error handling
            $script:applyFFUContent | Should -Match 'catch\s*\{[^}]*WIM driver installation'
        }

        It 'Should have finally block for cleanup' {
            # Verify cleanup happens in finally
            $script:applyFFUContent | Should -Match 'finally\s*\{[^}]*Dismount-WindowsImage'
        }
    }
}

Describe 'Native DISM Cmdlet Availability' -Tag 'NativeDISM', 'Prerequisites' {

    Context 'PowerShell DISM Module' {

        It 'Mount-WindowsImage cmdlet should be available' {
            $cmd = Get-Command -Name 'Mount-WindowsImage' -ErrorAction SilentlyContinue
            $cmd | Should -Not -BeNullOrEmpty
            $cmd.CommandType | Should -Be 'Cmdlet'
        }

        It 'Dismount-WindowsImage cmdlet should be available' {
            $cmd = Get-Command -Name 'Dismount-WindowsImage' -ErrorAction SilentlyContinue
            $cmd | Should -Not -BeNullOrEmpty
            $cmd.CommandType | Should -Be 'Cmdlet'
        }

        It 'Get-WindowsImage cmdlet should be available' {
            $cmd = Get-Command -Name 'Get-WindowsImage' -ErrorAction SilentlyContinue
            $cmd | Should -Not -BeNullOrEmpty
            $cmd.CommandType | Should -Be 'Cmdlet'
        }

        It 'Mount-WindowsImage should accept -ReadOnly parameter' {
            $cmd = Get-Command -Name 'Mount-WindowsImage'
            $cmd.Parameters.Keys | Should -Contain 'ReadOnly'
        }

        It 'Mount-WindowsImage should accept -Optimize parameter' {
            $cmd = Get-Command -Name 'Mount-WindowsImage'
            $cmd.Parameters.Keys | Should -Contain 'Optimize'
        }

        It 'Dismount-WindowsImage should accept -Discard parameter' {
            $cmd = Get-Command -Name 'Dismount-WindowsImage'
            $cmd.Parameters.Keys | Should -Contain 'Discard'
        }
    }
}

Describe 'Native DISM Usage in Other Modules' -Tag 'NativeDISM', 'Modules' {

    Context 'FFU.Media Module Uses Native DISM' {

        BeforeAll {
            $script:mediaModulePath = Join-Path $PSScriptRoot '..\FFUDevelopment\Modules\FFU.Media\FFU.Media.psm1'
            $script:mediaContent = Get-Content $script:mediaModulePath -Raw
        }

        It 'Should use Mount-WindowsImage for boot.wim mounting' {
            $script:mediaContent | Should -Match 'Mount-WindowsImage\s+-ImagePath'
        }

        It 'Should use Dismount-WindowsImage for boot.wim unmounting' {
            $script:mediaContent | Should -Match 'Dismount-WindowsImage\s+-Path'
        }
    }

    Context 'FFU.Imaging Module Uses Native DISM' {

        BeforeAll {
            $script:imagingModulePath = Join-Path $PSScriptRoot '..\FFUDevelopment\Modules\FFU.Imaging\FFU.Imaging.psm1'
            $script:imagingContent = Get-Content $script:imagingModulePath -Raw
        }

        It 'Should use Mount-WindowsImage for FFU mounting' {
            $script:imagingContent | Should -Match 'Mount-WindowsImage\s+-ImagePath'
        }

        It 'Should use Dismount-WindowsImage for FFU dismounting' {
            $script:imagingContent | Should -Match 'Dismount-WindowsImage\s+-Path'
        }
    }

    Context 'Create-PEMedia.ps1 Uses Native DISM' {

        BeforeAll {
            $script:peMediaPath = Join-Path $PSScriptRoot '..\FFUDevelopment\Create-PEMedia.ps1'
            $script:peMediaContent = Get-Content $script:peMediaPath -Raw
        }

        It 'Should use Mount-WindowsImage for WinPE boot.wim mounting' {
            $script:peMediaContent | Should -Match 'Mount-WindowsImage\s+-ImagePath'
        }

        It 'Should use Dismount-WindowsImage for WinPE boot.wim unmounting' {
            $script:peMediaContent | Should -Match 'Dismount-WindowsImage\s+-Path'
        }
    }
}

Describe 'DISM Cleanup Operations' -Tag 'NativeDISM', 'Cleanup' {

    Context 'Cleanup Uses OS dism.exe Correctly' {

        # Note: dism.exe /Cleanup-Mountpoints is fine to use - it doesn't use WIMMount filter
        # This test verifies we use it appropriately for cleanup operations

        BeforeAll {
            $script:coreModulePath = Join-Path $PSScriptRoot '..\FFUDevelopment\Modules\FFU.Core\FFU.Core.psm1'
            $script:coreContent = Get-Content $script:coreModulePath -Raw
        }

        It 'Should use dism.exe /Cleanup-Mountpoints for stale mount cleanup' {
            $script:coreContent | Should -Match 'dism\.exe\s+/Cleanup-Mountpoints'
        }

        It 'Should suppress cleanup output appropriately' {
            $script:coreContent | Should -Match 'dism\.exe\s+/Cleanup-Mountpoints.*\|\s*Out-Null'
        }
    }
}

Describe 'No ADK DISM Mount Operations' -Tag 'NativeDISM', 'Regression' {

    # This test ensures no future code uses ADK dism.exe for mount operations
    # ADK dism.exe may have WIMMount issues, native PowerShell cmdlets should be used

    Context 'Verify No ADK dism.exe Mount/Unmount Usage' {

        BeforeAll {
            # Get all PowerShell files in FFUDevelopment
            $script:allPsFiles = Get-ChildItem -Path (Join-Path $PSScriptRoot '..\FFUDevelopment') -Filter '*.ps1' -Recurse
            $script:allPsmFiles = Get-ChildItem -Path (Join-Path $PSScriptRoot '..\FFUDevelopment') -Filter '*.psm1' -Recurse
            $script:allFiles = @($script:allPsFiles) + @($script:allPsmFiles)
        }

        It 'No files should use dism.exe /Mount-Image (except in comments)' {
            $violations = @()
            foreach ($file in $script:allFiles) {
                $content = Get-Content $file.FullName -Raw
                $lines = $content -split "`n"
                $nonCommentLines = $lines | Where-Object { $_ -notmatch '^\s*#' -and $_ -notmatch '^\s*<#' }
                $nonCommentContent = $nonCommentLines -join "`n"

                if ($nonCommentContent -match 'dism\.exe\s+/Mount-Image') {
                    $violations += $file.Name
                }
            }

            $violations | Should -BeNullOrEmpty -Because "All WIM mount operations should use Mount-WindowsImage cmdlet, not dism.exe /Mount-Image. Violations: $($violations -join ', ')"
        }

        It 'No files should use Invoke-Process with dism.exe /Unmount-Image' {
            $violations = @()
            foreach ($file in $script:allFiles) {
                $content = Get-Content $file.FullName -Raw
                $lines = $content -split "`n"
                $nonCommentLines = $lines | Where-Object { $_ -notmatch '^\s*#' -and $_ -notmatch '^\s*<#' }
                $nonCommentContent = $nonCommentLines -join "`n"

                if ($nonCommentContent -match 'Invoke-Process.*dism.*Unmount-Image') {
                    $violations += $file.Name
                }
            }

            $violations | Should -BeNullOrEmpty -Because "All WIM unmount operations should use Dismount-WindowsImage cmdlet. Violations: $($violations -join ', ')"
        }
    }
}
