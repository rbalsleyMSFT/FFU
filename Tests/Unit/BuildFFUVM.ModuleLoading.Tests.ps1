#Requires -Module Pester
<#
.SYNOPSIS
    Pester tests for BuildFFUVM.ps1 module loading behavior.

.DESCRIPTION
    Tests that validate the defense-in-depth approach to module loading:
    - PSModulePath is configured early (before trap handlers)
    - Trap handler checks for function availability before calling
    - PowerShell.Exiting handler is defensive
    - Module dependencies can be resolved in background job contexts

.NOTES
    Version: 1.0.0
    Date: 2025-12-10
    Author: FFU Builder Team
    Related Issue: Module loading failure in ThreadJob context
#>

BeforeAll {
    # Set up paths
    $script:FFUDevelopmentPath = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:BuildFFUVMPath = Join-Path $script:FFUDevelopmentPath 'FFUDevelopment\BuildFFUVM.ps1'
    $script:ModulesPath = Join-Path $script:FFUDevelopmentPath 'FFUDevelopment\Modules'

    # Read the BuildFFUVM.ps1 content for static analysis
    $script:BuildFFUVMContent = Get-Content -Path $script:BuildFFUVMPath -Raw
}

Describe 'BuildFFUVM Module Loading' {

    Context 'PSModulePath Early Configuration' {

        It 'PSModulePath configuration exists in BuildFFUVM.ps1' {
            $script:BuildFFUVMContent | Should -Match 'PSModulePath'
        }

        It 'PSModulePath is configured BEFORE Import-Module FFU.Core' {
            # Find the position of PSModulePath setup
            $psModulePathMatch = [regex]::Match($script:BuildFFUVMContent, 'if \(\$env:PSModulePath -notlike "\*\$ModulePath\*"\)')
            $psModulePathPos = $psModulePathMatch.Index
            $psModulePathPos | Should -BeGreaterThan 0 -Because "PSModulePath configuration should exist"

            # Find the position of Import-Module FFU.Core
            $importCoreMatch = [regex]::Match($script:BuildFFUVMContent, 'Import-Module "FFU\.Core"')
            $importCorePos = $importCoreMatch.Index

            $psModulePathPos | Should -BeLessThan $importCorePos -Because "PSModulePath must be configured before importing FFU.Core"
        }

        It 'PSModulePath is configured after FFU.Common import' {
            # Find the position of FFU.Common import
            $importCommonMatch = [regex]::Match($script:BuildFFUVMContent, 'Import-Module "\$PSScriptRoot\\FFU\.Common"')
            $importCommonPos = $importCommonMatch.Index

            # Find the position of first PSModulePath setup
            $psModulePathMatch = [regex]::Match($script:BuildFFUVMContent, '\$ModulePath = "\$PSScriptRoot\\Modules"')
            $psModulePathPos = $psModulePathMatch.Index

            $psModulePathPos | Should -BeGreaterThan $importCommonPos -Because "PSModulePath setup should come after FFU.Common import"
        }

        It 'Contains defense-in-depth comment explaining early PSModulePath' {
            $script:BuildFFUVMContent | Should -Match 'EARLY PSModulePath Configuration \(Defense-in-Depth\)'
        }
    }

    Context 'Defensive Trap Handler' {

        It 'Trap handler exists in BuildFFUVM.ps1' {
            $script:BuildFFUVMContent | Should -Match 'trap \{'
        }

        It 'Trap handler checks for Get-CleanupRegistry availability before calling' {
            # The pattern should be: check Get-Command THEN call Get-CleanupRegistry
            $trapPattern = "trap \{[\s\S]*?Get-Command 'Get-CleanupRegistry'[\s\S]*?Get-CleanupRegistry[\s\S]*?\}"
            $script:BuildFFUVMContent | Should -Match $trapPattern -Because "Trap handler should check function availability first"
        }

        It 'Trap handler uses -ErrorAction SilentlyContinue for Get-Command check' {
            $script:BuildFFUVMContent | Should -Match "Get-Command 'Get-CleanupRegistry' -ErrorAction SilentlyContinue"
        }

        It 'Trap handler uses break to propagate errors' {
            $trapContent = [regex]::Match($script:BuildFFUVMContent, 'trap \{[\s\S]*?\n\}').Value
            $trapContent | Should -Match '\bbreak\b' -Because "Trap must propagate errors with 'break'"
        }
    }

    Context 'Defensive PowerShell.Exiting Handler' {

        It 'PowerShell.Exiting handler exists' {
            $script:BuildFFUVMContent | Should -Match 'Register-EngineEvent -SourceIdentifier PowerShell\.Exiting'
        }

        It 'PowerShell.Exiting handler checks for Get-CleanupRegistry availability' {
            $exitingPattern = "Register-EngineEvent -SourceIdentifier PowerShell\.Exiting -Action \{[\s\S]*?Get-Command 'Get-CleanupRegistry'"
            $script:BuildFFUVMContent | Should -Match $exitingPattern -Because "Exit handler should check function availability"
        }
    }

    Context 'Module Loading Order' {

        It 'FFU.Core is imported with -ErrorAction Stop' {
            $script:BuildFFUVMContent | Should -Match 'Import-Module "FFU\.Core".*-ErrorAction Stop'
        }

        It 'FFU.Core is imported with -Global for cross-scope availability' {
            $script:BuildFFUVMContent | Should -Match 'Import-Module "FFU\.Core".*-Global'
        }

        It 'Comment explains PSModulePath was configured earlier' {
            $script:BuildFFUVMContent | Should -Match 'PSModulePath was configured earlier in the script'
        }
    }
}

Describe 'Module Dependency Resolution' {

    Context 'FFU.Constants Availability' {

        It 'FFU.Constants module folder exists' {
            $constantsPath = Join-Path $script:ModulesPath 'FFU.Constants'
            Test-Path $constantsPath | Should -BeTrue
        }

        It 'FFU.Constants manifest exists' {
            $manifestPath = Join-Path $script:ModulesPath 'FFU.Constants\FFU.Constants.psd1'
            Test-Path $manifestPath | Should -BeTrue
        }

        It 'FFU.Constants can be imported when PSModulePath is set' {
            $originalPath = $env:PSModulePath
            try {
                if ($env:PSModulePath -notlike "*$script:ModulesPath*") {
                    $env:PSModulePath = "$script:ModulesPath;$env:PSModulePath"
                }
                { Import-Module 'FFU.Constants' -Force -ErrorAction Stop } | Should -Not -Throw
            }
            finally {
                $env:PSModulePath = $originalPath
                Remove-Module 'FFU.Constants' -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'FFU.Core Dependency Chain' {

        It 'FFU.Core requires FFU.Constants' {
            $manifestPath = Join-Path $script:ModulesPath 'FFU.Core\FFU.Core.psd1'
            $content = Get-Content $manifestPath -Raw
            # The manifest has RequiredModules with FFU.Constants - check for the pattern with possible line breaks
            $content | Should -Match "RequiredModules\s*=\s*@\(" -Because "RequiredModules should be defined"
            $content | Should -Match "FFU\.Constants" -Because "FFU.Constants should be a required module"
        }

        It 'FFU.Core can be imported when PSModulePath is set' {
            $originalPath = $env:PSModulePath
            try {
                if ($env:PSModulePath -notlike "*$script:ModulesPath*") {
                    $env:PSModulePath = "$script:ModulesPath;$env:PSModulePath"
                }
                { Import-Module 'FFU.Core' -Force -ErrorAction Stop } | Should -Not -Throw
            }
            finally {
                $env:PSModulePath = $originalPath
                Remove-Module 'FFU.Core' -Force -ErrorAction SilentlyContinue
                Remove-Module 'FFU.Constants' -Force -ErrorAction SilentlyContinue
            }
        }

        It 'Get-CleanupRegistry is available after FFU.Core import' {
            $originalPath = $env:PSModulePath
            try {
                if ($env:PSModulePath -notlike "*$script:ModulesPath*") {
                    $env:PSModulePath = "$script:ModulesPath;$env:PSModulePath"
                }
                Import-Module 'FFU.Core' -Force -ErrorAction Stop
                Get-Command 'Get-CleanupRegistry' -ErrorAction Stop | Should -Not -BeNullOrEmpty
            }
            finally {
                $env:PSModulePath = $originalPath
                Remove-Module 'FFU.Core' -Force -ErrorAction SilentlyContinue
                Remove-Module 'FFU.Constants' -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

Describe 'Background Job Module Loading Simulation' {

    Context 'ThreadJob Context Simulation' {

        It 'Module loading works in simulated background job context' {
            # Simulate what happens in a ThreadJob
            $scriptBlock = {
                param($ModulesPath)

                # This mimics what BuildFFUVM.ps1 does
                if ($env:PSModulePath -notlike "*$ModulesPath*") {
                    $env:PSModulePath = "$ModulesPath;$env:PSModulePath"
                }

                try {
                    Import-Module 'FFU.Core' -Force -ErrorAction Stop

                    # Test that Get-CleanupRegistry works
                    $cmd = Get-Command 'Get-CleanupRegistry' -ErrorAction SilentlyContinue
                    if ($cmd) {
                        return "SUCCESS"
                    }
                    return "FUNCTION_NOT_FOUND"
                }
                catch {
                    return "ERROR: $($_.Exception.Message)"
                }
            }

            if (Get-Command Start-ThreadJob -ErrorAction SilentlyContinue) {
                $job = Start-ThreadJob -ScriptBlock $scriptBlock -ArgumentList @($script:ModulesPath)
            } else {
                $job = Start-Job -ScriptBlock $scriptBlock -ArgumentList @($script:ModulesPath)
            }

            $job | Wait-Job -Timeout 30 | Out-Null
            $result = Receive-Job -Job $job
            Remove-Job -Job $job -Force

            $result | Should -Be "SUCCESS"
        }

        It 'Get-Command check returns null when module not loaded' {
            # In a clean context without FFU.Core loaded
            # Also remove FFU.Constants since FFU.Core depends on it
            Remove-Module 'FFU.Core' -Force -ErrorAction SilentlyContinue
            Remove-Module 'FFU.Constants' -Force -ErrorAction SilentlyContinue

            # Also clear from PSModulePath temporarily to prevent auto-loading
            $originalPath = $env:PSModulePath
            try {
                # Remove our modules folder from path to prevent auto-discovery
                $env:PSModulePath = ($env:PSModulePath -split ';' | Where-Object { $_ -notlike "*FFUDevelopment*" }) -join ';'

                $cmd = Get-Command 'Get-CleanupRegistry' -ErrorAction SilentlyContinue
                $cmd | Should -BeNullOrEmpty -Because "Function should not exist when module is not loaded and not discoverable"
            }
            finally {
                $env:PSModulePath = $originalPath
            }
        }
    }

    Context 'Error-Before-Module Scenario' {

        It 'Defensive check pattern works correctly' {
            # Simulate the defensive check pattern from the trap handler
            # Remove all FFU modules and prevent auto-loading
            Remove-Module 'FFU.Core' -Force -ErrorAction SilentlyContinue
            Remove-Module 'FFU.Constants' -Force -ErrorAction SilentlyContinue

            $originalPath = $env:PSModulePath
            try {
                # Remove our modules folder from path to prevent auto-discovery
                $env:PSModulePath = ($env:PSModulePath -split ';' | Where-Object { $_ -notlike "*FFUDevelopment*" }) -join ';'

                $defensiveBlock = {
                    if (Get-Command 'Get-CleanupRegistry' -ErrorAction SilentlyContinue) {
                        $registry = Get-CleanupRegistry
                        return "CLEANUP_CALLED"
                    }
                    return "SKIPPED_SAFELY"
                }

                $result = & $defensiveBlock
                $result | Should -Be "SKIPPED_SAFELY" -Because "Defensive check should skip when function unavailable"
            }
            finally {
                $env:PSModulePath = $originalPath
            }
        }

        It 'Defensive check calls cleanup when module IS loaded' {
            $originalPath = $env:PSModulePath
            try {
                if ($env:PSModulePath -notlike "*$script:ModulesPath*") {
                    $env:PSModulePath = "$script:ModulesPath;$env:PSModulePath"
                }
                Import-Module 'FFU.Core' -Force -ErrorAction Stop

                $defensiveBlock = {
                    if (Get-Command 'Get-CleanupRegistry' -ErrorAction SilentlyContinue) {
                        $registry = Get-CleanupRegistry
                        return "CLEANUP_AVAILABLE"
                    }
                    return "SKIPPED_SAFELY"
                }

                $result = & $defensiveBlock
                $result | Should -Be "CLEANUP_AVAILABLE" -Because "Defensive check should proceed when function available"
            }
            finally {
                $env:PSModulePath = $originalPath
                Remove-Module 'FFU.Core' -Force -ErrorAction SilentlyContinue
                Remove-Module 'FFU.Constants' -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

Describe 'Code Position Verification' {

    Context 'Line Number Ordering' {

        It 'PSModulePath setup appears before line 700 in the file' {
            $lines = $script:BuildFFUVMContent -split "`n"
            $earlySetupLine = -1

            for ($i = 0; $i -lt $lines.Count; $i++) {
                if ($lines[$i] -match 'EARLY PSModulePath Configuration') {
                    $earlySetupLine = $i + 1  # Convert to 1-based line number
                    break
                }
            }

            $earlySetupLine | Should -BeGreaterThan 0 -Because "Early PSModulePath comment should exist"
            $earlySetupLine | Should -BeLessThan 700 -Because "Early setup should be in first third of file"
        }

        It 'Import-Module FFU.Core appears after PSModulePath setup' {
            $lines = $script:BuildFFUVMContent -split "`n"
            $psModulePathLine = -1
            $importCoreLine = -1

            for ($i = 0; $i -lt $lines.Count; $i++) {
                if ($lines[$i] -match '\$env:PSModulePath = "\$ModulePath;\$env:PSModulePath"' -and $psModulePathLine -eq -1) {
                    $psModulePathLine = $i + 1
                }
                if ($lines[$i] -match 'Import-Module "FFU\.Core"') {
                    $importCoreLine = $i + 1
                    break
                }
            }

            $psModulePathLine | Should -BeGreaterThan 0
            $importCoreLine | Should -BeGreaterThan 0
            $importCoreLine | Should -BeGreaterThan $psModulePathLine
        }
    }
}
