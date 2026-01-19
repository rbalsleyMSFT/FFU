#Requires -Modules Pester
<#
.SYNOPSIS
    Integration tests for FFU build cancellation flow.

.DESCRIPTION
    Tests the complete cancellation mechanism including:
    - Messaging context creation and cancellation support
    - Cancellation request and detection via Test-BuildCancellation
    - Cleanup registry integration with cancellation
    - Build state transitions during cancellation
    - Message queue behavior during cancellation

.NOTES
    These tests require FFU.Messaging and FFU.Core modules.
    Tests use proper messaging context mocks for isolation.
#>

BeforeAll {
    # Import required modules
    $modulesPath = "$PSScriptRoot/../../FFUDevelopment/Modules"

    # Ensure module path is in PSModulePath for dependency resolution
    if ($env:PSModulePath -notlike "*$modulesPath*") {
        $env:PSModulePath = "$modulesPath;$env:PSModulePath"
    }

    # Import modules in dependency order
    Import-Module "$modulesPath/FFU.Messaging/FFU.Messaging.psd1" -Force -ErrorAction Stop
    Import-Module "$modulesPath/FFU.Core/FFU.Core.psd1" -Force -ErrorAction Stop

    # Create global WriteLog stub for FFU.Core functions that need it
    if (-not (Get-Command WriteLog -ErrorAction SilentlyContinue)) {
        function global:WriteLog { param([string]$Message) Write-Verbose $Message }
    }
}

AfterAll {
    # Clean up WriteLog stub
    Remove-Item Function:\WriteLog -ErrorAction SilentlyContinue
}

Describe 'Cancellation Flow Integration' {

    Context 'Messaging Context Lifecycle' {
        It 'Creates messaging context with cancellation support' {
            $ctx = New-FFUMessagingContext
            $ctx | Should -Not -BeNullOrEmpty
            $ctx.CancellationRequested | Should -Be $false
            $ctx.BuildState | Should -Be 'NotStarted'
        }

        It 'Messaging context contains required cancellation keys' {
            $ctx = New-FFUMessagingContext
            $ctx.ContainsKey('CancellationRequested') | Should -Be $true
            $ctx.ContainsKey('BuildState') | Should -Be $true
            $ctx.ContainsKey('MessageQueue') | Should -Be $true
        }

        It 'Request-FFUCancellation sets cancellation flag' {
            $ctx = New-FFUMessagingContext
            Request-FFUCancellation -Context $ctx
            $ctx.CancellationRequested | Should -Be $true
        }

        It 'Request-FFUCancellation sets state to Cancelling' {
            $ctx = New-FFUMessagingContext
            Request-FFUCancellation -Context $ctx
            $ctx.BuildState | Should -Be 'Cancelling'
        }

        It 'Test-FFUCancellationRequested returns correct status' {
            $ctx = New-FFUMessagingContext
            Test-FFUCancellationRequested -Context $ctx | Should -Be $false

            Request-FFUCancellation -Context $ctx
            Test-FFUCancellationRequested -Context $ctx | Should -Be $true
        }
    }

    Context 'Test-BuildCancellation Behavior' {
        BeforeEach {
            # Clear cleanup registry before each test to ensure isolation
            InModuleScope FFU.Core {
                $script:CleanupRegistry.Clear()
            }
        }

        It 'Returns false when context is null (CLI mode)' {
            $result = Test-BuildCancellation -MessagingContext $null -PhaseName "Test"
            $result | Should -Be $false
        }

        It 'Returns false when cancellation not requested' {
            $ctx = New-FFUMessagingContext
            $result = Test-BuildCancellation -MessagingContext $ctx -PhaseName "Test"
            $result | Should -Be $false
        }

        It 'Returns true when cancellation is requested' {
            $ctx = New-FFUMessagingContext
            Request-FFUCancellation -Context $ctx
            $result = Test-BuildCancellation -MessagingContext $ctx -PhaseName "Test"
            $result | Should -Be $true
        }

        It 'With -InvokeCleanup switch sets state to Cancelled' {
            $ctx = New-FFUMessagingContext
            Request-FFUCancellation -Context $ctx
            Test-BuildCancellation -MessagingContext $ctx -PhaseName "Test" -InvokeCleanup
            $ctx.BuildState | Should -Be 'Cancelled'
        }

        It 'Without -InvokeCleanup switch preserves Cancelling state' {
            $ctx = New-FFUMessagingContext
            Request-FFUCancellation -Context $ctx
            $ctx.BuildState | Should -Be 'Cancelling'

            Test-BuildCancellation -MessagingContext $ctx -PhaseName "Test"
            $ctx.BuildState | Should -Be 'Cancelling' -Because 'State should not change to Cancelled without -InvokeCleanup'
        }

        It 'Returns false immediately for CLI mode without logging errors' {
            # This should not throw or log errors
            { Test-BuildCancellation -MessagingContext $null -PhaseName "CLI Test" } | Should -Not -Throw
        }
    }

    Context 'Cleanup Registry Integration' {
        BeforeEach {
            # Clear cleanup registry before each test
            Clear-CleanupRegistry
        }

        AfterEach {
            # Ensure cleanup after each test
            Clear-CleanupRegistry
        }

        It 'Register-CleanupAction adds action to registry' {
            Register-CleanupAction -Name "Test Cleanup" -ResourceType "Other" -Action { $true }

            $registry = Get-CleanupRegistry
            $registry.Count | Should -Be 1
            $registry[0].Name | Should -Be "Test Cleanup"
        }

        It 'Multiple cleanup actions can be registered' {
            Register-CleanupAction -Name "First" -ResourceType "Other" -Action { 1 }
            Register-CleanupAction -Name "Second" -ResourceType "Other" -Action { 2 }
            Register-CleanupAction -Name "Third" -ResourceType "Other" -Action { 3 }

            $registry = Get-CleanupRegistry
            $registry.Count | Should -Be 3
        }

        It 'Clear-CleanupRegistry removes all actions without invoking them' {
            $script:actionInvoked = $false
            Register-CleanupAction -Name "Test" -ResourceType "Other" -Action {
                $script:actionInvoked = $true
            }

            (Get-CleanupRegistry).Count | Should -Be 1

            Clear-CleanupRegistry

            (Get-CleanupRegistry).Count | Should -Be 0
            $script:actionInvoked | Should -Be $false -Because 'Clear should not invoke actions'
        }

        It 'Invoke-FailureCleanup processes all registered actions' {
            Register-CleanupAction -Name "Action1" -ResourceType "Other" -Action { $true }
            Register-CleanupAction -Name "Action2" -ResourceType "Other" -Action { $true }

            (Get-CleanupRegistry).Count | Should -Be 2

            Invoke-FailureCleanup -Reason "Test cleanup"

            # After invocation, registry should be empty (actions are removed after processing)
            (Get-CleanupRegistry).Count | Should -Be 0
        }

        It 'Invoke-FailureCleanup continues on individual action failure' {
            $script:secondActionRan = $false

            Register-CleanupAction -Name "FailingAction" -ResourceType "Other" -Action {
                throw "Simulated failure"
            }
            Register-CleanupAction -Name "SuccessAction" -ResourceType "Other" -Action {
                $script:secondActionRan = $true
            }

            # Should not throw despite the failing action
            { Invoke-FailureCleanup -Reason "Error handling test" } | Should -Not -Throw

            # By design: Failed actions remain in registry for manual intervention
            # Only successful actions are removed
            (Get-CleanupRegistry).Count | Should -Be 1 -Because 'Failed cleanups remain in registry for manual review'
        }
    }

    Context 'State Transitions' {
        It 'Build state starts as NotStarted' {
            $ctx = New-FFUMessagingContext
            $ctx.BuildState | Should -Be 'NotStarted'
        }

        It 'Set-FFUBuildState changes state correctly' {
            $ctx = New-FFUMessagingContext
            Set-FFUBuildState -Context $ctx -State Running
            $ctx.BuildState | Should -Be 'Running'
        }

        It 'Full cancellation flow transitions: NotStarted -> Running -> Cancelling -> Cancelled' {
            $ctx = New-FFUMessagingContext

            # Initial state
            $ctx.BuildState | Should -Be 'NotStarted'

            # Simulate build start
            Set-FFUBuildState -Context $ctx -State Running
            $ctx.BuildState | Should -Be 'Running'

            # User requests cancellation
            Request-FFUCancellation -Context $ctx
            $ctx.BuildState | Should -Be 'Cancelling'

            # Build completes cancellation
            Set-FFUBuildState -Context $ctx -State Cancelled
            $ctx.BuildState | Should -Be 'Cancelled'
        }

        It 'Full success flow transitions: NotStarted -> Running -> Completed' {
            $ctx = New-FFUMessagingContext

            $ctx.BuildState | Should -Be 'NotStarted'

            Set-FFUBuildState -Context $ctx -State Running
            $ctx.BuildState | Should -Be 'Running'

            Set-FFUBuildState -Context $ctx -State Completed
            $ctx.BuildState | Should -Be 'Completed'
        }
    }

    Context 'Message Queue During Cancellation' {
        It 'Request-FFUCancellation enqueues cancellation message' {
            $ctx = New-FFUMessagingContext

            Request-FFUCancellation -Context $ctx

            # Read messages from queue
            $messages = @()
            $msg = $null
            while ($ctx.MessageQueue.TryDequeue([ref]$msg)) {
                $messages += $msg
            }

            $messages.Count | Should -BeGreaterOrEqual 1
        }

        It 'Cancellation messages contain relevant information' {
            $ctx = New-FFUMessagingContext

            Request-FFUCancellation -Context $ctx

            # Read messages
            $messages = @()
            $msg = $null
            while ($ctx.MessageQueue.TryDequeue([ref]$msg)) {
                $messages += $msg
            }

            # At least one message should mention cancellation or state change
            $cancellationRelated = $messages | Where-Object {
                $_.Message -match 'Cancel|Cancelling' -or
                ($_.Data -and $_.Data.ContainsKey('State'))
            }
            $cancellationRelated | Should -Not -BeNullOrEmpty
        }
    }

    Context 'End-to-End Cancellation Scenario' {
        BeforeEach {
            Clear-CleanupRegistry
        }

        AfterEach {
            Clear-CleanupRegistry
        }

        It 'Simulates full cancellation flow with cleanup' {
            # Create context and start "build"
            $ctx = New-FFUMessagingContext
            Set-FFUBuildState -Context $ctx -State Running

            # Register some cleanup actions (simulating resource creation)
            $script:vmCleaned = $false
            $script:vhdxCleaned = $false

            Register-CleanupAction -Name "VM Cleanup" -ResourceType "VM" -Action {
                $script:vmCleaned = $true
            }
            Register-CleanupAction -Name "VHDX Cleanup" -ResourceType "VHDX" -Action {
                $script:vhdxCleaned = $true
            }

            # Verify resources are registered
            (Get-CleanupRegistry).Count | Should -Be 2

            # User cancels build
            Request-FFUCancellation -Context $ctx
            $ctx.CancellationRequested | Should -Be $true
            $ctx.BuildState | Should -Be 'Cancelling'

            # Build detects cancellation at checkpoint and invokes cleanup
            $cancelled = Test-BuildCancellation -MessagingContext $ctx -PhaseName "Test Phase" -InvokeCleanup

            # Verify results
            $cancelled | Should -Be $true
            $ctx.BuildState | Should -Be 'Cancelled'
            (Get-CleanupRegistry).Count | Should -Be 0
        }

        It 'Normal completion clears cleanup registry' {
            $ctx = New-FFUMessagingContext
            Set-FFUBuildState -Context $ctx -State Running

            # Register cleanup actions
            Register-CleanupAction -Name "Test Resource" -ResourceType "Other" -Action { $true }
            (Get-CleanupRegistry).Count | Should -Be 1

            # Build completes normally - cleanup registry should be cleared
            Clear-CleanupRegistry
            Set-FFUBuildState -Context $ctx -State Completed

            (Get-CleanupRegistry).Count | Should -Be 0
            $ctx.BuildState | Should -Be 'Completed'
        }
    }

    Context 'Edge Cases' {
        BeforeEach {
            Clear-CleanupRegistry
        }

        It 'Double cancellation request is handled gracefully' {
            $ctx = New-FFUMessagingContext

            Request-FFUCancellation -Context $ctx
            $ctx.CancellationRequested | Should -Be $true

            # Second request should not throw
            { Request-FFUCancellation -Context $ctx } | Should -Not -Throw
            $ctx.CancellationRequested | Should -Be $true
        }

        It 'Test-BuildCancellation validates PhaseName parameter' {
            $ctx = New-FFUMessagingContext
            Request-FFUCancellation -Context $ctx

            # Empty phase name should fail parameter validation (PhaseName is Mandatory, no empty strings)
            { Test-BuildCancellation -MessagingContext $ctx -PhaseName "" } | Should -Throw -Because 'Empty PhaseName should be rejected by parameter validation'
        }

        It 'Cancellation check with non-requested context returns false' {
            $ctx = New-FFUMessagingContext
            $ctx.CancellationRequested = $false  # Explicitly set

            for ($i = 1; $i -le 5; $i++) {
                $result = Test-BuildCancellation -MessagingContext $ctx -PhaseName "Phase $i"
                $result | Should -Be $false
            }
        }
    }
}
