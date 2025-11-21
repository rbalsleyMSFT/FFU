<#
.SYNOPSIS
    FFU Builder OEM Driver Management Module

.DESCRIPTION
    OEM-specific driver download, parsing, and injection for FFU Builder.
    Supports Microsoft Surface, HP, Lenovo, and Dell driver catalogs with
    automatic download, extraction, and DISM injection capabilities.

.NOTES
    Module: FFU.Drivers
    Version: 1.0.0
    Dependencies: FFU.Core
#>

#Requires -Version 5.1

function Get-MicrosoftDrivers {
    <#
    .SYNOPSIS
    Downloads and extracts Microsoft Surface drivers for FFU builds

    .DESCRIPTION
    Downloads Microsoft Surface drivers from the official Microsoft support page,
    parses available models, and extracts the appropriate driver package for the
    specified Surface model and Windows version.

    .PARAMETER Make
    OEM manufacturer name (e.g., "Microsoft")

    .PARAMETER Model
    Surface model name (e.g., "Surface Pro 9")

    .PARAMETER WindowsRelease
    Windows release version (10 or 11)

    .PARAMETER Headers
    HTTP headers for web requests

    .PARAMETER UserAgent
    User agent string for web requests

    .PARAMETER DriversFolder
    Root path where drivers should be downloaded and extracted

    .PARAMETER FFUDevelopmentPath
    Root FFUDevelopment path for download tracking

    .EXAMPLE
    Get-MicrosoftDrivers -Make "Microsoft" -Model "Surface Pro 9" -WindowsRelease 11 `
                        -Headers $Headers -UserAgent $UserAgent -DriversFolder "C:\FFU\Drivers" `
                        -FFUDevelopmentPath "C:\FFU"
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Make,

        [Parameter(Mandatory = $true)]
        [string]$Model,

        [Parameter(Mandatory = $true)]
        [ValidateSet(10, 11)]
        [int]$WindowsRelease,

        [Parameter(Mandatory = $true)]
        [hashtable]$Headers,

        [Parameter(Mandatory = $true)]
        [string]$UserAgent,

        [Parameter(Mandatory = $true)]
        [string]$DriversFolder,

        [Parameter(Mandatory = $true)]
        [string]$FFUDevelopmentPath
    )

    $url = "https://support.microsoft.com/en-us/surface/download-drivers-and-firmware-for-surface-09bb2e09-2a4b-cb69-0951-078a7739e120"

    ### DOWNLOAD DRIVER PAGE CONTENT
    WriteLog "Getting Surface driver information from $url"
    $OriginalVerbosePreference = $VerbosePreference
    $VerbosePreference = 'SilentlyContinue'
    $webContent = Invoke-WebRequest -Uri $url -UseBasicParsing -Headers $Headers -UserAgent $UserAgent
    $VerbosePreference = $OriginalVerbosePreference
    WriteLog "Complete"

    ### PARSE THE DRIVER PAGE CONTENT FOR MODELS AND DOWNLOAD LINKS
    WriteLog "Parsing web content for models and download links"
    $html = $webContent.Content

    # Regex to match divs with selectable-content-options__option-content classes
    $divPattern = '<div[^>]*class="selectable-content-options__option-content(?: ocHidden)?"[^>]*>(.*?)</div>'
    $divMatches = [regex]::Matches($html, $divPattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)

    $models = @()

    foreach ($divMatch in $divMatches) {
        $divContent = $divMatch.Groups[1].Value

        # Find all tables within the div
        $tablePattern = '<table[^>]*>(.*?)</table>'
        $tableMatches = [regex]::Matches($divContent, $tablePattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)

        foreach ($tableMatch in $tableMatches) {
            $tableContent = $tableMatch.Groups[1].Value

            # Find all rows in the table
            $rowPattern = '<tr[^>]*>(.*?)</tr>'
            $rowMatches = [regex]::Matches($tableContent, $rowPattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)

            foreach ($rowMatch in $rowMatches) {
                $rowContent = $rowMatch.Groups[1].Value

                # Extract cells from the row
                $cellPattern = '<td[^>]*>\s*(?:<p[^>]*>)?(.*?)(?:</p>)?\s*</td>'
                $cellMatches = [regex]::Matches($rowContent, $cellPattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)

                if ($cellMatches.Count -ge 2) {
                    # Model name in the first TD
                    $modelName = ($cellMatches[0].Groups[1].Value).Trim()

                    # # Remove <p> and </p> tags if present
                    # $modelName = $modelName -replace '<p[^>]*>', '' -replace '</p>', ''
                    # $modelName = $modelName.Trim()


                    # The second TD might contain a link or just text
                    $secondTdContent = $cellMatches[1].Groups[1].Value.Trim()

                    # Look for a link in the second TD
                    $linkPattern = '<a[^>]+href="([^"]+)"[^>]*>'
                    $linkMatch = [regex]::Match($secondTdContent, $linkPattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

                    if ($linkMatch.Success) {
                        $modelLink = $linkMatch.Groups[1].Value
                    }
                    else {
                        # No link, just text instructions
                        $modelLink = $secondTdContent
                    }

                    $models += [PSCustomObject]@{ Model = $modelName; Link = $modelLink }
                }
            }
        }
    }

    WriteLog "Parsing complete"

    ### FIND THE MODEL IN THE LIST OF MODELS
    $selectedModel = $models | Where-Object { $_.Model -eq $Model }

    if ($null -eq $selectedModel) {
        if ($VerbosePreference -ne 'Continue') {
            Write-Host "The model '$Model' was not found in the list of available models."
            Write-Host "Please run the script with the -Verbose switch to see the list of available models."
        }
        WriteLog "The model '$Model' was not found in the list of available models."
        WriteLog "Please select a model from the list below by number:"

        for ($i = 0; $i -lt $models.Count; $i++) {
            if ($VerbosePreference -ne 'Continue') {
                Write-Host "$($i + 1). $($models[$i].Model)"
            }
            WriteLog "$($i + 1). $($models[$i].Model)"
        }

        do {
            $selection = Read-Host "Enter the number of the model you want to select"
            WriteLog "User selected model number: $selection"

            if ($selection -match '^\d+$' -and [int]$selection -ge 1 -and [int]$selection -le $models.Count) {
                $selectedModel = $models[$selection - 1]
            }
            else {
                if ($VerbosePreference -ne 'Continue') {
                    Write-Host "Invalid selection. Please try again."
                }
                WriteLog "Invalid selection. Please try again."
            }
        } while ($null -eq $selectedModel)
    }

    $Model = $selectedModel.Model
    WriteLog "Model: $Model"
    WriteLog "Download Page: $($selectedModel.Link)"

    ### GET THE DOWNLOAD LINK FOR THE SELECTED MODEL
    WriteLog "Getting download page content"
    $OriginalVerbosePreference = $VerbosePreference
    $VerbosePreference = 'SilentlyContinue'
    $downloadPageContent = Invoke-WebRequest -Uri $selectedModel.Link -UseBasicParsing -Headers $Headers -UserAgent $UserAgent
    $VerbosePreference = $OriginalVerbosePreference
    WriteLog "Complete"
    WriteLog "Parsing download page for file"
    $scriptPattern = '<script>window.__DLCDetails__={(.*?)}<\/script>'
    $scriptMatch = [regex]::Match($downloadPageContent.Content, $scriptPattern)

    if ($scriptMatch.Success) {
        $scriptContent = $scriptMatch.Groups[1].Value

        # Extract the download file information from the script tag
        $downloadFilePattern = '"name":"(.*?)",.*?"url":"(.*?)"'
        $downloadFileMatches = [regex]::Matches($scriptContent, $downloadFilePattern)

        $downloadLink = $null
        foreach ($downloadFile in $downloadFileMatches) {
            $fileName = $downloadFile.Groups[1].Value
            $fileUrl = $downloadFile.Groups[2].Value

            if ($fileName -match "Win$WindowsRelease") {
                $downloadLink = $fileUrl
                break
            }
        }


        ### CREATE FOLDER STRUCTURE AND DOWNLOAD AND EXTRACT THE FILE
        if ($downloadLink) {
            WriteLog "Download Link for Windows ${WindowsRelease}: $downloadLink"

            # Create directory structure
            if (-not (Test-Path -Path $DriversFolder)) {
                WriteLog "Creating Drivers folder: $DriversFolder"
                New-Item -Path $DriversFolder -ItemType Directory -Force | Out-Null
                WriteLog "Drivers folder created"
            }
            $sanitizedModel = ConvertTo-SafeName -Name $Model
            if ($sanitizedModel -ne $Model) { WriteLog "Sanitized model name: '$Model' -> '$sanitizedModel'" }
            $surfaceDriversPath = Join-Path -Path $DriversFolder -ChildPath $Make
            $modelPath = Join-Path -Path $surfaceDriversPath -ChildPath $sanitizedModel
            if (-Not (Test-Path -Path $modelPath)) {
                WriteLog "Creating model folder: $modelPath"
                New-Item -Path $modelPath -ItemType Directory | Out-Null
                WriteLog "Complete"
            }

            ### DOWNLOAD THE FILE
            $filePath = Join-Path -Path $surfaceDriversPath -ChildPath ($fileName)
            WriteLog "Downloading $Model driver file to $filePath"
            Mark-DownloadInProgress -FFUDevelopmentPath $FFUDevelopmentPath -TargetPath $filePath
            Start-BitsTransferWithRetry -Source $downloadLink -Destination $filePath
            Clear-DownloadInProgress -FFUDevelopmentPath $FFUDevelopmentPath -TargetPath $filePath
            WriteLog "Download complete"

            # Determine file extension
            $fileExtension = [System.IO.Path]::GetExtension($filePath).ToLower()

            ### EXTRACT THE FILE
            if ($fileExtension -eq ".msi") {
                # Extract the MSI file using an administrative install
                WriteLog "Extracting MSI file to $modelPath"
                $arguments = "/a `"$($filePath)`" /qn TARGETDIR=`"$($modelPath)`""
                Invoke-Process -FilePath "msiexec.exe" -ArgumentList $arguments | Out-Null
                WriteLog "Extraction complete"
            }
            elseif ($fileExtension -eq ".zip") {
                # Extract the ZIP file
                WriteLog "Extracting ZIP file to $modelPath"
                # $ProgressPreference = 'SilentlyContinue'
                Expand-Archive -Path $filePath -DestinationPath $modelPath -Force
                # $ProgressPreference = 'Continue'
                WriteLog "Extraction complete"
            }
            else {
                WriteLog "Unsupported file type: $fileExtension"
            }
            # Remove the downloaded file
            WriteLog "Removing $filePath"
            Remove-Item -Path $filePath -Force
            WriteLog "Complete"
        }
        else {
            WriteLog "No download link found for Windows $WindowsRelease."
        }
    }
    else {
        WriteLog "Failed to parse the download page for the MSI file."
    }
}

function Get-HPDrivers {
    <#
    .SYNOPSIS
    Downloads and extracts HP drivers for FFU builds

    .DESCRIPTION
    Downloads HP driver catalog, parses available models, and extracts the
    appropriate driver packages for the specified HP model and Windows version.
    Uses HP Image Assistant (HPIA) cloud catalog for driver discovery.

    .PARAMETER Make
    OEM manufacturer name (e.g., "HP")

    .PARAMETER Model
    HP model name (e.g., "EliteBook 840 G8")

    .PARAMETER WindowsArch
    Windows architecture (x64, x86, or ARM64)

    .PARAMETER WindowsRelease
    Windows release version (10 or 11)

    .PARAMETER WindowsVersion
    Specific Windows version/build (e.g., "21H2", "22H2")

    .PARAMETER DriversFolder
    Root path where drivers should be downloaded and extracted

    .PARAMETER FFUDevelopmentPath
    Root FFUDevelopment path for download tracking

    .EXAMPLE
    Get-HPDrivers -Make "HP" -Model "EliteBook 840 G8" -WindowsArch "x64" `
                  -WindowsRelease 11 -WindowsVersion "22H2" -DriversFolder "C:\FFU\Drivers" `
                  -FFUDevelopmentPath "C:\FFU"
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Make,

        [Parameter(Mandatory = $true)]
        [string]$Model,

        [Parameter(Mandatory = $true)]
        [ValidateSet("x64", "x86", "ARM64")]
        [string]$WindowsArch,

        [Parameter(Mandatory = $true)]
        [ValidateSet(10, 11)]
        [int]$WindowsRelease,

        [Parameter(Mandatory = $true)]
        [string]$WindowsVersion,

        [Parameter(Mandatory = $true)]
        [string]$DriversFolder,

        [Parameter(Mandatory = $true)]
        [string]$FFUDevelopmentPath
    )

    # Download and extract the PlatformList.cab
    $PlatformListUrl = 'https://hpia.hpcloud.hp.com/ref/platformList.cab'
    $DriversFolder = "$DriversFolder\$Make"
    $PlatformListCab = "$DriversFolder\platformList.cab"
    $PlatformListXml = "$DriversFolder\PlatformList.xml"

    if (-not (Test-Path -Path $DriversFolder)) {
        WriteLog "Creating Drivers folder: $DriversFolder"
        New-Item -Path $DriversFolder -ItemType Directory -Force | Out-Null
        WriteLog "Drivers folder created"
    }
    WriteLog "Downloading $PlatformListUrl to $PlatformListCab"
    Start-BitsTransferWithRetry -Source $PlatformListUrl -Destination $PlatformListCab
    WriteLog "Download complete"
    WriteLog "Expanding $PlatformListCab to $PlatformListXml"
    Invoke-Process -FilePath expand.exe -ArgumentList "$PlatformListCab $PlatformListXml" | Out-Null
    WriteLog "Expansion complete"

    # Parse the PlatformList.xml to find the SystemID based on the ProductName
    [xml]$PlatformListContent = Get-Content -Path $PlatformListXml
    $ProductNodes = $PlatformListContent.ImagePal.Platform | Where-Object { $_.ProductName.'#text' -match $Model }

    # Create a list of unique ProductName entries
    $ProductNames = @()
    foreach ($node in $ProductNodes) {
        foreach ($productName in $node.ProductName) {
            if ($productName.'#text' -match $Model) {
                $ProductNames += [PSCustomObject]@{
                    ProductName = $productName.'#text'
                    SystemID    = $node.SystemID
                    OSReleaseID = $node.OS.OSReleaseIdFileName -replace 'H', 'h'
                    IsWindows11 = $node.OS.IsWindows11 -contains 'true'
                }
            }
        }
    }

    if ($ProductNames.Count -gt 1) {
        Write-Output "More than one model found matching '$Model':"
        WriteLog "More than one model found matching '$Model':"
        $ProductNames | ForEach-Object -Begin { $i = 1 } -Process {
            if ($VerbosePreference -ne 'Continue') {
                Write-Output "$i. $($_.ProductName)"
            }
            WriteLog "$i. $($_.ProductName)"
            $i++
        }
        $selection = Read-Host "Please select the number corresponding to the correct model"
        WriteLog "User selected model number: $selection"
        if ($selection -match '^\d+$' -and [int]$selection -le $ProductNames.Count) {
            $SelectedProduct = $ProductNames[[int]$selection - 1]
            $ProductName = $SelectedProduct.ProductName
            WriteLog "Selected model: $ProductName"
            $SystemID = $SelectedProduct.SystemID
            WriteLog "SystemID: $SystemID"
            $ValidOSReleaseIDs = $SelectedProduct.OSReleaseID
            WriteLog "Valid OSReleaseIDs: $ValidOSReleaseIDs"
            $IsWindows11 = $SelectedProduct.IsWindows11
            WriteLog "IsWindows11 supported: $IsWindows11"
        }
        else {
            WriteLog "Invalid selection. Exiting."
            if ($VerbosePreference -ne 'Continue') {
                Write-Host "Invalid selection. Exiting."
            }
            exit
        }
    }
    elseif ($ProductNames.Count -eq 1) {
        $SelectedProduct = $ProductNames[0]
        $ProductName = $SelectedProduct.ProductName
        WriteLog "Selected model: $ProductName"
        $SystemID = $SelectedProduct.SystemID
        WriteLog "SystemID: $SystemID"
        $ValidOSReleaseIDs = $SelectedProduct.OSReleaseID
        WriteLog "OSReleaseID: $ValidOSReleaseIDs"
        $IsWindows11 = $SelectedProduct.IsWindows11
        WriteLog "IsWindows11: $IsWindows11"
    }
    else {
        WriteLog "No models found matching '$Model'. Exiting."
        if ($VerbosePreference -ne 'Continue') {
            Write-Host "No models found matching '$Model'. Exiting."
        }
        exit
    }

    if (-not $SystemID) {
        WriteLog "SystemID not found for model: $Model Exiting."
        if ($VerbosePreference -ne 'Continue') {
            Write-Host "SystemID not found for model: $Model Exiting."
        }
        exit
    }

    # Validate if WindowsRelease is 11 and there is no IsWindows11 element set to true
    if ($WindowsRelease -eq 11 -and -not $IsWindows11) {
        WriteLog "WindowsRelease is set to 11, but no drivers are available for this Windows release. Please set the -WindowsRelease parameter to 10, or provide your own drivers to the FFUDevelopment\Drivers folder."
        Write-Output "WindowsRelease is set to 11, but no drivers are available for this Windows release. Please set the -WindowsRelease parameter to 10, or provide your own drivers to the FFUDevelopment\Drivers folder."
        exit
    }

    # Validate WindowsVersion against OSReleaseID
    $OSReleaseIDs = $ValidOSReleaseIDs -split ' '
    $MatchingReleaseID = $OSReleaseIDs | Where-Object { $_ -eq "$WindowsVersion" }

    if (-not $MatchingReleaseID) {
        Write-Output "The specified WindowsVersion value '$WindowsVersion' is not valid for the selected model. Please select a valid OSReleaseID:"
        $OSReleaseIDs | ForEach-Object -Begin { $i = 1 } -Process {
            Write-Output "$i. $_"
            $i++
        }
        $selection = Read-Host "Please select the number corresponding to the correct OSReleaseID"
        WriteLog "User selected OSReleaseID number: $selection"
        if ($selection -match '^\d+$' -and [int]$selection -le $OSReleaseIDs.Count) {
            $WindowsVersion = $OSReleaseIDs[[int]$selection - 1]
            WriteLog "Selected OSReleaseID: $WindowsVersion"
        }
        else {
            WriteLog "Invalid selection. Exiting."
            exit
        }
    }

    # Modify WindowsArch for URL
    $Arch = $WindowsArch -replace "^x", ""

    # Construct the URL to download the driver XML cab for the model
    # The HPcloud reference site is case sensitve so we must convert the Windowsversion to lower 'h' first
    $WindowsVersionHP = $WindowsVersion -replace 'H', 'h'
    $ModelRelease = $SystemID + "_$Arch" + "_$WindowsRelease" + ".0.$WindowsVersionHP"
    $DriverCabUrl = "https://hpia.hpcloud.hp.com/ref/$SystemID/$ModelRelease.cab"
    $DriverCabFile = "$DriversFolder\$ModelRelease.cab"
    $DriverXmlFile = "$DriversFolder\$ModelRelease.xml"

    if (-not (Test-Url -Url $DriverCabUrl)) {
        WriteLog "HP Driver cab URL is not accessible: $DriverCabUrl Exiting"
        if ($VerbosePreference -ne 'Continue') {
            Write-Host "HP Driver cab URL is not accessible: $DriverCabUrl Exiting"
        }
        exit
    }

    # Download and extract the driver XML cab
    Writelog "Downloading HP Driver cab from $DriverCabUrl to $DriverCabFile"
    Start-BitsTransferWithRetry -Source $DriverCabUrl -Destination $DriverCabFile
    WriteLog "Expanding HP Driver cab to $DriverXmlFile"
    Invoke-Process -FilePath expand.exe -ArgumentList "$DriverCabFile $DriverXmlFile" | Out-Null

    # Parse the extracted XML file to download individual drivers
    [xml]$DriverXmlContent = Get-Content -Path $DriverXmlFile
    $baseUrl = "https://ftp.hp.com/pub/softpaq/sp"

    WriteLog "Downloading drivers for $ProductName"
    foreach ($update in $DriverXmlContent.ImagePal.Solutions.UpdateInfo) {
        if ($update.Category -notmatch '^Driver') {
            continue
        }

        $Name = $update.Name
        # Fix the name for drivers that contain illegal characters for folder name purposes
        $Name = $Name -replace '[\\\/\:\*\?\"\<\>\|]', '_'
        WriteLog "Downloading driver: $Name"
        $Category = $update.Category
        $Category = $Category -replace '[\\\/\:\*\?\"\<\>\|]', '_'
        $Version = $update.Version
        $Version = $Version -replace '[\\\/\:\*\?\"\<\>\|]', '_'
        $DriverUrl = "https://$($update.URL)"
        WriteLog "Driver URL: $DriverUrl"
        $DriverFileName = [System.IO.Path]::GetFileName($DriverUrl)
        $downloadFolder = "$DriversFolder\$ProductName\$Category"
        $DriverFilePath = Join-Path -Path $downloadFolder -ChildPath $DriverFileName

        if (Test-Path -Path $DriverFilePath) {
            WriteLog "Driver already downloaded: $DriverFilePath, skipping"
            continue
        }

        if (-not (Test-Path -Path $downloadFolder)) {
            WriteLog "Creating download folder: $downloadFolder"
            New-Item -Path $downloadFolder -ItemType Directory -Force | Out-Null
            WriteLog "Download folder created"
        }

        # Download the driver with retry
        WriteLog "Downloading driver to: $DriverFilePath"
        Mark-DownloadInProgress -FFUDevelopmentPath $FFUDevelopmentPath -TargetPath $DriverFilePath
        Start-BitsTransferWithRetry -Source $DriverUrl -Destination $DriverFilePath
        Clear-DownloadInProgress -FFUDevelopmentPath $FFUDevelopmentPath -TargetPath $DriverFilePath
        WriteLog 'Driver downloaded'

        # Make folder for extraction
        $extractFolder = "$downloadFolder\$Name\$Version\" + $DriverFileName.TrimEnd('.exe')
        Writelog "Creating extraction folder: $extractFolder"
        New-Item -Path $extractFolder -ItemType Directory -Force | Out-Null
        WriteLog 'Extraction folder created'

        # Extract the driver
        $arguments = "/s /e /f `"$extractFolder`""
        WriteLog "Extracting driver"
        Invoke-Process -FilePath $DriverFilePath -ArgumentList $arguments | Out-Null
        WriteLog "Driver extracted to: $extractFolder"

        # Delete the .exe driver file after extraction
        Remove-Item -Path $DriverFilePath -Force
        WriteLog "Driver installation file deleted: $DriverFilePath"
    }
    # Clean up the downloaded cab and xml files
    Remove-Item -Path $DriverCabFile, $DriverXmlFile, $PlatformListCab, $PlatformListXml -Force
    WriteLog "Driver cab and xml files deleted"
}

function Get-LenovoDrivers {
    <#
    .SYNOPSIS
    Downloads and extracts Lenovo drivers for FFU builds

    .DESCRIPTION
    Downloads Lenovo driver catalog, parses available models using PSREF API,
    and extracts the appropriate driver packages for the specified Lenovo model
    and Windows version.

    .PARAMETER Make
    OEM manufacturer name (e.g., "Lenovo")

    .PARAMETER Model
    Lenovo model name or machine type (e.g., "ThinkPad X1 Carbon Gen 9" or "20XW")

    .PARAMETER WindowsArch
    Windows architecture (x64, x86, or ARM64)

    .PARAMETER WindowsRelease
    Windows release version (10 or 11)

    .PARAMETER Headers
    HTTP headers for web requests (modified by function to add PSREF authentication)

    .PARAMETER UserAgent
    User agent string for web requests

    .PARAMETER DriversFolder
    Root path where drivers should be downloaded and extracted

    .PARAMETER FFUDevelopmentPath
    Root FFUDevelopment path for download tracking

    .EXAMPLE
    Get-LenovoDrivers -Make "Lenovo" -Model "ThinkPad X1 Carbon Gen 9" -WindowsArch "x64" `
                      -WindowsRelease 11 -Headers $Headers -UserAgent $UserAgent `
                      -DriversFolder "C:\FFU\Drivers" -FFUDevelopmentPath "C:\FFU"
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Make,

        [Parameter(Mandatory = $true)]
        [string]$Model,

        [Parameter(Mandatory = $true)]
        [ValidateSet("x64", "x86", "ARM64")]
        [string]$WindowsArch,

        [Parameter(Mandatory = $true)]
        [ValidateSet(10, 11)]
        [int]$WindowsRelease,

        [Parameter(Mandatory = $true)]
        [hashtable]$Headers,

        [Parameter(Mandatory = $true)]
        [string]$UserAgent,

        [Parameter(Mandatory = $true)]
        [string]$DriversFolder,

        [Parameter(Mandatory = $true)]
        [string]$FFUDevelopmentPath
    )

    function Get-LenovoPSREF {
        param (
            [string]$ModelName
        )

        # Lenovo is special - they prevent access to the PSREF API without a cookie as of July 2025.
        # This cookie must be retrieved via Javascript
        # It appears that the cookie is hard-coded. We'll see how long this lasts.
        # If anyone knows how to reliably get the the model and machine type information from Lenovo, let me know.
        # https://download.lenovo.com/cdrt/td/catalogv2.xml only provides a subset of the information available from PSREF (e.g. it's missing 300w, 500w, and other consumer models).

        # $lenovoCookie = "X-PSREF-USER-TOKEN=eyJ0eXAiOiJKV1QifQ.bjVTdWk0YklZeUc2WnFzL0lXU0pTeU1JcFo0aExzRXl1UGxHN3lnS1BtckI0ZVU5WEJyVGkvaFE0NmVNU2U1ZjNrK3ZqTEVIZ29nTk1TNS9DQmIwQ0pTN1Q1VytlY1RpNzZTUldXbm4wZ1g2RGJuQWg4MXRkTmxKT2YrOW9LRjBzQUZzV05HM3NpcU92WFVTM0o0blM1SDQyUlVXNThIV1VBS2R0c1B2NjJyQjIrUGxNZ2x6RTRhUjY5UDZWclBX.ZDBmM2EyMWRjZTg2N2JmYWMxZDIxY2NiYjQzMWFhNjg1YjEzZTAxNmU2M2RmN2M5ZjIyZWJhMzZkOWI1OWJhZg"

        # Wrote a separate function to grab the token. Check the function notes for more details. Keep the above comment for now to see if the cookie ever changes.
        $lenovoCookie = Get-LenovoPSREFToken

        # Add the cookie to the headers
        $Headers["Cookie"] = $lenovoCookie

        $url = "https://psref.lenovo.com/api/search/DefinitionFilterAndSearch/Suggest?kw=$ModelName"
        WriteLog "Querying Lenovo PSREF API for model: $ModelName"
        $OriginalVerbosePreference = $VerbosePreference
        $VerbosePreference = 'SilentlyContinue'
        $response = Invoke-WebRequest -Uri $url -UseBasicParsing -Headers $Headers -UserAgent $UserAgent
        $VerbosePreference = $OriginalVerbosePreference
        WriteLog "Complete"

        $jsonResponse = $response.Content | ConvertFrom-Json

        $products = @()
        foreach ($item in $jsonResponse.data) {
            if (-not [string]::IsNullOrEmpty($item.MachineType) -and -not [string]::IsNullOrEmpty($item.ProductName)) {
                $productName = $item.ProductName
                $machineTypes = $item.MachineType -split " / "

                foreach ($machineType in $machineTypes) {
                    if ($machineType -eq $ModelName) {
                        WriteLog "Model name entered is a matching machine type"
                        $products = @()
                        $products += [pscustomobject]@{
                            ProductName = $productName
                            MachineType = $machineType
                        }
                        WriteLog "Product Name: $productName Machine Type: $machineType"
                        return $products
                    }
                    $products += [pscustomobject]@{
                        ProductName = $productName
                        MachineType = $machineType
                    }
                }
            }
        }

        return , $products
    }

    # Parse the Lenovo PSREF page for the model
    $machineTypes = Get-LenovoPSREF -ModelName $Model
    if ($machineTypes.ProductName.Count -eq 0) {
        WriteLog "No machine types found for model: $Model"
        WriteLog "Enter a valid model or machine type in the -model parameter"
        exit
    }
    elseif ($machineTypes.ProductName.Count -eq 1) {
        $machineType = $machineTypes[0].MachineType
        $model = $machineTypes[0].ProductName
    }
    else {
        if ($VerbosePreference -ne 'Continue') {
            Write-Output "Multiple machine types found for model: $Model"
        }
        WriteLog "Multiple machine types found for model: $Model"
        for ($i = 0; $i -lt $machineTypes.ProductName.Count; $i++) {
            if ($VerbosePreference -ne 'Continue') {
                Write-Output "$($i + 1). $($machineTypes[$i].ProductName) ($($machineTypes[$i].MachineType))"
            }
            WriteLog "$($i + 1). $($machineTypes[$i].ProductName) ($($machineTypes[$i].MachineType))"
        }
        $selection = Read-Host "Enter the number of the model you want to select"
        $machineType = $machineTypes[$selection - 1].MachineType
        WriteLog "Selected machine type: $machineType"
        $model = $machineTypes[$selection - 1].ProductName
        WriteLog "Selected model: $model"
    }


    # Construct the catalog URL based on Windows release and machine type
    $ModelRelease = $machineType + "_Win" + $WindowsRelease
    $CatalogUrl = "https://download.lenovo.com/catalog/$ModelRelease.xml"
    WriteLog "Lenovo Driver catalog URL: $CatalogUrl"

    if (-not (Test-Url -Url $catalogUrl)) {
        Write-Error "Lenovo Driver catalog URL is not accessible: $catalogUrl"
        WriteLog "Lenovo Driver catalog URL is not accessible: $catalogUrl"
        exit
    }

    # Create the folder structure for the Lenovo drivers
    $driversFolder = "$DriversFolder\$Make"
    if (-not (Test-Path -Path $DriversFolder)) {
        WriteLog "Creating Drivers folder: $DriversFolder"
        New-Item -Path $DriversFolder -ItemType Directory -Force | Out-Null
        WriteLog "Drivers folder created"
    }

    # Download and parse the Lenovo catalog XML
    $LenovoCatalogXML = "$DriversFolder\$ModelRelease.xml"
    WriteLog "Downloading $catalogUrl to $LenovoCatalogXML"
    Start-BitsTransferWithRetry -Source $catalogUrl -Destination $LenovoCatalogXML
    WriteLog "Download Complete"
    $xmlContent = [xml](Get-Content -Path $LenovoCatalogXML)

    WriteLog "Parsing Lenovo catalog XML"
    # Process each package in the catalog
    foreach ($package in $xmlContent.packages.package) {
        $packageUrl = $package.location
        $category = $package.category

        #If category starts with BIOS, skip the package
        if ($category -like 'BIOS*') {
            continue
        }

        #If category name is 'Motherboard Devices Backplanes core chipset onboard video PCIe switches', truncate to 'Motherboard Devices' to shorten path
        if ($category -eq 'Motherboard Devices Backplanes core chipset onboard video PCIe switches') {
            $category = 'Motherboard Devices'
        }

        $packageName = [System.IO.Path]::GetFileName($packageUrl)
        #Remove the filename from the $packageURL
        $baseURL = $packageUrl -replace $packageName, ""

        # Download the package XML
        $packageXMLPath = "$DriversFolder\$packageName"
        WriteLog "Downloading $category package XML $packageUrl to $packageXMLPath"
        try {
            Start-BitsTransferWithRetry -Source $packageUrl -Destination $packageXMLPath -ErrorAction Stop
        }
        catch {
            Write-Output "Failed to download $category package XML: $packageXMLPath - $($_.Exception.Message)"
            WriteLog "Failed to download $category package XML: $packageXMLPath - $($_.Exception.Message)"
            continue
        }

        # Load the package XML content
        $packageXmlContent = [xml](Get-Content -Path $packageXMLPath)
        $packageType = $packageXmlContent.Package.PackageType.type
        $packageTitle = $packageXmlContent.Package.title.InnerText

        # Fix the name for drivers that contain illegal characters for folder name purposes
        $packageTitle = $packageTitle -replace '[\\\/\:\*\?\"\<\>\|]', '_'

        # If ' - ' is in the package title, truncate the title to the first part of the string.
        $packageTitle = $packageTitle -replace ' - .*', ''

        #Check if packagetype = 2. If packagetype is not 2, skip the package. $packageType is a System.Xml.XmlElement.
        #This filters out Firmware, BIOS, and other non-INF drivers
        if ($packageType -ne 2) {
            Remove-Item -Path $packageXMLPath -Force
            continue
        }

        # Extract the driver file name and the extract command
        $driverFileName = $packageXmlContent.Package.Files.Installer.File.Name
        $extractCommand = $packageXmlContent.Package.ExtractCommand

        #if extract command is empty/missing, skip the package
        if (!($extractCommand)) {
            Remove-Item -Path $packageXMLPath -Force
            continue
        }

        # Create the download URL and folder structure
        $driverUrl = $baseUrl + $driverFileName
        $downloadFolder = "$DriversFolder\$Model\$Category\$packageTitle"
        $driverFilePath = Join-Path -Path $downloadFolder -ChildPath $driverFileName

        # Check if file has already been downloaded
        if (Test-Path -Path $driverFilePath) {
            Write-Output "Driver already downloaded: $driverFilePath skipping"
            WriteLog "Driver already downloaded: $driverFilePath skipping"
            continue
        }

        if (-not (Test-Path -Path $downloadFolder)) {
            WriteLog "Creating download folder: $downloadFolder"
            New-Item -Path $downloadFolder -ItemType Directory -Force | Out-Null
            WriteLog "Download folder created"
        }

        # Download the driver with retry
        WriteLog "Downloading driver: $driverUrl to $driverFilePath"
        Mark-DownloadInProgress -FFUDevelopmentPath $FFUDevelopmentPath -TargetPath $driverFilePath
        Start-BitsTransferWithRetry -Source $driverUrl -Destination $driverFilePath
        Clear-DownloadInProgress -FFUDevelopmentPath $FFUDevelopmentPath -TargetPath $driverFilePath
        WriteLog "Driver downloaded"

        # Make folder for extraction
        $extractFolder = $downloadFolder + "\" + $driverFileName.TrimEnd($driverFileName[-4..-1])
        WriteLog "Creating extract folder: $extractFolder"
        New-Item -Path $extractFolder -ItemType Directory -Force | Out-Null
        WriteLog "Extract folder created"

        # Modify the extract command
        $modifiedExtractCommand = $extractCommand -replace '%PACKAGEPATH%', "`"$extractFolder`""

        # Extract the driver
        # Start-Process -FilePath $driverFilePath -ArgumentList $modifiedExtractCommand -Wait -NoNewWindow
        WriteLog "Extracting driver: $driverFilePath to $extractFolder"
        Invoke-Process -FilePath $driverFilePath -ArgumentList $modifiedExtractCommand | Out-Null
        WriteLog "Driver extracted"

        # Delete the .exe driver file after extraction
        WriteLog "Deleting driver installation file: $driverFilePath"
        Remove-Item -Path $driverFilePath -Force
        WriteLog "Driver installation file deleted: $driverFilePath"

        # Delete the package XML file after extraction
        WriteLog "Deleting package XML file: $packageXMLPath"
        Remove-Item -Path $packageXMLPath -Force
        WriteLog "Package XML file deleted"
    }

    #Delete the catalog XML file after processing
    WriteLog "Deleting catalog XML file: $LenovoCatalogXML"
    Remove-Item -Path $LenovoCatalogXML -Force
    WriteLog "Catalog XML file deleted"
}

function Get-DellDrivers {
    <#
    .SYNOPSIS
    Downloads and extracts Dell drivers for FFU builds

    .DESCRIPTION
    Downloads Dell driver catalog, parses available models, and extracts the
    appropriate driver packages for the specified Dell model and Windows version.
    Uses Dell's online catalog for driver discovery.

    .PARAMETER Make
    OEM manufacturer name (e.g., "Dell")

    .PARAMETER Model
    Dell model name (e.g., "Latitude 7490", "OptiPlex 7080")

    .PARAMETER WindowsArch
    Windows architecture (x64, x86, or ARM64)

    .PARAMETER WindowsRelease
    Windows release version (10, 11, 2016, 2019, 2022, 2025)

    .PARAMETER DriversFolder
    Root path where drivers should be downloaded and extracted

    .PARAMETER FFUDevelopmentPath
    Root FFUDevelopment path for download tracking

    .PARAMETER isServer
    Boolean indicating if target OS is Windows Server (affects driver extraction behavior)

    .EXAMPLE
    Get-DellDrivers -Make "Dell" -Model "Latitude 7490" -WindowsArch "x64" `
                    -WindowsRelease 11 -DriversFolder "C:\FFU\Drivers" `
                    -FFUDevelopmentPath "C:\FFU" -isServer $false
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Make,

        [Parameter(Mandatory = $true)]
        [string]$Model,

        [Parameter(Mandatory = $true)]
        [ValidateSet("x64", "x86", "ARM64")]
        [string]$WindowsArch,

        [Parameter(Mandatory = $true)]
        [int]$WindowsRelease,

        [Parameter(Mandatory = $true)]
        [string]$DriversFolder,

        [Parameter(Mandatory = $true)]
        [string]$FFUDevelopmentPath,

        [Parameter(Mandatory = $true)]
        [bool]$isServer
    )

    if (-not (Test-Path -Path $DriversFolder)) {
        WriteLog "Creating Drivers folder: $DriversFolder"
        New-Item -Path $DriversFolder -ItemType Directory -Force | Out-Null
        WriteLog "Drivers folder created"
    }

    $DriversFolder = "$DriversFolder\$Make"
    WriteLog "Creating Dell Drivers folder: $DriversFolder"
    New-Item -Path $DriversFolder -ItemType Directory -Force | Out-Null
    WriteLog "Dell Drivers folder created"

    #CatalogPC.cab is the catalog for Windows client PCs, Catalog.cab is the catalog for Windows Server
    if ($WindowsRelease -le 11) {
        $catalogUrl = "http://downloads.dell.com/catalog/CatalogPC.cab"
        $DellCabFile = "$DriversFolder\CatalogPC.cab"
        $DellCatalogXML = "$DriversFolder\CatalogPC.XML"
    }
    else {
        $catalogUrl = "https://downloads.dell.com/catalog/Catalog.cab"
        $DellCabFile = "$DriversFolder\Catalog.cab"
        $DellCatalogXML = "$DriversFolder\Catalog.xml"
    }

    if (-not (Test-Url -Url $catalogUrl)) {
        WriteLog "Dell Catalog cab URL is not accessible: $catalogUrl Exiting"
        if ($VerbosePreference -ne 'Continue') {
            Write-Host "Dell Catalog cab URL is not accessible: $catalogUrl Exiting"
        }
        exit
    }

    WriteLog "Downloading Dell Catalog cab file: $catalogUrl to $DellCabFile"
    Start-BitsTransferWithRetry -Source $catalogUrl -Destination $DellCabFile
    WriteLog "Dell Catalog cab file downloaded"

    WriteLog "Extracting Dell Catalog cab file to $DellCatalogXML"
    Invoke-Process -FilePath Expand.exe -ArgumentList "$DellCabFile $DellCatalogXML" | Out-Null
    WriteLog "Dell Catalog cab file extracted"

    $xmlContent = [xml](Get-Content -Path $DellCatalogXML)
    $baseLocation = "https://" + $xmlContent.manifest.baseLocation + "/"
    $latestDrivers = @{}

    $softwareComponents = $xmlContent.Manifest.SoftwareComponent | Where-Object { $_.ComponentType.value -eq "DRVR" }
    foreach ($component in $softwareComponents) {
        $models = $component.SupportedSystems.Brand.Model
        foreach ($item in $models) {
            if ($item.Display.'#cdata-section' -match $Model) {

                if ($WindowsRelease -le 11) {
                    $validOS = $component.SupportedOperatingSystems.OperatingSystem | Where-Object { $_.osArch -eq $WindowsArch }
                }
                elseif ($WindowsRelease -eq 2016) {
                    $validOS = $component.SupportedOperatingSystems.OperatingSystem | Where-Object { ($_.osArch -eq $WindowsArch) -and ($_.osCode -match "W14") }
                }
                elseif ($WindowsRelease -eq 2019) {
                    $validOS = $component.SupportedOperatingSystems.OperatingSystem | Where-Object { ($_.osArch -eq $WindowsArch) -and ($_.osCode -match "W19") }
                }
                elseif ($WindowsRelease -eq 2022) {
                    $validOS = $component.SupportedOperatingSystems.OperatingSystem | Where-Object { ($_.osArch -eq $WindowsArch) -and ($_.osCode -match "W22") }
                }
                elseif ($WindowsRelease -eq 2025) {
                    $validOS = $component.SupportedOperatingSystems.OperatingSystem | Where-Object { ($_.osArch -eq $WindowsArch) -and ($_.osCode -match "W25") }
                }
                else {
                    $validOS = $component.SupportedOperatingSystems.OperatingSystem | Where-Object { ($_.osArch -eq $WindowsArch) -and ($_.osCode -match "W22") }
                }

                if ($validOS) {
                    $driverPath = $component.path
                    $downloadUrl = $baseLocation + $driverPath
                    $driverFileName = [System.IO.Path]::GetFileName($driverPath)
                    $name = $component.Name.Display.'#cdata-section'
                    $name = $name -replace '[\\\/\:\*\?\"\<\>\| ]', '_'
                    $name = $name -replace '[\,]', '-'
                    $category = $component.Category.Display.'#cdata-section'
                    $category = $category -replace '[\\\/\:\*\?\"\<\>\| ]', '_'
                    $version = [version]$component.vendorVersion
                    $namePrefix = ($name -split '-')[0]

                    # Use hash table to store the latest driver for each category to prevent downloading older driver versions
                    if ($latestDrivers[$category]) {
                        if ($latestDrivers[$category][$namePrefix]) {
                            if ($latestDrivers[$category][$namePrefix].Version -lt $version) {
                                $latestDrivers[$category][$namePrefix] = [PSCustomObject]@{
                                    Name           = $name;
                                    DownloadUrl    = $downloadUrl;
                                    DriverFileName = $driverFileName;
                                    Version        = $version;
                                    Category       = $category
                                }
                            }
                        }
                        else {
                            $latestDrivers[$category][$namePrefix] = [PSCustomObject]@{
                                Name           = $name;
                                DownloadUrl    = $downloadUrl;
                                DriverFileName = $driverFileName;
                                Version        = $version;
                                Category       = $category
                            }
                        }
                    }
                    else {
                        $latestDrivers[$category] = @{}
                        $latestDrivers[$category][$namePrefix] = [PSCustomObject]@{
                            Name           = $name;
                            DownloadUrl    = $downloadUrl;
                            DriverFileName = $driverFileName;
                            Version        = $version;
                            Category       = $category
                        }
                    }
                }
            }
        }
    }

    foreach ($category in $latestDrivers.Keys) {
        foreach ($driver in $latestDrivers[$category].Values) {
            $downloadFolder = "$DriversFolder\$Model\$($driver.Category)"
            $driverFilePath = Join-Path -Path $downloadFolder -ChildPath $driver.DriverFileName

            if (Test-Path -Path $driverFilePath) {
                WriteLog "Driver already downloaded: $driverFilePath skipping"
                continue
            }

            WriteLog "Downloading driver: $($driver.Name)"
            if (-not (Test-Path -Path $downloadFolder)) {
                WriteLog "Creating download folder: $downloadFolder"
                New-Item -Path $downloadFolder -ItemType Directory -Force | Out-Null
                WriteLog "Download folder created"
            }

            WriteLog "Downloading driver: $($driver.DownloadUrl) to $driverFilePath"
            try {
                Mark-DownloadInProgress -FFUDevelopmentPath $FFUDevelopmentPath -TargetPath $driverFilePath
                Start-BitsTransferWithRetry -Source $driver.DownloadUrl -Destination $driverFilePath
                Clear-DownloadInProgress -FFUDevelopmentPath $FFUDevelopmentPath -TargetPath $driverFilePath
                WriteLog "Driver downloaded"
            }
            catch {
                WriteLog "Failed to download driver: $($driver.DownloadUrl) to $driverFilePath"
                continue
            }


            $extractFolder = $downloadFolder + "\" + $driver.DriverFileName.TrimEnd($driver.DriverFileName[-4..-1])
            # WriteLog "Creating extraction folder: $extractFolder"
            # New-Item -Path $extractFolder -ItemType Directory -Force | Out-Null
            # WriteLog "Extraction folder created"

            # $arguments = "/s /e /f `"$extractFolder`""
            $arguments = "/s /drivers=`"$extractFolder`""
            WriteLog "Extracting driver: $driverFilePath $arguments"
            try {
                #If Category is Chipset, must add -wait $false to the Invoke-Process command line to prevent the script from hanging on the Intel chipset driver which leaves a Window open
                if ($driver.Category -eq "Chipset") {
                    $process = Invoke-Process -FilePath $driverFilePath -ArgumentList $arguments -Wait $false

                    #Wait 5 seconds to allow for the extraction process to finish
                    Start-Sleep -Seconds 5

                    $childProcesses = Get-ChildProcesses $process.Id

                    # Find and stop the last created child process
                    if ($childProcesses) {
                        $latestProcess = $childProcesses | Sort-Object CreationDate -Descending | Select-Object -First 1
                        Stop-Process -Id $latestProcess.ProcessId -Force
                        # Sleep 1 second to let process finish exiting so its installer can be removed
                        Start-Sleep -Seconds 1
                    }
                    #If Category is Network and $isServer is $false, must add -wait $false to the Invoke-Process command line to prevent the script from hanging on the Intel network driver which leaves a Window open
                }
                elseif ($driver.Category -eq "Network" -and $isServer -eq $false) {

                    $process = Invoke-Process -FilePath $driverFilePath -ArgumentList $arguments -Wait $false

                    #Sometimes the network drivers will extract on client OS, wait 5 seconds and check if the process is still running
                    Start-Sleep -Seconds 5
                    if ($process.HasExited -eq $false) {
                        $childProcesses = Get-ChildProcesses $process.Id

                        # Find and stop the last created child process
                        if ($childProcesses) {
                            $latestProcess = $childProcesses | Sort-Object CreationDate -Descending | Select-Object -First 1
                            Stop-Process -Id $latestProcess.ProcessId -Force
                            #Move on to the next driver and skip this one - it won't extract on a client OS even with /s /e switches
                            continue
                        }
                    }
                }
                else {
                    Invoke-Process -FilePath $driverFilePath -ArgumentList $arguments | Out-Null
                }
                # If $extractFolder is empty, try alternative extraction method
                if (!(Get-ChildItem -Path $extractFolder -Recurse | Where-Object { -not $_.PSIsContainer })) {
                    WriteLog 'Extraction with /drivers= switch failed. Removing folder and retrying with /s /e switches'
                    Remove-Item -Path $extractFolder -Force -Recurse -ErrorAction SilentlyContinue
                    $arguments = "/s /e=`"$extractFolder`""
                    WriteLog "Extracting driver: $driverFilePath $arguments"
                    Invoke-Process -FilePath $driverFilePath -ArgumentList $arguments | Out-Null
                }
            }
            catch {
                WriteLog 'Extraction with /drivers= switch failed. Retrying with /s /e switches'
                $arguments = "/s /e=`"$extractFolder`""
                WriteLog "Extracting driver: $driverFilePath $arguments"
                Invoke-Process -FilePath $driverFilePath -ArgumentList $arguments | Out-Null
            }
            WriteLog "Driver extracted"

            WriteLog "Deleting driver file: $driverFilePath"
            Remove-Item -Path $driverFilePath -Force
            WriteLog "Driver file deleted"
        }
    }
}

function Copy-Drivers {
    <#
    .SYNOPSIS
    Copies WinPE-compatible drivers from OEM driver repository to deployment media

    .DESCRIPTION
    Filters and copies essential drivers (system, storage, HID) from downloaded OEM
    driver packages to WinPE media. Uses device class GUIDs to identify required
    drivers and excludes unnecessary components (audio, camera, firmware) to minimize
    media size.

    .PARAMETER Path
    Source path containing OEM driver packages to filter

    .PARAMETER Output
    Destination path where filtered drivers will be copied (typically WinPE media)

    .PARAMETER WindowsArch
    Windows architecture (x64, x86, or ARM64) - used to copy architecture-specific driver files

    .EXAMPLE
    Copy-Drivers -Path "C:\FFU\Drivers\Dell\Latitude 7490" -Output "C:\FFU\PEDrivers" -WindowsArch "x64"
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Output,

        [Parameter(Mandatory = $true)]
        [ValidateSet("x64", "x86", "ARM64")]
        [string]$WindowsArch
    )
    # Find more information about device classes here:
    # https://learn.microsoft.com/en-us/windows-hardware/drivers/install/system-defined-device-setup-classes-available-to-vendors
    # For now, included are system devices, scsi and raid controllers, keyboards, mice and HID devices for touch support
    # 4D36E97D-E325-11CE-BFC1-08002BE10318 = System devices
    # 4D36E97B-E325-11CE-BFC1-08002BE10318 = SCSI, RAID, and NVMe Controllers
    # 4d36e96b-e325-11ce-bfc1-08002be10318 = Keyboards
    # 4d36e96f-e325-11ce-bfc1-08002be10318 = Mice and other pointing devices
    # 745a17a0-74d3-11d0-b6fe-00a0c90f57da = Human Interface Devices
    $filterGUIDs = @("{4D36E97D-E325-11CE-BFC1-08002BE10318}", "{4D36E97B-E325-11CE-BFC1-08002BE10318}", "{4d36e96b-e325-11ce-bfc1-08002be10318}", "{4d36e96f-e325-11ce-bfc1-08002be10318}", "{745a17a0-74d3-11d0-b6fe-00a0c90f57da}")
    $exclusionList = "wdmaudio.inf|Sound|Machine Learning|Camera|Firmware"
    $pathLength = $Path.Length
    $infFiles = Get-ChildItem -Path $Path -Recurse -Filter "*.inf"

    for ($i = 0; $i -lt $infFiles.Count; $i++) {
        $infFullName = $infFiles[$i].FullName
        $infPath = Split-Path -Path $infFullName
        $childPath = $infPath.Substring($pathLength)
        $targetPath = Join-Path -Path $Output -ChildPath $childPath

        if ((Get-PrivateProfileString -FileName $infFullName -SectionName "version" -KeyName "ClassGUID") -in $filterGUIDs) {
            #Avoid drivers that reference keywords from the exclusion list to keep the total size small
            if (((Get-Content -Path $infFullName) -match $exclusionList).Length -eq 0) {
                $providerName = (Get-PrivateProfileString -FileName $infFullName -SectionName "Version" -KeyName "Provider").Trim("%")

                WriteLog "Copying PE drivers for $providerName"
                WriteLog "Driver inf is: $infFullName"
                [void](New-Item -Path $targetPath -ItemType Directory -Force)
                Copy-Item -Path $infFullName -Destination $targetPath -Force
                $CatalogFileName = Get-PrivateProfileString -FileName $infFullName -SectionName "version" -KeyName "Catalogfile"
                Copy-Item -Path "$infPath\$CatalogFileName" -Destination $targetPath -Force

                $sourceDiskFiles = Get-PrivateProfileSection -FileName $infFullName -SectionName "SourceDisksFiles"
                foreach ($sourceDiskFile in $sourceDiskFiles.Keys) {
                    if (!$sourceDiskFiles[$sourceDiskFile].Contains(",")) {
                        Copy-Item -Path "$infPath\$sourceDiskFile" -Destination $targetPath -Force
                    }
                    else {
                        $subdir = ($sourceDiskFiles[$sourceDiskFile] -split ",")[1]
                        [void](New-Item -Path "$targetPath\$subdir" -ItemType Directory -Force)
                        Copy-Item -Path "$infPath\$subdir\$sourceDiskFile" -Destination "$targetPath\$subdir" -Force
                    }
                }

                #Arch specific files override the files specified in the universal section
                $sourceDiskFiles = Get-PrivateProfileSection -FileName $infFullName -SectionName "SourceDisksFiles.$WindowsArch"
                foreach ($sourceDiskFile in $sourceDiskFiles.Keys) {
                    if (!$sourceDiskFiles[$sourceDiskFile].Contains(",")) {
                        Copy-Item -Path "$infPath\$sourceDiskFile" -Destination $targetPath -Force
                    }
                    else {
                        $subdir = ($sourceDiskFiles[$sourceDiskFile] -split ",")[1]
                        [void](New-Item -Path "$targetPath\$subdir" -ItemType Directory -Force)
                        Copy-Item -Path "$infPath\$subdir\$sourceDiskFile" -Destination "$targetPath\$subdir" -Force
                    }
                }
            }
        }
    }
}

# Export all functions
Export-ModuleMember -Function @(
    'Get-MicrosoftDrivers',
    'Get-HPDrivers',
    'Get-LenovoDrivers',
    'Get-DellDrivers',
    'Copy-Drivers'
)