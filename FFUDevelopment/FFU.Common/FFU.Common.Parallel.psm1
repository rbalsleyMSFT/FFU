function Invoke-ParallelProcessing {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$ItemsToProcess,
        [Parameter(Mandatory = $false)] 
        [object]$ListViewControl = $null, # Changed type to [object]
        [Parameter(Mandatory = $false)] 
        [string]$IdentifierProperty = 'Identifier', 
        [Parameter(Mandatory = $false)] 
        [string]$StatusProperty = 'Status',         
        [Parameter(Mandatory)]
        [ValidateSet('WingetDownload', 'CopyBYO', 'DownloadDriverByMake')]
        [string]$TaskType,
        [Parameter()]
        [hashtable]$TaskArguments = @{},
        [Parameter(Mandatory = $false)] 
        [string]$CompletedStatusText = "Completed",
        [Parameter(Mandatory = $false)] 
        [string]$ErrorStatusPrefix = "Error: ",
        [Parameter(Mandatory = $false)] 
        [object]$WindowObject = $null, # Changed type to [object]
        [Parameter(Mandatory = $false)]
        [string]$MainThreadLogPath = $null, # New parameter for the log path
        [Parameter(Mandatory = $false)]
        [int]$ThrottleLimit = 5
    )
    # Check if running in UI mode by verifying the types of the passed objects
    $isUiMode = ($null -ne $WindowObject -and $WindowObject -is [System.Windows.Window] -and $null -ne $ListViewControl -and $ListViewControl -is [System.Windows.Controls.ListView])

    if ($isUiMode) {
        WriteLog "Invoke-ParallelProcessing started for $($ItemsToProcess.Count) items in ListView '$($ListViewControl.Name)'."
    }
    else {
        WriteLog "Invoke-ParallelProcessing started for $($ItemsToProcess.Count) items (non-UI mode)."
    }
    $resultsCollection = [System.Collections.Generic.List[object]]::new()
    $jobs = @()
    $totalItems = $ItemsToProcess.Count
    $processedCount = 0
    $completedIdentifiers = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    # Create a thread-safe queue for intermediate progress updates
    $progressQueue = New-Object System.Collections.Concurrent.ConcurrentQueue[hashtable]

    # Define common paths locally within this function's scope
    $coreModulePath = $MyInvocation.MyCommand.Module.Path 
    $coreModuleDirectory = Split-Path -Path $coreModulePath -Parent
    $ffuDevelopmentRoot = Split-Path -Path $coreModuleDirectory -Parent 
    
    # Paths to the module DIRECTORIES needed by the parallel threads
    $commonModulePathForJob = Join-Path -Path $ffuDevelopmentRoot -ChildPath "FFU.Common"
    $uiCoreModulePathForJob = Join-Path -Path $ffuDevelopmentRoot -ChildPath "FFUUI.Core"    
    
    # Use the explicitly passed MainThreadLogPath for the parallel jobs.
    # If not provided (e.g., older calls or direct module use without this param), it might be null.
    # The parallel job's Set-CommonCoreLogPath will handle null/empty paths by warning.
    $currentLogFilePathForJob = $MainThreadLogPath

    $jobScopeVariables = $TaskArguments.Clone() 
    $jobScopeVariables['_commonModulePath'] = $commonModulePathForJob
    $jobScopeVariables['_uiCoreModulePath'] = $uiCoreModulePathForJob
    $jobScopeVariables['_currentLogFilePathForJob'] = $currentLogFilePathForJob # Pass the determined log path
    $jobScopeVariables['_progressQueue'] = $progressQueue

    # The $TaskScriptBlock parameter is already a local variable in this scope

    # Initial UI update needs to happen *before* starting the jobs
    # Update all items to a static "Processing..." status
    if ($isUiMode) {
        # Use the new $isUiMode flag
        foreach ($item in $ItemsToProcess) {
            $identifierValue = $item.$IdentifierProperty
            $initialStaticStatus = "Queued..." 
            try {
                # Update the UI on the main thread to show the item is being queued for processing
                $WindowObject.Dispatcher.Invoke([System.Windows.Threading.DispatcherPriority]::Background, [Action] { 
                        Update-ListViewItemStatus -WindowObject $WindowObject -ListView $ListViewControl -IdentifierProperty $IdentifierProperty -IdentifierValue $identifierValue -StatusProperty $StatusProperty -StatusValue $initialStaticStatus 
                    })
            }
            catch {
                WriteLog "Error setting initial status for item '$identifierValue': $($_.Exception.Message)"
            }
        }
    }

    # Queue items and start jobs using the pipeline and $using:
    try {
        # $jobScopeVariables and $TaskType are local here
        # Inside the -Parallel scriptblock, we access them with $using:
        $jobs = $ItemsToProcess | ForEach-Object -Parallel {
            # Access the current item via pipeline variable $_
            $currentItem = $_
            # Access the combined arguments hashtable from the calling scope using $using:
            $localJobArgs = $using:jobScopeVariables
            # Access the task type string from the calling scope using $using:
            $localTaskType = $using:TaskType
            # Access the progress queue using $using:
            $localProgressQueue = $localJobArgs['_progressQueue']

            # Initialize result hashtable
            $taskResult = $null
            $resultIdentifier = $null
            $resultStatus = "Error: Task type '$localTaskType' not recognized"
            $resultCode = 1 # Default to error

            try {
                # Import modules needed for the task
                Import-Module $localJobArgs['_commonModulePath'] -Force
                Import-Module $localJobArgs['_uiCoreModulePath'] -Force

                # Set the log path for this parallel thread
                Set-CommonCoreLogPath -Path $localJobArgs['_currentLogFilePathForJob']

                # Set other global variables if tasks rely on them (prefer passing as parameters)
                $global:AppsPath = $localJobArgs['AppsPath']
                $global:WindowsArch = $localJobArgs['WindowsArch']
                if ($localJobArgs.ContainsKey('OrchestrationPath')) {
                    $global:OrchestrationPath = $localJobArgs['OrchestrationPath']
                }

                # Execute the appropriate background task based on $localTaskType
                switch ($localTaskType) {
                    'WingetDownload' {
                        # Pass the progress queue to the task function
                        $taskResult = Start-WingetAppDownloadTask -ApplicationItemData $currentItem `
                            -AppListJsonPath $localJobArgs['AppListJsonPath'] `
                            -AppsPath $localJobArgs['AppsPath'] `
                            -WindowsArch $localJobArgs['WindowsArch'] `
                            -OrchestrationPath $localJobArgs['OrchestrationPath'] `
                            -ProgressQueue $localProgressQueue
                        if ($null -ne $taskResult) {
                            $resultIdentifier = $taskResult.Id
                            $resultStatus = $taskResult.Status
                            $resultCode = $taskResult.ResultCode
                        }
                        else {
                            $resultIdentifier = $currentItem.Id # Fallback
                            $resultStatus = "Error: WingetDownload task returned null"
                            $resultCode = 1
                            WriteLog $resultStatus
                        }
                    }
                    'CopyBYO' {
                        # Pass the progress queue to the task function
                        $taskResult = Start-CopyBYOApplicationTask -ApplicationItemData $currentItem `
                            -AppsPath $localJobArgs['AppsPath'] `
                            -ProgressQueue $localProgressQueue 
                        if ($null -ne $taskResult) {
                            $resultIdentifier = $taskResult.Name
                            $resultStatus = $taskResult.Status
                            $resultCode = if ($taskResult.Success) { 0 } else { 1 }
                        }
                        else {
                            $resultIdentifier = $currentItem.Name # Fallback
                            $resultStatus = "Error: CopyBYO task returned null"
                            $resultCode = 1
                            WriteLog $resultStatus
                        }
                    }
                    'DownloadDriverByMake' {
                        $make = $currentItem.Make
                        # Ensure $resultIdentifier is set before the switch, using the main IdentifierProperty
                        # This is crucial if a Make is unsupported or a task fails to return a result.
                        $resultIdentifier = $currentItem.$($using:IdentifierProperty)

                        switch ($make) {
                            'Microsoft' {
                                $taskResult = Save-MicrosoftDriversTask -DriverItemData $currentItem `
                                    -DriversFolder $localJobArgs['DriversFolder'] `
                                    -WindowsRelease $localJobArgs['WindowsRelease'] `
                                    -Headers $localJobArgs['Headers'] `
                                    -UserAgent $localJobArgs['UserAgent'] `
                                    -ProgressQueue $localProgressQueue `
                                    -CompressToWim $localJobArgs['CompressToWim']
                            }
                            'Dell' {
                                $taskResult = Save-DellDriversTask -DriverItemData $currentItem `
                                    -DriversFolder $localJobArgs['DriversFolder'] `
                                    -WindowsArch $localJobArgs['WindowsArch'] `
                                    -WindowsRelease $localJobArgs['WindowsRelease'] `
                                    -ProgressQueue $localProgressQueue `
                                    -CompressToWim $localJobArgs['CompressToWim']
                            }
                            'HP' {
                                $taskResult = Save-HPDriversTask -DriverItemData $currentItem `
                                    -DriversFolder $localJobArgs['DriversFolder'] `
                                    -WindowsArch $localJobArgs['WindowsArch'] `
                                    -WindowsRelease $localJobArgs['WindowsRelease'] `
                                    -WindowsVersion $localJobArgs['WindowsVersion'] `
                                    -ProgressQueue $localProgressQueue `
                                    -CompressToWim $localJobArgs['CompressToWim']
                            }
                            'Lenovo' {
                                $taskResult = Save-LenovoDriversTask -DriverItemData $currentItem `
                                    -DriversFolder $localJobArgs['DriversFolder'] `
                                    -WindowsRelease $localJobArgs['WindowsRelease'] `
                                    -Headers $localJobArgs['Headers'] `
                                    -UserAgent $localJobArgs['UserAgent'] `
                                    -ProgressQueue $localProgressQueue `
                                    -CompressToWim $localJobArgs['CompressToWim']
                            }
                            default {
                                $unsupportedMakeMessage = "Error: Unsupported Make '$make' for driver download."
                                WriteLog $unsupportedMakeMessage
                                $resultStatus = $unsupportedMakeMessage
                                $resultCode = 1
                                # $resultIdentifier is already set from $currentItem.$($using:IdentifierProperty)
                                $localProgressQueue.Enqueue(@{ Identifier = $resultIdentifier; Status = $resultStatus })
                                # $taskResult remains null, handled below
                            }
                        }

                        # Consolidate result handling for 'DownloadDriverByMake'
                        if ($null -ne $taskResult) {
                            # $resultIdentifier is already $currentItem.$($using:IdentifierProperty)
                            # We use the task's returned Model/Identifier for logging/status if needed,
                            # but the primary identifier for UI updates should be consistent.
                            $taskSpecificIdentifier = $null
                            if ($taskResult.PSObject.Properties.Name -contains 'Model') { $taskSpecificIdentifier = $taskResult.Model }
                            elseif ($taskResult.PSObject.Properties.Name -contains 'Identifier') { $taskSpecificIdentifier = $taskResult.Identifier }

                            $resultStatus = $taskResult.Status
                            # Simplified success check. All driver tasks should now return a 'Success' property.
                            if ($taskResult.PSObject.Properties.Name -contains 'Success') {
                                $resultCode = if ($taskResult.Success) { 0 } else { 1 }
                            }
                            else {
                                # Fallback for any task that *still* doesn't return 'Success'. This is now the exceptional case.
                                WriteLog "Warning: Task for '$taskSpecificIdentifier' did not return a 'Success' property. Inferring from status: '$($taskResult.Status)'"
                                if ($taskResult.Status -like 'Completed*' -or $taskResult.Status -like 'Already downloaded*') {
                                    $resultCode = 0 # Treat as success
                                }
                                else {
                                    $resultCode = 1 # Treat as error
                                }
                            }
                        }
                        elseif ($make -in ('Microsoft', 'Dell', 'HP', 'Lenovo')) {
                            # This means a specific Make case was hit, but $taskResult was unexpectedly null
                            $nullTaskResultMessage = "Error: Task for Make '$make' returned null."
                            WriteLog $nullTaskResultMessage
                            $resultStatus = $nullTaskResultMessage
                            $resultCode = 1
                            # $resultIdentifier is already set
                        }
                        # If it was an unsupported Make, $resultStatus and $resultCode are already set from the 'default' case.
                    }
                    Default {
                        # This handles unknown $localTaskType values
                        $resultStatus = "Error: Task type '$localTaskType' not recognized"
                        $resultCode = 1
                        if ($currentItem -is [pscustomobject] -and $currentItem.PSObject.Properties.Name -match $using:IdentifierProperty) {
                            $resultIdentifier = $currentItem.$($using:IdentifierProperty)
                        }
                        else {
                            $resultIdentifier = "UnknownItem"
                        }
                        WriteLog "Error in parallel job: Unknown TaskType '$localTaskType' provided for item '$resultIdentifier'."
                    }
                }
            }
            catch {
                # Catch errors within the parallel task execution
                $resultStatus = "Error: $($_.Exception.Message)"
                $resultCode = 1
                # Try to get an identifier
                if ($currentItem -is [pscustomobject] -and $currentItem.PSObject.Properties.Name -match $using:IdentifierProperty) {
                    $resultIdentifier = $currentItem.$($using:IdentifierProperty)
                }
                else {
                    $resultIdentifier = "UnknownItemOnError"
                }
                WriteLog "Exception during parallel task '$localTaskType' for item '$resultIdentifier': $($_.Exception.ToString())"
                # Enqueue the error status from the catch block
                $localProgressQueue.Enqueue(@{ Identifier = $resultIdentifier; Status = $resultStatus })
            }

            $driverPathValue = $null
            if ($null -ne $taskResult -and $taskResult.PSObject.Properties.Name -contains 'DriverPath') {
                $driverPathValue = $taskResult.DriverPath
            }

            # Return a consistent hashtable structure (final result)
            return @{
                Identifier = $resultIdentifier
                Status     = $resultStatus # Return the final status
                ResultCode = $resultCode
                DriverPath = $driverPathValue
            }

        } -ThrottleLimit $ThrottleLimit -AsJob
    }
    catch {
        # Catch errors during the *creation* of the parallel jobs (e.g., module loading in main thread failed)
        WriteLog "Error initiating ForEach-Object -Parallel: $($_.Exception.Message)"
        # Update all items to show a general startup error
        $errorStatus = "$ErrorStatusPrefix Failed to start processing"
        foreach ($item in $ItemsToProcess) {
            $identifier = $item.$IdentifierProperty
            $WindowObject.Dispatcher.Invoke([System.Windows.Threading.DispatcherPriority]::Background, [Action] { # Use $WindowObject
                    Update-ListViewItemStatus -WindowObject $WindowObject -ListView $ListViewControl -IdentifierProperty $IdentifierProperty -IdentifierValue $identifier -StatusProperty $StatusProperty -StatusValue $errorStatus # Pass $WindowObject
                })
        }
        # Exit the function as processing cannot proceed
        return
    }

    # Check if any jobs failed to start immediately (e.g., module loading issues within the job)
    $failedJobs = $jobs | Where-Object { $_.State -eq 'Failed' -and $_.JobStateInfo.Reason }
    foreach ($failedJob in $failedJobs) {
        WriteLog "Job $($failedJob.Id) failed to start or failed early: $($failedJob.JobStateInfo.Reason)"
        # We don't easily know which item failed here without more complex mapping
        # Update overall status maybe?
        $processedCount++
    }
    # Filter out jobs that failed immediately
    $jobs = $jobs | Where-Object { $_.State -ne 'Failed' }

    # Process job results and intermediate status updates without blocking the UI thread
    while ($jobs.Count -gt 0 -or -not $progressQueue.IsEmpty) {
        # Continue while jobs are running OR queue has messages

        # 1. Process intermediate status updates from the queue
        $statusUpdate = $null
        while ($progressQueue.TryDequeue([ref]$statusUpdate)) {
            if ($null -ne $statusUpdate) {
                WriteLog "Dequeued progress update: $($statusUpdate | ConvertTo-Json -Compress)"
                $intermediateIdentifier = $statusUpdate.Identifier
                # If this item has already been marked as complete, skip this stale intermediate update
                if ($completedIdentifiers.Contains($intermediateIdentifier)) {
                    WriteLog "Skipping stale intermediate status for already completed item: $intermediateIdentifier"
                    continue
                }
                $intermediateStatus = $statusUpdate.Status
                if ($isUiMode) {
                    # Use the new $isUiMode flag
                    # Update the UI with the intermediate status
                    try {
                        WriteLog "Dispatching INTERMEDIATE status for '$intermediateIdentifier': '$intermediateStatus'"
                        $WindowObject.Dispatcher.Invoke([System.Windows.Threading.DispatcherPriority]::Background, [Action] {
                                Update-ListViewItemStatus -WindowObject $WindowObject -ListView $ListViewControl -IdentifierProperty $IdentifierProperty -IdentifierValue $intermediateIdentifier -StatusProperty $StatusProperty -StatusValue $intermediateStatus
                            })
                    }
                    catch {
                        WriteLog "Error setting intermediate status for item '$intermediateIdentifier': $($_.Exception.Message)"
                    }
                }
                else {
                    # Log intermediate status if not in UI mode
                    WriteLog "Intermediate Status for '$intermediateIdentifier': $intermediateStatus"
                }
            }
        }

        # 2. Check for completed jobs
        $completedJobs = $jobs | Where-Object { $_.State -in 'Completed', 'Failed', 'Stopped' }

        if ($completedJobs) {
            foreach ($completedJob in $completedJobs) {
                $jobHandled = $false
                if ($completedJob.State -eq 'Failed') {
                    $jobHandled = $true
                    $finalIdentifier = "UnknownJob" # Placeholder
                    WriteLog "Job $($completedJob.Id) failed: $($completedJob.Error)"
                    $finalStatus = "$ErrorStatusPrefix Job Failed"
                    $finalResultCode = 1
                    $processedCount++
                    
                    # --- DISPATCH FOR FAILED JOB ---
                    $completedIdentifiers.Add($finalIdentifier) | Out-Null
                    if ($isUiMode) {
                        try {
                            WriteLog "Dispatching FINAL status for '$finalIdentifier': '$finalStatus'"
                            $WindowObject.Dispatcher.Invoke([System.Windows.Threading.DispatcherPriority]::Background, [Action] { Update-ListViewItemStatus -WindowObject $WindowObject -ListView $ListViewControl -IdentifierProperty $IdentifierProperty -IdentifierValue $finalIdentifier -StatusProperty $StatusProperty -StatusValue $finalStatus })
                            $WindowObject.Dispatcher.Invoke([System.Windows.Threading.DispatcherPriority]::Background, [Action] { Update-OverallProgress -WindowObject $WindowObject -CompletedCount $processedCount -TotalCount $totalItems -StatusText "Processed $processedCount of $totalItems..." -ProgressBarName "progressBar" -StatusLabelName "txtStatus" })
                        }
                        catch { WriteLog "Error setting FINAL status for item '$finalIdentifier': $($_.Exception.Message)" }
                    }
                    else { WriteLog "Final Status for '$finalIdentifier': $finalStatus (ResultCode: $finalResultCode)" }
                }
                elseif ($completedJob.HasMoreData) {
                    $jobHandled = $true
                    $jobResults = $completedJob | Receive-Job
                    foreach ($result in $jobResults) {
                        WriteLog "Received FINAL job result: $($result | ConvertTo-Json -Compress -Depth 3)"
                        if ($null -ne $result -and $result -is [hashtable] -and $result.ContainsKey('Identifier')) {
                            $finalIdentifier = $result.Identifier
                            $status = $result.Status
                            $finalResultCode = $result.ResultCode
                            $finalStatus = if ($finalResultCode -eq 0) { $status } else { "$($ErrorStatusPrefix)$($status)" }
                            $processedCount++
                        }
                        else {
                            $finalIdentifier = "UnknownResult"
                            WriteLog "Warning: Received unexpected final job result format: $($result | Out-String)"
                            $finalStatus = "$ErrorStatusPrefix Invalid Result Format"
                            $finalResultCode = 1
                            $processedCount++
                        }
                        if ($null -ne $result) { $resultsCollection.Add($result) }

                        # --- DISPATCH PER RESULT ---
                        $completedIdentifiers.Add($finalIdentifier) | Out-Null
                        if ($isUiMode) {
                            try {
                                WriteLog "Dispatching FINAL status for '$finalIdentifier': '$finalStatus'"
                                $WindowObject.Dispatcher.Invoke([System.Windows.Threading.DispatcherPriority]::Background, [Action] { Update-ListViewItemStatus -WindowObject $WindowObject -ListView $ListViewControl -IdentifierProperty $IdentifierProperty -IdentifierValue $finalIdentifier -StatusProperty $StatusProperty -StatusValue $finalStatus })
                                $WindowObject.Dispatcher.Invoke([System.Windows.Threading.DispatcherPriority]::Background, [Action] { Update-OverallProgress -WindowObject $WindowObject -CompletedCount $processedCount -TotalCount $totalItems -StatusText "Processed $processedCount of $totalItems..." -ProgressBarName "progressBar" -StatusLabelName "txtStatus" })
                            }
                            catch { WriteLog "Error setting FINAL status for item '$finalIdentifier': $($_.Exception.Message)" }
                        }
                        else { WriteLog "Final Status for '$finalIdentifier': $finalStatus (ResultCode: $finalResultCode)" }
                    }
                }
                
                if (-not $jobHandled) {
                    # Catches 'Completed' with no data
                    $finalIdentifier = "UnknownJob"
                    WriteLog "Job $($completedJob.Id) completed with state '$($completedJob.State)' but had no data."
                    $finalStatus = "$ErrorStatusPrefix No Result Data"
                    $finalResultCode = 1
                    $processedCount++

                    # --- DISPATCH FOR NO-DATA JOB ---
                    $completedIdentifiers.Add($finalIdentifier) | Out-Null
                    if ($isUiMode) {
                        try {
                            WriteLog "Dispatching FINAL status for '$finalIdentifier': '$finalStatus'"
                            $WindowObject.Dispatcher.Invoke([System.Windows.Threading.DispatcherPriority]::Background, [Action] { Update-ListViewItemStatus -WindowObject $WindowObject -ListView $ListViewControl -IdentifierProperty $IdentifierProperty -IdentifierValue $finalIdentifier -StatusProperty $StatusProperty -StatusValue $finalStatus })
                            $WindowObject.Dispatcher.Invoke([System.Windows.Threading.DispatcherPriority]::Background, [Action] { Update-OverallProgress -WindowObject $WindowObject -CompletedCount $processedCount -TotalCount $totalItems -StatusText "Processed $processedCount of $totalItems..." -ProgressBarName "progressBar" -StatusLabelName "txtStatus" })
                        }
                        catch { WriteLog "Error setting FINAL status for item '$finalIdentifier': $($_.Exception.Message)" }
                    }
                    else { WriteLog "Final Status for '$finalIdentifier': $finalStatus (ResultCode: $finalResultCode)" }
                }

                # Remove the completed/failed job from the list and clean it up
                $jobs = $jobs | Where-Object { $_.Id -ne $completedJob.Id }
                Remove-Job -Job $completedJob -Force -ErrorAction SilentlyContinue
            } # End foreach completedJob
        } # End if ($completedJobs)

        # 3. Allow UI events to process and sleep briefly
        if ($isUiMode) {
            # Use the new $isUiMode flag
            # Only sleep if jobs are still running AND the queue is empty (to avoid delaying UI updates)
            if ($jobs.Count -gt 0 -and $progressQueue.IsEmpty) {
                $WindowObject.Dispatcher.Invoke([System.Windows.Threading.DispatcherPriority]::Background, [action] { }) | Out-Null 
                Start-Sleep -Milliseconds 100
            }
            elseif (-not $progressQueue.IsEmpty) {
                # If queue has messages, process them immediately without sleeping
                $WindowObject.Dispatcher.Invoke([System.Windows.Threading.DispatcherPriority]::Background, [action] { }) | Out-Null 
            }
        }
        else {
            # Non-UI mode, just sleep if jobs are running
            if ($jobs.Count -gt 0) {
                Start-Sleep -Milliseconds 100
            }
        }
        # If jobs are done AND queue is empty, the loop condition will terminate

    } # End while ($jobs.Count -gt 0 -or -not $progressQueue.IsEmpty)

    # Final cleanup of any remaining jobs (shouldn't be necessary with this loop logic, but good practice)
    if ($jobs.Count -gt 0) {
        WriteLog "Cleaning up $($jobs.Count) remaining jobs after loop exit."
        Remove-Job -Job $jobs -Force -ErrorAction SilentlyContinue
    }

    if ($isUiMode) {
        # Use the new $isUiMode flag
        WriteLog "Invoke-ParallelProcessing finished for ListView '$($ListViewControl.Name)'."
        # Final overall progress update
        $WindowObject.Dispatcher.Invoke([System.Windows.Threading.DispatcherPriority]::Background, [Action] { 
                Update-OverallProgress -WindowObject $WindowObject -CompletedCount $processedCount -TotalCount $totalItems -StatusText "Processing complete. Processed $processedCount of $totalItems." -ProgressBarName "progressBar" -StatusLabelName "txtStatus" 
            })
    }
    else {
        WriteLog "Invoke-ParallelProcessing finished (non-UI mode). Processed $processedCount of $totalItems."
    }
        
    # Return all collected final results from jobs
    return $resultsCollection
}

Export-ModuleMember -Function Invoke-ParallelProcessing