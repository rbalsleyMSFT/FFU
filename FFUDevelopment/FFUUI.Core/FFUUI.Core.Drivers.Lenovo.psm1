<#
.SYNOPSIS
    Provides functions for discovering, downloading, and processing Lenovo drivers.
.DESCRIPTION
    This module queries Lenovo PSREF for models and runs the shared Lenovo driver-selection pipeline. Windows 11 downloads combine the model's Windows 10 and Windows 11 catalogs and inspect INF coverage before publication. The UI task handles existing downloads, progress, model completion, and optional WIM compression.
#>

# Function to get the list of Lenovo models using the PSREF API
function Get-LenovoDriversModelList {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true)]
		[string]$ModelSearchTerm,
		[Parameter(Mandatory = $true)]
		[hashtable]$Headers,
		[Parameter(Mandatory = $true)]
		[string]$UserAgent
	)

	$models = @(Get-LenovoPSREFModels -ModelSearchTerm $ModelSearchTerm -Headers $Headers -UserAgent $UserAgent)
	foreach ($model in $models) {
		[pscustomobject]@{
			Make        = 'Lenovo'
			Model       = "$($model.ProductName) ($($model.MachineType))"
			ProductName = $model.ProductName
			MachineType = $model.MachineType
		}
	}
}
# Function to download and extract drivers for a specific Lenovo model (Background Task)
function Save-LenovoDriversTask {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$DriverItemData, # Contains Model (ProductName) and MachineType
        [Parameter(Mandatory = $true)]
        [string]$DriversFolder,
        [Parameter(Mandatory = $true)]
        [int]$WindowsRelease,
		[Parameter(Mandatory = $true)]
		[ValidateSet('x64', 'x86', 'ARM64')]
		[string]$WindowsArch,
		[string]$WindowsVersion,
        [Parameter(Mandatory = $true)]
        [hashtable]$Headers,
        [Parameter(Mandatory = $true)]
        [string]$UserAgent,
        [Parameter()]
        [System.Collections.Concurrent.ConcurrentQueue[hashtable]]$ProgressQueue = $null,
        [Parameter()]
        [bool]$CompressToWim = $false,
        [Parameter()]
        [bool]$PreserveSourceOnCompress = $false,
		[pscustomobject]$DriverOperationContext
    )
            
    # The Model property from the UI already contains the combined "ProductName (MachineType)" string
    $identifier = $DriverItemData.Model
    $machineType = $DriverItemData.MachineType 
    $make = "Lenovo"
    $sanitizedIdentifier = ConvertTo-SafeName -Name $identifier
    if ($sanitizedIdentifier -ne $identifier) { WriteLog "Sanitized model identifier: '$identifier' -> '$sanitizedIdentifier'" }
    $status = "Starting..."
    $success = $false
	$failedDrivers = [Collections.Generic.List[object]]::new()
    
    # Define paths
    $makeDriversPath = Join-Path -Path $DriversFolder -ChildPath $Make
    # Use the identifier (which contains the model name and machine type) and sanitize it for the path
    $modelPath = Join-Path -Path $makeDriversPath -ChildPath $sanitizedIdentifier
    $driverRelativePath = Join-Path -Path $make -ChildPath $sanitizedIdentifier # Relative path for the driver folder
    
    if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $identifier -Status "Checking..." }
    
	$modelMutex = $null
	$modelExisted = $true
    try {
		$ignoreErrors = Get-DriverIgnoreDownloadErrors -DriverItem $DriverItemData
		$modelMutex = Get-DriverPublicationMutex -FinalPath $modelPath -Context $DriverOperationContext
		$modelExisted = Test-Path -LiteralPath $modelPath
		$retryModel = Test-DriverModelIncomplete -ModelPath $modelPath
        $existingDriver = Test-ExistingDriver -Make $make -Model $sanitizedIdentifier -DriversFolder $DriversFolder -Identifier $identifier -ProgressQueue $ProgressQueue
        if ($null -ne $existingDriver) {
            # The return object from Test-ExistingDriver uses 'Model' as the identifier key.
            # We need to return 'Identifier' for Lenovo's logic.
            $existingDriver | Add-Member -MemberType NoteProperty -Name 'Identifier' -Value $identifier -Force
            $existingDriver.PSObject.Properties.Remove('Model')

            # Special handling for existing folders that need compression
            if ($CompressToWim -and $existingDriver.Status -eq 'Already downloaded') {
                $wimFilePath = Join-Path -Path $makeDriversPath -ChildPath "$($sanitizedIdentifier).wim"
                $wimRelativePath = Join-Path -Path $make -ChildPath "$($sanitizedIdentifier).wim"
                $sourceFolderPath = Join-Path -Path $makeDriversPath -ChildPath $sanitizedIdentifier
                WriteLog "Attempting compression of existing folder '$sourceFolderPath' to '$wimFilePath'."
                if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $identifier -Status "Compressing existing..." }
                try {
					if (-not (Compress-DriverFolderToWim -SourceFolderPath $sourceFolderPath -DestinationWimPath $wimFilePath -WimName $identifier -WimDescription "Drivers for $identifier" -PreserveSource:$PreserveSourceOnCompress -ErrorAction Stop)) { throw 'Driver folder compression failed. See the FFU log.' }
                    $existingDriver.Status = "Compression successful"
                    $existingDriver.DriverPath = $wimRelativePath
                    $existingDriver.Success = $true
                    WriteLog "Successfully compressed existing drivers for $identifier to $wimFilePath."
                }
                catch {
                    WriteLog "Error compressing existing drivers for $($identifier): $($_.Exception.Message)"
                    $existingDriver.Status = "Already downloaded (Compression failed)"
                    $existingDriver.Success = $false
                }
                if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $identifier -Status $existingDriver.Status }
            }

            return $existingDriver
        }

        # Ensure base directories exist
		Set-DriverModelDownloadState -ModelPath $modelPath -State Incomplete -Context $DriverOperationContext
        if (-not (Test-Path -Path $makeDriversPath)) { New-Item -Path $makeDriversPath -ItemType Directory -Force | Out-Null }
        if (-not (Test-Path -Path $modelPath)) { New-Item -Path $modelPath -ItemType Directory -Force | Out-Null }
		$status = 'Selecting drivers...'
		if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $identifier -Status $status }
		$null = Save-LenovoDriverPackages -MachineType $machineType -ModelPath $modelPath -DriversFolder $makeDriversPath `
			-WindowsRelease $WindowsRelease -WindowsArch $WindowsArch -WindowsVersion $WindowsVersion `
			-Identifier $identifier -DriverOperationContext $DriverOperationContext -ProgressQueue $ProgressQueue `
			-RetryIncomplete:$retryModel -RenameLiteonFolders -IgnoreDriverDownloadErrors $ignoreErrors -FailedDrivers $failedDrivers
		Set-DriverModelDownloadState -ModelPath $modelPath -State Complete -Context $DriverOperationContext
        
        # --- Compress to WIM if requested (after all drivers processed) ---
        if ($CompressToWim) {
            $status = "Compressing..."
            if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $identifier -Status $status }
            $wimFileName = "$($sanitizedIdentifier).wim" # Use sanitized identifier for filename
            $destinationWimPath = Join-Path -Path $makeDriversPath -ChildPath $wimFileName
            WriteLog "Compressing '$modelPath' to '$destinationWimPath'..."
            try {
                $compressResult = Compress-DriverFolderToWim -SourceFolderPath $modelPath -DestinationWimPath $destinationWimPath -WimName $identifier -WimDescription $identifier -PreserveSource:$PreserveSourceOnCompress -ErrorAction Stop
                if ($compressResult) {
					$driverRelativePath = Join-Path -Path $make -ChildPath $wimFileName
                    WriteLog "Compression successful for '$identifier'."
                    $status = "Completed & Compressed"
                }
                else {
                    WriteLog "Compression failed for '$identifier'. Check verbose/error output from Compress-DriverFolderToWim."
                    $status = "Completed (Compression Failed)"
                }
            }
            catch {
                WriteLog "Error during compression for '$identifier': $($_.Exception.Message)"
                $status = "Completed (Compression Error)"
            }
        }
        else {
            $status = "Completed" 
        }
        # --- End Compression ---
		if ($failedDrivers.Count -gt 0) { $status += " with warnings ($($failedDrivers.Count) skipped)" }
        
        $success = $true # Mark success as download/extract was okay
        
    }
    catch {
        $status = "Error: $($_.Exception.Message)"
        WriteLog "Error saving Lenovo drivers for '$identifier': $($_.Exception.ToString())"
        $success = $false
		if (-not $modelExisted) { Remove-DriverModelFolder -DriversFolder $DriversFolder -TargetFolder $modelPath -Description $identifier }
        if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $identifier -Status $status }
        return [PSCustomObject]@{ Identifier = $identifier; Status = $status; Success = $success; DriverPath = $null; FailedDrivers = $failedDrivers.ToArray() }
    }
    finally {
		if ($null -ne $modelMutex) { $modelMutex.ReleaseMutex(); $modelMutex.Dispose() }
    }

    # Enqueue the final status (success or error) before returning
    if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $identifier -Status $status }

    # Return the final status
    return [PSCustomObject]@{ Identifier = $identifier; Status = $status; Success = $success; DriverPath = $driverRelativePath; FailedDrivers = $failedDrivers.ToArray() }
}

Export-ModuleMember -Function *