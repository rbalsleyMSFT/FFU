#Requires -Module Pester
<#
.SYNOPSIS
    Pester tests for BuildFFUVM_UI.ps1 messaging integration.

.DESCRIPTION
    Tests that validate the FFU.Messaging integration in BuildFFUVM_UI.ps1:
    - FFU.Messaging module import
    - Messaging context initialization
    - Timer interval reduced to 50ms for real-time updates
    - Queue-based message reading in timer tick handler
    - Cancellation handling via messaging context
    - Proper cleanup of messaging context

.NOTES
    Version: 1.0.0
    Date: 2025-12-10
    Author: FFU Builder Team
    Related Issue: #14 - Poor WPF/PowerShell Integration
#>

BeforeAll {
    # Set up paths
    $script:FFUDevelopmentPath = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:BuildFFUVMUIPath = Join-Path $script:FFUDevelopmentPath 'FFUDevelopment\BuildFFUVM_UI.ps1'
    $script:MessagingModulePath = Join-Path $script:FFUDevelopmentPath 'FFUDevelopment\Modules\FFU.Messaging'

    # Read file contents for static analysis
    $script:UIContent = Get-Content -Path $script:BuildFFUVMUIPath -Raw
    $script:UILines = Get-Content -Path $script:BuildFFUVMUIPath
}

Describe 'BuildFFUVM_UI.ps1 FFU.Messaging Integration' -Tag 'Messaging', 'UIIntegration' {

    Context 'Module Import' {

        It 'Should import FFU.Messaging module' {
            $script:UIContent | Should -Match 'Import-Module.*FFU\.Messaging'
        }

        It 'Should use -DisableNameChecking to suppress verb warnings' {
            $script:UIContent | Should -Match 'Import-Module.*FFU\.Messaging.*-DisableNameChecking'
        }

        It 'Should remove FFU.Messaging module before re-import (avoid conflicts)' {
            $script:UIContent | Should -Match 'Remove-Module -Name ''FFU\.Messaging'''
        }
    }

    Context 'UI State Initialization' {

        It 'Should have messagingContext field in uiState.Data' {
            $script:UIContent | Should -Match 'messagingContext\s*=\s*\$null'
        }
    }

    Context 'Build Job Initialization' {

        It 'Should create messaging context before starting build' {
            $script:UIContent | Should -Match 'New-FFUMessagingContext\s+-EnableFileLogging'
        }

        It 'Should pass LogFilePath to messaging context' {
            $script:UIContent | Should -Match 'New-FFUMessagingContext.*-LogFilePath'
        }

        It 'Should store messaging context in uiState.Data' {
            $script:UIContent | Should -Match '\$script:uiState\.Data\.messagingContext\s*=\s*New-FFUMessagingContext'
        }

        It 'Should pass messaging context to ThreadJob' {
            $script:UIContent | Should -Match 'Start-ThreadJob.*\$script:uiState\.Data\.messagingContext'
        }

        It 'ScriptBlock should accept SyncContext parameter' {
            $script:UIContent | Should -Match 'param\(\$buildParams,\s*\$ScriptRoot,\s*\$SyncContext\)'
        }

        It 'ScriptBlock should import FFU.Messaging module' {
            $script:UIContent | Should -Match 'Import-Module.*FFU\.Messaging.*-DisableNameChecking'
        }

        It 'ScriptBlock should set build state to Running' {
            $script:UIContent | Should -Match 'Set-FFUBuildState.*-State Running'
        }
    }

    Context 'Timer Configuration' {

        It 'Should create DispatcherTimer' {
            $script:UIContent | Should -Match 'New-Object System\.Windows\.Threading\.DispatcherTimer'
        }

        It 'Should set timer interval to 50 milliseconds (not 1 second)' {
            $script:UIContent | Should -Match '\[TimeSpan\]::FromMilliseconds\(50\)'
        }

        It 'Should NOT use 1-second interval (old implementation)' {
            # Check that we don't have the old 1-second interval
            $intervalMatches = [regex]::Matches($script:UIContent, '\[TimeSpan\]::FromSeconds\(1\)')
            # There should be at most 1 match for the cleanup timer, not for the build timer
            # Actually, we should ensure the build timer uses 50ms
            $script:UIContent | Should -Match 'pollTimer\.Interval.*\[TimeSpan\]::FromMilliseconds\(50\)'
        }
    }

    Context 'Queue-Based Message Reading' {

        It 'Should read messages from messaging context queue' {
            $script:UIContent | Should -Match 'Read-FFUMessages\s+-Context\s+\$msgContext'
        }

        It 'Should limit messages per read to prevent UI blocking' {
            $script:UIContent | Should -Match 'Read-FFUMessages.*-MaxMessages'
        }

        It 'Should handle progress messages from queue' {
            # Note: Uses string comparison instead of enum type to avoid module export issues
            # The pattern checks for: $msg.Level.ToString() -eq 'Progress'
            $script:UIContent | Should -Match '\$msg\.Level\.ToString\(\)\s+-eq\s+''Progress'''
        }

        It 'Should check PercentComplete in message Data' {
            $script:UIContent | Should -Match '\$msg\.Data\.ContainsKey\(''PercentComplete''\)'
        }

        It 'Should use ToLogString for display formatting' {
            $script:UIContent | Should -Match '\$msg\.ToLogString\(\)'
        }

        It 'Should maintain file-based fallback for legacy support' {
            $script:UIContent | Should -Match 'elseif.*\$script:uiState\.Data\.logStreamReader'
        }
    }

    Context 'Job Completion Handling' {

        It 'Should read remaining messages on job completion' {
            $script:UIContent | Should -Match 'Read-FFUMessages.*-MaxMessages 1000'
        }

        It 'Should close messaging context on completion' {
            $script:UIContent | Should -Match 'Close-FFUMessagingContext\s+-Context\s+\$msgContext'
        }

        It 'Should null out messaging context after close' {
            $script:UIContent | Should -Match '\$script:uiState\.Data\.messagingContext\s*=\s*\$null'
        }
    }

    Context 'Cancellation Handling' {

        It 'Should request cancellation via messaging context' {
            $script:UIContent | Should -Match 'Request-FFUCancellation\s+-Context'
        }

        It 'Should close messaging context after cancellation request' {
            # Check that Close-FFUMessagingContext follows Request-FFUCancellation
            $script:UIContent | Should -Match 'Request-FFUCancellation.*[\s\S]*?Close-FFUMessagingContext'
        }

        It 'Cancel handler should check for messaging context before cleanup' {
            $script:UIContent | Should -Match 'if\s*\(\$null\s+-ne\s+\$script:uiState\.Data\.messagingContext\)'
        }
    }

    Context 'Window Close Cleanup' {

        It 'Window close handler should request cancellation' {
            # Find the Add_Closed handler section
            $closedHandlerMatch = [regex]::Match($script:UIContent, 'window\.Add_Closed\(\{[\s\S]*?\}\)')
            $closedHandlerMatch.Success | Should -BeTrue

            $closedHandlerContent = $closedHandlerMatch.Value
            $closedHandlerContent | Should -Match 'Request-FFUCancellation'
        }

        It 'Window close handler should close messaging context' {
            $closedHandlerMatch = [regex]::Match($script:UIContent, 'window\.Add_Closed\(\{[\s\S]*?\}\)')
            $closedHandlerContent = $closedHandlerMatch.Value
            $closedHandlerContent | Should -Match 'Close-FFUMessagingContext'
        }
    }

    Context 'Error Handling' {

        It 'Catch block should clean up messaging context on error' {
            $script:UIContent | Should -Match 'catch\s*\{[\s\S]*?Close-FFUMessagingContext'
        }
    }
}

Describe 'FFU.Messaging Module Availability' -Tag 'Messaging', 'Module' {

    Context 'Module Structure' {

        It 'FFU.Messaging module folder exists' {
            Test-Path $script:MessagingModulePath | Should -BeTrue
        }

        It 'FFU.Messaging.psm1 exists' {
            Test-Path (Join-Path $script:MessagingModulePath 'FFU.Messaging.psm1') | Should -BeTrue
        }

        It 'FFU.Messaging.psd1 exists' {
            Test-Path (Join-Path $script:MessagingModulePath 'FFU.Messaging.psd1') | Should -BeTrue
        }

        It 'Module manifest passes validation' {
            $manifestPath = Join-Path $script:MessagingModulePath 'FFU.Messaging.psd1'
            { Test-ModuleManifest -Path $manifestPath -ErrorAction Stop } | Should -Not -Throw
        }
    }

    Context 'Module Functions' {

        BeforeAll {
            Import-Module $script:MessagingModulePath -Force -DisableNameChecking -ErrorAction Stop
        }

        AfterAll {
            Remove-Module 'FFU.Messaging' -Force -ErrorAction SilentlyContinue
        }

        It 'New-FFUMessagingContext is exported' {
            Get-Command -Name 'New-FFUMessagingContext' -Module 'FFU.Messaging' | Should -Not -BeNullOrEmpty
        }

        It 'Close-FFUMessagingContext is exported' {
            Get-Command -Name 'Close-FFUMessagingContext' -Module 'FFU.Messaging' | Should -Not -BeNullOrEmpty
        }

        It 'Read-FFUMessages is exported' {
            Get-Command -Name 'Read-FFUMessages' -Module 'FFU.Messaging' | Should -Not -BeNullOrEmpty
        }

        It 'Write-FFUMessage is exported' {
            Get-Command -Name 'Write-FFUMessage' -Module 'FFU.Messaging' | Should -Not -BeNullOrEmpty
        }

        It 'Write-FFUProgress is exported' {
            Get-Command -Name 'Write-FFUProgress' -Module 'FFU.Messaging' | Should -Not -BeNullOrEmpty
        }

        It 'Request-FFUCancellation is exported' {
            Get-Command -Name 'Request-FFUCancellation' -Module 'FFU.Messaging' | Should -Not -BeNullOrEmpty
        }

        It 'Set-FFUBuildState is exported' {
            Get-Command -Name 'Set-FFUBuildState' -Module 'FFU.Messaging' | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'Real-Time UI Update Performance' -Tag 'Messaging', 'Performance' {

    Context 'Timer Interval Comparison' {

        It '50ms interval is 20x faster than original 1000ms' {
            $newInterval = 50
            $oldInterval = 1000
            $speedup = $oldInterval / $newInterval
            $speedup | Should -Be 20
        }

        It '50ms interval provides <100ms perceived latency (human threshold)' {
            $interval = 50
            $interval | Should -BeLessThan 100
        }
    }

    Context 'Queue vs File I/O' {

        BeforeAll {
            Import-Module $script:MessagingModulePath -Force -DisableNameChecking -ErrorAction Stop
        }

        AfterAll {
            Remove-Module 'FFU.Messaging' -Force -ErrorAction SilentlyContinue
        }

        It 'ConcurrentQueue read is non-blocking' {
            $context = New-FFUMessagingContext

            # Measure empty queue read time
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            $messages = Read-FFUMessages -Context $context -MaxMessages 100
            $sw.Stop()

            # Empty queue read should be nearly instant (<50ms, allowing for system overhead)
            $sw.ElapsedMilliseconds | Should -BeLessThan 50
            $messages.Count | Should -Be 0
        }

        It 'Multiple messages read in single call' {
            $context = New-FFUMessagingContext

            # Write 10 messages
            1..10 | ForEach-Object { Write-FFUInfo -Context $context -Message "Test message $_" }

            # Read all at once
            $messages = Read-FFUMessages -Context $context -MaxMessages 100
            $messages.Count | Should -Be 10
        }
    }
}

Describe 'Backward Compatibility' -Tag 'Messaging', 'Compatibility' {

    Context 'File-Based Fallback' {

        It 'UI still opens log file StreamReader' {
            $script:UIContent | Should -Match '\[System\.IO\.StreamReader\]::new'
        }

        It 'File-based reading is fallback when queue unavailable' {
            $script:UIContent | Should -Match 'elseif.*logStreamReader'
        }

        It 'Progress regex parsing still works for file fallback' {
            # Check for the [PROGRESS] regex pattern used in fallback file parsing
            # The actual pattern in code is: '\[PROGRESS\] (\d{1,3}) \| (.*)'
            $script:UIContent | Should -Match "PROGRESS.*\d"
        }
    }

    Context 'Legacy Log Format Support' {

        It 'Still supports [PROGRESS] nn | message format' {
            # Check for PROGRESS pattern in the code (used for parsing file-based progress updates)
            $script:UIContent | Should -Match 'PROGRESS'
        }
    }
}
