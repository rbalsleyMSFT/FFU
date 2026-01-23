<#
.SYNOPSIS
    Common Microsoft/Surface driver helpers (cache index, SKU mapping).
.DESCRIPTION
    This module contains Microsoft/Surface-specific functions used by the UI and scripts
    to map Surface driver packs to System SKU values using:
    - Source A: Surface System SKU reference (Learn)
    - Source B: Support page model list
    - Source C: Download Center details (window.__DLCDetails__)
#>

# --------------------------------------------------------------------------
# SECTION: Microsoft Surface Driver Index Cache (Sources A/B/C)
# --------------------------------------------------------------------------

function Get-SurfaceDriverIndexCachePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DriversFolder
    )

    # Store the cache under Drivers\Microsoft so it travels with the driver content
    $microsoftDriversFolder = Join-Path -Path $DriversFolder -ChildPath 'Microsoft'
    if (-not (Test-Path -Path $microsoftDriversFolder -PathType Container)) {
        New-Item -Path $microsoftDriversFolder -ItemType Directory -Force | Out-Null
    }

    return (Join-Path -Path $microsoftDriversFolder -ChildPath 'SurfaceDriverIndex.json')
}

function Import-SurfaceDriverIndexCache {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DriversFolder
    )

    $cachePath = Get-SurfaceDriverIndexCachePath -DriversFolder $DriversFolder

    # Surface cache TTL (7 days): treat stale caches as missing so we re-download Sources A/B/C as needed.
    $cacheTtlDays = 7
    if (-not (Test-Path -Path $cachePath -PathType Leaf)) {
        return [pscustomobject]@{
            ModelIndex            = @()
            SkuIndex              = @()
            DownloadCenterDetails = @()
        }
    }

    try {
        $cacheAgeDays = ((Get-Date) - (Get-Item -Path $cachePath -ErrorAction Stop).LastWriteTime).TotalDays
        if ($cacheAgeDays -ge $cacheTtlDays) {
            WriteLog "Surface cache: Cache file '$cachePath' is older than $cacheTtlDays days ($([math]::Round($cacheAgeDays, 1)) days). Refreshing."
            return [pscustomobject]@{
                ModelIndex            = @()
                SkuIndex              = @()
                DownloadCenterDetails = @()
            }
        }

        WriteLog "Surface cache: Loading cached SurfaceDriverIndex.json from '$cachePath' (age: $([math]::Round($cacheAgeDays, 1)) days)."
    }
    catch {
        WriteLog "Surface cache: Failed to read cache timestamp for '$cachePath'. Refreshing. Error: $($_.Exception.Message)"
        return [pscustomobject]@{
            ModelIndex            = @()
            SkuIndex              = @()
            DownloadCenterDetails = @()
        }
    }

    try {
        $cache = Get-Content -Path $cachePath -Raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        WriteLog "Warning: Could not read Surface driver cache '$cachePath'. Creating a new cache. Error: $($_.Exception.Message)"
        return [pscustomobject]@{
            ModelIndex            = @()
            SkuIndex              = @()
            DownloadCenterDetails = @()
        }
    }

    if ($null -eq $cache) {
        return [pscustomobject]@{
            ModelIndex            = @()
            SkuIndex              = @()
            DownloadCenterDetails = @()
        }
    }

    # Ensure expected properties exist (backward compatible with earlier cache shapes)
    if (-not $cache.PSObject.Properties['ModelIndex']) {
        $cache | Add-Member -NotePropertyName ModelIndex -NotePropertyValue @()
    }
    if (-not $cache.PSObject.Properties['SkuIndex']) {
        $cache | Add-Member -NotePropertyName SkuIndex -NotePropertyValue @()
    }
    if (-not $cache.PSObject.Properties['DownloadCenterDetails']) {
        $cache | Add-Member -NotePropertyName DownloadCenterDetails -NotePropertyValue @()
    }

    return $cache
}

function Save-SurfaceDriverIndexCache {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Cache,
        [Parameter(Mandatory = $true)]
        [string]$DriversFolder
    )

    $cachePath = Get-SurfaceDriverIndexCachePath -DriversFolder $DriversFolder
    $Cache | ConvertTo-Json -Depth 10 | Set-Content -Path $cachePath -Encoding UTF8
}

function ConvertTo-SurfaceComparableName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text
    )

    # Normalize Surface marketing strings into a comparable family key.
    # This intentionally strips consumer/commercial/processor qualifiers so we can join Sources A/B/C.
    $value = [System.Net.WebUtility]::HtmlDecode($Text)
    if ([string]::IsNullOrWhiteSpace($value)) {
        return $null
    }

    $value = $value.Trim()
    $value = $value -replace '\(', ' '
    $value = $value -replace '\)', ' '
    $value = $value -replace ',', ' '

    # Normalize punctuation that frequently differs between Support/Learn pages
    # (e.g. Wi‑Fi unicode hyphen, AT&T, Y!mobile)
    $value = $value -replace '[-\u2010\u2011\u2012\u2013\u2014\u2212]', ' '
    $value = $value -replace '&', ' '
    $value = $value -replace '!', ' '
    $value = $value -replace '™', ' '

    $value = $value -replace '(?i)\bMicrosoft\b', ''
    $value = $value -replace '(?i)\bfor\s+Business\b', ''
    $value = $value -replace '(?i)\bConsumer\b', ''
    $value = $value -replace '(?i)\bCommercial\b', ''

    # Strip processor/connection qualifiers that cause mismatches between WMI, Learn, and Support naming.
    $value = $value -replace '(?i)\bwith\s+Intel\b', ''
    $value = $value -replace '(?i)\bIntel\s+processor\b', ''
    $value = $value -replace '(?i)\bIntel\b', ''
    $value = $value -replace '(?i)\bSnapdragon\s+processor\b', ''
    $value = $value -replace '(?i)\bSnapdragon\b', ''
    $value = $value -replace '(?i)\bwith\s+5G\b', ''
    $value = $value -replace '(?i)\bLTE\b', ''
    $value = $value -replace '(?i)\b4G\b', ''
    $value = $value -replace '(?i)\bprocessor\b', ''

    # Cleanup: remove orphaned "with" left behind by earlier removals (e.g., "Surface Pro 9 with Intel Processor")
    $value = $value -replace '(?i)\bwith\b', ''
    $value = $value -replace '\s+', ' '

    return $value.Trim().ToUpperInvariant()
}

function Get-SurfaceSystemSkuReferenceIndex {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DriversFolder
    )

    # Source A: Learn page with authoritative Device / System Model / System SKU table
    $cache = Import-SurfaceDriverIndexCache -DriversFolder $DriversFolder
    if ($cache.SkuIndex -and $cache.SkuIndex.Count -gt 0) {
        return @($cache.SkuIndex)
    }

    $url = 'https://learn.microsoft.com/en-us/surface/surface-system-sku-reference'
    WriteLog "Surface cache: Downloading System SKU reference table from $url"

    $headers = @{ 'User-Agent' = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)' }
    $webContent = Invoke-WebRequest -Uri $url -UseBasicParsing -Headers $headers
    $html = $webContent.Content

    $skuRows = [System.Collections.Generic.List[pscustomobject]]::new()

    $rowMatches = [regex]::Matches($html, '<tr[^>]*>(.*?)</tr>', [System.Text.RegularExpressions.RegexOptions]::Singleline)
    foreach ($rowMatch in $rowMatches) {
        $rowContent = $rowMatch.Groups[1].Value
        $cellMatches = [regex]::Matches($rowContent, '<td[^>]*>\s*(?:<p[^>]*>)?(.*?)(?:</p>)?\s*</td>', [System.Text.RegularExpressions.RegexOptions]::Singleline)
        if ($cellMatches.Count -lt 3) { continue }

        $device = ([System.Net.WebUtility]::HtmlDecode(($cellMatches[0].Groups[1].Value).Trim()))
        $systemModel = ([System.Net.WebUtility]::HtmlDecode(($cellMatches[1].Groups[1].Value).Trim()))
        $systemSkuRaw = ([System.Net.WebUtility]::HtmlDecode(($cellMatches[2].Groups[1].Value).Trim()))

        if ([string]::IsNullOrWhiteSpace($device) -or [string]::IsNullOrWhiteSpace($systemSkuRaw)) { continue }

        $skuList = @($systemSkuRaw)

        foreach ($sku in $skuList) {
            if ([string]::IsNullOrWhiteSpace($sku)) { continue }
            $skuRows.Add([pscustomobject]@{
                    Device      = $device
                    SystemModel = $systemModel
                    SystemSku   = $sku.Trim().ToUpperInvariant()
                })
        }
    }

    $cache.SkuIndex = @($skuRows)
    Save-SurfaceDriverIndexCache -Cache $cache -DriversFolder $DriversFolder
    WriteLog "Surface cache: Stored $($skuRows.Count) SKU entries."

    return @($skuRows)
}

function Get-SurfaceDownloadCenterDetails {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DriversFolder,
        [Parameter(Mandatory = $true)]
        [string]$ModelLink,
        [Parameter()]
        [string]$ModelName = $null
    )

    # Source C: Download Center details page (window.__DLCDetails__) containing file names + direct URLs
    $cache = Import-SurfaceDriverIndexCache -DriversFolder $DriversFolder
    $existing = @($cache.DownloadCenterDetails | Where-Object { $_.Link -eq $ModelLink } | Select-Object -First 1)
    if ($existing.Count -gt 0 -and $existing[0].Files -and $existing[0].Files.Count -gt 0) {
        # Backfill Model into cache when available
        if (-not [string]::IsNullOrWhiteSpace($ModelName)) {
            if (-not $existing[0].PSObject.Properties['Model'] -or [string]::IsNullOrWhiteSpace($existing[0].Model)) {
                try {
                    $existing[0] | Add-Member -NotePropertyName Model -NotePropertyValue $ModelName -Force

                    $newDetails = [System.Collections.Generic.List[pscustomobject]]::new()
                    foreach ($item in @($cache.DownloadCenterDetails)) {
                        if ($null -ne $item -and $item.PSObject.Properties['Link'] -and $item.Link -ne $ModelLink) {
                            $newDetails.Add($item)
                        }
                    }
                    $newDetails.Add($existing[0])
                    $cache.DownloadCenterDetails = @($newDetails)
                    Save-SurfaceDriverIndexCache -Cache $cache -DriversFolder $DriversFolder
                }
                catch {
                    WriteLog "Surface cache: Failed to backfill Model for DownloadCenterDetails entry '$ModelLink'. Error: $($_.Exception.Message)"
                }
            }
        }

        return @($existing[0].Files)
    }

    WriteLog "Surface cache: Downloading Download Center details from $ModelLink"
    $headers = @{ 'User-Agent' = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)' }
    $downloadPageContent = Invoke-WebRequest -Uri $ModelLink -UseBasicParsing -Headers $headers

    $scriptPattern = '<script>window.__DLCDetails__={(.*?)}<\/script>'
    $scriptMatch = [regex]::Match($downloadPageContent.Content, $scriptPattern)
    if (-not $scriptMatch.Success) {
        WriteLog "Surface cache: Could not find window.__DLCDetails__ on $ModelLink"
        return @()
    }

    $scriptContent = $scriptMatch.Groups[1].Value
    $downloadFilePattern = '"name":"([^"]+\.(?:msi|zip))",[^}]*?"url":"(.*?)"'
    $downloadFileMatches = [regex]::Matches($scriptContent, $downloadFilePattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

    $files = [System.Collections.Generic.List[pscustomobject]]::new()
    foreach ($downloadFile in $downloadFileMatches) {
        $currentFileName = $downloadFile.Groups[1].Value
        $fileUrl = $downloadFile.Groups[2].Value
        if ([string]::IsNullOrWhiteSpace($currentFileName) -or [string]::IsNullOrWhiteSpace($fileUrl)) { continue }

        $files.Add([pscustomobject]@{
                Name = $currentFileName
                Url  = $fileUrl
            })
    }

    # Persist into cache
    if ($files.Count -gt 0) {
        $detailsEntry = [pscustomobject][ordered]@{
            Model = $ModelName
            Link  = $ModelLink
            Files = @($files)
        }

        $newDetails = [System.Collections.Generic.List[pscustomobject]]::new()
        foreach ($item in @($cache.DownloadCenterDetails)) {
            if ($null -ne $item -and $item.PSObject.Properties['Link'] -and $item.Link -ne $ModelLink) {
                $newDetails.Add($item)
            }
        }
        $newDetails.Add($detailsEntry)
        $cache.DownloadCenterDetails = @($newDetails)
        Save-SurfaceDriverIndexCache -Cache $cache -DriversFolder $DriversFolder
    }

    return @($files)
}

function Get-SurfaceSystemSkuListForMicrosoftDriver {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DriversFolder,
        [Parameter(Mandatory = $true)]
        [string]$ModelName,
        [Parameter(Mandatory = $true)]
        [string]$ModelLink
    )

    $skuIndex = Get-SurfaceSystemSkuReferenceIndex -DriversFolder $DriversFolder
    if ($null -eq $skuIndex -or $skuIndex.Count -eq 0) {
        return @()
    }

    $files = Get-SurfaceDownloadCenterDetails -DriversFolder $DriversFolder -ModelLink $ModelLink -ModelName $ModelName
    $fileNames = @($files | ForEach-Object { $_.Name })

    # Infer architecture hints from the MSI naming convention (best-effort)
    $archHint = $null
    if ($fileNames -match '(?i)_ARM_') {
        $archHint = 'ARM64'
    }
    elseif ($fileNames -match '(?i)withIntel|_Intel_|Intel') {
        $archHint = 'x64'
    }
    elseif ($ModelName -match '(?i)\bSQ3\b|\bSnapdragon\b') {
        $archHint = 'ARM64'
    }
    elseif ($ModelName -match '(?i)with Intel') {
        $archHint = 'x64'
    }

    # Surface Pro (generic) is ambiguous in the SKU table because Surface Pro (5th Gen) and
    # Surface Pro with LTE Advanced (5th Gen) both reuse SystemModel="Surface Pro".
    # The "Surface Pro" driver pack does not have a unique SystemSKU value on the Learn page.
    if ($ModelName.Trim() -match '(?i)^Surface\s+Pro$') {
        return @()
    }

    # Build multiple candidate keys for models that contain multiple variants in one string
    # Example: "Surface Pro 7+ and Surface Pro 7+ LTE"
    $familyKeyCandidates = [System.Collections.Generic.List[string]]::new()
    $familyKeySet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    $primaryKey = ConvertTo-SurfaceComparableName -Text $ModelName
    if (-not [string]::IsNullOrWhiteSpace($primaryKey) -and $familyKeySet.Add($primaryKey)) {
        $familyKeyCandidates.Add($primaryKey) | Out-Null
    }

    $parts = [regex]::Split($ModelName, '(?i)\s+and\s+')

    # Track when the model text contains both LTE and non-LTE variants (e.g. "Surface Go 2 and Surface Go 2 LTE")
    $hasLtePart = (@($parts | Where-Object { $_ -match '(?i)\bLTE\b' }).Count -gt 0)
    $hasNonLtePart = (@($parts | Where-Object { $_ -notmatch '(?i)\bLTE\b' }).Count -gt 0)

    foreach ($part in @($parts)) {
        if ([string]::IsNullOrWhiteSpace($part)) { continue }
        $candidate = ConvertTo-SurfaceComparableName -Text $part
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and $familyKeySet.Add($candidate)) {
            $familyKeyCandidates.Add($candidate) | Out-Null
        }
    }

    if ($familyKeyCandidates.Count -eq 0) {
        return @()
    }

    # Surface 3 has multiple carrier/region variants that share the same SystemModel ("Surface 3").
    # Add a base key so we can match all Surface 3 SKU rows, then refine down to the correct variant.
    if ($ModelName -match '(?i)^Surface\s+3\b') {
        $surface3BaseKey = 'SURFACE 3'
        if ($familyKeySet.Add($surface3BaseKey)) {
            $familyKeyCandidates.Add($surface3BaseKey) | Out-Null
        }
    }

    # Surface Go variants share the same SystemModel ("Surface Go") in the SKU table.
    # Use a generation-aware base key so we don't cross-match Go vs Go 2/3/4 SKU rows.
    if ($ModelName -match '(?i)^Surface\s+Go\s+2\b') {
        $surfaceGoBaseKey = 'SURFACE GO 2'
        if ($familyKeySet.Add($surfaceGoBaseKey)) {
            $familyKeyCandidates.Add($surfaceGoBaseKey) | Out-Null
        }
    }
    elseif ($ModelName -match '(?i)^Surface\s+Go\s+3\b') {
        $surfaceGoBaseKey = 'SURFACE GO 3'
        if ($familyKeySet.Add($surfaceGoBaseKey)) {
            $familyKeyCandidates.Add($surfaceGoBaseKey) | Out-Null
        }
    }
    elseif ($ModelName -match '(?i)^Surface\s+Go\s+4\b') {
        $surfaceGoBaseKey = 'SURFACE GO 4'
        if ($familyKeySet.Add($surfaceGoBaseKey)) {
            $familyKeyCandidates.Add($surfaceGoBaseKey) | Out-Null
        }
    }
    elseif ($ModelName -match '(?i)^Surface\s+Go\b') {
        $surfaceGoBaseKey = 'SURFACE GO'
        if ($familyKeySet.Add($surfaceGoBaseKey)) {
            $familyKeyCandidates.Add($surfaceGoBaseKey) | Out-Null
        }
    }

    # Surface Pro 9 with 5G: the SKU table rows use SystemModel "Surface Pro 9".
    # Add a base key so we can match the Pro 9 SKU rows, then refine down to the 5G rows.
    if (($ModelName -match '(?i)^Surface\s+Pro\s+9\b') -and ($ModelName -match '(?i)\b5G\b')) {
        $surfacePro9BaseKey = 'SURFACE PRO 9'
        if ($familyKeySet.Add($surfacePro9BaseKey)) {
            $familyKeyCandidates.Add($surfacePro9BaseKey) | Out-Null
        }
    }

    # Surface Pro with LTE Advanced maps to the "Surface Pro with LTE Advanced (5th Gen)" SKU table row.
    # Add a base key so we can match Surface Pro rows, then refine to the LTE Advanced SKU.
    if ($ModelName -match '(?i)^Surface\s+Pro\s+with\s+LTE\s+Advanced\b') {
        $surfaceProBaseKey = 'SURFACE PRO'
        if ($familyKeySet.Add($surfaceProBaseKey)) {
            $familyKeyCandidates.Add($surfaceProBaseKey) | Out-Null
        }
    }

    # Surface Laptop (1st Gen) maps to the base "Surface Laptop" SKU table row.
    if (($ModelName -match '(?i)^Surface\s+Laptop\b') -and ($ModelName -match '(?i)\bGen\b')) {
        $surfaceLaptopBaseKey = 'SURFACE LAPTOP'
        if ($familyKeySet.Add($surfaceLaptopBaseKey)) {
            $familyKeyCandidates.Add($surfaceLaptopBaseKey) | Out-Null
        }
    }

    # Surface Studio (1st Gen) maps to the base "Surface Studio" SKU table row.
    if (($ModelName -match '(?i)^Surface\s+Studio\b') -and ($ModelName -match '(?i)\bGen\b')) {
        $surfaceStudioBaseKey = 'SURFACE STUDIO'
        if ($familyKeySet.Add($surfaceStudioBaseKey)) {
            $familyKeyCandidates.Add($surfaceStudioBaseKey) | Out-Null
        }
    }

    # Surface Laptop 3/4 AMD/Intel packs map to the "Surface Laptop 3/4" SystemModel rows in the SKU table.
    if ($ModelName -match '(?i)^Surface\s+Laptop\s+(3|4)\b' -and $ModelName -match '(?i)\b(AMD|Intel)\b') {
        $generationMatch = [regex]::Match($ModelName, '(?i)^Surface\s+Laptop\s+(3|4)\b')
        if ($generationMatch.Success) {
            $surfaceLaptopGenBaseKey = "SURFACE LAPTOP $($generationMatch.Groups[1].Value)"
            if ($familyKeySet.Add($surfaceLaptopGenBaseKey)) {
                $familyKeyCandidates.Add($surfaceLaptopGenBaseKey) | Out-Null
            }
        }
    }

    # Match by any candidate key against the SKU table
    $skuMatches = @($skuIndex | Where-Object {
            $deviceKey = ConvertTo-SurfaceComparableName -Text $_.Device
            $modelKey = ConvertTo-SurfaceComparableName -Text $_.SystemModel

            foreach ($candidateKey in $familyKeyCandidates) {
                if ($deviceKey -eq $candidateKey -or $modelKey -eq $candidateKey) {
                    return $true
                }
            }

            return $false
        })

    # Surface Hub 2 driver packs cover Surface Hub 2S + Surface Hub 3 devices.
    # The System SKU table does not have a "Surface Hub 2" row, so map Hub 2 to all Hub SKUs.
    if ($ModelName -match '(?i)^Surface\s+Hub\s+2\b') {
        $hubSkuRows = @($skuIndex | Where-Object { $_.Device -match '(?i)^Surface\s+Hub' })
        if ($hubSkuRows.Count -gt 0) {
            $skuMatches = @($hubSkuRows)
        }
    }

    # Surface 3: refine down to the correct SKU row based on the model variant text
    # Use normalized text so punctuation/Unicode differences don't drop matches to zero.
    if ($ModelName -match '(?i)^Surface\s+3\b') {
        $modelNorm = ConvertTo-SurfaceComparableName -Text $ModelName

        if ($modelNorm -match '(?i)\bWI\s+FI\b') {
            $skuMatches = @($skuMatches | Where-Object { (ConvertTo-SurfaceComparableName -Text $_.Device) -match '(?i)\bWI\s+FI\b' })
        }
        elseif ($modelNorm -match '(?i)\bVERIZON\b') {
            $skuMatches = @($skuMatches | Where-Object { (ConvertTo-SurfaceComparableName -Text $_.Device) -match '(?i)\bVERIZON\b' })
        }
        elseif ($modelNorm -match '(?i)\bOUTSIDE\s+OF\s+NORTH\s+AMERICA\b|\bY\s+MOBILE\b') {
            $skuMatches = @($skuMatches | Where-Object { (ConvertTo-SurfaceComparableName -Text $_.Device) -match '(?i)\bOUTSIDE\s+OF\s+NORTH\s+AMERICA\b|\bY\s+MOBILE\b' })
        }
        elseif ($modelNorm -match '(?i)\bNORTH\s+AMERICA\b') {
            # "North America (non-AT&T)" should map to the North America row (not AT&T/Verizon/outside-of-North-America)
            $skuMatches = @($skuMatches | Where-Object {
                    $deviceNorm = ConvertTo-SurfaceComparableName -Text $_.Device
                    ($deviceNorm -match '(?i)\bNORTH\s+AMERICA\b') -and
                    ($deviceNorm -notmatch '(?i)\bOUTSIDE\b|\bY\s+MOBILE\b') -and
                    ($deviceNorm -notmatch '(?i)\bAT\s+T\b|\bVERIZON\b')
                })
        }
        elseif (($modelNorm -match '(?i)\bAT\s+T\b') -and ($modelNorm -notmatch '(?i)\bNON\s+AT\s+T\b')) {
            $skuMatches = @($skuMatches | Where-Object { (ConvertTo-SurfaceComparableName -Text $_.Device) -match '(?i)\bAT\s+T\b' })
        }
    }

    # Surface Go: keep LTE SKU only for LTE-only models; exclude LTE SKU for non-LTE-only models.
    # If the model name includes BOTH LTE and non-LTE variants (joined with "and"), do not filter.
    # Surface Go 3 driver packs are treated as covering LTE + non-LTE unless explicitly labeled otherwise.
    if ($ModelName -match '(?i)^Surface\s+Go\b') {
        $isSurfaceGo3Base = ($ModelName -match '(?i)^Surface\s+Go\s+3\b') -and ($ModelName -notmatch '(?i)\bLTE\b')

        if (-not $isSurfaceGo3Base) {
            if (-not ($hasLtePart -and $hasNonLtePart)) {
                if ($ModelName -match '(?i)\bLTE\b') {
                    $skuMatches = @($skuMatches | Where-Object { $_.Device -match '(?i)\bLTE\b' })
                }
                else {
                    $skuMatches = @($skuMatches | Where-Object { $_.Device -notmatch '(?i)\bLTE\b' })
                }
            }
        }
    }

    # Surface Pro 9 with 5G (SQ3): keep only the 5G SKU rows (U.S. + outside of U.S.).
    if (($ModelName -match '(?i)^Surface\s+Pro\s+9\b') -and ($ModelName -match '(?i)\b5G\b')) {
        $skuMatches = @($skuMatches | Where-Object { $_.Device -match '(?i)\b5G\b' })
    }

    # Surface Pro 10: split non-5G vs 5G SKU rows so the two driver packs don't share the same SystemSKUs.
    if ($ModelName -match '(?i)^Surface\s+Pro\s+10\b') {
        if ($ModelName -match '(?i)\b5G\b') {
            $skuMatches = @($skuMatches | Where-Object {
                    ($_.SystemSku -match '^SURFACE_PRO_10_WITH_5G_FOR_BUSINESS_') -or
                    ($_.Device -match '(?i)\bwith\s+5G\b')
                })
        }
        else {
            $skuMatches = @($skuMatches | Where-Object { $_.SystemSku -eq 'SURFACE_PRO_10_FOR_BUSINESS_2079' })
        }
    }

    # Surface Pro with LTE Advanced: restrict to the LTE Advanced (5th Gen) SKU.
    if ($ModelName -match '(?i)^Surface\s+Pro\s+with\s+LTE\s+Advanced\b') {
        $skuMatches = @($skuMatches | Where-Object { $_.SystemSku -eq 'SURFACE_PRO_1807' })
    }

    # Surface Laptop 3/4: filter to AMD vs Intel rows (prevents AMD packs from inheriting Intel SKUs and vice-versa).
    if ($ModelName -match '(?i)^Surface\s+Laptop\s+(3|4)\b') {
        if ($ModelName -match '(?i)\bAMD\b') {
            $skuMatches = @($skuMatches | Where-Object { $_.Device -match '(?i)\bAMD\b' })
        }
        elseif ($ModelName -match '(?i)\bIntel\b') {
            $skuMatches = @($skuMatches | Where-Object { $_.Device -match '(?i)\bIntel\b' })
        }
    }

    # Apply architecture filtering when we can infer it
    if ($archHint -eq 'ARM64') {
        # ARM variants are typically called out as Snapdragon / SQ3 / 5G in the Learn table
        $skuMatches = @($skuMatches | Where-Object {
                ($_.Device -match '(?i)Snapdragon|SQ3|with 5G') -or
                ($_.SystemModel -match '(?i)Snapdragon|SQ3|with 5G')
            })
    }
    elseif ($archHint -eq 'x64') {
        # x64 variants are often NOT labeled "Intel" in the Learn table (e.g. Surface Pro 9).
        # Treat "not Snapdragon/SQ3/5G" as the x64 bucket.
        $skuMatches = @($skuMatches | Where-Object {
                ($_.Device -notmatch '(?i)Snapdragon|SQ3|with 5G') -and
                ($_.SystemModel -notmatch '(?i)Snapdragon|SQ3|with 5G')
            })
    }

    $skus = @($skuMatches | ForEach-Object { $_.SystemSku } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
    return $skus
}

Export-ModuleMember -Function `
    Get-SurfaceDriverIndexCachePath, `
    Import-SurfaceDriverIndexCache, `
    Save-SurfaceDriverIndexCache, `
    ConvertTo-SurfaceComparableName, `
    Get-SurfaceSystemSkuReferenceIndex, `
    Get-SurfaceDownloadCenterDetails, `
    Get-SurfaceSystemSkuListForMicrosoftDriver