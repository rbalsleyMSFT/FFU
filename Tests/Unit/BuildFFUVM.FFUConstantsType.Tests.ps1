#Requires -Module Pester
<#
.SYNOPSIS
    Pester tests for FFUConstants type availability in BuildFFUVM.ps1.

.DESCRIPTION
    Tests that validate the fix for "Unable to find type [FFUConstants]" error:
    - The [FFUConstants]:: class references have been replaced with hardcoded values
    - BuildFFUVM.ps1 no longer requires 'using module' statement
    - Values are documented with comments referencing FFUConstants
    - Modules that need FFUConstants properly use 'using module' statement

.NOTES
    Version: 1.0.0
    Date: 2025-12-10
    Author: FFU Builder Team
    Related Issue: Unable to find type [FFUConstants] during FFU capture

    Root Cause Analysis:
    - 'using module' was removed from BuildFFUVM.ps1 in v1.2.8 to fix ThreadJob path issue
    - But [FFUConstants]::VM_STATE_POLL_INTERVAL was still referenced at runtime (line 3542)
    - PowerShell classes require 'using module' to be available - Import-Module is not sufficient
    - Modules (FFU.Core, FFU.Imaging, etc.) work because they have their own 'using module' statements

    Solution:
    - Replace all [FFUConstants]:: runtime references in BuildFFUVM.ps1 with hardcoded values
    - Add comments referencing FFUConstants as the source of truth
    - Keep 'using module' statements in modules (they resolve relative to $PSScriptRoot)
#>

BeforeAll {
    # Set up paths
    $script:FFUDevelopmentPath = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:BuildFFUVMPath = Join-Path $script:FFUDevelopmentPath 'FFUDevelopment\BuildFFUVM.ps1'
    $script:ModulesPath = Join-Path $script:FFUDevelopmentPath 'FFUDevelopment\Modules'
    $script:FFUConstantsPath = Join-Path $script:ModulesPath 'FFU.Constants\FFU.Constants.psm1'

    # Read file contents for static analysis
    $script:BuildFFUVMContent = Get-Content -Path $script:BuildFFUVMPath -Raw
    $script:FFUConstantsContent = Get-Content -Path $script:FFUConstantsPath -Raw
}

Describe 'BuildFFUVM.ps1 FFUConstants Type Fix' -Tag 'FFUConstants', 'BugFix' {

    Context 'No [FFUConstants]:: Code References' {

        It 'Should NOT have any [FFUConstants]:: code references in BuildFFUVM.ps1' {
            # Extract all lines that have [FFUConstants]::
            $lines = $script:BuildFFUVMContent -split "`n"
            $codeReferences = @()

            for ($i = 0; $i -lt $lines.Count; $i++) {
                $line = $lines[$i]
                # Check if line has [FFUConstants]:: but is NOT a comment
                if ($line -match '\[FFUConstants\]::' -and
                    $line -notmatch '^\s*#' -and           # Line doesn't start with #
                    $line -notmatch '#.*\[FFUConstants\]') {  # FFUConstants is not in a comment
                    $codeReferences += "Line $($i + 1): $line"
                }
            }

            $codeReferences.Count | Should -Be 0 -Because @"
[FFUConstants]:: type requires 'using module' statement which was removed.
Found code references:
$($codeReferences -join "`n")
"@
        }

        It 'Comment references to FFUConstants are allowed (for documentation)' {
            # Verify we have comments referencing FFUConstants (for maintainability)
            $script:BuildFFUVMContent | Should -Match '#.*FFUConstants'
        }
    }

    Context 'Hardcoded Values with Documentation' {

        It 'VM poll interval (5 seconds) should be hardcoded with FFUConstants comment' {
            # The VM_STATE_POLL_INTERVAL was the last runtime reference
            $script:BuildFFUVMContent | Should -Match 'Start-Sleep -Seconds 5.*#.*VM.*POLL.*INTERVAL'
        }

        It 'Memory default (4GB) should be hardcoded with FFUConstants comment' {
            $script:BuildFFUVMContent | Should -Match '\$Memory\s*=\s*4GB.*#.*FFUConstants'
        }

        It 'Disksize default (50GB) should be hardcoded with FFUConstants comment' {
            $script:BuildFFUVMContent | Should -Match '\$Disksize\s*=\s*50GB.*#.*FFUConstants'
        }

        It 'Processors default (4) should be hardcoded with FFUConstants comment' {
            $script:BuildFFUVMContent | Should -Match '\$Processors\s*=\s*4.*#.*FFUConstants'
        }
    }

    Context 'Hardcoded Values Match FFU.Constants Module' {

        It 'VM_STATE_POLL_INTERVAL = 5 in FFU.Constants' {
            $match = [regex]::Match($script:FFUConstantsContent, 'VM_STATE_POLL_INTERVAL\s*=\s*(\d+)')
            $match.Success | Should -BeTrue -Because "VM_STATE_POLL_INTERVAL should exist in FFU.Constants"
            $match.Groups[1].Value | Should -Be '5'
        }

        It 'DEFAULT_VM_MEMORY = 4GB in FFU.Constants' {
            $match = [regex]::Match($script:FFUConstantsContent, 'DEFAULT_VM_MEMORY\s*=\s*(\d+GB)')
            $match.Success | Should -BeTrue
            $match.Groups[1].Value | Should -Be '4GB'
        }

        It 'DEFAULT_VHDX_SIZE = 50GB in FFU.Constants' {
            $match = [regex]::Match($script:FFUConstantsContent, 'DEFAULT_VHDX_SIZE\s*=\s*(\d+GB)')
            $match.Success | Should -BeTrue
            $match.Groups[1].Value | Should -Be '50GB'
        }

        It 'DEFAULT_VM_PROCESSORS = 4 in FFU.Constants' {
            $match = [regex]::Match($script:FFUConstantsContent, 'DEFAULT_VM_PROCESSORS\s*=\s*(\d+)')
            $match.Success | Should -BeTrue
            $match.Groups[1].Value | Should -Be '4'
        }
    }
}

Describe 'Modules Properly Use FFUConstants' -Tag 'FFUConstants', 'Modules' {

    Context 'Modules Have using module Statements' {

        It 'FFU.Core should have using module for FFU.Constants' {
            $modulePath = Join-Path $script:ModulesPath 'FFU.Core\FFU.Core.psm1'
            $moduleContent = Get-Content -Path $modulePath -Raw
            $moduleContent | Should -Match 'using module.*FFU\.Constants'
        }

        It 'FFU.Imaging should have using module for FFU.Constants' {
            $modulePath = Join-Path $script:ModulesPath 'FFU.Imaging\FFU.Imaging.psm1'
            $moduleContent = Get-Content -Path $modulePath -Raw
            $moduleContent | Should -Match 'using module.*FFU\.Constants'
        }

        It 'FFU.Media should have using module for FFU.Constants' {
            $modulePath = Join-Path $script:ModulesPath 'FFU.Media\FFU.Media.psm1'
            $moduleContent = Get-Content -Path $modulePath -Raw
            $moduleContent | Should -Match 'using module.*FFU\.Constants'
        }

        It 'FFU.Drivers should have using module for FFU.Constants' {
            $modulePath = Join-Path $script:ModulesPath 'FFU.Drivers\FFU.Drivers.psm1'
            $moduleContent = Get-Content -Path $modulePath -Raw
            $moduleContent | Should -Match 'using module.*FFU\.Constants'
        }

        It 'FFU.Updates should have using module for FFU.Constants' {
            $modulePath = Join-Path $script:ModulesPath 'FFU.Updates\FFU.Updates.psm1'
            $moduleContent = Get-Content -Path $modulePath -Raw
            $moduleContent | Should -Match 'using module.*FFU\.Constants'
        }
    }

    Context 'Module using module Paths Are Relative to Module Location' {

        It 'FFU.Core uses relative path ../FFU.Constants' {
            $modulePath = Join-Path $script:ModulesPath 'FFU.Core\FFU.Core.psm1'
            $moduleContent = Get-Content -Path $modulePath -Raw
            $moduleContent | Should -Match 'using module \.\.\\FFU\.Constants'
        }

        It 'Relative paths resolve correctly from module directory' {
            # Verify the relative path resolves to an existing file
            $ffuCorePath = Join-Path $script:ModulesPath 'FFU.Core'
            $relativePath = '..\FFU.Constants\FFU.Constants.psm1'
            $resolvedPath = Join-Path $ffuCorePath $relativePath

            Test-Path $resolvedPath | Should -BeTrue -Because "Relative path should resolve to FFU.Constants.psm1"
        }
    }
}

Describe 'BuildFFUVM.ps1 Has No using module Statement' -Tag 'FFUConstants', 'ThreadJob' {

    Context 'Removed to Fix ThreadJob Working Directory Issue' {

        It 'Should NOT have using module statement (causes ThreadJob failures)' {
            $lines = $script:BuildFFUVMContent -split "`n"
            $usingModuleLines = $lines | Where-Object { $_ -match '^\s*using module' }
            $usingModuleLines.Count | Should -Be 0
        }

        It 'Should have comment explaining why using module was removed' {
            $script:BuildFFUVMContent | Should -Match 'WHY NOT.*using module'
        }
    }
}

Describe 'FFU Capture Phase - Error Regression Prevention' -Tag 'FFUConstants', 'Regression' {

    Context 'FFU Capture Try Block Has No Type Dependencies' {

        It 'FFU capture section should not reference [FFUConstants]::' {
            # Find the FFU capture section (around line 3515-3592)
            $captureSection = [regex]::Match($script:BuildFFUVMContent,
                '(?s)#Capture FFU file\s*try \{.*?^Catch \{.*?throw \$_',
                [System.Text.RegularExpressions.RegexOptions]::Multiline)

            $captureSection.Success | Should -BeTrue -Because "FFU capture section should exist"

            # Check for [FFUConstants]:: code references (not comments)
            $lines = $captureSection.Value -split "`n"
            $codeRefs = $lines | Where-Object {
                $_ -match '\[FFUConstants\]::' -and
                $_ -notmatch '^\s*#' -and
                $_ -notmatch '#.*\[FFUConstants\]'
            }

            $codeRefs.Count | Should -Be 0 -Because "FFU capture should not depend on FFUConstants type"
        }
    }

    Context 'Error Message From Original Bug Should Not Occur' {

        It 'Sleep command in VM wait loop uses hardcoded value' {
            # This was the exact line that caused the error
            $script:BuildFFUVMContent | Should -Match 'do \{[\s\S]*?Start-Sleep -Seconds 5.*#.*VM.*poll[\s\S]*?\} while'
        }
    }
}

Describe 'ThreadJob Compatibility Validation' -Tag 'FFUConstants', 'ThreadJob', 'Functional' {

    Context 'Script Parses Without FFUConstants Type' {

        It 'BuildFFUVM.ps1 should parse without errors from any directory' {
            # Save current location
            $originalLocation = Get-Location

            try {
                # Change to temp directory (simulates ThreadJob working directory)
                Set-Location $env:TEMP

                # Parse the script - this should work because [FFUConstants]:: references are removed
                $parseErrors = $null
                [System.Management.Automation.Language.Parser]::ParseFile(
                    $script:BuildFFUVMPath,
                    [ref]$null,
                    [ref]$parseErrors
                ) | Out-Null

                $parseErrors.Count | Should -Be 0 -Because "Script should parse without type resolution errors"
            }
            finally {
                Set-Location $originalLocation
            }
        }
    }
}
