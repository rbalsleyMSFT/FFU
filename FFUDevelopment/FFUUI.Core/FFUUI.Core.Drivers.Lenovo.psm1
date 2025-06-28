# Function to get the list of Lenovo models using the PSREF API
function Get-LenovoDriversModelList {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ModelSearchTerm, # User input for model/machine type
        [Parameter(Mandatory = $true)]
        [hashtable]$Headers,
        [Parameter(Mandatory = $true)]
        [string]$UserAgent
    )

    WriteLog "Querying Lenovo PSREF API for model/machine type: $ModelSearchTerm"
    $url = "https://psref.lenovo.com/api/search/DefinitionFilterAndSearch/Suggest?kw=$([uri]::EscapeDataString($ModelSearchTerm))"
    $models = [System.Collections.Generic.List[PSCustomObject]]::new()

    try {
        $OriginalVerbosePreference = $VerbosePreference
        $VerbosePreference = 'SilentlyContinue'
        $response = Invoke-WebRequest -Uri $url -UseBasicParsing -Headers $Headers -UserAgent $UserAgent -ErrorAction Stop
        $VerbosePreference = $OriginalVerbosePreference
        WriteLog "PSREF API query complete."

        $jsonResponse = $response.Content | ConvertFrom-Json

        if ($null -ne $jsonResponse.data -and $jsonResponse.data.Count -gt 0) {
            foreach ($item in $jsonResponse.data) {
                $productName = $item.ProductName
                $machineTypes = $item.MachineType -split " / " # Split if multiple machine types are listed

                foreach ($machineTypeRaw in $machineTypes) {
                    $machineType = $machineTypeRaw.Trim()
                    # Only add if machine type is not empty
                    if (-not [string]::IsNullOrWhiteSpace($machineType)) {
                        # Create the combined display string
                        $displayModel = "$productName ($machineType)"
                        # Add each combination as a separate entry
                        $models.Add([PSCustomObject]@{
                                Make        = 'Lenovo'
                                Model       = $displayModel
                                ProductName = $productName 
                                MachineType = $machineType 
                            })
                    }
                    else {
                        WriteLog "Skipping entry for product '$productName' due to missing machine type."
                    }
                }
            }
            WriteLog "Found $($models.Count) potential model/machine type combinations for '$ModelSearchTerm'."
        }
        else {
            WriteLog "No models found matching '$ModelSearchTerm' in Lenovo PSREF."
        }
    }
    catch {
        WriteLog "Error querying Lenovo PSREF API: $($_.Exception.Message)"
        # Return empty list on error
    }
    return $models
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
        [Parameter()] # Made optional
        [System.Collections.Concurrent.ConcurrentQueue[hashtable]]$ProgressQueue = $null,
        [Parameter()]
        [bool]$CompressToWim = $false
    )
            
    # The Model property from the UI already contains the combined "ProductName (MachineType)" string
    $identifier = $DriverItemData.Model
    $machineType = $DriverItemData.MachineType 
    $make = "Lenovo"
    $sanitizedIdentifier = $identifier -replace '[\\/:"*?<>|]', '_'
    $status = "Starting..."
    $success = $false
    
    # Define paths
    $makeDriversPath = Join-Path -Path $DriversFolder -ChildPath $Make
    # Use the identifier (which contains the model name and machine type) and sanitize it for the path
    $modelPath = Join-Path -Path $makeDriversPath -ChildPath $sanitizedIdentifier
    $driverRelativePath = Join-Path -Path $make -ChildPath $sanitizedIdentifier # Relative path for the driver folder
    $tempDownloadPath = Join-Path -Path $makeDriversPath -ChildPath "_TEMP_$($machineType)_$($PID)" # Temp folder for catalog/package XMLs
    
    if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $identifier -Status "Checking..." }
    
    try {
        # Check for existing drivers
        $existingDriver = Test-ExistingDriver -Make $make -Model $sanitizedIdentifier -DriversFolder $DriversFolder -Identifier $identifier -ProgressQueue $ProgressQueue
        if ($null -ne $existingDriver) {
            # The return object from Test-ExistingDriver uses 'Model' as the identifier key.
            # We need to return 'Identifier' for Lenovo's logic.
            $existingDriver | Add-Member -MemberType NoteProperty -Name 'Identifier' -Value $identifier -Force
            $existingDriver.PSObject.Properties.Remove('Model')

            # Special handling for existing folders that need compression
            if ($CompressToWim -and $existingDriver.Status -eq 'Already downloaded') {
                $wimFilePath = Join-Path -Path $makeDriversPath -ChildPath "$($sanitizedIdentifier).wim"
                $sourceFolderPath = Join-Path -Path $makeDriversPath -ChildPath $sanitizedIdentifier
                WriteLog "Attempting compression of existing folder '$sourceFolderPath' to '$wimFilePath'."
                if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $identifier -Status "Compressing existing..." }
                try {
                    Compress-DriverFolderToWim -SourceFolderPath $sourceFolderPath -DestinationWimPath $wimFilePath -WimName $identifier -WimDescription "Drivers for $identifier" -ErrorAction Stop
                    $existingDriver.Status = "Already downloaded & Compressed"
                    $existingDriver.DriverPath = Join-Path -Path $make -ChildPath "$($sanitizedIdentifier).wim"
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

            # Ensure the Success property exists on the object being returned.
            if (-not $existingDriver.PSObject.Properties.Name -contains 'Success') {
                $existingDriver | Add-Member -MemberType NoteProperty -Name 'Success' -Value $true
            }

            return $existingDriver
        }

        # Ensure base directories exist
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

        Start-BitsTransferWithRetry -Source $catalogUrl -Destination $lenovoCatalogXML
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

            $status = "($processedPackages/$totalPackages) Getting package info..."
            if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $identifier -Status $status }

            # Download the package XML
            WriteLog "($processedPackages/$totalPackages) Downloading package XML: $packageUrl"
            try {
                Start-BitsTransferWithRetry -Source $packageUrl -Destination $packageXMLPath
            }
            catch {
                WriteLog "($processedPackages/$totalPackages) Failed to download package XML '$packageUrl'. Skipping. Error: $($_.Exception.Message)"
                continue # Skip this package
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
            if (Test-Path -Path $extractFolder -PathType Container) {
                $extractSize = (Get-ChildItem -Path $extractFolder -Recurse | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
                if ($extractSize -gt 1KB) {
                    WriteLog "($processedPackages/$totalPackages) Driver '$packageTitleRaw' already extracted to '$extractFolder'. Skipping."
                    Remove-Item -Path $packageXMLPath -Force -ErrorAction SilentlyContinue # Clean up package XML
                    continue
                }
            }

            # Ensure download folder exists
            if (-not (Test-Path -Path $downloadFolder)) {
                New-Item -Path $downloadFolder -ItemType Directory -Force | Out-Null
            }

            # Download the driver .exe
            $status = "($processedPackages/$totalPackages) Downloading $packageTitle..."
            if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $identifier -Status $status }
            WriteLog "($processedPackages/$totalPackages) Downloading driver: $driverUrl to $driverFilePath"
            try {
                Start-BitsTransferWithRetry -Source $driverUrl -Destination $driverFilePath
                WriteLog "($processedPackages/$totalPackages) Driver downloaded: $driverFileName"
            }
            catch {
                WriteLog "($processedPackages/$totalPackages) Failed to download driver '$driverUrl'. Skipping. Error: $($_.Exception.Message)"
                Remove-Item -Path $packageXMLPath -Force -ErrorAction SilentlyContinue # Clean up package XML
                continue # Skip this driver
            }

            # --- Extraction Logic ---
            $status = "($processedPackages/$totalPackages) Extracting $packageTitle..."
            if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $identifier -Status $status }
    
            # Always use a temporary extraction path to avoid long path issues
            $originalExtractFolder = $extractFolder # Store the originally intended final path
            $extractionSucceeded = $false
            $tempExtractBase = $null # Initialize
    
            # Create randomized number for use with temp folder name
            $randomNumber = Get-Random -Minimum 1000 -Maximum 9999
            $tempExtractBase = Join-Path $env:TEMP "LenovoDriverExtract_$randomNumber"
            $extractFolder = Join-Path $tempExtractBase ($driverFileName -replace '\.exe$', '') # Actual temp extraction folder
            WriteLog "($processedPackages/$totalPackages) Using temporary extraction path: $extractFolder"
    
            # Ensure the base temp directory exists
            if (-not (Test-Path -Path $tempExtractBase)) {
                New-Item -Path $tempExtractBase -ItemType Directory -Force | Out-Null
            }
            # Ensure the target temporary extraction folder exists
            if (-not (Test-Path -Path $extractFolder)) {
                New-Item -Path $extractFolder -ItemType Directory -Force | Out-Null
            }
    
            # Modify the extract command to point to the temporary folder
            $modifiedExtractCommand = $extractCommand -replace '%PACKAGEPATH%', "`"$extractFolder`""
            WriteLog "($processedPackages/$totalPackages) Extracting driver: $driverFilePath using command: $modifiedExtractCommand"
                
            try {
                Invoke-Process -FilePath $driverFilePath -ArgumentList $modifiedExtractCommand -Wait $true | Out-Null
                WriteLog "($processedPackages/$totalPackages) Driver extracted to temporary path: $extractFolder"
                $extractionSucceeded = $true
            }
            catch {
                WriteLog "($processedPackages/$totalPackages) Failed to extract driver '$driverFilePath' to temporary path. Skipping. Error: $($_.Exception.Message)"
                # Don't delete the downloaded exe yet if extraction fails
                Remove-Item -Path $packageXMLPath -Force -ErrorAction SilentlyContinue # Clean up package XML
                # Clean up temp folder if extraction failed
                if ($tempExtractBase -and (Test-Path -Path $tempExtractBase)) {
                    Remove-Item -Path $tempExtractBase -Recurse -Force -ErrorAction SilentlyContinue
                }
                continue # Skip further processing for this driver
            }
    
            # --- Post-Extraction Handling (Move from Temp to Final Destination) ---
            if ($extractionSucceeded) {
                WriteLog "($processedPackages/$totalPackages) Performing post-extraction move from temp to final destination..."
                try {
                    # Ensure the *original* final destination folder exists and is empty
                    if (Test-Path -Path $originalExtractFolder) {
                        WriteLog "($processedPackages/$totalPackages) Clearing existing final destination folder: $originalExtractFolder"
                        Get-ChildItem -Path $originalExtractFolder -Recurse | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
                    }
                    else {
                        WriteLog "($processedPackages/$totalPackages) Creating final destination folder: $originalExtractFolder"
                        New-Item -Path $originalExtractFolder -ItemType Directory -Force | Out-Null
                    }
    
                    # Get all items (files and folders) directly inside the temp extraction folder
                    $extractedItems = Get-ChildItem -Path $extractFolder -ErrorAction Stop
    
                    foreach ($item in $extractedItems) {
                        $itemName = $item.Name
                        $finalDestinationPath = $null
    
                        # Check if it's a directory containing 'Liteon'
                        if ($item.PSIsContainer -and $itemName -like '*Liteon*') {
                            # Rename Liteon folders with a random number suffix
                            $randomNumber = Get-Random -Minimum 1000 -Maximum 9999
                            $finalFolderName = "Liteon_$randomNumber"
                            $finalDestinationPath = Join-Path -Path $originalExtractFolder -ChildPath $finalFolderName
                            WriteLog "($processedPackages/$totalPackages) Moving Liteon folder '$itemName' to '$finalDestinationPath'"
                        }
                        else {
                            # For other files/folders, move them directly
                            $finalDestinationPath = Join-Path -Path $originalExtractFolder -ChildPath $itemName
                            WriteLog "($processedPackages/$totalPackages) Moving item '$itemName' to '$finalDestinationPath'"
                        }
    
                        # Perform the move
                        try {
                            Move-Item -Path $item.FullName -Destination $finalDestinationPath -Force -ErrorAction Stop
                        }
                        catch {
                            WriteLog "($processedPackages/$totalPackages) Failed to move item '$($item.FullName)' to '$finalDestinationPath'. Error: $($_.Exception.Message)"
                            # Decide if this should stop the whole process or just skip this item
                            # For now, we'll log and continue, but mark overall success as false
                            $extractionSucceeded = $false
                        }
                    } # End foreach ($item in $extractedItems)
    
                    if ($extractionSucceeded) {
                        WriteLog "($processedPackages/$totalPackages) All driver contents moved successfully from temp to final destination."
                    }
                    else {
                        WriteLog "($processedPackages/$totalPackages) Some driver contents failed to move. Check logs."
                    }
    
                }
                catch {
                    WriteLog "($processedPackages/$totalPackages) Error during post-extraction move: $($_.Exception.Message). Files might remain in temp."
                    $extractionSucceeded = $false # Mark as failed for cleanup logic below
                }
                finally {
                    # Clean up the base temporary directory regardless of move success/failure
                    if ($tempExtractBase -and (Test-Path -Path $tempExtractBase)) {
                        WriteLog "($processedPackages/$totalPackages) Cleaning up temporary extraction base: $tempExtractBase"
                        Remove-Item -Path $tempExtractBase -Recurse -Force -ErrorAction SilentlyContinue
                    }
                }
            }
    
            # --- Final Cleanup ---
            # Delete the downloaded .exe only if extraction AND move were successful
            if ($extractionSucceeded) {
                WriteLog "($processedPackages/$totalPackages) Deleting driver installation file: $driverFilePath"
                Remove-Item -Path $driverFilePath -Force -ErrorAction SilentlyContinue
            }
            else {
                WriteLog "($processedPackages/$totalPackages) Keeping driver installation file due to extraction/move failure: $driverFilePath"
            }
            # Always delete the package XML
            WriteLog "($processedPackages/$totalPackages) Deleting package XML file: $packageXMLPath"
            Remove-Item -Path $packageXMLPath -Force -ErrorAction SilentlyContinue
    
        } # End foreach package
        
        # --- Compress to WIM if requested (after all drivers processed) ---
        if ($CompressToWim) {
            $status = "Compressing..."
            if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $identifier -Status $status }
            $wimFileName = "$($sanitizedIdentifier).wim" # Use sanitized identifier for filename
            $destinationWimPath = Join-Path -Path $makeDriversPath -ChildPath $wimFileName
            $driverRelativePath = Join-Path -Path $make -ChildPath $wimFileName # Update relative path to the WIM file
            WriteLog "Compressing '$modelPath' to '$destinationWimPath'..."
            try {
                $compressResult = Compress-DriverFolderToWim -SourceFolderPath $modelPath -DestinationWimPath $destinationWimPath -WimName $identifier -WimDescription $identifier -ErrorAction Stop
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
        $status = "Error: $($_.Exception.Message.Split('.')[0])" # Shorten error message
        WriteLog "Error saving Lenovo drivers for '$identifier': $($_.Exception.ToString())" # Log full exception string
        $success = $false
        # Enqueue the error status before returning
        if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $identifier -Status $status }
        # Ensure return object is created even on error
        return [PSCustomObject]@{ Identifier = $identifier; Status = $status; Success = $success; DriverPath = $null }
    }
    finally {
        # Clean up the main catalog XML and temp folder
        WriteLog "Cleaning up temporary download folder: $tempDownloadPath"
        Remove-Item -Path $tempDownloadPath -Recurse -Force -ErrorAction SilentlyContinue
    }

    # Enqueue the final status (success or error) before returning
    if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $identifier -Status $status }

    # Return the final status
    return [PSCustomObject]@{ Identifier = $identifier; Status = $status; Success = $success; DriverPath = $driverRelativePath }
}

Export-ModuleMember -Function *