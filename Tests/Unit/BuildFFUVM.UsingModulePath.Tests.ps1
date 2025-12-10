#Requires -Module Pester
<#
.SYNOPSIS
    Pester tests for BuildFFUVM.ps1 module path resolution fix.

.DESCRIPTION
    Tests that validate the fix for the 'using module' relative path issue:
    - The 'using module' statement was removed from BuildFFUVM.ps1
    - Param block defaults are hardcoded instead of using FFUConstants
    - BuildFFUVM_UI.ps1 sets working directory before running BuildFFUVM.ps1
    - Module loading works correctly in ThreadJob context

.NOTES
    Version: 1.0.0
    Date: 2025-12-10
    Author: FFU Builder Team
    Related Issue: FFU.Constants not found in ThreadJob context
#>

BeforeAll {
    # Set up paths
    $script:FFUDevelopmentPath = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:BuildFFUVMPath = Join-Path $script:FFUDevelopmentPath 'FFUDevelopment\BuildFFUVM.ps1'
    $script:BuildFFUVMUIPath = Join-Path $script:FFUDevelopmentPath 'FFUDevelopment\BuildFFUVM_UI.ps1'
    $script:ModulesPath = Join-Path $script:FFUDevelopmentPath 'FFUDevelopment\Modules'
    $script:FFUConstantsPath = Join-Path $script:ModulesPath 'FFU.Constants\FFU.Constants.psm1'

    # Read file contents for static analysis
    $script:BuildFFUVMContent = Get-Content -Path $script:BuildFFUVMPath -Raw
    $script:BuildFFUVMUIContent = Get-Content -Path $script:BuildFFUVMUIPath -Raw
    $script:FFUConstantsContent = Get-Content -Path $script:FFUConstantsPath -Raw
}

Describe 'BuildFFUVM.ps1 Using Module Removal' {

    Context 'No using module Statement' {

        It 'Should NOT contain using module statement at beginning of script' {
            # Check that no line starts with 'using module' (ignoring comments mentioning it)
            $lines = $script:BuildFFUVMContent -split "`n"
            $usingModuleLines = $lines | Where-Object { $_ -match '^\s*using module' }
            $usingModuleLines.Count | Should -Be 0 -Because "Script should not have 'using module' statement"
        }

        It 'Should NOT contain relative path to FFU.Constants' {
            $script:BuildFFUVMContent | Should -Not -Match '\\\.\\Modules\\FFU\.Constants'
        }

        It 'Should contain comment explaining why using module was removed' {
            $script:BuildFFUVMContent | Should -Match 'WHY NOT.*using module'
        }

        It 'Should document that hardcoded values must match FFU.Constants' {
            $script:BuildFFUVMContent | Should -Match 'MUST match FFU\.Constants'
        }
    }

    Context 'Hardcoded Param Block Defaults' {

        It 'Memory default should be 4GB (not FFUConstants reference)' {
            $script:BuildFFUVMContent | Should -Match '\[uint64\]\$Memory\s*=\s*4GB'
            $script:BuildFFUVMContent | Should -Not -Match '\$Memory\s*=\s*\[FFUConstants\]::DEFAULT_VM_MEMORY'
        }

        It 'Disksize default should be 50GB (not FFUConstants reference)' {
            $script:BuildFFUVMContent | Should -Match '\[uint64\]\$Disksize\s*=\s*50GB'
            $script:BuildFFUVMContent | Should -Not -Match '\$Disksize\s*=\s*\[FFUConstants\]::DEFAULT_VHDX_SIZE'
        }

        It 'Processors default should be 4 (not FFUConstants reference)' {
            $script:BuildFFUVMContent | Should -Match '\[int\]\$Processors\s*=\s*4'
            $script:BuildFFUVMContent | Should -Not -Match '\$Processors\s*=\s*\[FFUConstants\]::DEFAULT_VM_PROCESSORS'
        }

        It 'Memory default should have comment referencing FFUConstants' {
            $script:BuildFFUVMContent | Should -Match '\$Memory\s*=\s*4GB.*#.*FFUConstants'
        }

        It 'Disksize default should have comment referencing FFUConstants' {
            $script:BuildFFUVMContent | Should -Match '\$Disksize\s*=\s*50GB.*#.*FFUConstants'
        }

        It 'Processors default should have comment referencing FFUConstants' {
            $script:BuildFFUVMContent | Should -Match '\$Processors\s*=\s*4.*#.*FFUConstants'
        }
    }

    Context 'Hardcoded Values Match FFU.Constants' {

        It 'Memory default (4GB) should match FFU.Constants DEFAULT_VM_MEMORY' {
            # Extract value from FFU.Constants
            $match = [regex]::Match($script:FFUConstantsContent, 'DEFAULT_VM_MEMORY\s*=\s*(\d+GB)')
            $constantValue = $match.Groups[1].Value
            $constantValue | Should -Be '4GB'
        }

        It 'Disksize default (50GB) should match FFU.Constants DEFAULT_VHDX_SIZE' {
            $match = [regex]::Match($script:FFUConstantsContent, 'DEFAULT_VHDX_SIZE\s*=\s*(\d+GB)')
            $constantValue = $match.Groups[1].Value
            $constantValue | Should -Be '50GB'
        }

        It 'Processors default (4) should match FFU.Constants DEFAULT_VM_PROCESSORS' {
            $match = [regex]::Match($script:FFUConstantsContent, 'DEFAULT_VM_PROCESSORS\s*=\s*(\d+)')
            $constantValue = $match.Groups[1].Value
            $constantValue | Should -Be '4'
        }
    }
}

Describe 'BuildFFUVM_UI.ps1 Working Directory Fix' {

    Context 'ScriptBlock Working Directory' {

        It 'Should contain Set-Location in the build scriptBlock' {
            $script:BuildFFUVMUIContent | Should -Match 'Set-Location \$ScriptRoot'
        }

        It 'Should use $ScriptRoot parameter (not $PSScriptRoot)' {
            # Check the scriptBlock parameter declaration
            $script:BuildFFUVMUIContent | Should -Match 'param\(\$buildParams,\s*\$ScriptRoot\)'
        }

        It 'Should have comment explaining why Set-Location is needed' {
            $script:BuildFFUVMUIContent | Should -Match 'working directory'
        }

        It 'Should mention ThreadJobs in the comment' {
            $script:BuildFFUVMUIContent | Should -Match 'ThreadJob'
        }

        It 'Set-Location should come BEFORE calling BuildFFUVM.ps1' {
            $setLocationPos = $script:BuildFFUVMUIContent.IndexOf('Set-Location $ScriptRoot')
            $invokeScriptPos = $script:BuildFFUVMUIContent.IndexOf('& "$ScriptRoot\BuildFFUVM.ps1"')

            $setLocationPos | Should -BeGreaterThan 0 -Because "Set-Location should exist"
            $invokeScriptPos | Should -BeGreaterThan 0 -Because "Script invocation should exist"
            $setLocationPos | Should -BeLessThan $invokeScriptPos -Because "Set-Location must come before script invocation"
        }
    }
}

Describe 'No Runtime FFUConstants References in BuildFFUVM.ps1' {

    Context 'VM_STATE_POLL_INTERVAL Hardcoded' {

        It 'Should NOT have runtime [FFUConstants]:: references (causes ThreadJob failures)' {
            # Check for actual code usage (not comments)
            $lines = $script:BuildFFUVMContent -split "`n"
            $codeUsages = $lines | Where-Object {
                # Must contain [FFUConstants]:: and NOT be a comment line or inside a comment
                $_ -match '\[FFUConstants\]::' -and
                $_ -notmatch '^\s*#' -and           # Not a comment line
                $_ -notmatch '#.*\[FFUConstants\]'  # Not referenced in a comment
            }
            $codeUsages.Count | Should -Be 0 -Because "[FFUConstants]:: type is not available without 'using module' statement"
        }

        It 'Should have hardcoded VM poll interval (5 seconds) with FFUConstants comment' {
            $script:BuildFFUVMContent | Should -Match 'Start-Sleep -Seconds 5.*#.*VM_STATE_POLL_INTERVAL'
        }

        It 'VM_STATE_POLL_INTERVAL should exist in FFU.Constants module (source of truth)' {
            $script:FFUConstantsContent | Should -Match 'VM_STATE_POLL_INTERVAL\s*=\s*5'
        }

        It 'Should have comment explaining VM poll interval value' {
            $script:BuildFFUVMContent | Should -Match 'VM poll interval.*must match'
        }
    }

    Context 'Only Comments Reference FFUConstants' {

        It 'FFUConstants references in param block should be in comments only' {
            # These are documentation comments, not actual code
            $script:BuildFFUVMContent | Should -Match '\$Memory\s*=\s*4GB.*#.*FFUConstants'
            $script:BuildFFUVMContent | Should -Match '\$Disksize\s*=\s*50GB.*#.*FFUConstants'
            $script:BuildFFUVMContent | Should -Match '\$Processors\s*=\s*4.*#.*FFUConstants'
        }
    }
}

Describe 'ThreadJob Working Directory Simulation' {

    Context 'Set-Location Effect' {

        It 'Set-Location should change working directory in job' {
            $targetDir = $script:FFUDevelopmentPath
            $targetDir = Join-Path $targetDir 'FFUDevelopment'

            $scriptBlock = {
                param($TargetDir)
                $before = Get-Location
                Set-Location $TargetDir
                $after = Get-Location
                return @{
                    Before = $before.Path
                    After = $after.Path
                    TargetDir = $TargetDir
                }
            }

            if (Get-Command Start-ThreadJob -ErrorAction SilentlyContinue) {
                $job = Start-ThreadJob -ScriptBlock $scriptBlock -ArgumentList @($targetDir)
            } else {
                $job = Start-Job -ScriptBlock $scriptBlock -ArgumentList @($targetDir)
            }

            $job | Wait-Job -Timeout 30 | Out-Null
            $result = Receive-Job -Job $job
            Remove-Job -Job $job -Force

            $result.After | Should -Be $targetDir
        }

        It 'Relative paths should resolve correctly after Set-Location' {
            $targetDir = Join-Path $script:FFUDevelopmentPath 'FFUDevelopment'

            $scriptBlock = {
                param($TargetDir)
                Set-Location $TargetDir
                $relativePath = ".\Modules\FFU.Constants"
                $resolved = Join-Path (Get-Location) $relativePath
                return @{
                    RelativePath = $relativePath
                    Resolved = $resolved
                    Exists = (Test-Path $resolved)
                }
            }

            if (Get-Command Start-ThreadJob -ErrorAction SilentlyContinue) {
                $job = Start-ThreadJob -ScriptBlock $scriptBlock -ArgumentList @($targetDir)
            } else {
                $job = Start-Job -ScriptBlock $scriptBlock -ArgumentList @($targetDir)
            }

            $job | Wait-Job -Timeout 30 | Out-Null
            $result = Receive-Job -Job $job
            Remove-Job -Job $job -Force

            $result.Exists | Should -BeTrue -Because "Relative path should resolve to existing module folder"
        }
    }

    Context 'Full Integration Simulation' {

        It 'BuildFFUVM.ps1 should be parseable from any working directory' {
            # Save current location
            $originalLocation = Get-Location

            try {
                # Change to a completely different directory (simulates ThreadJob default)
                Set-Location $env:TEMP

                # Try to parse BuildFFUVM.ps1 - this should work because 'using module' was removed
                $parseErrors = $null
                [System.Management.Automation.Language.Parser]::ParseFile(
                    $script:BuildFFUVMPath,
                    [ref]$null,
                    [ref]$parseErrors
                ) | Out-Null

                # Note: We can't fully verify module loading without actually running the script,
                # but successful parsing means the 'using module' issue is resolved
                $parseErrors.Count | Should -Be 0 -Because "Script should parse without errors from any directory"
            }
            finally {
                Set-Location $originalLocation
            }
        }
    }
}

Describe 'No Regression in Module Imports' {

    Context 'PSModulePath Configuration Still Present' {

        It 'Should still configure PSModulePath early in the script' {
            $script:BuildFFUVMContent | Should -Match 'PSModulePath'
        }

        It 'Should still import FFU.Core module' {
            $script:BuildFFUVMContent | Should -Match 'Import-Module "FFU\.Core"'
        }

        It 'FFU.Core should still depend on FFU.Constants via RequiredModules' {
            $ffuCoreManifestPath = Join-Path $script:ModulesPath 'FFU.Core\FFU.Core.psd1'
            $manifest = Get-Content $ffuCoreManifestPath -Raw
            $manifest | Should -Match 'FFU\.Constants'
        }
    }
}
