<#
.SYNOPSIS
    Provides functions for discovering, downloading, and processing Microsoft Surface device drivers.
.DESCRIPTION
    This module contains the logic specific to handling Microsoft Surface drivers for the FFU UI. It includes a function to scrape the official Microsoft support website to build a list of available Surface models and their driver download pages. It also provides a robust, parallel-capable function to download the correct driver package (MSI or ZIP) based on the selected Windows release, extract its contents, and optionally compress them into a WIM archive. The download process includes logic to handle MSI installer mutexes to prevent conflicts during parallel execution.
#>

# Function to get the list of Microsoft Surface models
function Get-MicrosoftDriversModelList {
    [CmdletBinding()]
    param(
        [hashtable]$Headers, # Pass necessary headers
        [string]$UserAgent # Pass UserAgent
    )

    $url = "https://support.microsoft.com/en-us/surface/download-drivers-and-firmware-for-surface-09bb2e09-2a4b-cb69-0951-078a7739e120"
    $models = @()

    try {
        WriteLog "Getting Surface driver information from $url"
        $OriginalVerbosePreference = $VerbosePreference
        $VerbosePreference = 'SilentlyContinue'
        # Use passed-in UserAgent and Headers
        $webContent = Invoke-WebRequest -Uri $url -UseBasicParsing -Headers $Headers -UserAgent $UserAgent
        $VerbosePreference = $OriginalVerbosePreference
        WriteLog "Complete"

        WriteLog "Parsing web content for models and download links"
        $html = $webContent.Content
        $divPattern = '<div[^>]*class="selectable-content-options__option-content(?: ocHidden)?"[^>]*>(.*?)</div>'
        $divMatches = [regex]::Matches($html, $divPattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)

        foreach ($divMatch in $divMatches) {
            $divContent = $divMatch.Groups[1].Value
            $tablePattern = '<table[^>]*>(.*?)</table>'
            $tableMatches = [regex]::Matches($divContent, $tablePattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)

            foreach ($tableMatch in $tableMatches) {
                $tableContent = $tableMatch.Groups[1].Value
                $rowPattern = '<tr[^>]*>(.*?)</tr>'
                $rowMatches = [regex]::Matches($tableContent, $rowPattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)

                foreach ($rowMatch in $rowMatches) {
                    $rowContent = $rowMatch.Groups[1].Value
                    $cellPattern = '<td[^>]*>\s*(?:<p[^>]*>)?(.*?)(?:</p>)?\s*</td>'
                    $cellMatches = [regex]::Matches($rowContent, $cellPattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)

                    if ($cellMatches.Count -ge 2) {
                        $modelName = ([System.Net.WebUtility]::HtmlDecode(($cellMatches[0].Groups[1].Value).Trim()))
                        $secondTdContent = $cellMatches[1].Groups[1].Value.Trim()
                        # $linkPattern = '<a[^>]+href="([^"]+)"[^>]*>'
                        # Change linkPattern to match https://www.microsoft.com/download/details.aspx?id=
                        $linkPattern = '<a[^>]+href="(https://www\.microsoft\.com/download/details\.aspx\?id=\d+)"[^>]*>'
                        $linkMatch = [regex]::Match($secondTdContent, $linkPattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

                        if ($linkMatch.Success) {
                            $modelLink = $linkMatch.Groups[1].Value
                        }
                        else {
                            continue
                        }

                        $models += [PSCustomObject]@{
                            Make  = 'Microsoft'
                            Model = $modelName
                            Link  = $modelLink
                        }
                    }
                }
            }
        }
        WriteLog "Parsing complete. Found $($models.Count) models."
        return $models
    }
    catch {
        WriteLog "Error getting Microsoft models: $($_.Exception.Message)"
        throw "Failed to retrieve Microsoft Surface models."
    }
}
# Function to download and extract drivers for a specific Microsoft model (Modified for ForEach-Object -Parallel)
function Save-MicrosoftDriversTask {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$DriverItemData, # Pass data, not the UI object
        [Parameter(Mandatory = $true)]
        [string]$DriversFolder,
        [Parameter(Mandatory = $true)]
        [int]$WindowsRelease,
        [Parameter(Mandatory = $true)]
        [hashtable]$Headers, # Pass necessary headers
        [Parameter(Mandatory = $true)]
        [string]$UserAgent, # Pass UserAgent
        [Parameter()] # Made optional
        [System.Collections.Concurrent.ConcurrentQueue[hashtable]]$ProgressQueue = $null, # Default to null
        [Parameter()]
        [bool]$CompressToWim = $false, # New parameter for compression
        [Parameter()]
        [bool]$PreserveSourceOnCompress = $false
        # REMOVED: UI-related parameters
    )
        
    $modelName = $DriverItemData.Model
    $modelLink = $DriverItemData.Link
    $make = $DriverItemData.Make
    $driverRelativePath = Join-Path -Path $make -ChildPath $modelName # Relative path for the driver folder
    $status = "Getting download link..." # Initial local status
    $success = $false
    
    # Initial status update
    if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $modelName -Status "Checking..." }
    
    try {
        # Check for existing drivers
        $existingDriver = Test-ExistingDriver -Make $make -Model $modelName -DriversFolder $DriversFolder -Identifier $modelName -ProgressQueue $ProgressQueue
        if ($null -ne $existingDriver) {
            # Add the 'Model' property to the return object for consistency if it's not there
            if (-not $existingDriver.PSObject.Properties['Model']) {
                $existingDriver | Add-Member -MemberType NoteProperty -Name 'Model' -Value $modelName
            }

            # Special handling for existing folders that need compression
            if ($CompressToWim -and $existingDriver.Status -eq 'Already downloaded') {
                $makeDriversPath = Join-Path -Path $DriversFolder -ChildPath $make
                $wimFilePath = Join-Path -Path $makeDriversPath -ChildPath "$($modelName).wim"
                $wimRelativePath = Join-Path -Path $make -ChildPath "$($modelName).wim"
                $sourceFolderPath = Join-Path -Path $makeDriversPath -ChildPath $modelName
                WriteLog "Attempting compression of existing folder '$sourceFolderPath' to '$wimFilePath'."
                if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $modelName -Status "Compressing existing..." }
                try {
                    $null = Compress-DriverFolderToWim -SourceFolderPath $sourceFolderPath -DestinationWimPath $wimFilePath -WimName $modelName -WimDescription "Drivers for $modelName" -PreserveSource:$PreserveSourceOnCompress -ErrorAction Stop
                    $existingDriver.Status = "Compression successful"
                    $existingDriver.DriverPath = $wimRelativePath
                    $existingDriver.Success = $true
                    WriteLog "Successfully compressed existing drivers for $modelName to $wimFilePath."
                }
                catch {
                    WriteLog "Error compressing existing drivers for $($modelName): $($_.Exception.Message)"
                    $existingDriver.Status = "Already downloaded (Compression failed)"
                    $existingDriver.Success = $false
                }
                if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $modelName -Status $existingDriver.Status }
            }

            return $existingDriver
        }

        ### GET THE DOWNLOAD LINK
        $status = "Getting download link..."
        if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $modelName -Status $status }
        WriteLog "Getting download page content for $modelName from $modelLink"
        $OriginalVerbosePreference = $VerbosePreference
        $VerbosePreference = 'SilentlyContinue'
        # Use passed-in UserAgent and Headers
        $downloadPageContent = Invoke-WebRequest -Uri $modelLink -UseBasicParsing -Headers $Headers -UserAgent $UserAgent
        $VerbosePreference = $OriginalVerbosePreference
        WriteLog "Complete"

        $status = "Parsing download page..."
        if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $modelName -Status $status }
        WriteLog "Parsing download page for file"
        $scriptPattern = '<script>window.__DLCDetails__={(.*?)}<\/script>'
        $scriptMatch = [regex]::Match($downloadPageContent.Content, $scriptPattern)

        if ($scriptMatch.Success) {
            $scriptContent = $scriptMatch.Groups[1].Value
            # $downloadFilePattern = '"name":"(.*?)",.*?"url":"(.*?)"'
            $downloadFilePattern = '"name":"([^"]+\.(?:msi|zip))",[^}]*?"url":"(.*?)"'
            $downloadFileMatches = [regex]::Matches($scriptContent, $downloadFilePattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)


            $win10Link = $null
            $win10FileName = $null
            $win11Link = $null
            $win11FileName = $null

            # Iterate through all matches to find potential Win10 and Win11 links
            foreach ($downloadFile in $downloadFileMatches) {
                $currentFileName = $downloadFile.Groups[1].Value
                $fileUrl = $downloadFile.Groups[2].Value

                if ($currentFileName -match "Win10") {
                    $win10Link = $fileUrl
                    $win10FileName = $currentFileName
                    WriteLog "Found Win10 link: $win10FileName"
                }
                elseif ($currentFileName -match "Win11") {
                    $win11Link = $fileUrl
                    $win11FileName = $currentFileName
                    WriteLog "Found Win11 link: $win11FileName"
                }
            }

            # Decision logic to select the appropriate download link
            $downloadLink = $null
            $fileName = $null
            $downloadedVersion = $null # Track which version we are actually downloading

            if ($WindowsRelease -eq 10 -and $win10Link) {
                $downloadLink = $win10Link
                $fileName = $win10FileName
                $downloadedVersion = 10
                WriteLog "Exact match found for Win10."
            }
            elseif ($WindowsRelease -eq 11 -and $win11Link) {
                $downloadLink = $win11Link
                $fileName = $win11FileName
                $downloadedVersion = 11
                WriteLog "Exact match found for Win11."
            }
            elseif (-not $win10Link -and $win11Link) {
                # Only Win11 available, regardless of $WindowsRelease
                $downloadLink = $win11Link
                $fileName = $win11FileName
                $downloadedVersion = 11
                WriteLog "Exact match for Win$($WindowsRelease) not found. Falling back to available Win11 driver."
            }
            elseif ($win10Link -and -not $win11Link) {
                # Only Win10 available, regardless of $WindowsRelease
                $downloadLink = $win10Link
                $fileName = $win10FileName
                $downloadedVersion = 10
                WriteLog "Exact match for Win$($WindowsRelease) not found. Falling back to available Win10 driver."
            }
            # If both Win10 and Win11 links exist, but neither matches $WindowsRelease, $downloadLink remains $null.

            ### DOWNLOAD AND EXTRACT
            if ($downloadLink) {
                WriteLog "Selected Download Link for $modelName (Actual: Windows $downloadedVersion): $downloadLink"
                $status = "Downloading Win$downloadedVersion $fileName"
                if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $modelName -Status $status }

                # Create directories
                if (-not (Test-Path -Path $DriversFolder)) {
                    WriteLog "Creating Drivers folder: $DriversFolder"
                    New-Item -Path $DriversFolder -ItemType Directory -Force | Out-Null
                }
                $sanitizedModelName = ConvertTo-SafeName -Name $modelName
                if ($sanitizedModelName -ne $modelName) { WriteLog "Sanitized model name: '$modelName' -> '$sanitizedModelName'" }
                $makeDriversPath = Join-Path -Path $DriversFolder -ChildPath $Make
                $modelPath = Join-Path -Path $makeDriversPath -ChildPath $sanitizedModelName
                if (-Not (Test-Path -Path $modelPath)) {
                    WriteLog "Creating model folder: $modelPath"
                    New-Item -Path $modelPath -ItemType Directory -Force | Out-Null
                }
                else {
                    WriteLog "Model folder already exists: $modelPath"
                }

                ### DOWNLOAD
                $filePath = Join-Path -Path $makeDriversPath -ChildPath ($fileName)
                WriteLog "Downloading $modelName driver file to $filePath"
                # Use Start-BitsTransferWithRetry
                Start-BitsTransferWithRetry -Source $downloadLink -Destination $filePath
                WriteLog "Download complete"

                $fileExtension = [System.IO.Path]::GetExtension($filePath).ToLower()

                ### EXTRACT
                if ($fileExtension -eq ".msi") {
                    $status = "Waiting for MSI lock..."
                    if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $modelName -Status $status }

                    # Use a named mutex to ensure only one MSI extraction happens at a time across all parallel tasks
                    $msiMutexName = "Global\FFUDevelopmentMSIExtractionMutex"
                    $msiMutex = New-Object System.Threading.Mutex($false, $msiMutexName)

                    try {
                        WriteLog "Waiting to acquire global MSI extraction lock for '$modelName'..."
                        $msiMutex.WaitOne() | Out-Null
                        WriteLog "Acquired global MSI extraction lock for '$modelName'."

                        # Loop indefinitely to wait for system mutex and handle MSIExec exit codes
                        while ($true) {
                            $mutexClear = $false

                            # 1. Check System-level MSI Mutex
                            try {
                                $sysMutex = [System.Threading.Mutex]::OpenExisting("Global\_MSIExecute")
                                $sysMutex.Dispose()
                                $status = "Waiting for MSIExec..."
                                if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $modelName -Status $status }
                                WriteLog "Another MSIExec installer is running (System Mutex Held). Waiting 5 seconds before rechecking for $modelName..."
                                Start-Sleep -Seconds 5
                                continue # Go back to start of while loop to re-check mutex
                            }
                            catch [System.Threading.WaitHandleCannotBeOpenedException] {
                                # Mutex is clear, proceed to extraction attempt
                                WriteLog "System MSI mutex clear. Proceeding with MSI extraction attempt for $modelName."
                                $status = "Extracting Win$downloadedVersion $fileName"
                                if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $modelName -Status $status }
                                $mutexClear = $true
                            }
                            catch {
                                # Handle other potential errors when checking the mutex
                                WriteLog "Warning: Error checking system MSI mutex for $($modelName): $_. Proceeding with caution."
                                $status = "Extracting Win$downloadedVersion $fileName (Mutex Error)"
                                if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $modelName -Status $status }
                                $mutexClear = $true # Proceed despite mutex error
                            }

                            # 2. Attempt Extraction (only if mutex was clear)
                            if ($mutexClear) {
                                WriteLog "Extracting MSI file to $modelPath"
                                $arguments = "/a `"$($filePath)`" /qn TARGETDIR=`"$($modelPath)`""
                                try {
                                    # Use Invoke-Process. It will throw an error for any non-zero exit code.
                                    Invoke-Process -FilePath "msiexec.exe" -ArgumentList $arguments -Wait $true -ErrorAction Stop | Out-Null
                                    
                                    # If Invoke-Process succeeded (didn't throw), extraction is complete.
                                    WriteLog "Extraction complete for $modelName (Exit Code 0)."
                                    
                                    # Verification Step: Ensure the target folder is not empty.
                                    $itemsInDest = Get-ChildItem -Path $modelPath -Recurse
                                    if ($itemsInDest.Count -eq 0) {
                                        WriteLog "VERIFICATION FAILED: MSI extraction for '$modelName' produced an empty folder. Retrying..."
                                        $status = "Retrying (Empty Folder)"
                                        if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $modelName -Status $status }
                                        Start-Sleep -Seconds 5
                                        continue # Retry the whole process
                                    }
                                    
                                    WriteLog "VERIFICATION PASSED: Target folder for '$modelName' is not empty."
                                    break # Success, exit the while loop
                                }
                                catch {
                                    # Catch errors thrown by Invoke-Process
                                    $errorMessage = $_.Exception.Message
                                    if ($errorMessage -match 'Process exited with code 1618') {
                                        # Specific handling for MSIExec busy error (1618)
                                        WriteLog "MSIExec collision detected (Exit Code 1618) for $modelName. Retrying after wait..."
                                        $status = "Waiting (MSI Collision)..."
                                        if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $modelName -Status $status }
                                        Start-Sleep -Seconds 5 # Wait before retrying
                                        continue # Go back to start of while loop to re-check mutex/retry
                                    }
                                    else {
                                        # Handle other errors from Invoke-Process (e.g., file not found, permissions, other exit codes)
                                        WriteLog "Error during MSI extraction process for $($modelName): $errorMessage"
                                        throw # Re-throw the original exception to be caught by the outer try/catch
                                    }
                                }
                            } # End if ($mutexClear)
                        } # End while ($true)
                    }
                    finally {
                        if ($null -ne $msiMutex) {
                            $msiMutex.ReleaseMutex()
                            $msiMutex.Dispose()
                            WriteLog "Released global MSI extraction lock for '$modelName'."
                        }
                    }
                }
                elseif ($fileExtension -eq ".zip") {
                    $status = "Extracting Win$downloadedVersion $fileName"
                    if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $modelName -Status $status }
                    WriteLog "Extracting ZIP file to $modelPath"
                    $ProgressPreference = 'SilentlyContinue'
                    Expand-Archive -Path $filePath -DestinationPath $modelPath -Force
                    $ProgressPreference = 'Continue'
                    WriteLog "Extraction complete"
                }
                else {
                    WriteLog "Unsupported file type: $fileExtension"
                    throw "Unsupported file type: $fileExtension"
                }
                # Remove downloaded file
                $status = "Cleaning up..."
                if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $modelName -Status $status }
                WriteLog "Removing $filePath"
                Remove-Item -Path $filePath -Force
                WriteLog "Cleanup complete." # Changed log message slightly
        
                # --- Compress to WIM if requested ---
                if ($CompressToWim) {
                    $status = "Compressing..."
                    if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $modelName -Status $status }
                    $wimFileName = "$($modelName).wim"
                    # Corrected WIM path: WIM file should be next to the model folder, not inside it.
                    $destinationWimPath = Join-Path -Path $makeDriversPath -ChildPath $wimFileName
                    $driverRelativePath = Join-Path -Path $make -ChildPath $wimFileName # Update relative path to the WIM file
                    WriteLog "Compressing '$modelPath' to '$destinationWimPath'..."
                    try {
                        # Use the function from the imported common module
                        $compressResult = Compress-DriverFolderToWim -SourceFolderPath $modelPath -DestinationWimPath $destinationWimPath -WimName $modelName -WimDescription $modelName -PreserveSource:$PreserveSourceOnCompress -ErrorAction Stop
                        if ($compressResult) {
                            WriteLog "Compression successful for '$modelName'."
                            $status = "Completed & Compressed"
                        }
                        else {
                            WriteLog "Compression failed for '$modelName'. Check verbose/error output from Compress-DriverFolderToWim."
                            $status = "Completed (Compression Failed)"
                            # Don't mark overall success as false, download/extract succeeded
                        }
                    }
                    catch {
                        WriteLog "Error during compression for '$modelName': $($_.Exception.Message)"
                        $status = "Completed (Compression Error)"
                        # Don't mark overall success as false
                    }
                }
                else {
                    $status = "Completed" # Final status if not compressing
                }
                # --- End Compression ---
        
                $success = $true # Mark success as download/extract was okay
            } # End if/elseif for .msi/.zip
            else {
                WriteLog "No suitable download link found for Windows $WindowsRelease (or fallback) for model $modelName."
                $status = "Error: No Win$($WindowsRelease)/Fallback link"
                $success = $false
            }
        }
        else {
            WriteLog "Failed to parse the download page for the driver file for model $modelName."
            $status = "Error: Parse failed"
            $success = $false
        }
    }
    catch {
        $status = "Error: $($_.Exception.Message.Split('.')[0])" # Shorten error message
        WriteLog "Error saving Microsoft drivers for $($modelName): $($_.Exception.Message)"
        $success = $false
        # Enqueue the error status before returning
        if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $modelName -Status $status }
        # Ensure return object is created even on error
        return [PSCustomObject]@{ Model = $modelName; Status = $status; Success = $success; DriverPath = $null }
    }
    
    # Enqueue the final status (success or error) before returning
    if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $modelName -Status $status }
    
    # Return the final status (this is still used by Receive-Job for final confirmation)
    return [PSCustomObject]@{ Model = $modelName; Status = $status; Success = $success; DriverPath = $driverRelativePath }
}

Export-ModuleMember -Function *