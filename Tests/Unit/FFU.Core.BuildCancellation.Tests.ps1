#Requires -Module Pester
<#
.SYNOPSIS
    Unit tests for Test-BuildCancellation function in FFU.Core module.

.DESCRIPTION
    Tests the cancellation helper function that checks for user cancellation requests
    at build phase boundaries and optionally invokes cleanup.

.NOTES
    Module: FFU.Core
    Function: Test-BuildCancellation
    Plan: 07-01
#>

BeforeAll {
    # Set up module path
    $script:ModulePath = Join-Path $PSScriptRoot "..\..\FFUDevelopment\Modules"
    $env:PSModulePath = "$script:ModulePath;$env:PSModulePath"

    # Create WriteLog stub before module imports
    function global:WriteLog {
        param([string]$Message)
        # Stub for testing - do nothing
    }

    # Import required modules
    Import-Module FFU.Constants -Force -ErrorAction Stop
    Import-Module FFU.Messaging -Force -ErrorAction Stop
    Import-Module FFU.Core -Force -ErrorAction Stop

    # Track log messages for verification
    $script:LogMessages = [System.Collections.Generic.List[string]]::new()
}

AfterAll {
    # Clean up
    Remove-Item -Path Function:\WriteLog -ErrorAction SilentlyContinue
}

Describe 'Test-BuildCancellation' {
    BeforeEach {
        # Reset log messages before each test
        $script:LogMessages.Clear()

        # Mock WriteLog to capture messages
        Mock WriteLog {
            param([string]$Message)
            $script:LogMessages.Add($Message)
        } -ModuleName FFU.Core
    }

    Context 'When MessagingContext is null (CLI mode)' {
        It 'Returns false without checking cancellation' {
            $result = Test-BuildCancellation -MessagingContext $null -PhaseName "Test Phase"
            $result | Should -Be $false
        }

        It 'Does not log any messages' {
            Test-BuildCancellation -MessagingContext $null -PhaseName "Test Phase"
            $script:LogMessages.Count | Should -Be 0
        }

        It 'Does not call Invoke-FailureCleanup even with -InvokeCleanup' {
            Mock Invoke-FailureCleanup {} -ModuleName FFU.Core

            Test-BuildCancellation -MessagingContext $null -PhaseName "Test Phase" -InvokeCleanup

            Should -Invoke Invoke-FailureCleanup -Times 0 -ModuleName FFU.Core
        }
    }

    Context 'When cancellation is not requested' {
        BeforeEach {
            # Create a mock messaging context with CancellationRequested = $false
            $script:MockContext = @{
                CancellationRequested = $false
                BuildState = 'Running'
            }

            # Mock Test-FFUCancellationRequested to return false
            Mock Test-FFUCancellationRequested {
                return $false
            } -ModuleName FFU.Core
        }

        It 'Returns false' {
            $result = Test-BuildCancellation -MessagingContext $script:MockContext -PhaseName "Driver Download"
            $result | Should -Be $false
        }

        It 'Does not log cancellation message' {
            Test-BuildCancellation -MessagingContext $script:MockContext -PhaseName "Driver Download"

            $script:LogMessages | Should -Not -Contain "Cancellation detected at phase: Driver Download"
        }

        It 'Does not call Invoke-FailureCleanup' {
            Mock Invoke-FailureCleanup {} -ModuleName FFU.Core

            Test-BuildCancellation -MessagingContext $script:MockContext -PhaseName "Driver Download" -InvokeCleanup

            Should -Invoke Invoke-FailureCleanup -Times 0 -ModuleName FFU.Core
        }

        It 'Does not change build state' {
            # Mock Set-FFUBuildState in FFU.Messaging module where it's defined
            Mock Set-FFUBuildState {} -ModuleName FFU.Messaging

            Test-BuildCancellation -MessagingContext $script:MockContext -PhaseName "Driver Download" -InvokeCleanup

            # No call expected because cancellation was NOT requested
            Should -Invoke Set-FFUBuildState -Times 0 -ModuleName FFU.Messaging
        }
    }

    Context 'When cancellation is requested' {
        BeforeEach {
            # Create a proper mock messaging context with required properties
            # MessageQueue must exist with TryDequeue method for Write-FFUMessage
            $mockQueue = [System.Collections.Concurrent.ConcurrentQueue[object]]::new()
            $script:MockContext = [hashtable]::Synchronized(@{
                CancellationRequested = $true
                BuildState = 'Running'
                MessageQueue = $mockQueue
                StartTime = [datetime]::UtcNow
                EndTime = $null
            })

            # Mock Test-FFUCancellationRequested to return true
            Mock Test-FFUCancellationRequested {
                return $true
            } -ModuleName FFU.Core
        }

        It 'Returns true' {
            $result = Test-BuildCancellation -MessagingContext $script:MockContext -PhaseName "VHDX Creation"
            $result | Should -Be $true
        }

        It 'Logs cancellation detected message' {
            Test-BuildCancellation -MessagingContext $script:MockContext -PhaseName "VHDX Creation"

            $script:LogMessages | Should -Contain "Cancellation detected at phase: VHDX Creation"
        }

        It 'Sends warning to UI via Write-FFUWarning' {
            Test-BuildCancellation -MessagingContext $script:MockContext -PhaseName "VHDX Creation"

            # Verify a message was enqueued to the context's MessageQueue
            $script:MockContext.MessageQueue.Count | Should -BeGreaterThan 0
        }

        Context 'Without -InvokeCleanup switch' {
            It 'Does not call Invoke-FailureCleanup' {
                Mock Invoke-FailureCleanup {} -ModuleName FFU.Core

                Test-BuildCancellation -MessagingContext $script:MockContext -PhaseName "VHDX Creation"

                Should -Invoke Invoke-FailureCleanup -Times 0 -ModuleName FFU.Core
            }

            It 'Does not set build state to Cancelled' {
                $originalState = $script:MockContext.BuildState
                Test-BuildCancellation -MessagingContext $script:MockContext -PhaseName "VHDX Creation"

                # Without -InvokeCleanup, build state should remain unchanged
                $script:MockContext.BuildState | Should -Be $originalState
            }
        }

        Context 'With -InvokeCleanup switch' {
            BeforeEach {
                Mock Invoke-FailureCleanup {} -ModuleName FFU.Core
            }

            It 'Calls Invoke-FailureCleanup with correct reason' {
                Test-BuildCancellation -MessagingContext $script:MockContext -PhaseName "FFU Capture" -InvokeCleanup

                Should -Invoke Invoke-FailureCleanup -Times 1 -ModuleName FFU.Core -ParameterFilter {
                    $Reason -eq "User cancelled build at: FFU Capture"
                }
            }

            It 'Sets build state to Cancelled' {
                Test-BuildCancellation -MessagingContext $script:MockContext -PhaseName "FFU Capture" -InvokeCleanup

                # Verify build state was set to Cancelled
                $script:MockContext.BuildState | Should -Be 'Cancelled'
            }

            It 'Returns true after cleanup' {
                $result = Test-BuildCancellation -MessagingContext $script:MockContext -PhaseName "FFU Capture" -InvokeCleanup
                $result | Should -Be $true
            }
        }
    }

    Context 'Phase name handling' {
        BeforeEach {
            # Create a proper mock messaging context
            $mockQueue = [System.Collections.Concurrent.ConcurrentQueue[object]]::new()
            $script:MockContext = [hashtable]::Synchronized(@{
                CancellationRequested = $true
                BuildState = 'Running'
                MessageQueue = $mockQueue
                StartTime = [datetime]::UtcNow
                EndTime = $null
            })

            Mock Test-FFUCancellationRequested { return $true } -ModuleName FFU.Core
            Mock Invoke-FailureCleanup {} -ModuleName FFU.Core
        }

        It 'Includes phase name in log message' {
            Test-BuildCancellation -MessagingContext $script:MockContext -PhaseName "Driver Download Phase"

            $script:LogMessages | Should -Contain "Cancellation detected at phase: Driver Download Phase"
        }

        It 'Includes phase name in cleanup reason' {
            Test-BuildCancellation -MessagingContext $script:MockContext -PhaseName "VM Creation" -InvokeCleanup

            Should -Invoke Invoke-FailureCleanup -Times 1 -ModuleName FFU.Core -ParameterFilter {
                $Reason -like "*VM Creation*"
            }
        }

        It 'Includes phase name in UI warning message' {
            Test-BuildCancellation -MessagingContext $script:MockContext -PhaseName "Pre-flight Validation"

            # Verify message was enqueued and contains the phase name
            $script:MockContext.MessageQueue.Count | Should -BeGreaterThan 0
            $message = $null
            $script:MockContext.MessageQueue.TryDequeue([ref]$message) | Should -Be $true
            $message.Message | Should -BeLike "*Pre-flight Validation*"
        }
    }

    Context 'Parameter validation' {
        It 'Requires PhaseName parameter' {
            { Test-BuildCancellation -MessagingContext $null } | Should -Throw
        }

        It 'Accepts hashtable for MessagingContext' {
            $context = @{ CancellationRequested = $false }
            Mock Test-FFUCancellationRequested { return $false } -ModuleName FFU.Core

            { Test-BuildCancellation -MessagingContext $context -PhaseName "Test" } | Should -Not -Throw
        }
    }

    Context 'Edge cases' {
        It 'Rejects empty phase name (mandatory parameter validation)' {
            # PowerShell mandatory string parameters reject empty strings by default
            { Test-BuildCancellation -MessagingContext @{} -PhaseName "" } | Should -Throw
        }

        It 'Handles empty hashtable context' {
            Mock Test-FFUCancellationRequested { return $false } -ModuleName FFU.Core

            $result = Test-BuildCancellation -MessagingContext @{} -PhaseName "Test"
            $result | Should -Be $false
        }

        It 'Handles context with extra properties' {
            $context = @{
                CancellationRequested = $false
                ExtraProperty = "value"
                AnotherProperty = 123
            }
            Mock Test-FFUCancellationRequested { return $false } -ModuleName FFU.Core

            $result = Test-BuildCancellation -MessagingContext $context -PhaseName "Test"
            $result | Should -Be $false
        }
    }
}
