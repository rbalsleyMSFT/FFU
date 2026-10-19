<#
.SYNOPSIS
    Provides functions for discovering, downloading, and processing Lenovo drivers.
.DESCRIPTION
    This module contains the logic specific to handling Lenovo drivers for the FFU Builder UI. It includes functions to query the Lenovo PSREF (Product Specification Reference) API to find and list available system models based on user search terms. It also provides the core background task for downloading all relevant driver packages for a selected model and Windows release. The download process involves parsing XML catalogs, downloading individual driver executables, silently extracting their contents, and organizing them into a structured folder. The module includes robust error handling, long path mitigation by using temporary extraction locations, and an option to compress the final driver set into a WIM archive.
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
    
    # Define paths
    $makeDriversPath = Join-Path -Path $DriversFolder -ChildPath $Make
    # Use the identifier (which contains the model name and machine type) and sanitize it for the path
    $modelPath = Join-Path -Path $makeDriversPath -ChildPath $sanitizedIdentifier
    $driverRelativePath = Join-Path -Path $make -ChildPath $sanitizedIdentifier # Relative path for the driver folder
    $tempDownloadPath = Join-Path -Path $makeDriversPath -ChildPath "_TEMP_$($machineType)_$([guid]::NewGuid().ToString('N').Substring(0, 8))"
    
    if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $identifier -Status "Checking..." }
    
	$modelMutex = $null
	$modelExisted = $true
    try {
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
                    $null = Compress-DriverFolderToWim -SourceFolderPath $sourceFolderPath -DestinationWimPath $wimFilePath -WimName $identifier -WimDescription "Drivers for $identifier" -PreserveSource:$PreserveSourceOnCompress -ErrorAction Stop
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
        if (-not (Test-Path -Path $tempDownloadPath)) { New-Item -Path $tempDownloadPath -ItemType Directory -Force | Out-Null }

        # 2. Construct and Download Catalog URL
        $modelRelease = $machineType + "_Win" + $WindowsRelease
        $catalogUrl = "https://download.lenovo.com/catalog/$modelRelease.xml"
        $lenovoCatalogXML = Join-Path -Path $tempDownloadPath -ChildPath "$modelRelease.xml"

        $status = "Downloading Catalog..."
        if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $identifier -Status $status }
        WriteLog "Downloading Lenovo Driver catalog for '$identifier' from $catalogUrl"

        # Check URL accessibility first
        try {
            $request = [System.Net.WebRequest]::Create($catalogUrl); $request.Method = 'HEAD'; $response = $request.GetResponse(); $response.Close()
        }
        catch { throw "Lenovo Driver catalog URL is not accessible: $catalogUrl. Error: $($_.Exception.Message)" }

		Save-DriverCatalogFile -Source $catalogUrl -Path $lenovoCatalogXML -DriverOperationContext $DriverOperationContext
        WriteLog "Catalog download Complete: $lenovoCatalogXML"

        # 3. Parse Catalog and Process Packages
        $status = "Parsing Catalog..."
        if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $identifier -Status $status }
        [xml]$xmlContent = Get-Content -Path $lenovoCatalogXML -Encoding UTF8

        $packages = @($xmlContent.packages.package) # Ensure it's an array
        $totalPackages = $packages.Count
        $processedPackages = 0
        WriteLog "Found $totalPackages packages in catalog for '$identifier'."

        foreach ($package in $packages) {
            $processedPackages++
            $category = $package.category
            $packageUrl = $package.location # URL to the package's *XML* file

            # Skip BIOS/Firmware based on category
            if ($category -like 'BIOS*' -or $category -like 'Firmware*') {
                WriteLog "($processedPackages/$totalPackages) Skipping BIOS/Firmware package: $category"
                continue
            }

            # Sanitize category for path
            $categoryClean = $category -replace '[\\/:"*?<>|]', '_'
            if ($categoryClean -eq 'Motherboard Devices Backplanes core chipset onboard video PCIe switches') {
                $categoryClean = 'Motherboard Devices' # Shorten long category name
            }

            $packageName = [System.IO.Path]::GetFileName($packageUrl)
            $packageXMLPath = Join-Path -Path $tempDownloadPath -ChildPath $packageName
            $baseURL = $packageUrl -replace [regex]::Escape($packageName), "" # Base URL for the driver file

            # Download the package XML
            WriteLog "($processedPackages/$totalPackages) Downloading package XML: $packageUrl"
            try {
				Save-DriverCatalogFile -Source $packageUrl -Path $packageXMLPath -DriverOperationContext $DriverOperationContext
            }
            catch {
                $failureMessage = "Failed to download Lenovo package XML '$packageUrl': $($_.Exception.Message)"
                WriteLog "($processedPackages/$totalPackages) $failureMessage"
                Remove-Item -Path $packageXMLPath -Force -ErrorAction SilentlyContinue
                throw (New-Object System.Exception($failureMessage, $_.Exception))
            }

            # Load and parse the package XML
            [xml]$packageXmlContent = Get-Content -Path $packageXMLPath -Encoding UTF8
            $packageType = $packageXmlContent.Package.PackageType.type
            $packageTitleRaw = $packageXmlContent.Package.title.InnerText

            # Filter out non-driver packages (Type 2 = Driver)
            if ($packageType -ne 2) {
                WriteLog "($processedPackages/$totalPackages) Skipping package '$packageTitleRaw' (Type: $packageType) - Not a driver."
                Remove-Item -Path $packageXMLPath -Force -ErrorAction SilentlyContinue # Clean up package XML
                continue
            }

            # Sanitize title for folder name
            $packageTitle = $packageTitleRaw -replace '[\\/:"*?<>|]', '_' -replace ' - .*', ''

            # Extract driver file name and extract command
            $driverFileName = $null
            $extractCommand = $null
            try {
                $driverFileName = $packageXmlContent.Package.Files.Installer.File.Name
                $extractCommand = $packageXmlContent.Package.ExtractCommand
            }
            catch {
                WriteLog "($processedPackages/$totalPackages) Error parsing package XML '$packageXMLPath' for file name/command. Skipping. Error: $($_.Exception.Message)"
                Remove-Item -Path $packageXMLPath -Force -ErrorAction SilentlyContinue
                continue
            }


            # Skip if essential info is missing
            if ([string]::IsNullOrWhiteSpace($driverFileName) -or [string]::IsNullOrWhiteSpace($extractCommand)) {
                WriteLog "($processedPackages/$totalPackages) Skipping package '$packageTitleRaw' - Missing driver file name or extract command in XML."
                Remove-Item -Path $packageXMLPath -Force -ErrorAction SilentlyContinue
                continue
            }

            # Construct paths
            $driverUrl = $baseURL + $driverFileName
            $categoryPath = Join-Path -Path $modelPath -ChildPath $categoryClean
            $downloadFolder = Join-Path -Path $categoryPath -ChildPath $packageTitle # Final destination subfolder
            $driverFilePath = Join-Path -Path $downloadFolder -ChildPath $driverFileName
            $extractFolder = Join-Path -Path $downloadFolder -ChildPath ($driverFileName -replace '\.exe$', '') # Extract to subfolder named after exe
            # Check if already extracted
            if (-not $retryModel -and (Test-Path -Path $extractFolder -PathType Container)) {
				try {
					$null = Test-DriverExtractionOutput -Path $extractFolder -RequireInf -AllowProvisioningPackage -ComponentName "$identifier | $packageTitle"
					Remove-Item -LiteralPath $packageXMLPath -Force -ErrorAction Stop
					continue
				}
				catch { WriteLog "Re-extracting incomplete Lenovo package '$packageTitleRaw': $($_.Exception.Message)" }
            }

            # Ensure download folder exists
            if (-not (Test-Path -Path $downloadFolder)) {
                New-Item -Path $downloadFolder -ItemType Directory -Force | Out-Null
            }

            # Download the driver .exe
            $status = "$processedPackages/$totalPackages Downloading $packageTitle"
            if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $identifier -Status $status }
            WriteLog "($processedPackages/$totalPackages) Downloading driver: $driverUrl to $driverFilePath"
			$driverWorkspace = New-DriverExtractionWorkspace -Context $DriverOperationContext -DriversFolder $DriversFolder -FileName $driverFileName -FinalPath $extractFolder -CachePath $driverFilePath -ComponentName "$identifier | $packageTitle"
            try {
				Save-DriverPackageToWorkspace -Workspace $driverWorkspace -Source $driverUrl
                WriteLog "($processedPackages/$totalPackages) Driver downloaded: $driverFileName"
            $status = "$processedPackages/$totalPackages Extracting $packageTitle"
            if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $identifier -Status $status }
			$modifiedExtractCommand = $extractCommand.Replace('%PACKAGEPATH%', "`"$($driverWorkspace.OutputPath)`"", [StringComparison]::OrdinalIgnoreCase)
			WriteLog "$processedPackages/$totalPackages Extracting '$($driverWorkspace.InputPath)' using '$modifiedExtractCommand'."
			$null = Invoke-DriverExtractionProcess -Workspace $driverWorkspace -ArgumentList $modifiedExtractCommand -EnableInnoLogging
			$null = Test-DriverExtractionOutput -Path $driverWorkspace.OutputPath -RequireInf -AllowProvisioningPackage -ComponentName $driverWorkspace.ComponentName
			foreach ($item in @(Get-ChildItem -LiteralPath $driverWorkspace.OutputPath -Directory -ErrorAction Stop | Where-Object { $_.Name -like '*Liteon*' })) {
				do { $finalFolderName = "Liteon_$(Get-Random -Minimum 1000 -Maximum 9999)" }
				while (Test-Path -LiteralPath (Join-Path $driverWorkspace.OutputPath $finalFolderName))
				WriteLog "Renaming Lenovo Liteon folder '$($item.Name)' to '$finalFolderName' before publication to '$extractFolder'."
				Rename-Item -LiteralPath $item.FullName -NewName $finalFolderName -ErrorAction Stop
			}
			Publish-DriverExtractionContent -Workspace $driverWorkspace -RequireInf -AllowProvisioningPackage
			}
			catch {
				WriteLog "Failed to download, extract, or publish Lenovo driver '$packageTitle': $($_.Exception.Message)"
				throw
			}
			finally {
				$null = Remove-DriverExtractionWorkspace -Workspace $driverWorkspace
				Remove-Item -LiteralPath $packageXMLPath -Force -ErrorAction SilentlyContinue
			}
    
        } # End foreach package
		Set-DriverModelDownloadState -ModelPath $modelPath -State Complete -Context $DriverOperationContext
        
        # --- Compress to WIM if requested (after all drivers processed) ---
        if ($CompressToWim) {
            $status = "Compressing..."
            if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $identifier -Status $status }
            $wimFileName = "$($sanitizedIdentifier).wim" # Use sanitized identifier for filename
            $destinationWimPath = Join-Path -Path $makeDriversPath -ChildPath $wimFileName
            $driverRelativePath = Join-Path -Path $make -ChildPath $wimFileName # Update relative path to the WIM file
            WriteLog "Compressing '$modelPath' to '$destinationWimPath'..."
            try {
                $compressResult = Compress-DriverFolderToWim -SourceFolderPath $modelPath -DestinationWimPath $destinationWimPath -WimName $identifier -WimDescription $identifier -PreserveSource:$PreserveSourceOnCompress -ErrorAction Stop
                if ($compressResult) {
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
        
        $success = $true # Mark success as download/extract was okay
        
    }
    catch {
        $status = "Error: $($_.Exception.Message)"
        WriteLog "Error saving Lenovo drivers for '$identifier': $($_.Exception.ToString())"
        $success = $false
		if (-not $modelExisted) { Remove-DriverModelFolder -DriversFolder $DriversFolder -TargetFolder $modelPath -Description $identifier }
        if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $identifier -Status $status }
        return [PSCustomObject]@{ Identifier = $identifier; Status = $status; Success = $success; DriverPath = $null }
    }
    finally {
		try {
			WriteLog "Cleaning up temporary download folder: $tempDownloadPath"
			Remove-Item -LiteralPath $tempDownloadPath -Recurse -Force -ErrorAction SilentlyContinue
		}
		finally {
			if ($null -ne $modelMutex) { $modelMutex.ReleaseMutex(); $modelMutex.Dispose() }
		}
    }

    # Enqueue the final status (success or error) before returning
    if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $identifier -Status $status }

    # Return the final status
    return [PSCustomObject]@{ Identifier = $identifier; Status = $status; Success = $success; DriverPath = $driverRelativePath }
}

Export-ModuleMember -Function *