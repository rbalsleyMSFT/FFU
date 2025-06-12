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
        [string]$MainThreadLogPath = $null # New parameter for the log path
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
    $results = @() # Store results from jobs
    $totalItems = $ItemsToProcess.Count
    $processedCount = 0

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
                                # DellCatalogXmlPath might be null if catalog prep failed; Save-DellDriversTask should handle this.
                                $taskResult = Save-DellDriversTask -DriverItemData $currentItem `
                                    -DriversFolder $localJobArgs['DriversFolder'] `
                                    -WindowsArch $localJobArgs['WindowsArch'] `
                                    -WindowsRelease $localJobArgs['WindowsRelease'] `
                                    -DellCatalogXmlPath $localJobArgs['DellCatalogXmlPath'] `
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
                            if ($taskResult.PSObject.Properties.Name -contains 'Success') {
                                # Dell, Microsoft, Lenovo
                                $resultCode = if ($taskResult.Success) { 0 } else { 1 }
                            }
                            elseif ($taskResult.Status -like 'Completed*') {
                                # HP success
                                $resultCode = 0
                            }
                            elseif ($taskResult.Status -like 'Error*') {
                                # HP error
                                $resultCode = 1
                            }
                            else {
                                # Default for HP if status is unexpected, or if 'Success' property is missing but status isn't 'Completed*' or 'Error*'
                                WriteLog "Unexpected status or missing 'Success' property from task for '$taskSpecificIdentifier': $($taskResult.Status)"
                                $resultCode = 1 # Assume error
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

            # Return a consistent hashtable structure (final result)
            return @{
                Identifier = $resultIdentifier
                Status     = $resultStatus # Return the final status
                ResultCode = $resultCode
            }

        } -ThrottleLimit 5 -AsJob
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
                $intermediateIdentifier = $statusUpdate.Identifier
                $intermediateStatus = $statusUpdate.Status
                if ($isUiMode) {
                    # Use the new $isUiMode flag
                    # Update the UI with the intermediate status
                    try {
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
                $finalIdentifier = "UnknownJob" # Placeholder if we can't get result
                $finalStatus = "$ErrorStatusPrefix Job $($completedJob.Id) ended unexpectedly"
                $finalResultCode = 1 # Assume error

                if ($completedJob.State -eq 'Failed') {
                    WriteLog "Job $($completedJob.Id) failed: $($completedJob.Error)"
                    # Try to get identifier from job name if possible (less reliable)
                    # $finalIdentifier = ... logic to parse job name or map ID ...
                    $finalStatus = "$ErrorStatusPrefix Job Failed"
                    $processedCount++ # Count failed job as processed
                }
                elseif ($completedJob.HasMoreData) {
                    # Receive final results specifically from the completed job
                    $jobResults = $completedJob | Receive-Job
                    foreach ($result in $jobResults) {
                        # Should only be one result per job in this setup
                        if ($null -ne $result -and $result -is [hashtable] -and $result.ContainsKey('Identifier')) {
                            $finalIdentifier = $result.Identifier
                            $status = $result.Status # This is the FINAL status returned by the task
                            $finalResultCode = $result.ResultCode
    
                            # Determine final status text based on the result code
                            if ($finalResultCode -eq 0) {
                                # Assuming 0 means success
                                # Use the specific status returned by the successful job
                                # This handles cases like "Already downloaded" correctly
                                $finalStatus = $status
                            }
                            else {
                                $finalStatus = "$($ErrorStatusPrefix)$($status)" # Use status from result for error message
                            }
                            $processedCount++
                        }
                        else {
                            WriteLog "Warning: Received unexpected final job result format: $($result | Out-String)"
                            $finalStatus = "$ErrorStatusPrefix Invalid Result Format"
                            $processedCount++ # Count as processed to avoid loop issues
                        }
                        # Add the received result (even if format was unexpected, for logging)
                        if ($null -ne $result) { $resultsCollection.Add($result) }
                        break # Only process first result from this job
                    }
                }
                else {
                    # Job completed but had no data
                    if ($completedJob.State -ne 'Failed') {
                        WriteLog "Job $($completedJob.Id) completed with state '$($completedJob.State)' but had no data."
                        # $finalIdentifier = ... logic to parse job name or map ID ...
                        $finalStatus = "$ErrorStatusPrefix No Result Data"
                        $processedCount++
                    }
                    # If it was 'Failed', it was handled above
                }

                # Update the specific item in the ListView with its FINAL status
                if ($isUiMode) {
                    # Use the new $isUiMode flag
                    try {
                        $WindowObject.Dispatcher.Invoke([System.Windows.Threading.DispatcherPriority]::Background, [Action] { 
                                Update-ListViewItemStatus -WindowObject $WindowObject -ListView $ListViewControl -IdentifierProperty $IdentifierProperty -IdentifierValue $finalIdentifier -StatusProperty $StatusProperty -StatusValue $finalStatus 
                            })
                    }
                    catch {
                        WriteLog "Error setting FINAL status for item '$finalIdentifier': $($_.Exception.Message)"
                    }

                    # Update overall progress after processing a job's results
                    $WindowObject.Dispatcher.Invoke([System.Windows.Threading.DispatcherPriority]::Background, [Action] { 
                            Update-OverallProgress -WindowObject $WindowObject -CompletedCount $processedCount -TotalCount $totalItems -StatusText "Processed $processedCount of $totalItems..." -ProgressBarName "progressBar" -StatusLabelName "txtStatus" 
                        })
                }
                else {
                    # Log final status if not in UI mode
                    WriteLog "Final Status for '$finalIdentifier': $finalStatus (ResultCode: $finalResultCode)"
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