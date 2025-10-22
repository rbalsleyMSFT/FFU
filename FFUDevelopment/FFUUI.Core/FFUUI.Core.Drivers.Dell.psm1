<#
.SYNOPSIS
    Provides functions for discovering, downloading, and processing Dell device drivers.
.DESCRIPTION
    This module contains the logic specific to handling Dell drivers for the FFU Builder UI. It includes functions to parse Dell's large XML driver catalog to retrieve a list of supported models (Get-DellDriversModelList). It also provides a parallel-capable task function (Save-DellDriversTask) that finds, downloads, extracts, and optionally compresses all the latest driver packages for a specified Dell model and operating system.
#>

# Function to get the list of Dell models from the catalog using XML streaming
function Get-DellDriversModelList {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int]$WindowsRelease,
        [Parameter(Mandatory = $true)]
        [string]$DriversFolder,
        [Parameter(Mandatory = $true)]
        [string]$Make
    )

    # Client pathway (<=11) uses CatalogIndexPC to build full Brand Model (SystemID) strings.
    if ($WindowsRelease -le 11) {
        $dellModels = Get-DellClientModels -CatalogIndexXmlPath (Get-DellCatalogIndex -DriversFolder $DriversFolder)
        $final = [System.Collections.Generic.List[pscustomobject]]::new()
        foreach ($m in $dellModels) {
            $final.Add([pscustomobject]@{
                Make            = $Make
                Model           = $m.ModelDisplay
                Brand           = $m.Brand
                ModelNumber     = $m.ModelNumber
                SystemId        = $m.SystemId
                CabRelativePath = $m.CabRelativePath
                CabUrl          = $m.CabUrl
            })
        }
        return $final
    }

    # Server pathway (unchanged – still uses Catalog.cab)
    $dellDriversFolder = Join-Path -Path $DriversFolder -ChildPath "Dell"
    $catalogBaseName = "Catalog"
    $dellCabFile = Join-Path -Path $dellDriversFolder -ChildPath "$($catalogBaseName).cab"
    $dellCatalogXML = Join-Path -Path $dellDriversFolder -ChildPath "$($catalogBaseName).xml"
    $catalogUrl = "https://downloads.dell.com/catalog/Catalog.cab"

    if (-not (Test-Path -Path $dellDriversFolder)) {
        New-Item -Path $dellDriversFolder -ItemType Directory -Force | Out-Null
    }

    $download = $true
    if (Test-Path -Path $dellCatalogXML) {
        if (((Get-Date) - (Get-Item $dellCatalogXML).CreationTime).TotalDays -lt 7) {
            $download = $false
        }
    }

    if ($download) {
        if (Test-Path $dellCabFile) { Remove-Item $dellCabFile -Force -ErrorAction SilentlyContinue }
        if (Test-Path $dellCatalogXML) { Remove-Item $dellCatalogXML -Force -ErrorAction SilentlyContinue }
        Start-BitsTransferWithRetry -Source $catalogUrl -Destination $dellCabFile
        Invoke-Process -FilePath Expand.exe -ArgumentList """$dellCabFile"" ""$dellCatalogXML""" | Out-Null
        Remove-Item $dellCabFile -Force -ErrorAction SilentlyContinue
    }

    if (-not (Test-Path $dellCatalogXML)) { throw "Dell server catalog XML missing: $dellCatalogXML" }

    $settings = New-Object System.Xml.XmlReaderSettings
    $settings.IgnoreWhitespace = $true
    $settings.IgnoreComments = $true
    $reader = [System.Xml.XmlReader]::Create($dellCatalogXML,$settings)
    $inDriver = $false
    $inModel = $false
    $depthModel = -1
    $modelsHash = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    try {
        while ($reader.Read()) {
            switch ($reader.NodeType) {
                ([System.Xml.XmlNodeType]::Element) {
                    switch ($reader.Name) {
                        'SoftwareComponent' { $inDriver = $false }
                        'ComponentType' { if ($reader.GetAttribute('value') -eq 'DRVR') { $inDriver = $true } }
                        'Model' { if ($inDriver) { $inModel = $true; $depthModel = $reader.Depth } }
                    }
                }
                ([System.Xml.XmlNodeType]::CDATA) {
                    if ($inDriver -and $inModel) {
                        $val = $reader.Value.Trim()
                        if ($val) { $modelsHash.Add($val) | Out-Null }
                        $inModel = $false
                    }
                }
                ([System.Xml.XmlNodeType]::EndElement) {
                    if ($reader.Name -eq 'SoftwareComponent') { $inDriver = $false; $inModel = $false }
                    elseif ($reader.Name -eq 'Model' -and $reader.Depth -eq $depthModel) { $inModel = $false; $depthModel = -1 }
                }
            }
        }
    }
    finally {
        $reader.Dispose()
    }

    $out = [System.Collections.Generic.List[pscustomobject]]::new()
    foreach ($nm in ($modelsHash | Sort-Object)) {
        $out.Add([pscustomobject]@{ Make = $Make; Model = $nm })
    }
    return $out
}

# Function to download and extract drivers for a specific Dell model (Modified for ForEach-Object -Parallel)
function Save-DellDriversTask {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$DriverItemData,
        [Parameter(Mandatory = $true)]
        [string]$DriversFolder,
        [Parameter(Mandatory = $true)]
        [string]$WindowsArch,
        [Parameter(Mandatory = $true)]
        [int]$WindowsRelease,
        [Parameter()]
        [System.Collections.Concurrent.ConcurrentQueue[hashtable]]$ProgressQueue = $null,
        [Parameter()]
        [bool]$CompressToWim = $false,
        [Parameter()]
        [bool]$PreserveSourceOnCompress = $false
    )

    $modelDisplay = $DriverItemData.Model
    $make = 'Dell'
    if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $modelDisplay -Status 'Checking...' }

    $sanitizedModelName = ConvertTo-SafeName -Name $modelDisplay
    $makeDriversPath = Join-Path -Path $DriversFolder -ChildPath $make
    $modelPath = Join-Path -Path $makeDriversPath -ChildPath $sanitizedModelName
    $driverRelativePath = Join-Path -Path $make -ChildPath $sanitizedModelName

    # Helper: safe folder removal
    function Remove-SafeFolder {
        param([string]$Path)
        if ([string]::IsNullOrWhiteSpace($Path)) { return }
        # Never allow deleting the entire Dell root folder accidentally
        $dellRoot = (Resolve-Path $makeDriversPath).ProviderPath
        $target = (Resolve-Path $Path -ErrorAction SilentlyContinue)?.ProviderPath
        if ($null -eq $target) { return }
        if ($target -eq $dellRoot) { return }
        if (-not ($target.StartsWith($dellRoot,[System.StringComparison]::OrdinalIgnoreCase))) { return }
        Remove-Item -Path $target -Recurse -Force -ErrorAction SilentlyContinue
    }

    try {
        # Existing drivers short‑circuit
        $existing = Test-ExistingDriver -Make $make -Model $sanitizedModelName -DriversFolder $DriversFolder -Identifier $modelDisplay -ProgressQueue $ProgressQueue
        if ($existing) {
            if (-not $existing.PSObject.Properties['Model']) {
                $existing | Add-Member -MemberType NoteProperty -Name 'Model' -Value $modelDisplay
            }
            if ($CompressToWim -and $existing.Status -eq 'Already downloaded') {
                $wimPath = Join-Path $makeDriversPath "$sanitizedModelName.wim"
                $srcPath = Join-Path $makeDriversPath $sanitizedModelName
                if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $modelDisplay -Status 'Compressing existing...' }
                try {
                    Compress-DriverFolderToWim -SourceFolderPath $srcPath -DestinationWimPath $wimPath -WimName $modelDisplay -WimDescription "Drivers for $modelDisplay" -PreserveSource:$PreserveSourceOnCompress -ErrorAction Stop
                    $existing.Status = 'Already downloaded & Compressed'
                    $existing.DriverPath = Join-Path $make "$sanitizedModelName.wim"
                    $existing.Success = $true
                }
                catch {
                    WriteLog "Compression failed for $($modelDisplay): $($_.Exception.Message)"
                    $existing.Status = 'Already downloaded (Compression failed)'
                }
                if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $modelDisplay -Status $existing.Status }
            }
            return $existing
        }

        if (-not (Test-Path $makeDriversPath)) { New-Item -Path $makeDriversPath -ItemType Directory -Force | Out-Null }
        if (-not (Test-Path $modelPath)) { New-Item -Path $modelPath -ItemType Directory -Force | Out-Null }

        $packages = @()

        if ($WindowsRelease -le 11) {
            $cabUrl = $DriverItemData.CabUrl
            if ([string]::IsNullOrWhiteSpace($cabUrl)) {
                WriteLog "CabUrl missing for '$modelDisplay' – falling back to legacy CatalogPC parsing."
                # Fallback legacy client method
                $catalogCab = Join-Path $makeDriversPath 'CatalogPC.cab'
                $catalogXml = Join-Path $makeDriversPath 'CatalogPC.xml'
                $catalogUrl = 'http://downloads.dell.com/catalog/CatalogPC.cab'
                $need = $true
                if (Test-Path $catalogXml) {
                    if (((Get-Date) - (Get-Item $catalogXml).CreationTime).TotalDays -lt 7) { $need = $false }
                }
                if ($need) {
                    if (Test-Path $catalogCab) { Remove-SafeFolder $catalogCab }
                    if (Test-Path $catalogXml) { Remove-SafeFolder $catalogXml }
                    Start-BitsTransferWithRetry -Source $catalogUrl -Destination $catalogCab
                    Invoke-Process -FilePath Expand.exe -ArgumentList """$catalogCab"" ""$catalogXml""" | Out-Null
                    Remove-Item $catalogCab -Force -ErrorAction SilentlyContinue
                }
                if (-not (Test-Path $catalogXml)) { throw "Legacy fallback failed; missing $catalogXml" }
                [xml]$xmlContent = Get-Content -Path $catalogXml -Raw
                $baseLocation = "https://$($xmlContent.manifest.baseLocation)/"
                $softwareComponents = $xmlContent.Manifest.SoftwareComponent | Where-Object { $_.ComponentType.value -eq 'DRVR' }

                $latestDrivers = @{}
                foreach ($component in $softwareComponents) {
                    $models = $component.SupportedSystems.Brand.Model
                    foreach ($m in $models) {
                        if ($m.Display.'#cdata-section' -eq $modelDisplay) {
                            $validOS = $component.SupportedOperatingSystems.OperatingSystem | Where-Object { $_.osArch -eq $WindowsArch }
                            if (-not $validOS) { continue }
                            $driverPath = $component.path
                            $downloadUrl = $baseLocation + $driverPath
                            $fileName = [IO.Path]::GetFileName($driverPath)
                            $name = $component.Name.Display.'#cdata-section' -replace '[\\\/\:\*\?\"\<\>\| ]','_' -replace '[\,]','-'
                            $category = $component.Category.Display.'#cdata-section' -replace '[\\\/\:\*\?\"\<\>\| ]','_'
                            $version = [version]$component.vendorVersion
                            $namePrefix = ($name -split '-')[0]
                            if (-not $latestDrivers[$category]) { $latestDrivers[$category] = @{} }
                            if (-not $latestDrivers[$category][$namePrefix] -or $latestDrivers[$category][$namePrefix].Version -lt $version) {
                                $latestDrivers[$category][$namePrefix] = [pscustomobject]@{
                                    Name = $name
                                    DownloadUrl = $downloadUrl
                                    DriverFileName = $fileName
                                    Version = $version
                                    Category = $category
                                }
                            }
                        }
                    }
                }
                foreach ($cat in $latestDrivers.Keys) { foreach ($drv in $latestDrivers[$cat].Values) { $packages += $drv } }
            }
            else {
                # Normal new model-based workflow
                $modelCabName = [IO.Path]::GetFileName($cabUrl)
                if ([string]::IsNullOrWhiteSpace($modelCabName)) { throw "Derived model cab name empty for $modelDisplay" }
                $modelCabPath = Join-Path $makeDriversPath $modelCabName
                $modelXmlPath = Join-Path $makeDriversPath ([IO.Path]::GetFileNameWithoutExtension($modelCabName) + '.xml')

                if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $modelDisplay -Status 'Downloading catalog...' }
                if (Test-Path $modelCabPath) { Remove-SafeFolder $modelCabPath }
                if (Test-Path $modelXmlPath) { Remove-SafeFolder $modelXmlPath }

                Start-BitsTransferWithRetry -Source $cabUrl -Destination $modelCabPath
                Invoke-Process -FilePath Expand.exe -ArgumentList """$modelCabPath"" ""$modelXmlPath""" | Out-Null
                Remove-Item $modelCabPath -Force -ErrorAction SilentlyContinue
                if (-not (Test-Path $modelXmlPath)) { throw "Model XML not found after extraction: $modelXmlPath" }

                if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $modelDisplay -Status 'Selecting latest drivers...' }
                $packages = Get-DellLatestDriverPackages -ModelXmlPath $modelXmlPath -WindowsArch $WindowsArch -WindowsRelease $WindowsRelease
            }
        }
        else {
            # Server legacy logic unchanged (kept as before)
            if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $modelDisplay -Status 'Preparing server catalog...' }
            $catalogCab = Join-Path $makeDriversPath 'Catalog.cab'
            $catalogXml = Join-Path $makeDriversPath 'Catalog.xml'
            $catalogUrl = 'https://downloads.dell.com/catalog/Catalog.cab'
            $need = $true
            if (Test-Path $catalogXml) {
                if (((Get-Date) - (Get-Item $catalogXml).CreationTime).TotalDays -lt 7) { $need = $false }
            }
            if ($need) {
                if (Test-Path $catalogCab) { Remove-SafeFolder $catalogCab }
                if (Test-Path $catalogXml) { Remove-SafeFolder $catalogXml }
                Start-BitsTransferWithRetry -Source $catalogUrl -Destination $catalogCab
                Invoke-Process -FilePath Expand.exe -ArgumentList """$catalogCab"" ""$catalogXml""" | Out-Null
                Remove-Item $catalogCab -Force -ErrorAction SilentlyContinue
            }
            if (-not (Test-Path $catalogXml)) { throw "Server catalog XML missing: $catalogXml" }

            [xml]$xmlContent = Get-Content -Path $catalogXml -Raw
            $baseLocation = "https://$($xmlContent.manifest.baseLocation)/"
            $softwareComponents = $xmlContent.Manifest.SoftwareComponent | Where-Object { $_.ComponentType.value -eq 'DRVR' }
            $latestDrivers = @{}
            foreach ($component in $softwareComponents) {
                $models = $component.SupportedSystems.Brand.Model
                foreach ($m in $models) {
                    if ($m.Display.'#cdata-section' -eq $modelDisplay) {
                        $validOS = $component.SupportedOperatingSystems.OperatingSystem | Where-Object { $_.osArch -eq $WindowsArch }
                        if (-not $validOS) { continue }
                        $driverPath = $component.path
                        $downloadUrl = $baseLocation + $driverPath
                        $fileName = [IO.Path]::GetFileName($driverPath)
                        $name = $component.Name.Display.'#cdata-section' -replace '[\\\/\:\*\?\"\<\>\| ]','_' -replace '[\,]','-'
                        $category = $component.Category.Display.'#cdata-section' -replace '[\\\/\:\*\?\"\<\>\| ]','_'
                        $version = [version]$component.vendorVersion
                        $namePrefix = ($name -split '-')[0]
                        if (-not $latestDrivers[$category]) { $latestDrivers[$category] = @{} }
                        if (-not $latestDrivers[$category][$namePrefix] -or $latestDrivers[$category][$namePrefix].Version -lt $version) {
                            $latestDrivers[$category][$namePrefix] = [pscustomobject]@{
                                Name = $name
                                DownloadUrl = $downloadUrl
                                DriverFileName = $fileName
                                Version = $version
                                Category = $category
                            }
                        }
                    }
                }
            }
            foreach ($cat in $latestDrivers.Keys) { foreach ($drv in $latestDrivers[$cat].Values) { $packages += $drv } }
        }

        if (-not $packages -or $packages.Count -eq 0) {
            if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $modelDisplay -Status 'No drivers found for OS' }
            return [pscustomobject]@{ Model = $modelDisplay; Status = 'No drivers found for OS'; Success = $true; DriverPath = $driverRelativePath }
        }

        $total = $packages.Count
        $idx = 0
        foreach ($pkg in $packages) {
            $idx++
            $status = "Downloading $idx/$total"
            if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $modelDisplay -Status $status }

            $categorySafe = ($pkg.Category -replace '[\\\/\:\*\?\"\<\>\| ]','_')
            $downloadFolder = Join-Path $modelPath $categorySafe
            if (-not (Test-Path $downloadFolder)) { New-Item -Path $downloadFolder -ItemType Directory -Force | Out-Null }
            $driverFilePath = Join-Path $downloadFolder $pkg.DriverFileName
            $plainName = [IO.Path]::GetFileNameWithoutExtension($pkg.DriverFileName)
            if ([string]::IsNullOrWhiteSpace($plainName)) { $plainName = "_extract" }
            $extractFolder = Join-Path $downloadFolder $plainName

            if (Test-Path $extractFolder) {
                $sz = (Get-ChildItem -Path $extractFolder -Recurse -Exclude *.log | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
                if ($sz -gt 1KB) { continue }
            }

            if (-not (Test-Path $driverFilePath)) {
                try { Start-BitsTransferWithRetry -Source $pkg.DownloadUrl -Destination $driverFilePath }
                catch { WriteLog "Download failed: $($pkg.DownloadUrl) $($_.Exception.Message)"; continue }
            }

            if (-not (Test-Path $extractFolder)) { New-Item -Path $extractFolder -ItemType Directory -Force | Out-Null }

            $arg1 = "/s /e=`"$extractFolder`" /l=`"$extractFolder\log.log`""
            $arg2 = "/s /drivers=`"$extractFolder`" /l=`"$extractFolder\log.log`""
            $ok = $false
            try {
                Invoke-Process -FilePath $driverFilePath -ArgumentList $arg1 | Out-Null
                $sz = (Get-ChildItem -Path $extractFolder -Recurse -Exclude *.log | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
                if ($sz -gt 1KB) { $ok = $true }
                if (-not $ok) {
                    Remove-SafeFolder $extractFolder
                    New-Item -Path $extractFolder -ItemType Directory -Force | Out-Null
                    Invoke-Process -FilePath $driverFilePath -ArgumentList $arg2 | Out-Null
                    $sz = (Get-ChildItem -Path $extractFolder -Recurse -Exclude *.log | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
                    if ($sz -gt 1KB) { $ok = $true }
                }
            }
            catch {
                WriteLog "Extraction error: $($_.Exception.Message)"
            }

            if ($ok) {
                Remove-Item $driverFilePath -Force -ErrorAction SilentlyContinue
            }
        }

        if ($CompressToWim) {
            if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $modelDisplay -Status 'Compressing...' }
            $wimPath = Join-Path $makeDriversPath "$sanitizedModelName.wim"
            try {
                Compress-DriverFolderToWim -SourceFolderPath $modelPath -DestinationWimPath $wimPath -WimName $modelDisplay -WimDescription $modelDisplay -PreserveSource:$PreserveSourceOnCompress -ErrorAction Stop
                $driverRelativePath = Join-Path $make "$sanitizedModelName.wim"
                $statusFinal = 'Completed & Compressed'
            }
            catch {
                WriteLog "Compression failed for $($modelDisplay): $($_.Exception.Message)"
                $statusFinal = 'Completed (Compression Failed)'
            }
        }
        else {
            $statusFinal = 'Completed'
        }

        if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $modelDisplay -Status $statusFinal }
        return [pscustomobject]@{ Model = $modelDisplay; Status = $statusFinal; Success = $true; DriverPath = $driverRelativePath }
    }
    catch {
        $err = "Error: $($_.Exception.Message.Split('.')[0])"
        WriteLog "Save-DellDriversTask error for $($modelDisplay): $($_.Exception.ToString())"
        if ($null -ne $ProgressQueue) { Invoke-ProgressUpdate -ProgressQueue $ProgressQueue -Identifier $modelDisplay -Status $err }
        return [pscustomobject]@{ Model = $modelDisplay; Status = $err; Success = $false; DriverPath = $null }
    }
}

Export-ModuleMember -Function *