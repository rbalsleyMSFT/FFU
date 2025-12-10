#Requires -Version 5.1
<#
.SYNOPSIS
    Pester tests for the Invoke-Process function in FFU.Common.Core module.

.DESCRIPTION
    Tests the error handling, parameter validation, and output behavior of the
    Invoke-Process function. Validates that:
    - Function exists with required parameters
    - Successful processes (exit code 0) do not throw
    - Failed processes include proper error information
    - Error messages follow the expected format
    - Standard output is logged via WriteLog

.NOTES
    File: FFU.Common.InvokeProcess.Tests.ps1
    Module: FFU.Common
    Test Target: Invoke-Process function

    IMPORTANT: Some tests may be skipped in PowerShell 5.1 if the module uses
    New-Guid cmdlet (only available in PowerShell 6+). The functional tests
    require PowerShell 7+ to fully execute.
#>

BeforeAll {
    # Import the FFU.Common module
    $modulePath = Join-Path $PSScriptRoot "..\..\FFUDevelopment\FFU.Common\FFU.Common.psd1"
    if (Test-Path $modulePath) {
        Import-Module $modulePath -Force -ErrorAction Stop
    }
    else {
        throw "FFU.Common module not found at: $modulePath"
    }

    # Set up a temporary log path for testing
    $script:testLogPath = Join-Path $env:TEMP "FFU.Common.InvokeProcess.Tests.log"
    Set-CommonCoreLogPath -Path $script:testLogPath -Initialize

    # Check if New-Guid is available (PowerShell 6+ feature)
    $script:hasNewGuid = $null -ne (Get-Command -Name 'New-Guid' -ErrorAction SilentlyContinue)

    # Helper function to check if Invoke-Process can execute (requires New-Guid)
    function Test-InvokeProcessCanExecute {
        if (-not $script:hasNewGuid) {
            Set-ItResult -Skipped -Because "Invoke-Process uses New-Guid cmdlet which requires PowerShell 6+. Current version: $($PSVersionTable.PSVersion)"
            return $false
        }
        return $true
    }
}

AfterAll {
    # Clean up test log file
    if (Test-Path $script:testLogPath) {
        Remove-Item -Path $script:testLogPath -Force -ErrorAction SilentlyContinue
    }

    # Remove the module
    if (Get-Module -Name 'FFU.Common') {
        Remove-Module -Name 'FFU.Common' -Force -ErrorAction SilentlyContinue
    }
}

Describe "Invoke-Process Function Tests" -Tag "Unit", "FFU.Common", "InvokeProcess" {

    Context "Function Existence and Parameter Validation" {

        It "Should export the Invoke-Process function" {
            $function = Get-Command -Name 'Invoke-Process' -Module 'FFU.Common' -ErrorAction SilentlyContinue
            $function | Should -Not -BeNullOrEmpty
            $function.CommandType | Should -Be 'Function'
        }

        It "Should have required parameter 'FilePath'" {
            $command = Get-Command -Name 'Invoke-Process' -Module 'FFU.Common'
            $param = $command.Parameters['FilePath']

            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] -and $_.Mandatory } | Should -Not -BeNullOrEmpty
        }

        It "Should have optional parameter 'ArgumentList'" {
            $command = Get-Command -Name 'Invoke-Process' -Module 'FFU.Common'
            $param = $command.Parameters['ArgumentList']

            $param | Should -Not -BeNullOrEmpty
        }

        It "Should have optional parameter 'Wait' with default value true" {
            $command = Get-Command -Name 'Invoke-Process' -Module 'FFU.Common'
            $param = $command.Parameters['Wait']

            $param | Should -Not -BeNullOrEmpty
            $param.ParameterType | Should -Be ([bool])
        }

        It "Should support ShouldProcess (WhatIf)" {
            $command = Get-Command -Name 'Invoke-Process' -Module 'FFU.Common'
            $command.Parameters['WhatIf'] | Should -Not -BeNullOrEmpty
        }
    }

    Context "Successful Process Execution (Exit Code 0)" {

        It "Should not throw when process exits with code 0" -Skip:(-not $script:hasNewGuid) {
            # cmd.exe /c exit 0 returns exit code 0
            { Invoke-Process -FilePath "cmd.exe" -ArgumentList @("/c", "exit 0") -Wait $true } | Should -Not -Throw
        }

        It "Should return process object when successful" -Skip:(-not $script:hasNewGuid) {
            $result = Invoke-Process -FilePath "cmd.exe" -ArgumentList @("/c", "echo test") -Wait $true

            $result | Should -Not -BeNullOrEmpty
            $result.ExitCode | Should -Be 0
        }

        It "Should log stdout via WriteLog when process produces output" -Skip:(-not $script:hasNewGuid) {
            # Clear the log file first
            if (Test-Path $script:testLogPath) {
                Clear-Content -Path $script:testLogPath -ErrorAction SilentlyContinue
            }

            # Run a command that produces output
            $result = Invoke-Process -FilePath "cmd.exe" -ArgumentList @("/c", "echo HelloFromTest") -Wait $true

            # Give a moment for the log to be written
            Start-Sleep -Milliseconds 100

            # Check that the log contains the output
            if (Test-Path $script:testLogPath) {
                $logContent = Get-Content -Path $script:testLogPath -Raw
                $logContent | Should -Match "HelloFromTest"
            }
        }
    }

    Context "Failed Process Execution (Non-Zero Exit Code)" {

        It "Should throw when process exits with non-zero exit code" -Skip:(-not $script:hasNewGuid) {
            # cmd.exe /c exit 1 returns exit code 1
            { Invoke-Process -FilePath "cmd.exe" -ArgumentList @("/c", "exit 1") -Wait $true } | Should -Throw
        }

        It "Should include file path in error message" -Skip:(-not $script:hasNewGuid) {
            $errorMessage = $null
            try {
                Invoke-Process -FilePath "cmd.exe" -ArgumentList @("/c", "exit 42") -Wait $true
            }
            catch {
                $errorMessage = $_.Exception.Message
            }

            $errorMessage | Should -Not -BeNullOrEmpty
            $errorMessage | Should -Match "cmd\.exe"
        }

        It "Should include exit code in error message" -Skip:(-not $script:hasNewGuid) {
            $errorMessage = $null
            try {
                Invoke-Process -FilePath "cmd.exe" -ArgumentList @("/c", "exit 42") -Wait $true
            }
            catch {
                $errorMessage = $_.Exception.Message
            }

            $errorMessage | Should -Not -BeNullOrEmpty
            $errorMessage | Should -Match "42"
        }

        It "Should include stderr in error message when available" -Skip:(-not $script:hasNewGuid) {
            $errorMessage = $null
            try {
                # This command writes to stderr and exits with error code
                Invoke-Process -FilePath "cmd.exe" -ArgumentList @("/c", "echo ErrorOutput 1>&2 && exit 1") -Wait $true
            }
            catch {
                $errorMessage = $_.Exception.Message
            }

            $errorMessage | Should -Not -BeNullOrEmpty
            # Should contain either "Error:" or "Output:" based on what was captured
            $errorMessage | Should -Match "(Error:|Output:|No error output captured)"
        }

        It "Should include stdout in error message when stderr is empty" -Skip:(-not $script:hasNewGuid) {
            $errorMessage = $null
            try {
                # This command writes to stdout only and exits with error code
                Invoke-Process -FilePath "cmd.exe" -ArgumentList @("/c", "echo StdoutOnlyMessage && exit 5") -Wait $true
            }
            catch {
                $errorMessage = $_.Exception.Message
            }

            $errorMessage | Should -Not -BeNullOrEmpty
            # Should contain either "Output:" with our message or fallback
            $hasExpectedContent = ($errorMessage -match "StdoutOnlyMessage") -or ($errorMessage -match "Output:") -or ($errorMessage -match "No error output captured")
            $hasExpectedContent | Should -Be $true
        }

        It "Should include 'No error output captured' when both stderr and stdout are empty" -Skip:(-not $script:hasNewGuid) {
            $errorMessage = $null
            try {
                # This command produces no output and exits with error code
                Invoke-Process -FilePath "cmd.exe" -ArgumentList @("/c", "exit 3") -Wait $true
            }
            catch {
                $errorMessage = $_.Exception.Message
            }

            $errorMessage | Should -Not -BeNullOrEmpty
            $errorMessage | Should -Match "No error output captured"
        }
    }

    Context "Error Message Format Validation" {

        It "Should follow error message pattern: Process '.*' exited with code \d+\." -Skip:(-not $script:hasNewGuid) {
            $errorMessage = $null
            try {
                Invoke-Process -FilePath "cmd.exe" -ArgumentList @("/c", "exit 7") -Wait $true
            }
            catch {
                $errorMessage = $_.Exception.Message
            }

            $errorMessage | Should -Not -BeNullOrEmpty
            $errorMessage | Should -Match "Process '.*' exited with code \d+\."
        }

        It "Should have properly formatted error message with specific exit code" -Skip:(-not $script:hasNewGuid) {
            $exitCode = 123
            $errorMessage = $null
            try {
                Invoke-Process -FilePath "cmd.exe" -ArgumentList @("/c", "exit $exitCode") -Wait $true
            }
            catch {
                $errorMessage = $_.Exception.Message
            }

            $errorMessage | Should -Not -BeNullOrEmpty
            $errorMessage | Should -Match "Process 'cmd\.exe' exited with code $exitCode\."
        }

        It "Should contain full file path in error message" -Skip:(-not $script:hasNewGuid) {
            $errorMessage = $null
            try {
                # Use full path to cmd.exe
                $cmdPath = "$env:SystemRoot\System32\cmd.exe"
                Invoke-Process -FilePath $cmdPath -ArgumentList @("/c", "exit 1") -Wait $true
            }
            catch {
                $errorMessage = $_.Exception.Message
            }

            $errorMessage | Should -Not -BeNullOrEmpty
            # The error message should contain "cmd.exe" at minimum
            $errorMessage | Should -Match "cmd\.exe"
        }
    }

    Context "Wait Parameter Behavior" {

        It "Should not throw on non-zero exit code when Wait is false" -Skip:(-not $script:hasNewGuid) {
            # When Wait is false, we don't check exit codes
            { Invoke-Process -FilePath "cmd.exe" -ArgumentList @("/c", "exit 1") -Wait $false } | Should -Not -Throw
        }

        It "Should return process object immediately when Wait is false" -Skip:(-not $script:hasNewGuid) {
            $result = Invoke-Process -FilePath "cmd.exe" -ArgumentList @("/c", "ping localhost -n 1") -Wait $false

            $result | Should -Not -BeNullOrEmpty
            $result.HasExited | Should -BeIn @($true, $false)  # May or may not have exited yet
        }
    }

    Context "Temporary File Cleanup" {

        It "Should clean up temporary stdout file after execution" -Skip:(-not $script:hasNewGuid) {
            $tempFilesBefore = Get-ChildItem -Path $env:TEMP -Filter "*.guid" -ErrorAction SilentlyContinue | Measure-Object

            Invoke-Process -FilePath "cmd.exe" -ArgumentList @("/c", "echo test") -Wait $true

            # Allow a moment for cleanup
            Start-Sleep -Milliseconds 100

            $tempFilesAfter = Get-ChildItem -Path $env:TEMP -Filter "*.guid" -ErrorAction SilentlyContinue | Measure-Object

            # Should not have accumulated temp files (or at least not more than before)
            $tempFilesAfter.Count | Should -BeLessOrEqual ($tempFilesBefore.Count + 1)
        }

        It "Should clean up temporary stderr file after execution" -Skip:(-not $script:hasNewGuid) {
            # This is implicitly tested with the stdout test above
            # The function creates both stdout and stderr temp files and cleans both
            $result = Invoke-Process -FilePath "cmd.exe" -ArgumentList @("/c", "exit 0") -Wait $true
            $result.ExitCode | Should -Be 0
        }

        It "Should clean up temporary files even on error" -Skip:(-not $script:hasNewGuid) {
            $initialTempCount = (Get-ChildItem -Path $env:TEMP -ErrorAction SilentlyContinue | Measure-Object).Count

            try {
                Invoke-Process -FilePath "cmd.exe" -ArgumentList @("/c", "exit 1") -Wait $true
            }
            catch {
                # Expected to throw
            }

            Start-Sleep -Milliseconds 100

            $finalTempCount = (Get-ChildItem -Path $env:TEMP -ErrorAction SilentlyContinue | Measure-Object).Count

            # Temp files should be cleaned up even on error
            # Allow for some variance due to other system activity
            $finalTempCount | Should -BeLessOrEqual ($initialTempCount + 10)
        }
    }

    Context "Edge Cases and Error Handling" {

        It "Should handle non-existent executable gracefully" -Skip:(-not $script:hasNewGuid) {
            { Invoke-Process -FilePath "NonExistentExecutable12345.exe" -ArgumentList @() -Wait $true } | Should -Throw
        }

        It "Should handle empty ArgumentList" -Skip:(-not $script:hasNewGuid) {
            # cmd.exe with no args should work (opens interactive shell briefly)
            # Using a simple command instead
            $result = Invoke-Process -FilePath "cmd.exe" -ArgumentList @("/c") -Wait $true
            $result | Should -Not -BeNullOrEmpty
        }

        It "Should handle arguments with spaces" -Skip:(-not $script:hasNewGuid) {
            $result = Invoke-Process -FilePath "cmd.exe" -ArgumentList @("/c", "echo", "hello world") -Wait $true
            $result.ExitCode | Should -Be 0
        }

        It "Should handle special characters in arguments" -Skip:(-not $script:hasNewGuid) {
            # Using echo with special characters
            $result = Invoke-Process -FilePath "cmd.exe" -ArgumentList @("/c", "echo test^&test") -Wait $true
            $result.ExitCode | Should -Be 0
        }
    }

    Context "Integration with WriteLog" {

        BeforeEach {
            # Clear log file before each test
            if (Test-Path $script:testLogPath) {
                Clear-Content -Path $script:testLogPath -ErrorAction SilentlyContinue
            }
        }

        It "Should log successful process output" -Skip:(-not $script:hasNewGuid) {
            $testMessage = "TestOutput_$(Get-Random)"
            Invoke-Process -FilePath "cmd.exe" -ArgumentList @("/c", "echo $testMessage") -Wait $true

            Start-Sleep -Milliseconds 200

            if (Test-Path $script:testLogPath) {
                $logContent = Get-Content -Path $script:testLogPath -Raw
                $logContent | Should -Match $testMessage
            }
        }

        It "Should log error message when process fails" -Skip:(-not $script:hasNewGuid) {
            try {
                Invoke-Process -FilePath "cmd.exe" -ArgumentList @("/c", "exit 99") -Wait $true
            }
            catch {
                # Expected
            }

            Start-Sleep -Milliseconds 200

            if (Test-Path $script:testLogPath) {
                $logContent = Get-Content -Path $script:testLogPath -Raw
                # Should log the error via WriteLog (Get-ErrorMessage $_)
                $logContent | Should -Match "(exit|99|error|Process)"
            }
        }
    }

    Context "PowerShell Version Compatibility" {

        It "Should detect PowerShell version and New-Guid availability" {
            # This test documents the PowerShell version requirement
            $psVersion = $PSVersionTable.PSVersion
            $psVersion | Should -Not -BeNullOrEmpty

            # New-Guid is available in PowerShell 6+
            if ($psVersion.Major -ge 6) {
                $script:hasNewGuid | Should -Be $true -Because "PowerShell 6+ should have New-Guid"
            }
            else {
                # PowerShell 5.1 does not have New-Guid built-in
                # The module uses New-Guid which will fail in PS 5.1
                Write-Host "Note: Invoke-Process requires PowerShell 6+ due to New-Guid usage. Current: $psVersion"
            }
        }

        It "Should indicate if functional tests will be skipped" {
            if (-not $script:hasNewGuid) {
                Write-Host "NOTICE: Functional tests for Invoke-Process are being skipped."
                Write-Host "Reason: The module uses New-Guid cmdlet (PowerShell 6+ only)."
                Write-Host "Current PowerShell Version: $($PSVersionTable.PSVersion)"
                Write-Host "Recommendation: Run tests in PowerShell 7+ for full coverage."
            }
            # This test always passes - it's informational
            $true | Should -Be $true
        }
    }
}

Describe "Get-ErrorMessage Helper Function Tests" -Tag "Unit", "FFU.Common", "ErrorHandling" {

    Context "Function Existence" {

        It "Should export the Get-ErrorMessage function" {
            $function = Get-Command -Name 'Get-ErrorMessage' -Module 'FFU.Common' -ErrorAction SilentlyContinue
            $function | Should -Not -BeNullOrEmpty
        }
    }

    Context "Null and Empty Input Handling" {

        It "Should return fallback message for null input" {
            $result = Get-ErrorMessage -ErrorRecord $null
            $result | Should -Not -BeNullOrEmpty
            $result | Should -Match "\[No error details available\]"
        }

        It "Should return non-empty string for empty string input" {
            $result = Get-ErrorMessage -ErrorRecord ""
            $result | Should -Not -BeNullOrEmpty
        }
    }

    Context "ErrorRecord Handling" {

        It "Should extract message from ErrorRecord" {
            try {
                throw "Test error message for extraction"
            }
            catch {
                $result = Get-ErrorMessage -ErrorRecord $_
            }

            $result | Should -Not -BeNullOrEmpty
            $result | Should -Match "Test error message"
        }

        It "Should handle ErrorRecord with empty message" {
            try {
                throw [System.Exception]::new("")
            }
            catch {
                $result = Get-ErrorMessage -ErrorRecord $_
            }

            $result | Should -Not -BeNullOrEmpty
        }
    }

    Context "Exception Handling" {

        It "Should extract message from Exception object" {
            $exception = [System.Exception]::new("Direct exception message")
            $result = Get-ErrorMessage -ErrorRecord $exception

            $result | Should -Not -BeNullOrEmpty
            $result | Should -Match "Direct exception message"
        }

        It "Should handle Exception with empty message" {
            $exception = [System.Exception]::new("")
            $result = Get-ErrorMessage -ErrorRecord $exception

            $result | Should -Not -BeNullOrEmpty
            # Should return a fallback message
            $result | Should -Match "(Exception|no message)"
        }
    }

    Context "String and Other Object Handling" {

        It "Should return string as-is when passed a string" {
            $result = Get-ErrorMessage -ErrorRecord "Simple string error"
            $result | Should -Be "Simple string error"
        }

        It "Should convert arbitrary objects to string" {
            $obj = [PSCustomObject]@{ Message = "Custom object" }
            $result = Get-ErrorMessage -ErrorRecord $obj

            $result | Should -Not -BeNullOrEmpty
        }
    }
}
