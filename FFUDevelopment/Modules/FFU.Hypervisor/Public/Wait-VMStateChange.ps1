#Requires -Version 5.1

<#
.SYNOPSIS
    Wait for Hyper-V VM to reach specified state using CIM event subscription.

.DESCRIPTION
    Uses Register-CimIndicationEvent to subscribe to Msvm_ComputerSystem state changes
    instead of polling. This is more efficient and provides faster response than
    Start-Sleep polling loops.

    For VMware VMs, use traditional polling as VMware lacks CIM event support.

.PARAMETER VMName
    Name of the Hyper-V virtual machine to monitor.

.PARAMETER TargetState
    Desired VM state to wait for: Running, Off, Paused, Saved.

.PARAMETER TimeoutSeconds
    Maximum time to wait for state change. Default is 3600 (1 hour).

.PARAMETER PollFallbackMs
    Milliseconds between event checks. The event subscription is async,
    so we need a small sleep to allow PowerShell to process events.
    Default is 500ms. This is NOT polling the VM - just allowing event processing.

.OUTPUTS
    [bool] True if target state reached, False if timeout exceeded.

.EXAMPLE
    Wait-VMStateChange -VMName "FFU_Build_VM" -TargetState Off -TimeoutSeconds 1800
    # Waits up to 30 minutes for VM to shut down

.NOTES
    PERF-02: Event-driven VM state monitoring for Hyper-V
    Replaces polling loops with WMI event subscription.
#>
function Wait-VMStateChange {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$VMName,

        [Parameter(Mandatory)]
        [ValidateSet('Running', 'Off', 'Paused', 'Saved')]
        [string]$TargetState,

        [int]$TimeoutSeconds = 3600,

        [int]$PollFallbackMs = 500
    )

    # Map state names to EnabledState values
    # See: https://learn.microsoft.com/en-us/windows/win32/hyperv_v2/msvm-computersystem
    $stateMap = @{
        'Running' = 2    # Enabled
        'Off'     = 3    # Disabled
        'Paused'  = 32768  # Paused
        'Saved'   = 32769  # Suspended
    }
    $targetStateValue = $stateMap[$TargetState]

    # Check current state first - may already be at target
    $currentVM = Get-VM -Name $VMName -ErrorAction SilentlyContinue
    if (-not $currentVM) {
        # Safe logging pattern for ThreadJob compatibility (v1.3.3)
        $warningMsg = "VM '$VMName' not found"
        if ($function:WriteLog) {
            WriteLog "WARNING: $warningMsg"
        }
        else {
            Write-Verbose "WARNING: $warningMsg"
        }
        return $false
    }

    $currentState = switch ($currentVM.State) {
        'Running' { 2 }
        'Off' { 3 }
        'Paused' { 32768 }
        'Saved' { 32769 }
        default { 0 }
    }

    if ($currentState -eq $targetStateValue) {
        Write-Verbose "VM '$VMName' is already in state '$TargetState'"
        return $true
    }

    # Unique source identifier for this subscription
    $sourceId = "VMStateChange_$VMName_$([Guid]::NewGuid().ToString('N'))"

    # Use script-scope variable for event communication
    $script:VMStateReached = $false

    try {
        # WQL query for VM state modification
        # WITHIN 2 = check every 2 seconds (balance between responsiveness and CPU)
        $query = @"
SELECT * FROM __InstanceModificationEvent WITHIN 2
WHERE TargetInstance ISA 'Msvm_ComputerSystem'
AND TargetInstance.ElementName = '$VMName'
"@

        Write-Verbose "Registering CIM event subscription for VM '$VMName' target state '$TargetState'"
        Write-Verbose "WQL Query: $query"

        # Register for indication with action block
        $eventJob = Register-CimIndicationEvent `
            -Query $query `
            -Namespace "root\virtualization\v2" `
            -SourceIdentifier $sourceId `
            -Action {
                $vm = $Event.SourceEventArgs.NewEvent.TargetInstance
                $currentEnabled = $vm.EnabledState

                # Access target from outer scope - use event MessageData
                if ($currentEnabled -eq $Event.MessageData.TargetStateValue) {
                    $script:VMStateReached = $true
                }
            } -MessageData @{ TargetStateValue = $targetStateValue }

        # Wait with timeout, checking for event
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        while (-not $script:VMStateReached -and $stopwatch.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
            # Brief sleep to allow PowerShell to process events
            # This is NOT polling the VM - just allowing the event system to work
            Start-Sleep -Milliseconds $PollFallbackMs

            # Also check VM state directly in case event was missed
            # (defense in depth - events can occasionally be dropped)
            $checkVM = Get-VM -Name $VMName -ErrorAction SilentlyContinue
            if ($checkVM) {
                $checkState = switch ($checkVM.State) {
                    'Running' { 2 }
                    'Off' { 3 }
                    'Paused' { 32768 }
                    'Saved' { 32769 }
                    default { 0 }
                }
                if ($checkState -eq $targetStateValue) {
                    $script:VMStateReached = $true
                }
            }

            # Log progress every 30 seconds
            if ($stopwatch.Elapsed.TotalSeconds % 30 -lt 1) {
                Write-Verbose "Waiting for VM '$VMName' to reach state '$TargetState' (elapsed: $([int]$stopwatch.Elapsed.TotalSeconds)s)"
            }
        }

        $elapsed = $stopwatch.Elapsed.TotalSeconds
        if ($script:VMStateReached) {
            Write-Verbose "VM '$VMName' reached state '$TargetState' after $([int]$elapsed) seconds"
            return $true
        }
        else {
            # Safe logging pattern for ThreadJob compatibility (v1.3.3)
            $warningMsg = "Timeout waiting for VM '$VMName' to reach state '$TargetState' after $TimeoutSeconds seconds"
            if ($function:WriteLog) {
                WriteLog "WARNING: $warningMsg"
            }
            else {
                Write-Verbose "WARNING: $warningMsg"
            }
            return $false
        }
    }
    finally {
        # Always clean up event subscription
        Unregister-Event -SourceIdentifier $sourceId -ErrorAction SilentlyContinue
        Remove-Job -Name $sourceId -Force -ErrorAction SilentlyContinue
        Remove-Variable -Name VMStateReached -Scope Script -ErrorAction SilentlyContinue
        Write-Verbose "Cleaned up CIM event subscription '$sourceId'"
    }
}

Export-ModuleMember -Function Wait-VMStateChange
