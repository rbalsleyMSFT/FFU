#Requires -Version 5.1
<#
.SYNOPSIS
    Test suite for FFU.Messaging module.

.DESCRIPTION
    Comprehensive tests for the messaging system including:
    - Context creation and validation
    - Message writing and reading
    - Thread safety under concurrent access
    - Progress messages
    - Cancellation support
    - File logging
    - Cross-runspace communication

.NOTES
    Run with: .\Test-FFUMessaging.ps1
    Or with Pester: Invoke-Pester -Path .\Test-FFUMessaging.ps1

    Note: PowerShell class types are only available with 'using module' syntax.
    These tests use PSObjects and duck-typing for broader compatibility.
#>

param(
    [switch]$Verbose,
    [switch]$SkipThreadTests
)

$ErrorActionPreference = 'Stop'
$VerbosePreference = if ($Verbose) { 'Continue' } else { 'SilentlyContinue' }

# Import module using 'using module' for type access
# Must be at script scope (not inside function)
$modulePath = Join-Path $PSScriptRoot '..\FFUDevelopment\Modules\FFU.Messaging\FFU.Messaging.psd1'
if (-not (Test-Path $modulePath)) {
    throw "Module not found at: $modulePath"
}

# Standard Import-Module for functions
Import-Module $modulePath -Force

# For type access in tests, we need to use the module's internal scope
# Create a scriptblock that runs in the module's context
$script:ModuleScope = {
    param($operation, $args1, $args2, $args3, $args4)
    switch ($operation) {
        'NewMessage' { return [FFUMessage]::new([FFUMessageLevel]::$args1, $args2, $args3, $args4) }
        'NewProgress' { return [FFUProgressMessage]::new($args1, $args2, $args3, $args4) }
        'GetLevel' { return [FFUMessageLevel]::$args1 }
        'GetState' { return [FFUBuildState]::$args1 }
        'CompareLevel' { return $args1 -eq [FFUMessageLevel]::$args2 }
        'CompareState' { return $args1 -eq [FFUBuildState]::$args2 }
    }
}

# Get module for internal execution
$script:FFUModule = Get-Module FFU.Messaging

# Helper to run code in module scope with type access
function Invoke-InModuleScope {
    param([string]$Operation, $Arg1, $Arg2, $Arg3, $Arg4)
    & $script:FFUModule $script:ModuleScope $Operation $Arg1 $Arg2 $Arg3 $Arg4
}

# Test results tracking
$script:TestResults = @{
    Passed = 0
    Failed = 0
    Skipped = 0
    Tests = [System.Collections.Generic.List[PSObject]]::new()
}

function Write-TestResult {
    param(
        [string]$TestName,
        [string]$Status,
        [string]$Message = ''
    )

    $color = switch ($Status) {
        'PASS' { 'Green' }
        'FAIL' { 'Red' }
        'SKIP' { 'Yellow' }
        default { 'White' }
    }

    $statusStr = "[$Status]".PadRight(7)
    Write-Host "$statusStr $TestName" -ForegroundColor $color
    if ($Message) {
        Write-Host "        $Message" -ForegroundColor Gray
    }

    $script:TestResults.Tests.Add([PSCustomObject]@{
        Name = $TestName
        Status = $Status
        Message = $Message
    })

    switch ($Status) {
        'PASS' { $script:TestResults.Passed++ }
        'FAIL' { $script:TestResults.Failed++ }
        'SKIP' { $script:TestResults.Skipped++ }
    }
}

Write-Host ""
Write-Host "=" * 70 -ForegroundColor Cyan
Write-Host "FFU.Messaging Module Test Suite" -ForegroundColor Cyan
Write-Host "=" * 70 -ForegroundColor Cyan
Write-Host ""

#region Context Creation Tests

Write-Host "--- Context Creation Tests ---" -ForegroundColor Yellow

# Test 1: Basic context creation
try {
    $ctx = New-FFUMessagingContext
    if ($ctx -and $ctx.MessageQueue -and $ctx.Version -eq '1.0.0') {
        Write-TestResult -TestName "Basic context creation" -Status "PASS"
    }
    else {
        Write-TestResult -TestName "Basic context creation" -Status "FAIL" -Message "Missing required properties"
    }
}
catch {
    Write-TestResult -TestName "Basic context creation" -Status "FAIL" -Message $_.Exception.Message
}

# Test 2: Context with file logging
try {
    $logPath = Join-Path $env:TEMP "FFUMessaging_Test_$(Get-Date -Format 'yyyyMMddHHmmss').log"
    $ctx = New-FFUMessagingContext -EnableFileLogging -LogFilePath $logPath

    if ($ctx.FileLoggingEnabled -and $ctx.LogFilePath -eq $logPath -and (Test-Path $logPath)) {
        Write-TestResult -TestName "Context with file logging" -Status "PASS"
        Remove-Item $logPath -Force -ErrorAction SilentlyContinue
    }
    else {
        Write-TestResult -TestName "Context with file logging" -Status "FAIL" -Message "File logging not properly configured"
    }
}
catch {
    Write-TestResult -TestName "Context with file logging" -Status "FAIL" -Message $_.Exception.Message
}

# Test 3: Context validation - valid
try {
    $ctx = New-FFUMessagingContext
    $result = Test-FFUMessagingContext -Context $ctx
    if ($result) {
        Write-TestResult -TestName "Context validation (valid context)" -Status "PASS"
    }
    else {
        Write-TestResult -TestName "Context validation (valid context)" -Status "FAIL"
    }
}
catch {
    Write-TestResult -TestName "Context validation (valid context)" -Status "FAIL" -Message $_.Exception.Message
}

# Test 4: Context validation - invalid
try {
    $invalidCtx = @{ SomeKey = 'SomeValue' }
    Test-FFUMessagingContext -Context $invalidCtx
    Write-TestResult -TestName "Context validation (invalid context)" -Status "FAIL" -Message "Should have thrown"
}
catch {
    if ($_.Exception.Message -like "*Invalid messaging context*") {
        Write-TestResult -TestName "Context validation (invalid context)" -Status "PASS"
    }
    else {
        Write-TestResult -TestName "Context validation (invalid context)" -Status "FAIL" -Message "Wrong exception: $($_.Exception.Message)"
    }
}

# Test 5: EnableFileLogging without path should throw
try {
    $ctx = New-FFUMessagingContext -EnableFileLogging
    Write-TestResult -TestName "EnableFileLogging without path throws" -Status "FAIL" -Message "Should have thrown"
}
catch {
    if ($_.Exception.Message -like "*LogFilePath is required*") {
        Write-TestResult -TestName "EnableFileLogging without path throws" -Status "PASS"
    }
    else {
        Write-TestResult -TestName "EnableFileLogging without path throws" -Status "FAIL" -Message "Wrong exception"
    }
}

#endregion

#region Message Writing Tests

Write-Host ""
Write-Host "--- Message Writing Tests ---" -ForegroundColor Yellow

# Test 6: Write-FFUMessage basic
try {
    $ctx = New-FFUMessagingContext
    Write-FFUMessage -Context $ctx -Message "Test message" -Level Info

    if ($ctx.MessageQueue.Count -eq 1 -and $ctx.MessageCount -eq 1) {
        $msg = $null
        $ctx.MessageQueue.TryDequeue([ref]$msg)
        # Check message using duck typing (no direct type comparison)
        if ($msg.Message -eq "Test message" -and $msg.Level.ToString() -eq 'Info') {
            Write-TestResult -TestName "Write-FFUMessage basic" -Status "PASS"
        }
        else {
            Write-TestResult -TestName "Write-FFUMessage basic" -Status "FAIL" -Message "Message content incorrect: $($msg.Message), Level: $($msg.Level)"
        }
    }
    else {
        Write-TestResult -TestName "Write-FFUMessage basic" -Status "FAIL" -Message "Queue count: $($ctx.MessageQueue.Count)"
    }
}
catch {
    Write-TestResult -TestName "Write-FFUMessage basic" -Status "FAIL" -Message $_.Exception.Message
}

# Test 7: Write-FFUMessage with source and data
try {
    $ctx = New-FFUMessagingContext
    Write-FFUMessage -Context $ctx -Message "Test" -Level Warning -Source "TestFunc" -Data @{ Key = "Value" }

    $msg = $null
    $ctx.MessageQueue.TryDequeue([ref]$msg)
    if ($msg.Source -eq "TestFunc" -and $msg.Data.Key -eq "Value" -and $msg.Level.ToString() -eq 'Warning') {
        Write-TestResult -TestName "Write-FFUMessage with source and data" -Status "PASS"
    }
    else {
        Write-TestResult -TestName "Write-FFUMessage with source and data" -Status "FAIL" -Message "Source: $($msg.Source), Level: $($msg.Level)"
    }
}
catch {
    Write-TestResult -TestName "Write-FFUMessage with source and data" -Status "FAIL" -Message $_.Exception.Message
}

# Test 8: Null/empty message handling
try {
    $ctx = New-FFUMessagingContext
    Write-FFUMessage -Context $ctx -Message ""
    Write-FFUMessage -Context $ctx -Message $null

    if ($ctx.MessageQueue.Count -eq 0) {
        Write-TestResult -TestName "Null/empty message handling" -Status "PASS"
    }
    else {
        Write-TestResult -TestName "Null/empty message handling" -Status "FAIL" -Message "Empty messages were queued"
    }
}
catch {
    Write-TestResult -TestName "Null/empty message handling" -Status "FAIL" -Message $_.Exception.Message
}

# Test 9: Error counting
try {
    $ctx = New-FFUMessagingContext
    Write-FFUMessage -Context $ctx -Message "Info" -Level Info
    Write-FFUMessage -Context $ctx -Message "Error1" -Level Error
    Write-FFUMessage -Context $ctx -Message "Error2" -Level Error
    Write-FFUMessage -Context $ctx -Message "Critical" -Level Critical

    if ($ctx.ErrorCount -eq 3 -and $ctx.LastError.Message -eq "Critical") {
        Write-TestResult -TestName "Error counting" -Status "PASS"
    }
    else {
        Write-TestResult -TestName "Error counting" -Status "FAIL" -Message "ErrorCount: $($ctx.ErrorCount)"
    }
}
catch {
    Write-TestResult -TestName "Error counting" -Status "FAIL" -Message $_.Exception.Message
}

# Test 10: Convenience functions
try {
    $ctx = New-FFUMessagingContext
    Write-FFUInfo -Context $ctx -Message "Info msg"
    Write-FFUSuccess -Context $ctx -Message "Success msg"
    Write-FFUWarning -Context $ctx -Message "Warning msg"
    Write-FFUError -Context $ctx -Message "Error msg"
    Write-FFUDebug -Context $ctx -Message "Debug msg"

    if ($ctx.MessageQueue.Count -eq 5) {
        Write-TestResult -TestName "Convenience functions (Info/Success/Warning/Error/Debug)" -Status "PASS"
    }
    else {
        Write-TestResult -TestName "Convenience functions" -Status "FAIL" -Message "Count: $($ctx.MessageQueue.Count)"
    }
}
catch {
    Write-TestResult -TestName "Convenience functions" -Status "FAIL" -Message $_.Exception.Message
}

#endregion

#region Progress Message Tests

Write-Host ""
Write-Host "--- Progress Message Tests ---" -ForegroundColor Yellow

# Test 11: Write-FFUProgress basic
try {
    $ctx = New-FFUMessagingContext
    Write-FFUProgress -Context $ctx -Activity "Downloading" -PercentComplete 50

    if ($ctx.CurrentProgress -eq 50 -and $ctx.CurrentPhase -eq "Downloading") {
        $msg = $null
        $ctx.MessageQueue.TryDequeue([ref]$msg)
        if ($msg.Data['PercentComplete'] -eq 50) {
            Write-TestResult -TestName "Write-FFUProgress basic" -Status "PASS"
        }
        else {
            Write-TestResult -TestName "Write-FFUProgress basic" -Status "FAIL" -Message "Progress data incorrect"
        }
    }
    else {
        Write-TestResult -TestName "Write-FFUProgress basic" -Status "FAIL"
    }
}
catch {
    Write-TestResult -TestName "Write-FFUProgress basic" -Status "FAIL" -Message $_.Exception.Message
}

# Test 12: Write-FFUProgress with details
try {
    $ctx = New-FFUMessagingContext
    Write-FFUProgress -Context $ctx -Activity "Building" -PercentComplete 75 -CurrentOperation "Applying image" -Status "In Progress" -SecondsRemaining 120

    $msg = $null
    $ctx.MessageQueue.TryDequeue([ref]$msg)
    if ($msg.Data['CurrentOperation'] -eq "Applying image" -and
        $msg.Data['Status'] -eq "In Progress" -and
        $msg.Data['SecondsRemaining'] -eq 120) {
        Write-TestResult -TestName "Write-FFUProgress with details" -Status "PASS"
    }
    else {
        Write-TestResult -TestName "Write-FFUProgress with details" -Status "FAIL" -Message "Data: $($msg.Data | ConvertTo-Json -Compress)"
    }
}
catch {
    Write-TestResult -TestName "Write-FFUProgress with details" -Status "FAIL" -Message $_.Exception.Message
}

# Test 13: Progress validation (0-100)
try {
    $ctx = New-FFUMessagingContext
    $threw = $false
    try {
        Write-FFUProgress -Context $ctx -Activity "Test" -PercentComplete -10
    }
    catch {
        $threw = $true
    }

    if ($threw) {
        Write-TestResult -TestName "Progress validation (0-100)" -Status "PASS" -Message "ValidateRange enforced"
    }
    else {
        Write-TestResult -TestName "Progress validation (0-100)" -Status "FAIL" -Message "Should have thrown for -10"
    }
}
catch {
    Write-TestResult -TestName "Progress validation (0-100)" -Status "FAIL" -Message $_.Exception.Message
}

#endregion

#region Message Reading Tests

Write-Host ""
Write-Host "--- Message Reading Tests ---" -ForegroundColor Yellow

# Test 14: Read-FFUMessages drains queue
try {
    $ctx = New-FFUMessagingContext
    1..10 | ForEach-Object { Write-FFUInfo -Context $ctx -Message "Message $_" }

    $messages = Read-FFUMessages -Context $ctx
    if ($messages.Count -eq 10 -and $ctx.MessageQueue.Count -eq 0) {
        Write-TestResult -TestName "Read-FFUMessages drains queue" -Status "PASS"
    }
    else {
        Write-TestResult -TestName "Read-FFUMessages drains queue" -Status "FAIL" -Message "Read: $($messages.Count), Remaining: $($ctx.MessageQueue.Count)"
    }
}
catch {
    Write-TestResult -TestName "Read-FFUMessages drains queue" -Status "FAIL" -Message $_.Exception.Message
}

# Test 15: Read-FFUMessages MaxMessages limit
try {
    $ctx = New-FFUMessagingContext
    1..100 | ForEach-Object { Write-FFUInfo -Context $ctx -Message "Message $_" }

    $messages = Read-FFUMessages -Context $ctx -MaxMessages 25
    if ($messages.Count -eq 25 -and $ctx.MessageQueue.Count -eq 75) {
        Write-TestResult -TestName "Read-FFUMessages MaxMessages limit" -Status "PASS"
    }
    else {
        Write-TestResult -TestName "Read-FFUMessages MaxMessages limit" -Status "FAIL"
    }
}
catch {
    Write-TestResult -TestName "Read-FFUMessages MaxMessages limit" -Status "FAIL" -Message $_.Exception.Message
}

# Test 16: Read-FFUMessages empty queue
try {
    $ctx = New-FFUMessagingContext
    $messages = Read-FFUMessages -Context $ctx
    if ($messages.Count -eq 0) {
        Write-TestResult -TestName "Read-FFUMessages empty queue returns empty array" -Status "PASS"
    }
    else {
        Write-TestResult -TestName "Read-FFUMessages empty queue returns empty array" -Status "FAIL"
    }
}
catch {
    Write-TestResult -TestName "Read-FFUMessages empty queue returns empty array" -Status "FAIL" -Message $_.Exception.Message
}

# Test 17: Peek-FFUMessage
try {
    $ctx = New-FFUMessagingContext
    Write-FFUInfo -Context $ctx -Message "Peek test"

    $peeked = Peek-FFUMessage -Context $ctx
    $stillThere = $ctx.MessageQueue.Count -eq 1
    $msg = $null
    $ctx.MessageQueue.TryDequeue([ref]$msg)

    if ($peeked.Message -eq "Peek test" -and $stillThere -and $msg.Message -eq "Peek test") {
        Write-TestResult -TestName "Peek-FFUMessage" -Status "PASS"
    }
    else {
        Write-TestResult -TestName "Peek-FFUMessage" -Status "FAIL"
    }
}
catch {
    Write-TestResult -TestName "Peek-FFUMessage" -Status "FAIL" -Message $_.Exception.Message
}

# Test 18: Get-FFUMessageCount
try {
    $ctx = New-FFUMessagingContext
    1..7 | ForEach-Object { Write-FFUInfo -Context $ctx -Message "Test" }

    if ((Get-FFUMessageCount -Context $ctx) -eq 7) {
        Write-TestResult -TestName "Get-FFUMessageCount" -Status "PASS"
    }
    else {
        Write-TestResult -TestName "Get-FFUMessageCount" -Status "FAIL"
    }
}
catch {
    Write-TestResult -TestName "Get-FFUMessageCount" -Status "FAIL" -Message $_.Exception.Message
}

#endregion

#region Build State Tests

Write-Host ""
Write-Host "--- Build State Tests ---" -ForegroundColor Yellow

# Test 19: Set-FFUBuildState
try {
    $ctx = New-FFUMessagingContext
    Set-FFUBuildState -Context $ctx -State Running

    # Use string comparison instead of type comparison
    if ($ctx.BuildState.ToString() -eq 'Running' -and $ctx.StartTime) {
        Write-TestResult -TestName "Set-FFUBuildState" -Status "PASS"
    }
    else {
        Write-TestResult -TestName "Set-FFUBuildState" -Status "FAIL" -Message "State: $($ctx.BuildState), StartTime: $($ctx.StartTime)"
    }
}
catch {
    Write-TestResult -TestName "Set-FFUBuildState" -Status "FAIL" -Message $_.Exception.Message
}

# Test 20: Set-FFUBuildState with message
try {
    $ctx = New-FFUMessagingContext
    Set-FFUBuildState -Context $ctx -State Completed -SendMessage

    if ($ctx.MessageQueue.Count -eq 1) {
        $msg = $null
        $ctx.MessageQueue.TryDequeue([ref]$msg)
        if ($msg.Level.ToString() -eq 'Success' -and $msg.Message -like "*completed*") {
            Write-TestResult -TestName "Set-FFUBuildState with message" -Status "PASS"
        }
        else {
            Write-TestResult -TestName "Set-FFUBuildState with message" -Status "FAIL" -Message "Level: $($msg.Level), Msg: $($msg.Message)"
        }
    }
    else {
        Write-TestResult -TestName "Set-FFUBuildState with message" -Status "FAIL" -Message "Queue count: $($ctx.MessageQueue.Count)"
    }
}
catch {
    Write-TestResult -TestName "Set-FFUBuildState with message" -Status "FAIL" -Message $_.Exception.Message
}

#endregion

#region Cancellation Tests

Write-Host ""
Write-Host "--- Cancellation Tests ---" -ForegroundColor Yellow

# Test 21: Request-FFUCancellation
try {
    $ctx = New-FFUMessagingContext
    Request-FFUCancellation -Context $ctx

    if ($ctx.CancellationRequested -and $ctx.BuildState.ToString() -eq 'Cancelling') {
        Write-TestResult -TestName "Request-FFUCancellation" -Status "PASS"
    }
    else {
        Write-TestResult -TestName "Request-FFUCancellation" -Status "FAIL" -Message "CancellationRequested: $($ctx.CancellationRequested), State: $($ctx.BuildState)"
    }
}
catch {
    Write-TestResult -TestName "Request-FFUCancellation" -Status "FAIL" -Message $_.Exception.Message
}

# Test 22: Test-FFUCancellationRequested
try {
    $ctx = New-FFUMessagingContext
    $before = Test-FFUCancellationRequested -Context $ctx
    $ctx.CancellationRequested = $true
    $after = Test-FFUCancellationRequested -Context $ctx

    if (-not $before -and $after) {
        Write-TestResult -TestName "Test-FFUCancellationRequested" -Status "PASS"
    }
    else {
        Write-TestResult -TestName "Test-FFUCancellationRequested" -Status "FAIL"
    }
}
catch {
    Write-TestResult -TestName "Test-FFUCancellationRequested" -Status "FAIL" -Message $_.Exception.Message
}

#endregion

#region Thread Safety Tests

Write-Host ""
Write-Host "--- Thread Safety Tests ---" -ForegroundColor Yellow

if ($SkipThreadTests) {
    Write-TestResult -TestName "Concurrent write test" -Status "SKIP" -Message "-SkipThreadTests specified"
    Write-TestResult -TestName "Cross-runspace communication" -Status "SKIP" -Message "-SkipThreadTests specified"
}
else {
    # Test 23: Concurrent writes from multiple runspaces
    try {
        $ctx = New-FFUMessagingContext
        $jobs = @()
        $messagesPerJob = 100
        $jobCount = 5

        # Start multiple jobs writing concurrently
        1..$jobCount | ForEach-Object {
            $jobNum = $_
            $jobs += Start-ThreadJob -ScriptBlock {
                param($context, $count, $num)
                1..$count | ForEach-Object {
                    $msg = [PSCustomObject]@{
                        Timestamp = [datetime]::UtcNow
                        Level = 'Info'
                        Message = "Job$num-Msg$_"
                        Source = "Job$num"
                        Data = @{}
                    }
                    $context.MessageQueue.Enqueue($msg)
                }
            } -ArgumentList $ctx, $messagesPerJob, $jobNum
        }

        # Wait for all jobs
        $jobs | Wait-Job | Out-Null
        $jobs | Remove-Job

        # Verify all messages arrived
        $expectedCount = $jobCount * $messagesPerJob
        $actualCount = $ctx.MessageQueue.Count

        if ($actualCount -eq $expectedCount) {
            Write-TestResult -TestName "Concurrent write test ($jobCount jobs x $messagesPerJob messages)" -Status "PASS"
        }
        else {
            Write-TestResult -TestName "Concurrent write test" -Status "FAIL" -Message "Expected $expectedCount, got $actualCount"
        }
    }
    catch {
        Write-TestResult -TestName "Concurrent write test" -Status "FAIL" -Message $_.Exception.Message
    }

    # Test 24: Cross-runspace communication with actual module functions
    try {
        $logPath = Join-Path $env:TEMP "FFUMessaging_CrossRunspace_$(Get-Date -Format 'yyyyMMddHHmmss').log"
        $ctx = New-FFUMessagingContext -EnableFileLogging -LogFilePath $logPath

        # Get absolute path to module
        $absModulePath = (Resolve-Path $modulePath).Path

        $job = Start-ThreadJob -ScriptBlock {
            param($context, $modPath)
            Import-Module $modPath -Force
            Write-FFUInfo -Context $context -Message "Hello from background job"
            Write-FFUProgress -Context $context -Activity "Working" -PercentComplete 50
            Write-FFUSuccess -Context $context -Message "Job completed"
        } -ArgumentList $ctx, $absModulePath

        $job | Wait-Job | Out-Null
        $jobResult = $job | Receive-Job -ErrorAction SilentlyContinue
        $job | Remove-Job

        $messages = Read-FFUMessages -Context $ctx
        $hasInfo = $messages | Where-Object { $_.Message -eq "Hello from background job" }
        $hasProgress = $messages | Where-Object { $_.Level.ToString() -eq 'Progress' }
        $hasSuccess = $messages | Where-Object { $_.Message -eq "Job completed" }

        if ($hasInfo -and $hasProgress -and $hasSuccess) {
            Write-TestResult -TestName "Cross-runspace communication with module" -Status "PASS"
        }
        else {
            $msgList = ($messages | ForEach-Object { "$($_.Level): $($_.Message)" }) -join '; '
            Write-TestResult -TestName "Cross-runspace communication with module" -Status "FAIL" -Message "Messages: $msgList"
        }

        Remove-Item $logPath -Force -ErrorAction SilentlyContinue
    }
    catch {
        Write-TestResult -TestName "Cross-runspace communication with module" -Status "FAIL" -Message $_.Exception.Message
    }
}

#endregion

#region File Logging Tests

Write-Host ""
Write-Host "--- File Logging Tests ---" -ForegroundColor Yellow

# Test 25: Messages written to file
try {
    $logPath = Join-Path $env:TEMP "FFUMessaging_FileTest_$(Get-Date -Format 'yyyyMMddHHmmss').log"
    $ctx = New-FFUMessagingContext -EnableFileLogging -LogFilePath $logPath

    Write-FFUInfo -Context $ctx -Message "Test log entry"
    Write-FFUWarning -Context $ctx -Message "Warning entry"
    Write-FFUError -Context $ctx -Message "Error entry"

    Start-Sleep -Milliseconds 200  # Allow file write

    $content = Get-Content $logPath -Raw
    if ($content -match "Test log entry" -and $content -match "Warning entry" -and $content -match "Error entry") {
        Write-TestResult -TestName "Messages written to file" -Status "PASS"
    }
    else {
        Write-TestResult -TestName "Messages written to file" -Status "FAIL" -Message "Content: $($content.Substring(0, [Math]::Min(100, $content.Length)))"
    }

    Remove-Item $logPath -Force -ErrorAction SilentlyContinue
}
catch {
    Write-TestResult -TestName "Messages written to file" -Status "FAIL" -Message $_.Exception.Message
}

# Test 26: SkipFileLog parameter
try {
    $logPath = Join-Path $env:TEMP "FFUMessaging_SkipFile_$(Get-Date -Format 'yyyyMMddHHmmss').log"
    $ctx = New-FFUMessagingContext -EnableFileLogging -LogFilePath $logPath

    Write-FFUMessage -Context $ctx -Message "Should be in file" -Level Info
    Write-FFUMessage -Context $ctx -Message "Should NOT be in file" -Level Info -SkipFileLog

    Start-Sleep -Milliseconds 200

    $content = Get-Content $logPath -Raw
    if ($content -match "Should be in file" -and $content -notmatch "Should NOT be in file") {
        Write-TestResult -TestName "SkipFileLog parameter" -Status "PASS"
    }
    else {
        Write-TestResult -TestName "SkipFileLog parameter" -Status "FAIL"
    }

    Remove-Item $logPath -Force -ErrorAction SilentlyContinue
}
catch {
    Write-TestResult -TestName "SkipFileLog parameter" -Status "FAIL" -Message $_.Exception.Message
}

#endregion

#region Cleanup Tests

Write-Host ""
Write-Host "--- Cleanup Tests ---" -ForegroundColor Yellow

# Test 27: Close-FFUMessagingContext
try {
    $logPath = Join-Path $env:TEMP "FFUMessaging_Close_$(Get-Date -Format 'yyyyMMddHHmmss').log"
    $ctx = New-FFUMessagingContext -EnableFileLogging -LogFilePath $logPath
    $ctx.StartTime = [datetime]::UtcNow.AddMinutes(-5)
    $ctx.EndTime = [datetime]::UtcNow
    $ctx.MessageCount = 100
    $ctx.ErrorCount = 2

    Write-FFUInfo -Context $ctx -Message "Pre-close message"
    Close-FFUMessagingContext -Context $ctx

    Start-Sleep -Milliseconds 200

    $content = Get-Content $logPath -Raw
    if ($content -match "Messaging context closed" -and $content -match "Total messages:" -and $content -match "Errors:") {
        Write-TestResult -TestName "Close-FFUMessagingContext" -Status "PASS"
    }
    else {
        Write-TestResult -TestName "Close-FFUMessagingContext" -Status "FAIL" -Message "Content: $($content.Substring(0, [Math]::Min(200, $content.Length)))"
    }

    Remove-Item $logPath -Force -ErrorAction SilentlyContinue
}
catch {
    Write-TestResult -TestName "Close-FFUMessagingContext" -Status "FAIL" -Message $_.Exception.Message
}

#endregion

#region Message Class Tests (using module scope)

Write-Host ""
Write-Host "--- Message Class Tests ---" -ForegroundColor Yellow

# Test 28: FFUMessage ToLogString format
try {
    $ctx = New-FFUMessagingContext
    Write-FFUMessage -Context $ctx -Message "Test warning" -Level Warning -Source "TestSource"

    $msg = $null
    $ctx.MessageQueue.TryDequeue([ref]$msg)
    $logStr = $msg.ToLogString()

    if ($logStr -match "\d{4}-\d{2}-\d{2}" -and $logStr -match "WARNING" -and $logStr -match "\[TestSource\]" -and $logStr -match "Test warning") {
        Write-TestResult -TestName "FFUMessage ToLogString format" -Status "PASS"
    }
    else {
        Write-TestResult -TestName "FFUMessage ToLogString format" -Status "FAIL" -Message "Format: $logStr"
    }
}
catch {
    Write-TestResult -TestName "FFUMessage ToLogString format" -Status "FAIL" -Message $_.Exception.Message
}

# Test 29: FFUMessage ToDisplayString format
try {
    $ctx = New-FFUMessagingContext
    Write-FFUMessage -Context $ctx -Message "Display message" -Level Info -Source "Source"

    $msg = $null
    $ctx.MessageQueue.TryDequeue([ref]$msg)
    $displayStr = $msg.ToDisplayString()

    if ($displayStr -eq "[Source] Display message") {
        Write-TestResult -TestName "FFUMessage ToDisplayString format" -Status "PASS"
    }
    else {
        Write-TestResult -TestName "FFUMessage ToDisplayString format" -Status "FAIL" -Message "Format: $displayStr"
    }
}
catch {
    Write-TestResult -TestName "FFUMessage ToDisplayString format" -Status "FAIL" -Message $_.Exception.Message
}

# Test 30: FFUProgressMessage properties
try {
    $ctx = New-FFUMessagingContext
    Write-FFUProgress -Context $ctx -Activity "Downloading" -PercentComplete 75 -CurrentOperation "File 3 of 4" -Status "In Progress"

    $msg = $null
    $ctx.MessageQueue.TryDequeue([ref]$msg)

    if ($msg.PercentComplete -eq 75 -and
        $msg.CurrentOperation -eq "File 3 of 4" -and
        $msg.Status -eq "In Progress" -and
        $msg.Level.ToString() -eq 'Progress') {
        Write-TestResult -TestName "FFUProgressMessage properties" -Status "PASS"
    }
    else {
        Write-TestResult -TestName "FFUProgressMessage properties" -Status "FAIL" -Message "Percent: $($msg.PercentComplete), Op: $($msg.CurrentOperation)"
    }
}
catch {
    Write-TestResult -TestName "FFUProgressMessage properties" -Status "FAIL" -Message $_.Exception.Message
}

#endregion

#region Performance Test

Write-Host ""
Write-Host "--- Performance Test ---" -ForegroundColor Yellow

# Test 31: Queue throughput
try {
    $ctx = New-FFUMessagingContext
    $iterations = 10000

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    1..$iterations | ForEach-Object {
        $msg = [PSCustomObject]@{
            Timestamp = [datetime]::UtcNow
            Level = 'Info'
            Message = "Perf test message $_"
            Source = ''
            Data = @{}
        }
        $ctx.MessageQueue.Enqueue($msg)
    }
    $writeTime = $sw.ElapsedMilliseconds

    $sw.Restart()
    $msg = $null
    while ($ctx.MessageQueue.TryDequeue([ref]$msg)) { }
    $readTime = $sw.ElapsedMilliseconds
    $sw.Stop()

    $writeRate = if ($writeTime -gt 0) { [int]($iterations / ($writeTime / 1000)) } else { 'N/A' }
    $readRate = if ($readTime -gt 0) { [int]($iterations / ($readTime / 1000)) } else { 'N/A' }

    Write-TestResult -TestName "Queue throughput ($iterations messages)" -Status "PASS" -Message "Write: ${writeRate}/sec, Read: ${readRate}/sec"
}
catch {
    Write-TestResult -TestName "Queue throughput" -Status "FAIL" -Message $_.Exception.Message
}

#endregion

# Summary
Write-Host ""
Write-Host "=" * 70 -ForegroundColor Cyan
Write-Host "Test Summary" -ForegroundColor Cyan
Write-Host "=" * 70 -ForegroundColor Cyan
Write-Host ""
Write-Host "Passed: $($script:TestResults.Passed)" -ForegroundColor Green
Write-Host "Failed: $($script:TestResults.Failed)" -ForegroundColor Red
Write-Host "Skipped: $($script:TestResults.Skipped)" -ForegroundColor Yellow
Write-Host ""

$totalTests = $script:TestResults.Passed + $script:TestResults.Failed + $script:TestResults.Skipped
$passRate = if ($totalTests -gt 0) { [math]::Round(($script:TestResults.Passed / $totalTests) * 100, 1) } else { 0 }
Write-Host "Pass Rate: $passRate%" -ForegroundColor $(if ($passRate -ge 90) { 'Green' } elseif ($passRate -ge 70) { 'Yellow' } else { 'Red' })
Write-Host ""

# Return exit code
if ($script:TestResults.Failed -gt 0) {
    exit 1
}
exit 0
