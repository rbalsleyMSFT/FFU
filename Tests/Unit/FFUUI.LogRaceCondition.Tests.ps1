<#
.SYNOPSIS
    Pester tests for the Monitor Tab log race condition fix in BuildFFUVM_UI.ps1

.DESCRIPTION
    Tests the fix for the bug where the Monitor tab shows log entries from the
    previous build run when clicking the Build button. The race condition occurs when:

    1. Previous run's FFUDevelopment.log exists with old content
    2. User clicks Build -> UI starts background job
    3. UI checks: "Does log file exist?" -> YES (old file still exists)
    4. UI opens StreamReader at position 0 (beginning of old file)
    5. Background job finally starts, deletes old log, creates new log
    6. UI's StreamReader reads old content before deletion completes

    The fix deletes the old log file from the UI BEFORE starting the background job.

.NOTES
    Related to: BuildFFUVM_UI.ps1 Build button click handler
    Fix Location: Lines 610-624 (approximately)
#>

BeforeAll {
    $script:FFUDevelopmentPath = Join-Path $PSScriptRoot "..\..\..\FFUDevelopment" | Resolve-Path -ErrorAction SilentlyContinue
    if (-not $script:FFUDevelopmentPath) {
        $script:FFUDevelopmentPath = "C:\claude\FFUBuilder\FFUDevelopment"
    }
    $script:BuildFFUVM_UIPath = Join-Path $script:FFUDevelopmentPath "BuildFFUVM_UI.ps1"
}

Describe "Monitor Tab Log Race Condition Fix" {

    Context "Code Structure Validation" {

        It "BuildFFUVM_UI.ps1 exists" {
            Test-Path $script:BuildFFUVM_UIPath | Should -BeTrue
        }

        It "Contains the specific FIX comment for race condition" {
            $content = Get-Content $script:BuildFFUVM_UIPath -Raw
            # The specific fix comment we added
            $content | Should -Match 'FIX:.*Delete old log file BEFORE starting the background job to prevent race condition'
        }

        It "Contains comment explaining stale log entries prevention" {
            $content = Get-Content $script:BuildFFUVM_UIPath -Raw
            $content | Should -Match 'stale log entries.*appearing in the Monitor tab'
        }

        It "Contains Remove-Item for mainLogPath with Force" {
            $content = Get-Content $script:BuildFFUVM_UIPath -Raw
            $content | Should -Match 'Remove-Item\s+-Path\s+\$mainLogPath\s+-Force'
        }

        It "Contains log message about removing previous log file" {
            $content = Get-Content $script:BuildFFUVM_UIPath -Raw
            $content | Should -Match 'Removed previous log file to prevent race condition'
        }

        It "Contains warning message for deletion failure" {
            $content = Get-Content $script:BuildFFUVM_UIPath -Raw
            $content | Should -Match 'Warning:.*Could not remove old log file'
        }

        It "Contains 100ms delay after log file deletion" {
            $content = Get-Content $script:BuildFFUVM_UIPath -Raw
            $content | Should -Match 'Start-Sleep\s+-Milliseconds\s+100'
        }
    }

    Context "Fix Location Validation" {

        It "Log deletion fix appears after script block definition" {
            $content = Get-Content $script:BuildFFUVM_UIPath -Raw

            # Find the script block definition for the build job
            $scriptBlockMatch = [regex]::Match($content, '\$scriptBlock\s*=\s*\{\s*param\(\$buildParams,\s*\$PSScriptRoot\)')

            # Find the FIX comment
            $fixMatch = [regex]::Match($content, 'FIX:.*Delete old log file BEFORE starting')

            $scriptBlockMatch.Success | Should -BeTrue -Because "Script block definition should exist"
            $fixMatch.Success | Should -BeTrue -Because "FIX comment should exist"

            # Fix should come after script block definition
            $fixMatch.Index | Should -BeGreaterThan $scriptBlockMatch.Index -Because "Fix should come after script block is defined"
        }

        It "Log deletion fix appears before Start-ThreadJob" {
            $content = Get-Content $script:BuildFFUVM_UIPath -Raw

            # Find the FIX comment
            $fixMatch = [regex]::Match($content, 'FIX:.*Delete old log file BEFORE starting')

            # Find the first Start-ThreadJob after the fix (the one that starts the build job)
            # We need to find the one with "Build job started using ThreadJob"
            $buildJobMatch = [regex]::Match($content, 'Build job started using ThreadJob')

            $fixMatch.Success | Should -BeTrue -Because "FIX comment should exist"
            $buildJobMatch.Success | Should -BeTrue -Because "Build job start message should exist"

            # Fix should come before the build job starts
            $fixMatch.Index | Should -BeLessThan $buildJobMatch.Index -Because "Fix should be applied before build job starts"
        }
    }

    Context "StreamReader Cleanup Before Build" {

        It "Contains StreamReader cleanup code for previous builds" {
            $content = Get-Content $script:BuildFFUVM_UIPath -Raw
            # Should have code to close StreamReader from previous builds
            $content | Should -Match 'Close any existing StreamReader from previous builds'
        }

        It "StreamReader cleanup has try-catch error handling" {
            $content = Get-Content $script:BuildFFUVM_UIPath -Raw
            # The cleanup should have error handling
            $content | Should -Match 'try\s*\{[\s\S]*?logStreamReader\.Close\(\)[\s\S]*?\}\s*catch'
        }

        It "StreamReader is set to null after disposal" {
            $content = Get-Content $script:BuildFFUVM_UIPath -Raw
            # After cleanup, should set to null
            $content | Should -Match 'Ignore errors when closing stale reader[\s\S]*?logStreamReader\s*=\s*\$null'
        }
    }

    Context "Log Data Collection Cleared" {

        It "logData.Clear() is called before build starts" {
            $content = Get-Content $script:BuildFFUVM_UIPath -Raw
            $content | Should -Match 'Clear previous log data and reset autoscroll[\s\S]*?logData\.Clear\(\)'
        }

        It "autoScrollLog is reset with log data clear" {
            $content = Get-Content $script:BuildFFUVM_UIPath -Raw
            $content | Should -Match 'logData\.Clear\(\)[\s\S]*?autoScrollLog\s*=\s*\$true'
        }
    }

    Context "Error Handling in Fix" {

        It "Log deletion uses try-catch" {
            $content = Get-Content $script:BuildFFUVM_UIPath -Raw
            # Find the specific try-catch around our Remove-Item
            $content | Should -Match 'try\s*\{[\s\S]*?Remove-Item\s+-Path\s+\$mainLogPath\s+-Force\s+-ErrorAction\s+Stop[\s\S]*?\}\s*catch'
        }

        It "Catch block logs warning but does not throw" {
            $content = Get-Content $script:BuildFFUVM_UIPath -Raw
            # Extract section around "Could not remove old log file"
            $pattern = 'catch\s*\{[^}]*Could not remove old log file[^}]*\}'
            $catchMatch = [regex]::Match($content, $pattern)

            $catchMatch.Success | Should -BeTrue -Because "Catch block with warning should exist"

            # The catch block should NOT contain 'throw' or 'return'
            $catchContent = $catchMatch.Value
            $catchContent | Should -Not -Match '\bthrow\b' -Because "Should not throw on deletion failure"
            $catchContent | Should -Not -Match '\breturn\b' -Because "Should not return on deletion failure"
        }
    }
}

Describe "Functional Simulation Tests" {

    BeforeAll {
        $script:TestLogPath = Join-Path $env:TEMP "FFUUI_RaceCondition_Test.log"
    }

    AfterEach {
        if (Test-Path $script:TestLogPath) {
            Remove-Item $script:TestLogPath -Force -ErrorAction SilentlyContinue
        }
    }

    Context "Log file deletion behavior" {

        It "Can delete existing log file" {
            # Create a test log file
            "Old log content from previous build" | Set-Content $script:TestLogPath

            Test-Path $script:TestLogPath | Should -BeTrue

            # Delete it (simulating the fix)
            Remove-Item -Path $script:TestLogPath -Force

            Test-Path $script:TestLogPath | Should -BeFalse
        }

        It "Deletion is idempotent (no error if file doesn't exist)" {
            # Ensure file doesn't exist
            if (Test-Path $script:TestLogPath) {
                Remove-Item $script:TestLogPath -Force
            }

            # This should not throw
            {
                if (Test-Path $script:TestLogPath) {
                    Remove-Item -Path $script:TestLogPath -Force -ErrorAction Stop
                }
            } | Should -Not -Throw
        }

        It "StreamReader can be properly closed and file deleted" {
            # Create test file
            "Test content line 1`nTest content line 2" | Set-Content $script:TestLogPath

            # Open with StreamReader (simulating UI behavior)
            $fileStream = [System.IO.File]::Open($script:TestLogPath, 'Open', 'Read', 'ReadWrite')
            $reader = [System.IO.StreamReader]::new($fileStream)

            # Read some content
            $line = $reader.ReadLine()
            $line | Should -Be "Test content line 1"

            # Close reader (part of the fix)
            $reader.Close()
            $reader.Dispose()

            # Now file should be deletable
            { Remove-Item -Path $script:TestLogPath -Force -ErrorAction Stop } | Should -Not -Throw

            Test-Path $script:TestLogPath | Should -BeFalse
        }

        It "File cannot be deleted while StreamReader is open with exclusive lock" {
            # Create test file
            "Test content" | Set-Content $script:TestLogPath

            # Open with exclusive read (simulating a locked file scenario)
            $fileStream = [System.IO.File]::Open($script:TestLogPath, 'Open', 'Read', 'Read')
            $reader = [System.IO.StreamReader]::new($fileStream)

            try {
                # This should fail because file is locked
                { Remove-Item -Path $script:TestLogPath -Force -ErrorAction Stop } | Should -Throw
            }
            finally {
                $reader.Close()
                $reader.Dispose()

                # Clean up
                if (Test-Path $script:TestLogPath) {
                    Remove-Item $script:TestLogPath -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }

    Context "Race condition prevention" {

        It "New file is empty after deletion and recreation" {
            # Simulate old log with content
            "=== Previous Build Log ===`nOld entry 1`nOld entry 2`n[PROGRESS] 50 | Old status" | Set-Content $script:TestLogPath

            # Get old content size
            $oldSize = (Get-Item $script:TestLogPath).Length
            $oldSize | Should -BeGreaterThan 0

            # Delete (simulating fix)
            Remove-Item -Path $script:TestLogPath -Force

            # Wait (simulating the 100ms delay in the fix)
            Start-Sleep -Milliseconds 100

            # Create new file (simulating background job)
            "" | Set-Content $script:TestLogPath

            # New file should be empty (or very small due to BOM)
            $newSize = (Get-Item $script:TestLogPath).Length
            $newSize | Should -BeLessThan $oldSize
        }

        It "StreamReader position is at beginning for new file" {
            # Create fresh log file
            "First line of new build" | Set-Content $script:TestLogPath

            # Open StreamReader at position 0 (default)
            $fileStream = [System.IO.File]::Open($script:TestLogPath, 'Open', 'Read', 'ReadWrite')
            $reader = [System.IO.StreamReader]::new($fileStream)

            try {
                # First read should get the first line
                $line = $reader.ReadLine()
                $line | Should -Be "First line of new build"
            }
            finally {
                $reader.Close()
                $reader.Dispose()
            }
        }
    }
}

Describe "Integration Scenario" {

    Context "Complete fix workflow simulation" {

        BeforeAll {
            $script:TestLogPath = Join-Path $env:TEMP "FFUUI_Integration_Test.log"
        }

        AfterAll {
            if (Test-Path $script:TestLogPath) {
                Remove-Item $script:TestLogPath -Force -ErrorAction SilentlyContinue
            }
        }

        It "Simulates the complete fix workflow without race condition" {
            # Step 1: Simulate previous build left a log file
            "=== Previous Build ===`n[PROGRESS] 100 | Build completed`nOld entry that should not appear" | Set-Content $script:TestLogPath
            $oldContent = Get-Content $script:TestLogPath -Raw

            # Step 2: Simulate UI cleanup (StreamReader from previous run)
            # In real scenario, there would be an existing StreamReader
            # For test, just verify file exists
            Test-Path $script:TestLogPath | Should -BeTrue

            # Step 3: Simulate the fix - delete old log file
            if (Test-Path $script:TestLogPath) {
                Remove-Item -Path $script:TestLogPath -Force -ErrorAction Stop
                Start-Sleep -Milliseconds 100
            }

            # Step 4: Verify old file is gone
            Test-Path $script:TestLogPath | Should -BeFalse

            # Step 5: Simulate background job creating new log
            "=== New Build ===" | Set-Content $script:TestLogPath
            Start-Sleep -Milliseconds 50
            Add-Content $script:TestLogPath "[PROGRESS] 0 | Starting new build"

            # Step 6: Simulate UI opening new StreamReader
            $fileStream = [System.IO.File]::Open($script:TestLogPath, 'Open', 'Read', 'ReadWrite')
            $reader = [System.IO.StreamReader]::new($fileStream)

            try {
                # Step 7: Verify we only see new content, not old
                $firstLine = $reader.ReadLine()
                $firstLine | Should -Be "=== New Build ===" -Because "First line should be from new build, not old"

                $secondLine = $reader.ReadLine()
                $secondLine | Should -Match "Starting new build" -Because "Second line should be from new build"

                # Verify old content is NOT present
                $allContent = Get-Content $script:TestLogPath -Raw
                $allContent | Should -Not -Match "Previous Build" -Because "Old content should not be present"
                $allContent | Should -Not -Match "Old entry that should not appear"
            }
            finally {
                $reader.Close()
                $reader.Dispose()
            }
        }
    }
}
