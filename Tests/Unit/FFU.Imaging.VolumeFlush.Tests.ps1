#Requires -Modules Pester

<#
.SYNOPSIS
    Pester tests for FFU.Imaging volume flush optimization (PERF-01)

.DESCRIPTION
    Tests Invoke-VerifiedVolumeFlush function behavior including:
    - Write-VolumeCache usage when available
    - fsutil fallback for older Windows
    - Error handling and graceful degradation
    - Correct VHD disk identification
#>

BeforeAll {
    # Import module under test with PSModulePath setup
    $modulePath = Join-Path $PSScriptRoot "..\..\FFUDevelopment\Modules"
    $commonPath = Join-Path $PSScriptRoot "..\..\FFUDevelopment\FFU.Common"
    $env:PSModulePath = $modulePath + ';' + $env:PSModulePath

    # Import FFU.Common first to get WriteLog function (dependency of FFU.Core/FFU.Imaging)
    Import-Module $commonPath -Force -ErrorAction Stop

    # Now import FFU.Imaging (which depends on FFU.Core, which uses WriteLog)
    Import-Module FFU.Imaging -Force -ErrorAction Stop

    # Mock WriteLog in FFU.Common module to suppress log output during tests
    Mock WriteLog { } -ModuleName FFU.Common
}

Describe "Invoke-VerifiedVolumeFlush Source Code" {

    Context "Function implementation patterns" {

        BeforeAll {
            $moduleContent = Get-Content (Join-Path $PSScriptRoot "..\..\FFUDevelopment\Modules\FFU.Imaging\FFU.Imaging.psm1") -Raw
        }

        It "Should have Write-VolumeCache as primary flush method" {
            $moduleContent | Should -Match "Write-VolumeCache -DriveLetter"
        }

        It "Should check Write-VolumeCache availability before using" {
            $moduleContent | Should -Match "Get-Command Write-VolumeCache"
        }

        It "Should have fsutil fallback when Write-VolumeCache unavailable" {
            $moduleContent | Should -Match "fsutil volume flush"
        }

        It "Should check for File Backed Virtual disk type" {
            $moduleContent | Should -Match "BusType -eq 'File Backed Virtual'"
        }

        It "Should filter partitions with drive letters" {
            $moduleContent | Should -Match "Where-Object \{ \`$_\.DriveLetter \}"
        }

        It "Should have proper error handling with try/catch" {
            # Verify Invoke-VerifiedVolumeFlush has error handling
            $moduleContent | Should -Match "function Invoke-VerifiedVolumeFlush[\s\S]*?try[\s\S]*?catch"
        }

        It "Should return boolean indicating flush success" {
            $moduleContent | Should -Match "\[OutputType\(\[bool\]\)\][\s\S]*?param\(\s*\[Parameter\(Mandatory\)\]\s*\[string\]\`$VhdPath"
        }

        It "Should call fallback when disk not identified" {
            $moduleContent | Should -Match "return Invoke-FallbackVolumeFlush"
        }
    }
}

Describe "Invoke-FallbackVolumeFlush Source Code" {

    Context "Fallback implementation patterns" {

        BeforeAll {
            $moduleContent = Get-Content (Join-Path $PSScriptRoot "..\..\FFUDevelopment\Modules\FFU.Imaging\FFU.Imaging.psm1") -Raw
        }

        It "Should flush Fixed and Removable drive types" {
            $moduleContent | Should -Match "DriveType -in @\('Fixed', 'Removable'\)"
        }

        It "Should use fsutil for fallback flush" {
            $moduleContent | Should -Match "function Invoke-FallbackVolumeFlush[\s\S]*?fsutil volume flush"
        }
    }
}

Describe "Dismount-ScratchVhd Integration" {

    It "Should NOT contain triple-pass flush loop" {
        $moduleContent = Get-Content (Join-Path $PSScriptRoot "..\..\FFUDevelopment\Modules\FFU.Imaging\FFU.Imaging.psm1") -Raw

        $moduleContent | Should -Not -Match "Flush pass .* of 3"
        $moduleContent | Should -Not -Match "for \(`\$flushPass = 1"
    }

    It "Should call Invoke-VerifiedVolumeFlush" {
        $moduleContent = Get-Content (Join-Path $PSScriptRoot "..\..\FFUDevelopment\Modules\FFU.Imaging\FFU.Imaging.psm1") -Raw

        $moduleContent | Should -Match "Invoke-VerifiedVolumeFlush"
    }

    It "Should NOT have 5-second I/O wait delay" {
        $moduleContent = Get-Content (Join-Path $PSScriptRoot "..\..\FFUDevelopment\Modules\FFU.Imaging\FFU.Imaging.psm1") -Raw

        # The old code had "Start-Sleep -Seconds 5" with "Waiting for disk I/O to complete" comment
        # Make sure this specific delay is gone from Dismount-ScratchVhd
        $moduleContent | Should -Not -Match "Waiting for disk I/O to complete"
    }

    It "Should only have 2-second safety pause when flush fails" {
        $moduleContent = Get-Content (Join-Path $PSScriptRoot "..\..\FFUDevelopment\Modules\FFU.Imaging\FFU.Imaging.psm1") -Raw

        # Verify the conditional 2-second pause exists (only triggered on flush failure)
        $moduleContent | Should -Match "if \(-not \`$flushSuccess\)"
        $moduleContent | Should -Match "Start-Sleep -Seconds 2"
    }
}

Describe "Module Version and Release Notes" {

    It "Should have updated module version for PERF-01" {
        $manifest = Import-PowerShellDataFile (Join-Path $PSScriptRoot "..\..\FFUDevelopment\Modules\FFU.Imaging\FFU.Imaging.psd1")

        # Version should be at least 1.0.11 (PERF-01 release)
        $version = [Version]$manifest.ModuleVersion
        $version | Should -BeGreaterOrEqual ([Version]'1.0.11')
    }

    It "Should have PERF-01 in release notes" {
        $manifest = Import-PowerShellDataFile (Join-Path $PSScriptRoot "..\..\FFUDevelopment\Modules\FFU.Imaging\FFU.Imaging.psd1")

        $manifest.PrivateData.PSData.ReleaseNotes | Should -Match "PERF-01"
        $manifest.PrivateData.PSData.ReleaseNotes | Should -Match "Write-VolumeCache"
    }
}
