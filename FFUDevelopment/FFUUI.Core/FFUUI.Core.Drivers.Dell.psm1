# Function to get the list of Dell models from the catalog using XML streaming
function Get-DellDriversModelList {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int]$WindowsRelease,
        [Parameter(Mandatory = $true)]
        [string]$DriversFolder, # Base drivers folder (e.g., C:\FFUDevelopment\Drivers)
        [Parameter(Mandatory = $true)]
        [string]$Make # Should be 'Dell'
    )

    # Define Dell specific drivers folder and catalog file names
    $dellDriversFolder = Join-Path -Path $DriversFolder -ChildPath "Dell"
    $catalogBaseName = if ($WindowsRelease -le 11) { "CatalogPC" } else { "Catalog" }
    $dellCabFile = Join-Path -Path $dellDriversFolder -ChildPath "$($catalogBaseName).cab"
    $dellCatalogXML = Join-Path -Path $dellDriversFolder -ChildPath "$($catalogBaseName).xml"
    $catalogUrl = if ($WindowsRelease -le 11) { "http://downloads.dell.com/catalog/CatalogPC.cab" } else { "https://downloads.dell.com/catalog/Catalog.cab" }

    $uniqueModelNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $reader = $null 

    try {
        # Check if the Dell catalog XML exists and is recent
        $downloadCatalog = $true
        if (Test-Path -Path $dellCatalogXML -PathType Leaf) {
            WriteLog "Dell Catalog XML found: $dellCatalogXML"
            $dellCatalogCreationTime = (Get-Item $dellCatalogXML).CreationTime
            WriteLog "Dell Catalog XML Creation time: $dellCatalogCreationTime"
            # Check if the XML file is less than 7 days old
            if (((Get-Date) - $dellCatalogCreationTime).TotalDays -lt 7) {
                WriteLog "Using existing Dell Catalog XML (less than 7 days old): $dellCatalogXML"
                $downloadCatalog = $false
            }
            else {
                WriteLog "Existing Dell Catalog XML is older than 7 days: $dellCatalogXML"
            }
        }
        else {
            WriteLog "Dell Catalog XML not found: $dellCatalogXML"
        }

        if ($downloadCatalog) {
            WriteLog "Attempting to download and extract Dell Catalog for Get-DellDriversModelList..."
            # Ensure Dell drivers folder exists
            if (-not (Test-Path -Path $dellDriversFolder -PathType Container)) {
                WriteLog "Creating Dell drivers folder: $dellDriversFolder"
                New-Item -Path $dellDriversFolder -ItemType Directory -Force | Out-Null
            }

            # Check URL accessibility
            try {
                $request = [System.Net.WebRequest]::Create($catalogUrl)
                $request.Method = 'HEAD'; $response = $request.GetResponse(); $response.Close()
            }
            catch { throw "Dell Catalog URL '$catalogUrl' not accessible: $($_.Exception.Message)" }

            # Remove existing files before download if they exist
            if (Test-Path -Path $dellCabFile) { Remove-Item -Path $dellCabFile -Force -ErrorAction SilentlyContinue }
            if (Test-Path -Path $dellCatalogXML) { Remove-Item -Path $dellCatalogXML -Force -ErrorAction SilentlyContinue }

            WriteLog "Downloading Dell Catalog cab file: $catalogUrl to $dellCabFile"
            Start-BitsTransferWithRetry -Source $catalogUrl -Destination $dellCabFile
            WriteLog "Dell Catalog cab file downloaded to $dellCabFile"

            WriteLog "Extracting Dell Catalog cab file '$dellCabFile' to '$dellCatalogXML'"
            Invoke-Process -FilePath "Expand.exe" -ArgumentList """$dellCabFile"" ""$dellCatalogXML""" | Out-Null
            WriteLog "Dell Catalog cab file extracted to $dellCatalogXML"

            # Delete the CAB file after extraction
            WriteLog "Deleting Dell Catalog CAB file: $dellCabFile"
            Remove-Item -Path $dellCabFile -Force -ErrorAction SilentlyContinue
        }

        # Ensure the XML file exists before trying to read it
        if (-not (Test-Path -Path $dellCatalogXML -PathType Leaf)) {
            throw "Dell Catalog XML file '$dellCatalogXML' not found after download/check attempt."
        }
        
        # Use XmlReader for streaming from the XML file
        $settings = New-Object System.Xml.XmlReaderSettings
        $settings.IgnoreWhitespace = $true
        $settings.IgnoreComments = $true
        # $settings.DtdProcessing = [System.Xml.DtdProcessing]::Ignore # Optional

        $reader = [System.Xml.XmlReader]::Create($dellCatalogXML, $settings)
        WriteLog "Starting XML stream parsing for Dell models from '$dellCatalogXML'..."

        $isDriverComponent = $false
        $isModelElement = $false
        $modelDepth = -1 # Track depth to handle nested elements if needed

        # Read through the XML stream node by node
        while ($reader.Read()) {
            switch ($reader.NodeType) {
                ([System.Xml.XmlNodeType]::Element) {
                    switch ($reader.Name) {
                        'SoftwareComponent' { $isDriverComponent = $false } # Reset flag
                        'ComponentType' { if ($reader.GetAttribute('value') -eq 'DRVR') { $isDriverComponent = $true } }
                        'Model' { if ($isDriverComponent) { $isModelElement = $true; $modelDepth = $reader.Depth } }
                    }
                }
                ([System.Xml.XmlNodeType]::CDATA) {
                    if ($isModelElement -and $isDriverComponent) {
                        $modelName = $reader.Value.Trim()
                        if (-not [string]::IsNullOrWhiteSpace($modelName)) { $uniqueModelNames.Add($modelName) | Out-Null }
                        $isModelElement = $false # Reset after reading CDATA
                    }
                }
                ([System.Xml.XmlNodeType]::EndElement) {
                    switch ($reader.Name) {
                        'SoftwareComponent' { $isDriverComponent = $false; $isModelElement = $false; $modelDepth = -1 }
                        'Model' { if ($reader.Depth -eq $modelDepth) { $isModelElement = $false; $modelDepth = -1 } }
                    }
                }
            }
        } # End while ($reader.Read())

        WriteLog "Finished XML stream parsing. Found $($uniqueModelNames.Count) unique Dell models."

    }
    catch {
        WriteLog "Error getting Dell models: $($_.Exception.ToString())" # Log full exception
        throw "Failed to retrieve Dell models. Check log for details." # Re-throw for UI handling
    }
    finally {
        # Ensure the reader is closed and disposed
        if ($null -ne $reader) {
            $reader.Dispose()
        }
        # Ensure CAB file is deleted even if extraction failed but download succeeded
        if (Test-Path -Path $dellCabFile) {
            WriteLog "Cleaning up downloaded Dell CAB file: $dellCabFile"
            Remove-Item -Path $dellCabFile -Force -ErrorAction SilentlyContinue
        }
    }

    # Convert HashSet to sorted list of PSCustomObjects
    $models = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($modelName in ($uniqueModelNames | Sort-Object)) {
        $models.Add([PSCustomObject]@{
                Make  = $Make
                Model = $modelName
                # Link is not applicable here like for Microsoft
            })
    }

    return $models
}

# Function to download and extract drivers for a specific Dell model (Modified for ForEach-Object -Parallel)
function Save-DellDriversTask {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$DriverItemData, # Contains Model property
        [Parameter(Mandatory = $true)]
        [string]$DriversFolder,         # Base drivers folder (e.g., C:\FFUDevelopment\Drivers)
        [Parameter(Mandatory = $true)]
        [string]$WindowsArch,
        [Parameter(Mandatory = $true)]
        [int]$WindowsRelease,
        [Parameter()] # Made optional
        [System.Collections.Concurrent.ConcurrentQueue[hashtable]]$ProgressQueue = $null, # Default to null
        [Parameter()]
        [bool]$CompressToWim = $false # New parameter for compression
    )
        
    $modelName = $DriverItemData.Model
    $make = "Dell" # Hardcoded for this task
    $status = "Starting..." # Initial local status
    $success = $false
    
    # Initial status update
    if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $modelName -Status "Checking..." }
    
    $makeDriversPath = Join-Path -Path $DriversFolder -ChildPath $Make
    $modelPath = Join-Path -Path $makeDriversPath -ChildPath $modelName
    $driverRelativePath = Join-Path -Path $make -ChildPath $modelName # Relative path for the driver folder

    try {
        # Check if WIM file or driver folder already exist
        $wimFilePath = Join-Path -Path $makeDriversPath -ChildPath "$($modelName).wim"
        if (Test-Path -Path $wimFilePath -PathType Leaf) {
            $status = "Already downloaded (WIM)"
            WriteLog "Driver WIM for '$modelName' already exists at '$wimFilePath'."
            if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $modelName -Status $status }
            $wimRelativePath = Join-Path -Path $make -ChildPath "$($modelName).wim"
            return [PSCustomObject]@{ Model = $modelName; Status = $status; Success = $true; DriverPath = $wimRelativePath }
        }

        if (Test-Path -Path $modelPath -PathType Container) {
            $folderSize = (Get-ChildItem -Path $modelPath -Recurse | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
            if ($folderSize -gt 1MB) {
                $status = "Already downloaded"
                WriteLog "Drivers for '$modelName' already exist in '$modelPath'."
                if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $modelName -Status $status }
                return [PSCustomObject]@{ Model = $modelName; Status = $status; Success = $true; DriverPath = $driverRelativePath }
            }
            else {
                WriteLog "Driver folder '$modelPath' for '$modelName' exists but is empty/small. Re-downloading."
            }
        }

        # Define paths for Dell catalog. The catalog is assumed to be prepared by the calling function.
        $dellDriversFolder = Join-Path -Path $DriversFolder -ChildPath "Dell"
        $catalogBaseName = if ($WindowsRelease -le 11) { "CatalogPC" } else { "Catalog" }
        $dellCatalogXML = Join-Path -Path $dellDriversFolder -ChildPath "$($catalogBaseName).xml"

        # 3. Parse the *EXISTING* XML and Find Drivers for *this specific model*
        $status = "Finding drivers..."
        if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $modelName -Status $status }

        # Check if the provided XML path exists
        if (-not (Test-Path -Path $dellCatalogXML -PathType Leaf)) {
            throw "Dell Catalog XML file not found at specified path: $dellCatalogXML"
        }

        WriteLog "Parsing existing Dell Catalog XML for model '$modelName' from: $dellCatalogXML"
        
        # Initialize variables
        $baseLocation = $null
        $latestDrivers = @{} # Hashtable to store latest drivers for this model
        $modelSpecificDriversFound = $false
        
        # Create XML reader settings
        $settings = New-Object System.Xml.XmlReaderSettings
        $settings.IgnoreWhitespace = $true
        $settings.IgnoreComments = $true
        
        # Create XML reader
        $reader = $null
        try {
            $reader = [System.Xml.XmlReader]::Create($dellCatalogXML, $settings)
            
            # First pass - get baseLocation from manifest
            while ($reader.Read()) {
                if ($reader.NodeType -eq [System.Xml.XmlNodeType]::Element -and $reader.Name -eq "Manifest") {
                    $baseLocationAttr = $reader.GetAttribute("baseLocation")
                    if ($null -ne $baseLocationAttr) {
                        $baseLocation = "https://" + $baseLocationAttr + "/"
                        break
                    }
                }
            }
            
            if ($null -eq $baseLocation) {
                throw "Invalid Dell Catalog XML format: Missing 'baseLocation' attribute in Manifest element."
            }
            
            # Reset reader for second pass
            $reader.Dispose()
            $reader = [System.Xml.XmlReader]::Create($dellCatalogXML, $settings)
            
            # Process SoftwareComponents
            while ($reader.Read()) {
                if ($reader.NodeType -eq [System.Xml.XmlNodeType]::Element -and $reader.Name -eq "SoftwareComponent") {
                    # Read the entire SoftwareComponent subtree
                    $componentXml = $reader.ReadSubtree()
                    $component = New-Object System.Xml.XmlDocument
                    $component.Load($componentXml)
                    $componentXml.Dispose()
                    
                    # Check if it's a driver component
                    $componentTypeNode = $component.SelectSingleNode("//ComponentType[@value='DRVR']")
                    if ($null -eq $componentTypeNode) {
                        continue
                    }
                    
                    # Check if component supports the model
                    $modelNodes = $component.SelectNodes("//SupportedSystems/Brand/Model")
                    $modelMatch = $false
                    
                    foreach ($modelNode in $modelNodes) {
                        $displayNode = $modelNode.SelectSingleNode("Display")
                        if ($null -ne $displayNode -and $displayNode.InnerText.Trim() -eq $modelName) {
                            $modelMatch = $true
                            break
                        }
                    }
                    
                    if ($modelMatch) {
                        # Check OS compatibility
                        $validOS = $null
                        $osNodes = $component.SelectNodes("//SupportedOperatingSystems/OperatingSystem")
                        
                        if ($null -ne $osNodes) {
                            foreach ($osNode in $osNodes) {
                                $osArch = $osNode.GetAttribute("osArch")
                                
                                if ($WindowsRelease -le 11) {
                                    # Client OS check
                                    if ($osArch -eq $WindowsArch) {
                                        $validOS = $osNode
                                        break
                                    }
                                }
                                else {
                                    # Server OS check
                                    $osCode = $osNode.GetAttribute("osCode")
                                    $osCodePattern = switch ($WindowsRelease) {
                                        2016 { "W14" }
                                        2019 { "W19" }
                                        2022 { "W22" }
                                        2025 { "W25" }
                                        default { "W22" }
                                    }
                                    if ($osArch -eq $WindowsArch -and $osCode -match $osCodePattern) {
                                        $validOS = $osNode
                                        break
                                    }
                                }
                            }
                        }
                        
                        if ($validOS) {
                            $modelSpecificDriversFound = $true
                            
                            # Extract driver information
                            $driverPath = $component.SoftwareComponent.GetAttribute("path")
                            $downloadUrl = $baseLocation + $driverPath
                            $driverFileName = [System.IO.Path]::GetFileName($driverPath)
                            
                            # Get name
                            $nameNode = $component.SelectSingleNode("//Name/Display")
                            $name = if ($null -ne $nameNode) { $nameNode.InnerText } else { "UnknownDriver" }
                            $name = $name -replace '[\\\/\:\*\?\"\<\>\| ]', '_' -replace '[\,]', '-'
                            
                            # Get category
                            $categoryNode = $component.SelectSingleNode("//Category/Display")
                            $category = if ($null -ne $categoryNode) { $categoryNode.InnerText } else { "Uncategorized" }
                            $category = $category -replace '[\\\/\:\*\?\"\<\>\| ]', '_'
                            
                            # Get version
                            $version = [version]"0.0"
                            $vendorVersion = $component.SoftwareComponent.GetAttribute("vendorVersion")
                            if ($null -ne $vendorVersion) {
                                try { $version = [version]$vendorVersion } catch { WriteLog "Warning: Could not parse version '$vendorVersion' for driver '$name'. Using 0.0." }
                            }
                            
                            $namePrefix = ($name -split '-')[0]
                            
                            # Store the latest version for each category/prefix combination
                            if (-not $latestDrivers.ContainsKey($category)) { $latestDrivers[$category] = @{} }
                            if (-not $latestDrivers[$category].ContainsKey($namePrefix) -or $latestDrivers[$category][$namePrefix].Version -lt $version) {
                                $latestDrivers[$category][$namePrefix] = [PSCustomObject]@{
                                    Name           = $name
                                    DownloadUrl    = $downloadUrl
                                    DriverFileName = $driverFileName
                                    Version        = $version
                                    Category       = $category
                                }
                            }
                        }
                    }
                }
            }
        }
        finally {
            if ($null -ne $reader) {
                $reader.Dispose()
            }
        }

        WriteLog "Searching $($softwareComponents.Count) DRVR components in '$dellCatalogXML' for model '$modelName'..."

        foreach ($component in $softwareComponents) {
            # Check if SupportedSystems and Brand exist
            if ($null -eq $component.SupportedSystems -or $null -eq $component.SupportedSystems.Brand) { continue }
            # Ensure Model is iterable
            $componentModels = @($component.SupportedSystems.Brand.Model)
            if ($null -eq $componentModels) { continue }

            $modelMatch = $false
            foreach ($item in $componentModels) {
                # Check if Display and its CDATA section exist before accessing
                if ($null -ne $item.Display -and $null -ne $item.Display.'#cdata-section' -and $item.Display.'#cdata-section'.Trim() -eq $modelName) {
                    $modelMatch = $true
                    break
                }
            }

            if ($modelMatch) {
                # Model matches, now check OS compatibility
                $validOS = $null
                if ($null -ne $component.SupportedOperatingSystems) {
                    # Ensure OperatingSystem is always an array/collection
                    $osList = @($component.SupportedOperatingSystems.OperatingSystem)

                    if ($null -ne $osList) {
                        if ($WindowsRelease -le 11) {
                            # Client OS check
                            $validOS = $osList | Where-Object { $_.osArch -eq $WindowsArch } | Select-Object -First 1
                        }
                        else {
                            # Server OS check
                            $osCodePattern = switch ($WindowsRelease) {
                                2016 { "W14" } # Note: Dell uses W14 for Server 2016
                                2019 { "W19" }
                                2022 { "W22" }
                                2025 { "W25" }
                                default { "W22" } # Fallback, adjust as needed
                            }
                            $validOS = $osList | Where-Object { ($_.osArch -eq $WindowsArch) -and ($_.osCode -match $osCodePattern) } | Select-Object -First 1
                        }
                    }
                }

                if ($validOS) {
                    $modelSpecificDriversFound = $true # Mark that we found at least one relevant driver component
                    $driverPath = $component.path
                    $downloadUrl = $baseLocation + $driverPath
                    $driverFileName = [System.IO.Path]::GetFileName($driverPath)
                    # Check if Name, Display, and CDATA exist
                    $name = "UnknownDriver" # Default name
                    if ($null -ne $component.Name -and $null -ne $component.Name.Display -and $null -ne $component.Name.Display.'#cdata-section') {
                        $name = $component.Name.Display.'#cdata-section'
                        $name = $name -replace '[\\\/\:\*\?\"\<\>\| ]', '_' -replace '[\,]', '-'
                    }
                    # Check if Category, Display, and CDATA exist
                    $category = "Uncategorized" # Default category
                    if ($null -ne $component.Category -and $null -ne $component.Category.Display -and $null -ne $component.Category.Display.'#cdata-section') {
                        $category = $component.Category.Display.'#cdata-section'
                        $category = $category -replace '[\\\/\:\*\?\"\<\>\| ]', '_'
                    }
                    $version = [version]"0.0" # Default version
                    if ($null -ne $component.vendorVersion) {
                        try { $version = [version]$component.vendorVersion } catch { WriteLog "Warning: Could not parse version '$($component.vendorVersion)' for driver '$name'. Using 0.0." }
                    }
                    $namePrefix = ($name -split '-')[0] # Group by prefix within category

                    # Store the latest version for each category/prefix combination
                    if (-not $latestDrivers.ContainsKey($category)) { $latestDrivers[$category] = @{} }
                    if (-not $latestDrivers[$category].ContainsKey($namePrefix) -or $latestDrivers[$category][$namePrefix].Version -lt $version) {
                        $latestDrivers[$category][$namePrefix] = [PSCustomObject]@{
                            Name           = $name
                            DownloadUrl    = $downloadUrl
                            DriverFileName = $driverFileName
                            Version        = $version
                            Category       = $category
                        }
                    }
                }
            } # End if ($modelMatch)
        } # End foreach ($component in $softwareComponents)

        if (-not $modelSpecificDriversFound) {
            $status = "No drivers found for OS"
            WriteLog "No drivers found for model '$modelName' matching Windows Release '$WindowsRelease' and Arch '$WindowsArch' in '$dellCatalogXML'."
            if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $modelName -Status $status }
            # Consider this success as the process completed, just no drivers to download
            return [PSCustomObject]@{ Model = $modelName; Status = $status; Success = $true }
        }

        # 4. Download and Extract Found Drivers (Logic remains largely the same)
        $totalDriversToProcess = ($latestDrivers.Values | ForEach-Object { $_.Values.Count } | Measure-Object -Sum).Sum
        $driversProcessed = 0
        WriteLog "Found $totalDriversToProcess latest driver packages to download for $modelName."

        # Ensure base directories exist before loop
        if (-not (Test-Path -Path $makeDriversPath)) { New-Item -Path $makeDriversPath -ItemType Directory -Force | Out-Null }
        if (-not (Test-Path -Path $modelPath)) { New-Item -Path $modelPath -ItemType Directory -Force | Out-Null }

        foreach ($category in $latestDrivers.Keys) {
            foreach ($driver in $latestDrivers[$category].Values) {
                $driversProcessed++
                $status = "Downloading $($driversProcessed)/$($totalDriversToProcess): $($driver.Name)"
                if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $modelName -Status $status }

                $downloadFolder = Join-Path -Path $modelPath -ChildPath $driver.Category
                $driverFilePath = Join-Path -Path $downloadFolder -ChildPath $driver.DriverFileName
                $extractFolder = Join-Path -Path $downloadFolder -ChildPath $driver.DriverFileName.TrimEnd($driver.DriverFileName[-4..-1])

                # Check if already extracted (more robust check)
                if (Test-Path -Path $extractFolder -PathType Container) {
                    $extractSize = (Get-ChildItem -Path $extractFolder -Recurse -Exclude *.log | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
                    if ($extractSize -gt 1KB) {
                        WriteLog "Driver already extracted: $($driver.Name) in $extractFolder. Skipping."
                        continue # Skip to next driver
                    }
                }
                # Check if download file exists but extraction folder doesn't or is empty
                if (Test-Path -Path $driverFilePath -PathType Leaf) {
                    WriteLog "Download file $($driver.DriverFileName) exists, but extraction folder '$extractFolder' is missing or empty. Will attempt extraction."
                    # Proceed to extraction logic below
                }
                else {
                    # Download the driver
                    WriteLog "Downloading driver: $($driver.Name) ($($driver.DriverFileName))"
                    if (-not (Test-Path -Path $downloadFolder)) {
                        WriteLog "Creating download folder: $downloadFolder"
                        New-Item -Path $downloadFolder -ItemType Directory -Force | Out-Null
                    }
                    WriteLog "Downloading from: $($driver.DownloadUrl) to $driverFilePath"
                    try {
                        Start-BitsTransferWithRetry -Source $driver.DownloadUrl -Destination $driverFilePath
                        WriteLog "Driver downloaded: $($driver.DriverFileName)"
                    }
                    catch {
                        WriteLog "Failed to download driver: $($driver.DownloadUrl). Error: $($_.Exception.Message). Skipping."
                        # Update status for this specific driver failure? Maybe too granular.
                        continue # Skip to next driver
                    }
                }


                # Extract the driver
                $status = "Extracting $($driversProcessed)/$($totalDriversToProcess): $($driver.Name)"
                if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $modelName -Status $status }
                
                # Ensure extraction folder exists before attempting extraction
                if (-not (Test-Path -Path $extractFolder)) {
                    WriteLog "Creating extraction folder: $extractFolder"
                    New-Item -Path $extractFolder -ItemType Directory -Force | Out-Null
                }

                # Dell uses /e to extact the entire DUP while /drivers to extract only the drivers
                # In many cases /drivers will extract drivers for mutliple OS versions
                # Which can cause many duplicate files and bloat your driver folder
                # /e seems to be better and only extracts what is necessary and has less issues
                # We will default to using /e, but will fall back to /drivers if content cannot be found

                $arguments = "/s /e=`"$extractFolder`" /l=`"$extractFolder\log.log`""
                $altArguments = "/s /drivers=`"$extractFolder`" /l=`"$extractFolder\log.log`""
                $extractionSuccess = $false
                try {
                    # Handle special cases (Chipset/Network) - Check if OS is Server
                    $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem # Get OS info within the task scope
                    $isServer = $osInfo.Caption -match 'server'
                    
                    # Chipset drivers may require killing child processes in some cases
                    if ($driver.Category -eq "Chipset") {
                        WriteLog "Extracting Chipset driver: $driverFilePath $arguments"
                        $process = Invoke-Process -FilePath $driverFilePath -ArgumentList $arguments -Wait $false
                        Start-Sleep -Seconds 5 # Allow time for extraction
                        WriteLog "Extraction exited with exit code: $($process.ExitCode)"
                        # Attempt to gracefully close child process if needed (logic from original script)
                        $childProcesses = Get-CimInstance Win32_Process -Filter "ParentProcessId = $($process.Id)"
                        if ($childProcesses) {
                            $latestProcess = $childProcesses | Sort-Object CreationDate -Descending | Select-Object -First 1
                            WriteLog "Stopping child process for Chipset driver: $($latestProcess.Name) (PID: $($latestProcess.ProcessId))"
                            Stop-Process -Id $latestProcess.ProcessId -Force -ErrorAction SilentlyContinue
                            Start-Sleep -Seconds 1
                        }
                    }
                    # Network drivers on client OS may require killing child processes
                    elseif ($driver.Category -eq "Network" -and -not $isServer) {
                        WriteLog "Extracting Network driver: $driverFilePath $arguments"
                        $process = Invoke-Process -FilePath $driverFilePath -ArgumentList $arguments -Wait $false
                        Start-Sleep -Seconds 5
                        WriteLog "Extraction exited with exit code: $($process.ExitCode)"
                        if (-not $process.HasExited) {
                            $childProcesses = Get-CimInstance Win32_Process -Filter "ParentProcessId = $($process.Id)"
                            if ($childProcesses) {
                                $latestProcess = $childProcesses | Sort-Object CreationDate -Descending | Select-Object -First 1
                                WriteLog "Stopping child process for Network driver: $($latestProcess.Name) (PID: $($latestProcess.ProcessId))"
                                Stop-Process -Id $latestProcess.ProcessId -Force -ErrorAction SilentlyContinue
                                Start-Sleep -Seconds 1
                            }
                        }
                    }
                    else {
                        WriteLog "Extracting driver: $driverFilePath $arguments"
                        $process = Invoke-Process -FilePath $driverFilePath -ArgumentList $arguments
                        WriteLog "Extraction exited with exit code: $($process.ExitCode)"
                    }

                    # Verify extraction (check if folder has content)
                    if (Test-Path -Path $extractFolder -PathType Container) {
                        $extractSize = (Get-ChildItem -Path $extractFolder -Recurse -Exclude *.log | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
                        if ($extractSize -gt 1KB) {
                            $extractionSuccess = $true
                            WriteLog "Extraction successful (Method 1) for $driverFilePath $arguments"
                        }
                    }

                    # If primary extraction failed or folder is empty, try alternative
                    if (-not $extractionSuccess) {
                        # $arguments = "/s /e=`"$extractFolder`""
                        # $altArguments = "/s /drivers=`"$extractFolder`""
                        WriteLog "Extraction with $arguments failed or resulted in empty folder for $driverFilePath. Retrying with $altArguments"
                        # Clean up potentially empty folder before retrying
                        Remove-Item -Path $extractFolder -Recurse -Force -ErrorAction SilentlyContinue
                        New-Item -Path $extractFolder -ItemType Directory -Force | Out-Null # Recreate empty folder
                        $process = Invoke-Process -FilePath $driverFilePath -ArgumentList $altArguments
                        WriteLog "Extraction exited with exit code: $($process.ExitCode)"

                        # Verify extraction again
                        if (Test-Path -Path $extractFolder -PathType Container) {
                            $extractSize = (Get-ChildItem -Path $extractFolder -Recurse -Exclude *.log | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
                            if ($extractSize -gt 1KB) {
                                $extractionSuccess = $true
                                WriteLog "Extraction successful (Method 2) for $driverFilePath $altArguments"
                            }
                        }
                    }
                }
                catch {
                    WriteLog "Error during extraction process for $($driver.DriverFileName): $($_.Exception.Message). Trying alternative method."
                    # Try alternative method on any error during the first attempt block
                    try {
                        if (Test-Path -Path $extractFolder) {
                            # Clean up before retry if needed
                            Remove-Item -Path $extractFolder -Recurse -Force -ErrorAction SilentlyContinue
                        }
                        New-Item -Path $extractFolder -ItemType Directory -Force | Out-Null
                        # $arguments = "/s /e=`"$extractFolder`""
                        # $altArguments = "/s /drivers=`"$extractFolder`""
                        WriteLog "Extracting driver (Method 2): $driverFilePath $altArguments"
                        $process = Invoke-Process -FilePath $driverFilePath -ArgumentList $altArguments
                        WriteLog "Extraction exited with exit code: $($process.ExitCode)"

                        # Verify extraction again
                        if (Test-Path -Path $extractFolder -PathType Container) {
                            $extractSize = (Get-ChildItem -Path $extractFolder -Recurse -Exclude *.log | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
                            if ($extractSize -gt 1KB) {
                                $extractionSuccess = $true
                                WriteLog "Extraction successful (Method 2) for $driverFilePath."
                            }
                        }
                    }
                    catch {
                        WriteLog "Alternative extraction method also failed for $($driver.DriverFileName): $($_.Exception.Message)."
                        # Extraction failed completely
                    }
                }

                # Cleanup downloaded file only if extraction was successful
                if ($extractionSuccess) {
                    WriteLog "Deleting driver file: $driverFilePath"
                    Remove-Item -Path $driverFilePath -Force -ErrorAction SilentlyContinue
                    WriteLog "Driver file deleted: $driverFilePath"
                }
                else {
                    WriteLog "Extraction failed for $($driver.DriverFileName). Downloaded file kept at $driverFilePath for inspection."
                    # Update status to indicate partial failure?
                }

            } # End foreach ($driver in $latestDrivers)
        } # End foreach ($category in $latestDrivers)
            
        # --- Compress to WIM if requested (after all drivers processed) ---
        if ($CompressToWim) {
            $status = "Compressing..."
            if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $modelName -Status $status }
            $wimFileName = "$($modelName).wim"
            $destinationWimPath = Join-Path -Path $makeDriversPath -ChildPath $wimFileName
            $driverRelativePath = Join-Path -Path $make -ChildPath $wimFileName # Update relative path to the WIM file
            WriteLog "Compressing '$modelPath' to '$destinationWimPath'..."
            try {
                $compressResult = Compress-DriverFolderToWim -SourceFolderPath $modelPath -DestinationWimPath $destinationWimPath -WimName $modelName -WimDescription $modelName -ErrorAction Stop
                if ($compressResult) {
                    WriteLog "Compression successful for '$modelName'."
                    $status = "Completed & Compressed"
                }
                else {
                    WriteLog "Compression failed for '$modelName'. Check verbose/error output from Compress-DriverFolderToWim."
                    $status = "Completed (Compression Failed)"
                }
            }
            catch {
                WriteLog "Error during compression for '$modelName': $($_.Exception.Message)"
                $status = "Completed (Compression Error)"
            }
        }
        else {
            $status = "Completed" # Final status if not compressing
        }
        # --- End Compression ---
            
        $success = $true # Mark success as download/extract was okay
            
    }
    catch {
        $status = "Error: $($_.Exception.Message.Split('.')[0])" # Shorten error message
        WriteLog "Error saving Dell drivers for $($modelName): $($_.Exception.ToString())" # Log full exception string
        $success = $false
        # Enqueue the error status before returning
        if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $modelName -Status $status }
        # Ensure return object is created even on error
        return [PSCustomObject]@{ Model = $modelName; Status = $status; Success = $success; DriverPath = $null }
    }

    # Enqueue the final status (success or error) before returning
    if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $modelName -Status $status }

    # Return the final status
    return [PSCustomObject]@{ Model = $modelName; Status = $status; Success = $success; DriverPath = $driverRelativePath }
}

Export-ModuleMember -Function *