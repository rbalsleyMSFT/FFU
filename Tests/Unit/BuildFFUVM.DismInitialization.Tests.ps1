#Requires -Modules Pester
<#
.SYNOPSIS
    Pester tests for DISM initialization fix in BuildFFUVM.ps1.

.DESCRIPTION
    Tests the fix for DISM initialization error 0x80004005 that occurred when
    Get-WindowsOptionalFeature was called before logging was set up.

    The fix:
    1. Moves logging initialization BEFORE the Hyper-V check
    2. Adds DISM cleanup (dism.exe /Cleanup-Mountpoints) before the check
    3. Adds retry logic (3 retries, 5 second delays)
    4. Provides actionable error messages on failure

.NOTES
    Version: 1.0.0
    Date: 2025-12-09
    Author: Claude Code
    Bug Reference: DismInitialize failed. Error code = 0x80004005
#>

BeforeAll {
    # Get script path
    $ScriptPath = Join-Path $PSScriptRoot "..\..\FFUDevelopment\BuildFFUVM.ps1"

    # Read the script content for static analysis
    $ScriptContent = Get-Content $ScriptPath -Raw

    # Parse the script to get the AST for detailed analysis
    $ScriptBlock = [ScriptBlock]::Create($ScriptContent)
    $Ast = $ScriptBlock.Ast

    # Get line numbers for key sections
    $script:Lines = Get-Content $ScriptPath
}

Describe "BuildFFUVM.ps1 DISM Initialization Fix" -Tag "DismInitialization", "BugFix" {

    Context "Logging Initialization Order" {
        It "Should set LogFile default BEFORE Hyper-V check" {
            # Find where LogFile is first set
            $logFileSetLine = ($script:Lines | Select-String -Pattern 'if \(-not \$LogFile\) \{ \$LogFile = ').LineNumber | Select-Object -First 1

            # Find where Hyper-V check starts (Get-WindowsOptionalFeature)
            $hyperVCheckLine = ($script:Lines | Select-String -Pattern 'Get-WindowsOptionalFeature.*Microsoft-Hyper-V-All').LineNumber | Select-Object -First 1

            # LogFile should be set BEFORE Hyper-V check
            $logFileSetLine | Should -BeLessThan $hyperVCheckLine -Because "LogFile must be available for DISM error logging"
        }

        It "Should initialize Set-CommonCoreLogPath BEFORE Hyper-V check" {
            # Find where logging is initialized
            $logInitLine = ($script:Lines | Select-String -Pattern 'Set-CommonCoreLogPath.*-Initialize').LineNumber | Select-Object -First 1

            # Find where Hyper-V check starts
            $hyperVCheckLine = ($script:Lines | Select-String -Pattern 'Get-WindowsOptionalFeature.*Microsoft-Hyper-V-All').LineNumber | Select-Object -First 1

            # Logging should be initialized BEFORE Hyper-V check
            $logInitLine | Should -BeLessThan $hyperVCheckLine -Because "Logging must be active to capture DISM errors"
        }

        It "Should have comment explaining early LogFile initialization" {
            $ScriptContent | Should -Match 'Set LogFile default EARLY.*before Hyper-V check'
        }

        It "Should have comment explaining early logging initialization" {
            $ScriptContent | Should -Match 'Initialize logging EARLY.*before Hyper-V check'
        }
    }

    Context "DISM Cleanup Before Hyper-V Check" {
        It "Should run DISM cleanup before Get-WindowsOptionalFeature" {
            # Find DISM cleanup line
            $dismCleanupLine = ($script:Lines | Select-String -Pattern 'dism\.exe /Cleanup-Mountpoints').LineNumber | Select-Object -First 1

            # Find Get-WindowsOptionalFeature line
            $hyperVCheckLine = ($script:Lines | Select-String -Pattern 'Get-WindowsOptionalFeature.*Microsoft-Hyper-V-All').LineNumber | Select-Object -First 1

            # DISM cleanup should be BEFORE Hyper-V check
            $dismCleanupLine | Should -BeLessThan $hyperVCheckLine -Because "DISM cleanup prevents 0x80004005 errors"
        }

        It "Should use WriteLog for DISM cleanup status" {
            $ScriptContent | Should -Match 'WriteLog "Cleaning stale DISM mount points'
        }

        It "Should log DISM cleanup completion" {
            $ScriptContent | Should -Match 'WriteLog "DISM cleanup completed'
        }

        It "Should handle DISM cleanup failures gracefully" {
            # Should have try-catch around DISM cleanup
            $ScriptContent | Should -Match 'catch \{[\s\S]*?WriteLog "Warning: DISM cleanup failed'
        }
    }

    Context "Retry Logic Structure" {
        It "Should define maxRetries as 3" {
            $ScriptContent | Should -Match '\$maxRetries\s*=\s*3'
        }

        It "Should define retryDelay as 5 seconds" {
            $ScriptContent | Should -Match '\$retryDelay\s*=\s*5'
        }

        It "Should have a for loop for retry attempts" {
            $ScriptContent | Should -Match 'for \(\$attempt\s*=\s*1;\s*\$attempt\s*-le\s*\$maxRetries'
        }

        It "Should log each retry attempt" {
            $ScriptContent | Should -Match 'WriteLog "Checking Hyper-V feature state \(attempt \$attempt of \$maxRetries\)'
        }

        It "Should use -ErrorAction Stop for Get-WindowsOptionalFeature" {
            $ScriptContent | Should -Match 'Get-WindowsOptionalFeature.*-ErrorAction Stop'
        }

        It "Should break out of loop on success" {
            $ScriptContent | Should -Match 'WriteLog "Hyper-V feature state:.*\$\(\$hyperVFeature\.State\)"[\s\S]*?break'
        }

        It "Should use Start-Sleep between retries" {
            $ScriptContent | Should -Match 'Start-Sleep\s*-Seconds\s*\$retryDelay'
        }

        It "Should log warning before each retry" {
            $ScriptContent | Should -Match 'WriteLog "Waiting \$retryDelay seconds before retry'
        }
    }

    Context "Error Messages Quality" {
        It "Should provide actionable error message on final failure" {
            $ScriptContent | Should -Match 'Failed to query Hyper-V feature state after \$maxRetries attempts'
        }

        It "Should mention DISM operation in progress as common cause" {
            $ScriptContent | Should -Match 'Another DISM operation in progress'
        }

        It "Should mention running dism.exe /Cleanup-Mountpoints" {
            $ScriptContent | Should -Match "run 'dism\.exe /Cleanup-Mountpoints' as Administrator"
        }

        It "Should mention antivirus as potential cause" {
            $ScriptContent | Should -Match 'Antivirus blocking DISM'
        }

        It "Should mention permissions requirement" {
            $ScriptContent | Should -Match 'ensure running as Administrator'
        }

        It "Should include the original exception message" {
            $ScriptContent | Should -Match 'Error: \$\(\$_\.Exception\.Message\)'
        }

        It "Should log error with WriteLog before throwing" {
            $ScriptContent | Should -Match 'WriteLog "ERROR: \$errorMsg"[\s\S]*?throw \$errorMsg'
        }
    }

    Context "Code Flow Integrity" {
        It "Should still check Hyper-V state after successful query" {
            $ScriptContent | Should -Match '\$hyperVFeature\.State -ne "Enabled"'
        }

        It "Should preserve Windows Server handling (Get-WindowsFeature)" {
            $ScriptContent | Should -Match 'Get-WindowsFeature -Name Hyper-V'
        }

        It "Should have isServer check to differentiate client vs server" {
            $ScriptContent | Should -Match '\$isServer = \$osInfo\.Caption -match ''server'''
        }

        It "Should not duplicate Set-CommonCoreLogPath calls" {
            # Count Set-CommonCoreLogPath -Initialize occurrences (should be exactly 1)
            $matches = [regex]::Matches($ScriptContent, 'Set-CommonCoreLogPath\s+-Path\s+\$LogFile\s+-Initialize')
            $matches.Count | Should -Be 1 -Because "Logging should only be initialized once"
        }
    }

    Context "Cleanup Mode Handling" {
        It "Should handle -Cleanup parameter for logging (append, not initialize)" {
            $ScriptContent | Should -Match 'else\s*\{[\s\S]*?# For cleanup operations, append to existing log[\s\S]*?Set-CommonCoreLogPath -Path \$LogFile[\s\S]*?\}'
        }
    }
}

Describe "DISM Initialization Fix - Functional Tests" -Tag "DismInitialization", "Functional" {

    Context "Script Line Number Verification" {
        BeforeAll {
            $script:LogFileSetLineNumber = ($script:Lines | Select-String -Pattern 'if \(-not \$LogFile\) \{ \$LogFile = ').LineNumber | Select-Object -First 1
            $script:LogInitLineNumber = ($script:Lines | Select-String -Pattern 'Set-CommonCoreLogPath.*-Initialize').LineNumber | Select-Object -First 1
            $script:DismCleanupLineNumber = ($script:Lines | Select-String -Pattern 'dism\.exe /Cleanup-Mountpoints').LineNumber | Select-Object -First 1
            $script:HyperVCheckLineNumber = ($script:Lines | Select-String -Pattern 'Get-WindowsOptionalFeature.*Microsoft-Hyper-V-All').LineNumber | Select-Object -First 1
        }

        It "LogFile default is set before line 1275" {
            # Line number adjusted for v1.2.8 changes (using module removal added documentation comments)
            $script:LogFileSetLineNumber | Should -BeLessThan 1275 -Because "LogFile must be set early in the script"
        }

        It "Logging is initialized before line 1285" {
            # Line number adjusted for v1.2.8 changes (using module removal added documentation comments)
            $script:LogInitLineNumber | Should -BeLessThan 1285 -Because "Logging must be initialized early"
        }

        It "DISM cleanup is before Hyper-V check (within 30 lines)" {
            ($script:HyperVCheckLineNumber - $script:DismCleanupLineNumber) | Should -BeLessThan 30 -Because "DISM cleanup should be close to Hyper-V check"
        }

        It "Correct order: LogFile -> LogInit -> DismCleanup -> HyperVCheck" {
            $script:LogFileSetLineNumber | Should -BeLessThan $script:LogInitLineNumber
            $script:LogInitLineNumber | Should -BeLessThan $script:DismCleanupLineNumber
            $script:DismCleanupLineNumber | Should -BeLessThan $script:HyperVCheckLineNumber
        }
    }

    Context "Retry Constants Validation" {
        It "Uses industry standard retry count (3)" {
            $match = [regex]::Match($ScriptContent, '\$maxRetries\s*=\s*(\d+)')
            [int]$match.Groups[1].Value | Should -Be 3
        }

        It "Uses reasonable retry delay (5 seconds)" {
            $match = [regex]::Match($ScriptContent, '\$retryDelay\s*=\s*(\d+)')
            [int]$match.Groups[1].Value | Should -Be 5
        }
    }
}

Describe "Regression Prevention Tests" -Tag "DismInitialization", "Regression" {

    Context "No Duplicate Initialization" {
        It "LogFile default should appear only once" {
            $matches = [regex]::Matches($ScriptContent, "if \(-not \`$LogFile\) \{ \`$LogFile = [^}]+\}")
            $matches.Count | Should -Be 1 -Because "LogFile default should not be duplicated"
        }

        It "Should have note about LogFile being set early where duplicate used to be" {
            $ScriptContent | Should -Match '# Note: \$LogFile default is now set EARLY'
        }

        It "Should have note about Set-CommonCoreLogPath being called early where duplicate used to be" {
            $ScriptContent | Should -Match '# Note: Set-CommonCoreLogPath is now called EARLY'
        }
    }

    Context "Original Functionality Preserved" {
        It "Still exits if Hyper-V is not enabled" {
            $ScriptContent | Should -Match 'if \(\$hyperVFeature\.State -ne "Enabled"\)[\s\S]*?Write-Host "Hyper-V feature is not enabled[\s\S]*?exit'
        }

        It "Still handles Windows Server differently" {
            $ScriptContent | Should -Match 'if \(\$isServer\)[\s\S]*?Get-WindowsFeature -Name Hyper-V'
        }

        It "WriteLog function calls preserved for Hyper-V state" {
            $ScriptContent | Should -Match 'WriteLog "Hyper-V feature state:'
        }
    }
}
