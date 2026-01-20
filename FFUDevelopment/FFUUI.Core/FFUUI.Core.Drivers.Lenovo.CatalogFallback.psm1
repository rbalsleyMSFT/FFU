<#
.SYNOPSIS
    Lenovo catalogv2.xml fallback for driver discovery when PSREF API unavailable.

.DESCRIPTION
    Provides enterprise model coverage (ThinkPad, ThinkCentre, ThinkStation) from
    the Lenovo catalogv2.xml catalog when PSREF API authentication fails.

    IMPORTANT: catalogv2.xml has PARTIAL coverage compared to PSREF:
    - Included: ThinkPad, ThinkCentre, ThinkStation enterprise models
    - Missing: 300w, 500w, 100e, and other consumer/education models

.NOTES
    Module: FFUUI.Core.Drivers.Lenovo.CatalogFallback
    Version: 1.0.0
#>

# Module-scoped cache
$script:CatalogCache = @{
    Data      = $null
    CachedAt  = [DateTime]::MinValue
    TTLMinutes = 10080  # 7 days default
}

function Get-LenovoCatalogV2 {
    <#
    .SYNOPSIS
        Downloads and caches the Lenovo catalogv2.xml file.

    .DESCRIPTION
        Retrieves the Lenovo catalogv2.xml enterprise driver catalog. Uses a
        two-tier caching strategy: memory cache for fast access, file cache
        for persistence across sessions.

    .PARAMETER FFUDevelopmentPath
        Base path for FFUDevelopment folder. Used to locate cache directory.

    .PARAMETER ForceRefresh
        Forces download of fresh catalog, bypassing both memory and file cache.

    .OUTPUTS
        System.Xml.XmlDocument containing the parsed catalog.

    .EXAMPLE
        $catalog = Get-LenovoCatalogV2
        Returns cached catalog or downloads fresh if cache expired.

    .EXAMPLE
        $catalog = Get-LenovoCatalogV2 -ForceRefresh
        Downloads fresh catalog regardless of cache state.
    #>
    [CmdletBinding()]
    [OutputType([System.Xml.XmlDocument])]
    param(
        [Parameter()]
        [string]$FFUDevelopmentPath = $null,

        [Parameter()]
        [switch]$ForceRefresh
    )

    $catalogUrl = 'https://download.lenovo.com/cdrt/td/catalogv2.xml'

    # Use local cache file if available
    if ([string]::IsNullOrEmpty($FFUDevelopmentPath)) {
        $FFUDevelopmentPath = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    }
    $cacheDir = Join-Path $FFUDevelopmentPath '.cache'
    $cachePath = Join-Path $cacheDir 'catalogv2.xml'

    # Check memory cache first
    $cacheAge = ([DateTime]::Now - $script:CatalogCache.CachedAt).TotalMinutes
    if (-not $ForceRefresh -and $script:CatalogCache.Data -and $cacheAge -lt $script:CatalogCache.TTLMinutes) {
        Write-Verbose "Using memory-cached catalogv2.xml (age: $([int]$cacheAge) minutes)"
        return $script:CatalogCache.Data
    }

    # Check file cache
    if (-not $ForceRefresh -and (Test-Path $cachePath)) {
        $fileAge = ([DateTime]::Now - (Get-Item $cachePath).LastWriteTime).TotalMinutes
        if ($fileAge -lt $script:CatalogCache.TTLMinutes) {
            try {
                [xml]$catalog = Get-Content -Path $cachePath -Encoding UTF8 -ErrorAction Stop
                $script:CatalogCache.Data = $catalog
                $script:CatalogCache.CachedAt = (Get-Item $cachePath).LastWriteTime
                if (Get-Command -Name WriteLog -ErrorAction SilentlyContinue) {
                    WriteLog "Loaded catalogv2.xml from file cache (age: $([int]$fileAge) minutes)"
                }
                else {
                    Write-Verbose "Loaded catalogv2.xml from file cache (age: $([int]$fileAge) minutes)"
                }
                return $catalog
            }
            catch {
                $errorMsg = "Failed to load cached catalog: $($_.Exception.Message)"
                if (Get-Command -Name WriteLog -ErrorAction SilentlyContinue) {
                    WriteLog $errorMsg
                }
                else {
                    Write-Warning $errorMsg
                }
            }
        }
    }

    # Download fresh catalog
    $downloadMsg = "Downloading Lenovo catalogv2.xml from $catalogUrl..."
    if (Get-Command -Name WriteLog -ErrorAction SilentlyContinue) {
        WriteLog $downloadMsg
    }
    else {
        Write-Verbose $downloadMsg
    }

    try {
        # Ensure cache directory exists
        if (-not (Test-Path $cacheDir)) {
            New-Item -Path $cacheDir -ItemType Directory -Force | Out-Null
        }

        # Download to temp then move
        $tempPath = Join-Path $env:TEMP "catalogv2_$(Get-Random).xml"
        Invoke-WebRequest -Uri $catalogUrl -OutFile $tempPath -UseBasicParsing -ErrorAction Stop

        # Parse to validate
        [xml]$catalog = Get-Content -Path $tempPath -Encoding UTF8 -ErrorAction Stop

        # Move to cache
        Move-Item -Path $tempPath -Destination $cachePath -Force

        # Update memory cache
        $script:CatalogCache.Data = $catalog
        $script:CatalogCache.CachedAt = [DateTime]::Now

        $successMsg = "Downloaded and cached catalogv2.xml successfully"
        if (Get-Command -Name WriteLog -ErrorAction SilentlyContinue) {
            WriteLog $successMsg
        }
        else {
            Write-Verbose $successMsg
        }
        return $catalog
    }
    catch {
        $errorMsg = "ERROR: Failed to download catalogv2.xml: $($_.Exception.Message)"
        if (Get-Command -Name WriteLog -ErrorAction SilentlyContinue) {
            WriteLog $errorMsg
        }
        else {
            Write-Error $errorMsg
        }
        throw
    }
}

function Get-LenovoCatalogV2Models {
    <#
    .SYNOPSIS
        Searches catalogv2.xml for models matching the search term.

    .DESCRIPTION
        Returns model information from catalogv2.xml as fallback when PSREF unavailable.
        NOTE: Only enterprise models (ThinkPad, ThinkCentre, ThinkStation) are included.
        Consumer models (300w, 500w, 100e, etc.) are NOT available in catalogv2.xml.

    .PARAMETER ModelSearchTerm
        The model name or machine type to search for.

    .PARAMETER FFUDevelopmentPath
        Base path for FFUDevelopment folder. Used to locate cache directory.

    .OUTPUTS
        Array of PSCustomObjects with Make, Model, ProductName, MachineType, IsFallback properties.
        IsFallback is always $true to indicate results came from catalog fallback.

    .EXAMPLE
        Get-LenovoCatalogV2Models -ModelSearchTerm "ThinkPad L490"
        Returns all ThinkPad L490 variants from catalogv2.xml.

    .EXAMPLE
        Get-LenovoCatalogV2Models -ModelSearchTerm "20Q6"
        Searches by machine type and returns matching models.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ModelSearchTerm,

        [Parameter()]
        [string]$FFUDevelopmentPath = $null
    )

    $models = [System.Collections.Generic.List[PSCustomObject]]::new()

    try {
        $catalog = Get-LenovoCatalogV2 -FFUDevelopmentPath $FFUDevelopmentPath

        # Log that we're in fallback mode
        $fallbackMsg = "FALLBACK MODE: Searching catalogv2.xml (partial coverage - enterprise models only)"
        if (Get-Command -Name WriteLog -ErrorAction SilentlyContinue) {
            WriteLog $fallbackMsg
        }
        else {
            Write-Warning $fallbackMsg
        }

        # Search products by model name
        foreach ($product in $catalog.Products.Product) {
            foreach ($model in $product.Model) {
                $modelName = $model.name

                # Check if model name matches search term
                if ($modelName -like "*$ModelSearchTerm*") {
                    foreach ($type in $model.Types.Type) {
                        $machineType = $type.mtm

                        if (-not [string]::IsNullOrWhiteSpace($machineType)) {
                            $displayModel = "$modelName ($machineType)"
                            $models.Add([PSCustomObject]@{
                                Make        = 'Lenovo'
                                Model       = $displayModel
                                ProductName = $modelName
                                MachineType = $machineType
                                IsFallback  = $true  # Flag to indicate fallback source
                            })
                        }
                    }
                }
            }
        }

        # Also search by machine type if no results from model name search
        if ($models.Count -eq 0) {
            foreach ($product in $catalog.Products.Product) {
                foreach ($model in $product.Model) {
                    foreach ($type in $model.Types.Type) {
                        if ($type.mtm -like "*$ModelSearchTerm*") {
                            $modelName = $model.name
                            $machineType = $type.mtm
                            $displayModel = "$modelName ($machineType)"

                            $models.Add([PSCustomObject]@{
                                Make        = 'Lenovo'
                                Model       = $displayModel
                                ProductName = $modelName
                                MachineType = $machineType
                                IsFallback  = $true
                            })
                        }
                    }
                }
            }
        }

        if ($models.Count -gt 0) {
            $successMsg = "Found $($models.Count) models in catalogv2.xml for '$ModelSearchTerm' (fallback mode)"
            if (Get-Command -Name WriteLog -ErrorAction SilentlyContinue) {
                WriteLog $successMsg
            }
            else {
                Write-Verbose $successMsg
            }
        }
        else {
            $notFoundMsg = "No models found in catalogv2.xml for '$ModelSearchTerm'. This model may require PSREF API."
            if (Get-Command -Name WriteLog -ErrorAction SilentlyContinue) {
                WriteLog $notFoundMsg
            }
            else {
                Write-Warning $notFoundMsg
            }
        }
    }
    catch {
        $errorMsg = "ERROR: Failed to search catalogv2.xml: $($_.Exception.Message)"
        if (Get-Command -Name WriteLog -ErrorAction SilentlyContinue) {
            WriteLog $errorMsg
        }
        else {
            Write-Error $errorMsg
        }
    }

    return $models.ToArray()
}

function Get-LenovoCatalogV2DriverUrl {
    <#
    .SYNOPSIS
        Gets the SCCM driver pack URL for a specific machine type from catalogv2.xml.

    .DESCRIPTION
        Looks up the SCCM driver pack URL for a given Lenovo machine type and
        Windows version. First tries to find an exact version match, then falls
        back to any available win10 driver pack.

    .PARAMETER MachineType
        The Lenovo machine type (e.g., "20Q6").

    .PARAMETER WindowsVersion
        The Windows version (e.g., "22H2", "23H2"). Defaults to "22H2".

    .PARAMETER FFUDevelopmentPath
        Base path for FFUDevelopment folder. Used to locate cache directory.

    .OUTPUTS
        String URL to the SCCM driver pack, or $null if not found.

    .EXAMPLE
        Get-LenovoCatalogV2DriverUrl -MachineType "20Q6"
        Returns SCCM driver pack URL for machine type 20Q6 with Windows 22H2.

    .EXAMPLE
        Get-LenovoCatalogV2DriverUrl -MachineType "21HD" -WindowsVersion "23H2"
        Returns SCCM driver pack URL for machine type 21HD with Windows 23H2.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$MachineType,

        [Parameter()]
        [string]$WindowsVersion = '22H2',

        [Parameter()]
        [string]$FFUDevelopmentPath = $null
    )

    try {
        $catalog = Get-LenovoCatalogV2 -FFUDevelopmentPath $FFUDevelopmentPath

        foreach ($product in $catalog.Products.Product) {
            foreach ($model in $product.Model) {
                foreach ($type in $model.Types.Type) {
                    if ($type.mtm -eq $MachineType) {
                        # Look for SCCM pack matching Windows version
                        foreach ($sccm in $type.SCCM) {
                            if ($sccm.version -eq $WindowsVersion -and $sccm.os -eq 'win10') {
                                $url = $sccm.InnerText.Trim()
                                if (-not [string]::IsNullOrWhiteSpace($url)) {
                                    $foundMsg = "Found SCCM pack for $MachineType Win${WindowsVersion}: $url"
                                    if (Get-Command -Name WriteLog -ErrorAction SilentlyContinue) {
                                        WriteLog $foundMsg
                                    }
                                    else {
                                        Write-Verbose $foundMsg
                                    }
                                    return $url
                                }
                            }
                        }
                        # Fallback: any SCCM pack for win10
                        foreach ($sccm in $type.SCCM) {
                            if ($sccm.os -eq 'win10') {
                                $url = $sccm.InnerText.Trim()
                                if (-not [string]::IsNullOrWhiteSpace($url)) {
                                    $altMsg = "Found alternate SCCM pack for $MachineType`: $url (version: $($sccm.version))"
                                    if (Get-Command -Name WriteLog -ErrorAction SilentlyContinue) {
                                        WriteLog $altMsg
                                    }
                                    else {
                                        Write-Verbose $altMsg
                                    }
                                    return $url
                                }
                            }
                        }
                    }
                }
            }
        }

        $notFoundMsg = "No SCCM driver pack found in catalogv2.xml for machine type: $MachineType"
        if (Get-Command -Name WriteLog -ErrorAction SilentlyContinue) {
            WriteLog $notFoundMsg
        }
        else {
            Write-Warning $notFoundMsg
        }
        return $null
    }
    catch {
        $errorMsg = "ERROR: Failed to lookup driver URL: $($_.Exception.Message)"
        if (Get-Command -Name WriteLog -ErrorAction SilentlyContinue) {
            WriteLog $errorMsg
        }
        else {
            Write-Error $errorMsg
        }
        return $null
    }
}

function Reset-LenovoCatalogV2Cache {
    <#
    .SYNOPSIS
        Resets the in-memory catalog cache.

    .DESCRIPTION
        Clears the memory cache for catalogv2.xml, forcing a fresh download
        on the next call to Get-LenovoCatalogV2. Does not delete the file cache.

    .EXAMPLE
        Reset-LenovoCatalogV2Cache
        Clears the memory cache.
    #>
    [CmdletBinding()]
    param()

    $script:CatalogCache.Data = $null
    $script:CatalogCache.CachedAt = [DateTime]::MinValue
    Write-Verbose "Lenovo catalogv2.xml memory cache cleared"
}

Export-ModuleMember -Function Get-LenovoCatalogV2, Get-LenovoCatalogV2Models, Get-LenovoCatalogV2DriverUrl, Reset-LenovoCatalogV2Cache
