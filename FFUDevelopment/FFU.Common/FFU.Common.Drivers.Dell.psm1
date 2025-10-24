<#
.SYNOPSIS
    Common Dell driver helpers (catalog index, model listing, latest package selection).
#>

function Convert-DellVendorVersion {
    param([Parameter(Mandatory=$true)][string]$VendorVersion)
    $segments = $VendorVersion.Split('.') | ForEach-Object {
        if ($_ -match '^\d+$') { [int]$_ } else { 0 }
    }
    return ,$segments
}

function Compare-DellVendorVersion {
    param(
        [int[]]$Left,
        [int[]]$Right
    )
    $len = [Math]::Max($Left.Length,$Right.Length)
    for ($i=0; $i -lt $len; $i++) {
        $l = if ($i -lt $Left.Length) { $Left[$i] } else { 0 }
        $r = if ($i -lt $Right.Length) { $Right[$i] } else { 0 }
        if ($l -gt $r) { return 1 }
        if ($l -lt $r) { return -1 }
    }
    return 0
}

function Get-DellCatalogIndex {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$DriversFolder
    )

    $dellFolder = Join-Path $DriversFolder 'Dell'
    if (-not (Test-Path $dellFolder)) { New-Item -Path $dellFolder -ItemType Directory -Force | Out-Null }
    $cabPath = Join-Path $dellFolder 'CatalogIndexPC.cab'
    $xmlPath = Join-Path $dellFolder 'CatalogIndexPC.xml'
    $url = 'https://downloads.dell.com/catalog/CatalogIndexPC.cab'

    $need = $true
    if (Test-Path $xmlPath) {
        $ageDays = ((Get-Date) - (Get-Item $xmlPath).CreationTime).TotalDays
        if ($ageDays -lt 7) { $need = $false }
    }

    if ($need) {
        if (Test-Path $cabPath) { Remove-Item $cabPath -Force -ErrorAction SilentlyContinue }
        if (Test-Path $xmlPath) { Remove-Item $xmlPath -Force -ErrorAction SilentlyContinue }
        Start-BitsTransferWithRetry -Source $url -Destination $cabPath
        Invoke-Process -FilePath Expand.exe -ArgumentList """$cabPath"" ""$xmlPath""" | Out-Null
        Remove-Item $cabPath -Force -ErrorAction SilentlyContinue
    }

    if (-not (Test-Path $xmlPath)) { throw "Dell CatalogIndexPC XML missing: $xmlPath" }
    return $xmlPath
}

function Get-DellClientModels {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$CatalogIndexXmlPath
    )

    $settings = New-Object System.Xml.XmlReaderSettings
    $settings.IgnoreWhitespace = $true
    $settings.IgnoreComments = $true
    $reader = [System.Xml.XmlReader]::Create($CatalogIndexXmlPath,$settings)

    $models = [System.Collections.Generic.List[pscustomobject]]::new()
    try {
        while ($reader.Read()) {
            if ($reader.NodeType -eq [System.Xml.XmlNodeType]::Element -and $reader.Name -eq 'GroupManifest') {
                # Read subtree to pick out brand/model/systemID + path
                $sub = $reader.ReadSubtree()
                $doc = New-Object System.Xml.XmlDocument
                $doc.Load($sub)
                $sub.Dispose()

                # Use local-name() to ignore namespaces
                $brandNode = $doc.SelectSingleNode("//*[local-name()='SupportedSystems']/*[local-name()='Brand']")
                if (-not $brandNode) { continue }
                $brandDisplay = ($brandNode.SelectSingleNode("*[local-name()='Display']")?.InnerText).Trim()
                $modelNode = $brandNode.SelectSingleNode("*[local-name()='Model']")
                if (-not $modelNode) { continue }
                $modelNumber = ($modelNode.SelectSingleNode("*[local-name()='Display']")?.InnerText).Trim()
                $systemId = $modelNode.GetAttribute('systemID')
                $manifestInfo = $doc.SelectSingleNode("//*[local-name()='ManifestInformation']")
                if (-not $manifestInfo) { continue }
                $pathAttr = $manifestInfo.GetAttribute('path')
                if (-not $pathAttr) { continue }
                $cabUrl = 'https://downloads.dell.com/' + $pathAttr
                # Normalize model display to avoid duplicate brand (e.g. Latitude Latitude 13 (0432))
                $prefixedModelNumber = $modelNumber
                if ($modelNumber -and $brandDisplay) {
                    if ($modelNumber.StartsWith($brandDisplay,[System.StringComparison]::OrdinalIgnoreCase)) {
                        $prefixedModelNumber = $modelNumber
                    }
                    else {
                        $prefixedModelNumber = "$brandDisplay $modelNumber"
                    }
                }
                elseif ($brandDisplay -and -not $modelNumber) {
                    $prefixedModelNumber = $brandDisplay
                }
                $modelDisplay = "$prefixedModelNumber ($systemId)"
                $models.Add([pscustomobject]@{
                    Brand           = $brandDisplay
                    ModelNumber     = $modelNumber
                    SystemId        = $systemId
                    CabRelativePath = $pathAttr
                    CabUrl          = $cabUrl
                    ModelDisplay    = $modelDisplay
                })
            }
        }
    }
    finally {
        $reader.Dispose()
    }
    return $models
}

function Get-DellLatestDriverPackages {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$ModelXmlPath,
        [Parameter(Mandatory=$true)][string]$WindowsArch,
        [Parameter(Mandatory=$true)][int]$WindowsRelease
    )

    if (-not (Test-Path $ModelXmlPath)) { throw "Model XML not found: $ModelXmlPath" }

    $xml = [xml](Get-Content -Path $ModelXmlPath -Raw)

    # Collect all SoftwareComponent nodes
    $components = $xml.SelectNodes("//*[local-name()='SoftwareComponent']")
    if (-not $components) { return @() }

    $rawPackages = [System.Collections.Generic.List[pscustomobject]]::new()

    foreach ($comp in $components) {
        $ctype = $comp.SelectSingleNode("*[local-name()='ComponentType']")
        if (-not $ctype) { continue }
        if ($ctype.GetAttribute('value') -ne 'DRVR') { continue }

        # OS filtering (arch only – release filtering intentionally minimal for now)
        $osNodes = @($comp.SelectNodes("*[local-name()='SupportedOperatingSystems']/*[local-name()='OperatingSystem']"))
        if (-not $osNodes) { continue }
        $validOS = $osNodes | Where-Object { $_.GetAttribute('osArch') -eq $WindowsArch } | Select-Object -First 1
        if (-not $validOS) { continue }

        $path = $comp.GetAttribute('path')
        if (-not $path) { continue }

        $downloadUrl    = "https://downloads.dell.com/$path"
        $fileName       = [IO.Path]::GetFileName($path)
        $vendorVersion  = $comp.GetAttribute('vendorVersion')
        $versionArr     = if ($vendorVersion) { Convert-DellVendorVersion $vendorVersion } else { @(0) }
        $dateTimeAttr   = $comp.GetAttribute('dateTime')
        $dt             = Get-Date
        if ($dateTimeAttr) {
            try { $dt = [DateTime]::Parse($dateTimeAttr) } catch { }
        }

        $categoryNode = $comp.SelectSingleNode("*[local-name()='Category']/*[local-name()='Display']")
        $category     = if ($categoryNode) { $categoryNode.InnerText.Trim() } else { 'Uncategorized' }

        # Collect componentIDs (SupportedDevices + SupportedDCHDevices)
        $compIds = [System.Collections.Generic.List[string]]::new()
        $devNodes = @($comp.SelectNodes(".//*[local-name()='Device']"))
        foreach ($dn in $devNodes) {
            $id = $dn.GetAttribute('componentID')
            if ($id) { [void]$compIds.Add($id) }
        }
        if ($compIds.Count -eq 0) { continue }

        # Build a deterministic sortable key: zero-pad each numeric segment to 6 digits
        $versionSortable = ($versionArr | ForEach-Object { $_.ToString('D6') }) -join '-'

        $rawPackages.Add([pscustomobject]@{
            Path            = $path
            DownloadUrl     = $downloadUrl
            FileName        = $fileName
            Category        = $category
            VendorVersion   = $vendorVersion
            VersionArray    = $versionArr
            VersionSortable = $versionSortable
            DateTime        = $dt
            ComponentIds    = $compIds
        })
    }

    if ($rawPackages.Count -eq 0) { return @() }

    # Sort newest first by VersionSortable (lexicographic works due to zero padding) then DateTime
    $sorted = $rawPackages | Sort-Object -Property @{ Expression = { $_.VersionSortable }; Descending = $true }, @{ Expression = { $_.DateTime }; Descending = $true }

    $chosen      = [System.Collections.Generic.List[pscustomobject]]::new()
    $assignedIds = [System.Collections.Generic.HashSet[string]]::new()

    foreach ($pkg in $sorted) {
        $hasOverlap = $false
        foreach ($cid in $pkg.ComponentIds) {
            if ($assignedIds.Contains($cid)) { $hasOverlap = $true; break }
        }
        if ($hasOverlap) {
            WriteLog "Get-DellLatestDriverPackages: Skipping superseded package $($pkg.FileName) (shared componentID with newer package)."
            continue
        }

        foreach ($cid in $pkg.ComponentIds) { [void]$assignedIds.Add($cid) }

        $chosen.Add([pscustomobject]@{
            Path           = $pkg.Path
            DownloadUrl    = $pkg.DownloadUrl
            DriverFileName = $pkg.FileName
            Category       = $pkg.Category
            VendorVersion  = $pkg.VendorVersion
            DateTime       = $pkg.DateTime
            ComponentIds   = $pkg.ComponentIds
        })
    }

    if ($chosen.Count -eq 0) {
        WriteLog "Get-DellLatestDriverPackages: No qualifying driver packages after supersedence."
        return @()
    }

    WriteLog ("Get-DellLatestDriverPackages: Selected {0} package(s) after supersedence." -f $chosen.Count)
    return $chosen
}

# Resolve a Dell per‑model CabUrl when missing by inspecting CatalogIndexPC
function Resolve-DellCabUrlFromModel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$DriversFolder,
        [Parameter()][string]$ModelDisplay,
        [Parameter()][string]$SystemId
    )

    if ([string]::IsNullOrWhiteSpace($SystemId) -and -not [string]::IsNullOrWhiteSpace($ModelDisplay)) {
        # Try to parse the trailing (XXXX) token (SystemId)
        if ($ModelDisplay -match '\(([0-9A-Fa-f]{4})\)\s*$') {
            $SystemId = $matches[1].ToUpperInvariant()
        }
    }

    if ([string]::IsNullOrWhiteSpace($SystemId)) {
        WriteLog "Resolve-DellCabUrlFromModel: No SystemId could be determined from '$ModelDisplay'."
        return $null
    }

    try {
        $indexXml = Get-DellCatalogIndex -DriversFolder $DriversFolder
        # Reuse existing model parsing to avoid duplicating streaming logic
        $allModels = Get-DellClientModels -CatalogIndexXmlPath $indexXml
        $match = $allModels | Where-Object { $_.SystemId -eq $SystemId } | Select-Object -First 1
        if ($null -eq $match) {
            WriteLog "Resolve-DellCabUrlFromModel: SystemId '$SystemId' not found in CatalogIndexPC.xml."
            return $null
        }
        WriteLog "Resolve-DellCabUrlFromModel: Resolved CabUrl for '$($match.ModelDisplay)' -> $($match.CabUrl)"
        return [pscustomobject]@{
            Brand           = $match.Brand
            ModelNumber     = $match.ModelNumber
            SystemId        = $match.SystemId
            CabRelativePath = $match.CabRelativePath
            CabUrl          = $match.CabUrl
            ModelDisplay    = $match.ModelDisplay
        }
    }
    catch {
        WriteLog "Resolve-DellCabUrlFromModel: Failure resolving CabUrl for '$ModelDisplay' / SystemId '$SystemId' : $($_.Exception.Message)"
        return $null
    }
}

Export-ModuleMember -Function Convert-DellVendorVersion,Compare-DellVendorVersion,Get-DellCatalogIndex,Get-DellClientModels,Get-DellLatestDriverPackages,Resolve-DellCabUrlFromModel