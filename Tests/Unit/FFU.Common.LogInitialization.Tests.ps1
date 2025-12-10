#Requires -Modules Pester
<#
.SYNOPSIS
    Pester tests for Set-CommonCoreLogPath -Initialize functionality.

.DESCRIPTION
    Tests the log file initialization fix that ensures proper log file lifecycle
    management when starting a fresh build session.

.NOTES
    Version: 1.0.0
    Date: 2025-12-09
    Author: Claude Code

    This test suite verifies:
    - Set-CommonCoreLogPath -Initialize properly deletes existing log files
    - Set-CommonCoreLogPath -Initialize creates the log directory if needed
    - WriteLog works correctly after Set-CommonCoreLogPath -Initialize is called
    - Backward compatibility (without -Initialize, behaves as before)
#>

BeforeAll {
    # Import the FFU.Common module
    $modulePath = Join-Path $PSScriptRoot "..\..\FFUDevelopment\FFU.Common\FFU.Common.psd1"

    if (Test-Path $modulePath) {
        Import-Module $modulePath -Force -ErrorAction Stop
    }
    else {
        # Try alternate path structure
        $modulePath = Join-Path $PSScriptRoot "..\..\FFUDevelopment\FFU.Common\FFU.Common.Core.psm1"
        Import-Module $modulePath -Force -ErrorAction Stop
    }

    # Create temp directory for test log files
    $script:TestLogDir = Join-Path $env:TEMP "FFULogTests_$(Get-Random)"
    New-Item -Path $script:TestLogDir -ItemType Directory -Force | Out-Null
}

AfterAll {
    # Cleanup test directory
    if (Test-Path $script:TestLogDir) {
        Remove-Item -Path $script:TestLogDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe "Set-CommonCoreLogPath Function" -Tag "Logging", "LogInitialization" {

    BeforeEach {
        # Create a fresh test log file path for each test
        $script:TestLogFile = Join-Path $script:TestLogDir "test_$(Get-Random).log"
    }

    AfterEach {
        # Clean up test log file
        if (Test-Path $script:TestLogFile) {
            Remove-Item -Path $script:TestLogFile -Force -ErrorAction SilentlyContinue
        }
    }

    Context "Function Exists and Has Required Parameters" {
        It "Should have Set-CommonCoreLogPath function available" {
            $cmd = Get-Command Set-CommonCoreLogPath -ErrorAction SilentlyContinue
            $cmd | Should -Not -BeNullOrEmpty
        }

        It "Should have -Path parameter" {
            $cmd = Get-Command Set-CommonCoreLogPath
            $cmd.Parameters.Keys | Should -Contain 'Path'
        }

        It "Should have -Initialize switch parameter" {
            $cmd = Get-Command Set-CommonCoreLogPath
            $cmd.Parameters.Keys | Should -Contain 'Initialize'
            $cmd.Parameters['Initialize'].SwitchParameter | Should -BeTrue
        }
    }

    Context "Basic Functionality Without -Initialize" {
        It "Should set log path without error" {
            { Set-CommonCoreLogPath -Path $script:TestLogFile } | Should -Not -Throw
        }

        It "Should allow WriteLog to create log file" {
            Set-CommonCoreLogPath -Path $script:TestLogFile
            WriteLog "Test message"

            Test-Path $script:TestLogFile | Should -BeTrue
        }

        It "Should append to existing log file when -Initialize not specified" {
            # Create initial log file with content
            Set-Content -Path $script:TestLogFile -Value "Existing content"

            Set-CommonCoreLogPath -Path $script:TestLogFile
            WriteLog "New message"

            $content = Get-Content -Path $script:TestLogFile -Raw
            $content | Should -Match "Existing content"
            $content | Should -Match "New message"
        }
    }

    Context "-Initialize Parameter Functionality" {
        It "Should delete existing log file when -Initialize is specified" {
            # Create existing log file
            Set-Content -Path $script:TestLogFile -Value "Old content that should be deleted"

            Test-Path $script:TestLogFile | Should -BeTrue

            Set-CommonCoreLogPath -Path $script:TestLogFile -Initialize

            # File should exist but with new content (fresh session message)
            Test-Path $script:TestLogFile | Should -BeTrue
            $content = Get-Content -Path $script:TestLogFile -Raw
            $content | Should -Not -Match "Old content that should be deleted"
        }

        It "Should create log directory if it doesn't exist" {
            $newDir = Join-Path $script:TestLogDir "NewSubDir_$(Get-Random)"
            $newLogFile = Join-Path $newDir "test.log"

            Test-Path $newDir | Should -BeFalse

            Set-CommonCoreLogPath -Path $newLogFile -Initialize
            WriteLog "Test in new directory"

            Test-Path $newDir | Should -BeTrue
            Test-Path $newLogFile | Should -BeTrue

            # Cleanup
            Remove-Item -Path $newDir -Recurse -Force -ErrorAction SilentlyContinue
        }

        It "Should log fresh session started message" {
            Set-CommonCoreLogPath -Path $script:TestLogFile -Initialize

            $content = Get-Content -Path $script:TestLogFile -Raw
            $content | Should -Match "Fresh log session started"
        }

        It "Should work correctly when log file doesn't exist" {
            # Ensure file doesn't exist
            if (Test-Path $script:TestLogFile) {
                Remove-Item $script:TestLogFile -Force
            }

            { Set-CommonCoreLogPath -Path $script:TestLogFile -Initialize } | Should -Not -Throw

            WriteLog "First message in fresh session"

            Test-Path $script:TestLogFile | Should -BeTrue
        }
    }

    Context "WriteLog After Fresh Initialization" {
        It "Should successfully write multiple log entries after -Initialize" {
            Set-CommonCoreLogPath -Path $script:TestLogFile -Initialize

            WriteLog "Message 1"
            WriteLog "Message 2"
            WriteLog "Message 3"

            $content = Get-Content -Path $script:TestLogFile -Raw
            $content | Should -Match "Message 1"
            $content | Should -Match "Message 2"
            $content | Should -Match "Message 3"
        }

        It "Should include timestamps in log entries" {
            Set-CommonCoreLogPath -Path $script:TestLogFile -Initialize
            WriteLog "Test with timestamp"

            $content = Get-Content -Path $script:TestLogFile -Raw
            # Check for date pattern like "12/9/2025" or similar
            $content | Should -Match "\d{1,2}/\d{1,2}/\d{4}"
        }

        It "Should handle special characters in log messages" {
            Set-CommonCoreLogPath -Path $script:TestLogFile -Initialize

            WriteLog "Message with 'quotes' and `"double quotes`""
            WriteLog "Message with special chars: !@#$%^&*()"
            WriteLog "Message with path: C:\Test\Path\File.txt"

            Test-Path $script:TestLogFile | Should -BeTrue
            $lines = @(Get-Content -Path $script:TestLogFile)
            $lines.Count | Should -BeGreaterOrEqual 4  # Fresh message + 3 test messages
        }
    }

    Context "Concurrent Access Safety" {
        It "Should handle rapid successive writes" {
            Set-CommonCoreLogPath -Path $script:TestLogFile -Initialize

            1..10 | ForEach-Object {
                WriteLog "Rapid message $_"
            }

            $content = Get-Content -Path $script:TestLogFile -Raw
            $content | Should -Match "Rapid message 1"
            $content | Should -Match "Rapid message 10"
        }
    }
}

Describe "Integration: Build Script Log Initialization Pattern" -Tag "Logging", "Integration" {

    BeforeAll {
        $script:IntegrationLogDir = Join-Path $env:TEMP "FFULogIntegration_$(Get-Random)"
        New-Item -Path $script:IntegrationLogDir -ItemType Directory -Force | Out-Null
    }

    AfterAll {
        if (Test-Path $script:IntegrationLogDir) {
            Remove-Item -Path $script:IntegrationLogDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context "Simulating Build Script Initialization" {
        It "Should correctly initialize log file like BuildFFUVM.ps1 does" {
            $logFile = Join-Path $script:IntegrationLogDir "FFUDevelopment.log"

            # Simulate what BuildFFUVM.ps1 does:
            # 1. Set log path with -Initialize (deletes old, creates new)
            Set-CommonCoreLogPath -Path $logFile -Initialize

            # 2. Start logging build operations
            WriteLog "FFU build process started"
            WriteLog "Initializing build environment"
            WriteLog "Starting VM creation"

            # Verify log file exists and has content
            Test-Path $logFile | Should -BeTrue

            $content = Get-Content -Path $logFile -Raw
            $content | Should -Match "Fresh log session started"
            $content | Should -Match "FFU build process started"
            $content | Should -Match "Initializing build environment"
            $content | Should -Match "Starting VM creation"
        }

        It "Should correctly handle cleanup mode (no -Initialize)" {
            $logFile = Join-Path $script:IntegrationLogDir "FFUDevelopment_cleanup.log"

            # First, create an existing log file with build content
            Set-CommonCoreLogPath -Path $logFile -Initialize
            WriteLog "Original build started"
            WriteLog "Build completed"

            # Now simulate cleanup mode (appends to existing log)
            Set-CommonCoreLogPath -Path $logFile  # No -Initialize
            WriteLog "Cleanup operation started"
            WriteLog "Cleanup completed"

            $content = Get-Content -Path $logFile -Raw
            # Should have both original build and cleanup entries
            $content | Should -Match "Original build started"
            $content | Should -Match "Build completed"
            $content | Should -Match "Cleanup operation started"
            $content | Should -Match "Cleanup completed"
        }

        It "Should handle multiple fresh sessions (simulate multiple builds)" {
            $logFile = Join-Path $script:IntegrationLogDir "FFUDevelopment_multi.log"

            # First build
            Set-CommonCoreLogPath -Path $logFile -Initialize
            WriteLog "Build 1 started"
            WriteLog "Build 1 completed"

            # Second build (Initialize, replaces first)
            Set-CommonCoreLogPath -Path $logFile -Initialize
            WriteLog "Build 2 started"
            WriteLog "Build 2 completed"

            $content = Get-Content -Path $logFile -Raw
            # Should only have Build 2 content
            $content | Should -Not -Match "Build 1"
            $content | Should -Match "Build 2 started"
            $content | Should -Match "Build 2 completed"
        }
    }
}

Describe "Edge Cases and Error Handling" -Tag "Logging", "EdgeCases" {

    BeforeAll {
        $script:EdgeCaseLogDir = Join-Path $env:TEMP "FFULogEdgeCases_$(Get-Random)"
        New-Item -Path $script:EdgeCaseLogDir -ItemType Directory -Force | Out-Null
    }

    AfterAll {
        if (Test-Path $script:EdgeCaseLogDir) {
            Remove-Item -Path $script:EdgeCaseLogDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context "Path with Spaces" {
        It "Should handle log path with spaces" {
            $pathWithSpaces = Join-Path $script:EdgeCaseLogDir "Path With Spaces"
            New-Item -Path $pathWithSpaces -ItemType Directory -Force | Out-Null
            $logFile = Join-Path $pathWithSpaces "test log.log"

            { Set-CommonCoreLogPath -Path $logFile -Initialize } | Should -Not -Throw
            WriteLog "Test message"

            Test-Path $logFile | Should -BeTrue
        }
    }

    Context "Long Path" {
        It "Should handle reasonably long path" {
            $longSubDir = "A" * 50  # 50 character directory name
            $longPath = Join-Path $script:EdgeCaseLogDir $longSubDir
            New-Item -Path $longPath -ItemType Directory -Force | Out-Null
            $logFile = Join-Path $longPath "test.log"

            { Set-CommonCoreLogPath -Path $logFile -Initialize } | Should -Not -Throw
            WriteLog "Test message in long path"

            Test-Path $logFile | Should -BeTrue
        }
    }

    Context "Empty and Null Messages" {
        It "Should handle empty string message gracefully" {
            $logFile = Join-Path $script:EdgeCaseLogDir "empty_msg_$(Get-Random).log"
            Set-CommonCoreLogPath -Path $logFile -Initialize

            { WriteLog "" } | Should -Not -Throw
            { WriteLog $null } | Should -Not -Throw
        }
    }
}
