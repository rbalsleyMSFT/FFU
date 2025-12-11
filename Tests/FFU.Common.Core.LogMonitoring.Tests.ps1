#Requires -Version 7.0
#Requires -Modules Pester

<#
.SYNOPSIS
    Tests for WriteLog messaging queue integration in FFU.Common.Core module.

.DESCRIPTION
    Validates the log monitoring fix that enables WriteLog to write messages
    to both the log file AND the FFU.Messaging queue for real-time UI updates.

.NOTES
    Fix: Monitor tab only showing "Build started" - WriteLog was not writing to messaging queue
    Root cause: UI timer if/elseif structure meant file fallback never executed when queue existed
    Solution: Integrate WriteLog with messaging queue via Set-CommonCoreMessagingContext
#>

BeforeAll {
    # Import the module
    $ModulePath = Join-Path $PSScriptRoot '..\FFUDevelopment\FFU.Common\FFU.Common.Core.psm1'
    Import-Module $ModulePath -Force -DisableNameChecking
}

Describe 'Set-CommonCoreMessagingContext Function' -Tag 'LogMonitoring', 'FFU.Common.Core' {

    Context 'Function Existence and Export' {

        It 'Should export Set-CommonCoreMessagingContext function' {
            $cmd = Get-Command -Name 'Set-CommonCoreMessagingContext' -ErrorAction SilentlyContinue
            $cmd | Should -Not -BeNullOrEmpty
        }

        It 'Should accept hashtable Context parameter' {
            $cmd = Get-Command -Name 'Set-CommonCoreMessagingContext'
            $param = $cmd.Parameters['Context']
            $param | Should -Not -BeNullOrEmpty
            $param.ParameterType.Name | Should -Be 'Hashtable'
        }

        It 'Should allow null Context parameter' {
            { Set-CommonCoreMessagingContext -Context $null } | Should -Not -Throw
        }
    }

    Context 'Context Management' {

        BeforeEach {
            # Clear any existing context
            Set-CommonCoreMessagingContext -Context $null
        }

        AfterEach {
            # Cleanup
            Set-CommonCoreMessagingContext -Context $null
        }

        It 'Should set messaging context when provided' {
            $mockQueue = [System.Collections.Concurrent.ConcurrentQueue[PSCustomObject]]::new()
            $context = @{ MessageQueue = $mockQueue }

            { Set-CommonCoreMessagingContext -Context $context } | Should -Not -Throw
        }

        It 'Should clear messaging context when null is provided' {
            $mockQueue = [System.Collections.Concurrent.ConcurrentQueue[PSCustomObject]]::new()
            $context = @{ MessageQueue = $mockQueue }

            Set-CommonCoreMessagingContext -Context $context
            { Set-CommonCoreMessagingContext -Context $null } | Should -Not -Throw
        }
    }
}

Describe 'WriteLog Messaging Queue Integration' -Tag 'LogMonitoring', 'FFU.Common.Core' {

    Context 'Without Messaging Context' {

        BeforeAll {
            # Ensure no messaging context
            Set-CommonCoreMessagingContext -Context $null
            $script:testLogPath = Join-Path $env:TEMP "FFU_WriteLog_Test_$([Guid]::NewGuid().ToString('N')).log"
            $CommonCoreLogFilePath = $script:testLogPath
        }

        AfterAll {
            if (Test-Path $script:testLogPath) {
                Remove-Item $script:testLogPath -Force -ErrorAction SilentlyContinue
            }
        }

        It 'Should write to file without error when no messaging context' {
            { WriteLog 'Test message without context' } | Should -Not -Throw
        }
    }

    Context 'With Messaging Context' {

        BeforeEach {
            # Re-import module to get clean state
            Import-Module (Join-Path $PSScriptRoot '..\FFUDevelopment\FFU.Common\FFU.Common.Core.psm1') -Force -DisableNameChecking

            # Create a mock messaging queue
            $script:mockQueue = [System.Collections.Concurrent.ConcurrentQueue[PSCustomObject]]::new()
            $script:mockContext = @{ MessageQueue = $script:mockQueue }

            # Set the messaging context
            Set-CommonCoreMessagingContext -Context $script:mockContext
        }

        AfterEach {
            # Clear messaging context
            Set-CommonCoreMessagingContext -Context $null
        }

        It 'Should write to messaging queue when context is set' {
            $testMessage = "Test queue message $(Get-Date -Format 'HHmmss')"
            WriteLog $testMessage

            # Check queue has message
            $script:mockQueue.Count | Should -BeGreaterThan 0
        }

        It 'Should write message with correct content to queue' {
            $testMessage = "Specific test message"
            WriteLog $testMessage

            $result = $null
            $dequeued = $script:mockQueue.TryDequeue([ref]$result)

            $dequeued | Should -BeTrue
            $result.Message | Should -Be $testMessage
        }

        It 'Should include Timestamp in queued message' {
            WriteLog 'Timestamp test'

            $result = $null
            $script:mockQueue.TryDequeue([ref]$result)

            $result.Timestamp | Should -Not -BeNullOrEmpty
            $result.Timestamp | Should -BeOfType [DateTime]
        }

        It 'Should include Level in queued message' {
            WriteLog 'Level test'

            $result = $null
            $script:mockQueue.TryDequeue([ref]$result)

            $result.Level | Should -Be 'Info'
        }

        It 'Should include Source in queued message' {
            WriteLog 'Source test'

            $result = $null
            $script:mockQueue.TryDequeue([ref]$result)

            $result.Source | Should -Be 'WriteLog'
        }

        It 'Should have ToLogString method on queued message' {
            WriteLog 'Method test'

            $result = $null
            $script:mockQueue.TryDequeue([ref]$result)

            $result | Get-Member -Name 'ToLogString' -MemberType ScriptMethod | Should -Not -BeNullOrEmpty
        }

        It 'ToLogString method should return formatted string' {
            WriteLog 'Format test'

            $result = $null
            $script:mockQueue.TryDequeue([ref]$result)

            $logString = $result.ToLogString()
            $logString | Should -Match '\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3}'
            $logString | Should -Match '\[Info'
            $logString | Should -Match 'Format test'
        }

        It 'Should write multiple messages to queue in order' {
            $messages = @('First', 'Second', 'Third')
            $messages | ForEach-Object { WriteLog $_ }

            $script:mockQueue.Count | Should -Be 3

            $results = @()
            for ($i = 0; $i -lt 3; $i++) {
                $result = $null
                $script:mockQueue.TryDequeue([ref]$result)
                $results += $result.Message
            }

            $results | Should -Be $messages
        }
    }

    Context 'Error Handling' {

        BeforeEach {
            # Re-import module to get clean state
            Import-Module (Join-Path $PSScriptRoot '..\FFUDevelopment\FFU.Common\FFU.Common.Core.psm1') -Force -DisableNameChecking

            # Create a context with invalid queue (no Enqueue method)
            $script:badContext = @{ MessageQueue = @{} }
            Set-CommonCoreMessagingContext -Context $script:badContext
        }

        AfterEach {
            Set-CommonCoreMessagingContext -Context $null
        }

        It 'Should not throw when messaging queue enqueue fails' {
            { WriteLog 'Error handling test' } | Should -Not -Throw
        }
    }

    Context 'Empty/Null Message Handling' {

        BeforeEach {
            # Re-import module to get clean state
            Import-Module (Join-Path $PSScriptRoot '..\FFUDevelopment\FFU.Common\FFU.Common.Core.psm1') -Force -DisableNameChecking

            $script:mockQueue = [System.Collections.Concurrent.ConcurrentQueue[PSCustomObject]]::new()
            $script:mockContext = @{ MessageQueue = $script:mockQueue }
            Set-CommonCoreMessagingContext -Context $script:mockContext
        }

        AfterEach {
            Set-CommonCoreMessagingContext -Context $null
        }

        It 'Should handle empty string without enqueueing' {
            WriteLog ''
            $script:mockQueue.Count | Should -Be 0
        }

        It 'Should handle null without enqueueing' {
            WriteLog $null
            $script:mockQueue.Count | Should -Be 0
        }
    }
}

Describe 'BuildFFUVM_UI ThreadJob Integration' -Tag 'LogMonitoring', 'Integration' {

    Context 'ThreadJob Scriptblock Configuration' {

        BeforeAll {
            $script:uiScriptPath = Join-Path $PSScriptRoot '..\FFUDevelopment\BuildFFUVM_UI.ps1'
            $script:uiContent = Get-Content $script:uiScriptPath -Raw
        }

        It 'Should import FFU.Common.Core module in ThreadJob' {
            $script:uiContent | Should -Match 'Import-Module.*FFU\.Common\\FFU\.Common\.Core\.psm1'
        }

        It 'Should call Set-CommonCoreMessagingContext in ThreadJob' {
            $script:uiContent | Should -Match 'Set-CommonCoreMessagingContext\s+-Context\s+\$SyncContext'
        }

        It 'Should set messaging context before Set-FFUBuildState' {
            # Find positions in the full file content (sequential order matters)
            $contextSetPos = $script:uiContent.IndexOf('Set-CommonCoreMessagingContext')
            $buildStateFirstPos = $script:uiContent.IndexOf('Set-FFUBuildState -Context $SyncContext -State Running')

            # Both should be found
            $contextSetPos | Should -BeGreaterThan -1 -Because 'Set-CommonCoreMessagingContext should exist in the file'
            $buildStateFirstPos | Should -BeGreaterThan -1 -Because 'Set-FFUBuildState should exist in the file'

            # Context should be set before build state Running message
            $contextSetPos | Should -BeLessThan $buildStateFirstPos -Because 'Messaging context must be set before build state messages are sent'
        }
    }
}

Describe 'BuildFFUVM.ps1 Messaging Context Restoration' -Tag 'LogMonitoring', 'Integration', 'Regression' {

    Context 'Module Import Does Not Break Messaging Context' {

        BeforeAll {
            $script:buildScriptPath = Join-Path $PSScriptRoot '..\FFUDevelopment\BuildFFUVM.ps1'
            $script:buildContent = Get-Content $script:buildScriptPath -Raw
        }

        It 'Should restore messaging context after FFU.Common import with -Force' {
            # BuildFFUVM.ps1 imports FFU.Common with -Force which resets the script-scoped
            # CommonCoreMessagingContext variable. It MUST call Set-CommonCoreMessagingContext
            # after the import to restore the context for real-time UI updates.

            # Find the FFU.Common import with -Force
            $importPos = $script:buildContent.IndexOf('Import-Module "$PSScriptRoot\FFU.Common" -Force')
            $importPos | Should -BeGreaterThan -1 -Because 'FFU.Common import should exist'

            # Find the context restoration call
            $restorePattern = 'if \(\$MessagingContext\)\s*\{\s*Set-CommonCoreMessagingContext\s+-Context\s+\$MessagingContext'
            $script:buildContent | Should -Match $restorePattern -Because 'Messaging context must be restored after -Force import'
        }

        It 'Should restore context AFTER the FFU.Common import' {
            # The Set-CommonCoreMessagingContext call must come AFTER the Import-Module -Force
            $importPos = $script:buildContent.IndexOf('Import-Module "$PSScriptRoot\FFU.Common" -Force')
            $restorePos = $script:buildContent.IndexOf('Set-CommonCoreMessagingContext -Context $MessagingContext')

            $importPos | Should -BeGreaterThan -1
            $restorePos | Should -BeGreaterThan -1
            $restorePos | Should -BeGreaterThan $importPos -Because 'Context must be set AFTER module import resets it'
        }

        It 'Should have comment explaining the defense-in-depth pattern' {
            # Ensure the fix is documented for future maintainers
            $script:buildContent | Should -Match 'MESSAGING CONTEXT RESTORATION' -Because 'Defense-in-depth pattern should be documented'
            $script:buildContent | Should -Match '-Force import.*resets' -Because 'Root cause should be documented'
        }
    }
}
