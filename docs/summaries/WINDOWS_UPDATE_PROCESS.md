# Windows Update Download and Storage Process

## Overview

FFUBuilder downloads Windows updates from the Microsoft Update Catalog and stores them in the `FFUDevelopment\KB` directory. This document explains the complete workflow from search to application.

---

## Directory Structure

```
FFUDevelopment\
├── KB\                           # Main updates directory
│   ├── windows11.0-kb5034441-x64_*.msu    # Cumulative Updates (CU)
│   ├── windows11.0-kb5034129-x64_*.msu    # Servicing Stack Updates (SSU)
│   ├── windows11.0-kb5033375-x64_*.msu    # .NET Framework updates
│   ├── NET\                      # .NET updates for LTSC (2016/2019/2021)
│   │   └── *.msu
│   └── Microcode\                # CPU microcode updates (optional)
│       └── *.msu
├── Apps\
│   └── Defender\                 # Windows Defender updates (separate location)
│       └── *.exe
└── config\
```

**Key Locations:**
- **Main KB Path:** `$FFUDevelopmentPath\KB` (default: `C:\claude\FFUBuilder\FFUDevelopment\KB`)
- **.NET Updates (LTSC):** `$FFUDevelopmentPath\KB\NET`
- **Microcode Updates:** `$FFUDevelopmentPath\KB\Microcode`
- **Defender Updates:** `$FFUDevelopmentPath\Apps\Defender`

---

## Update Types and Parameters

### 1. Cumulative Updates (CU)
**Parameter:** `-UpdateLatestCU $true`
**Description:** Latest monthly cumulative update for Windows
**Storage:** `KB\` (root)
**Example:** `windows11.0-kb5034441-x64_a866c6e0c0c98f27c9b75e14d5c85f4c9a67b111.msu`

### 2. Servicing Stack Updates (SSU)
**Parameter:** Automatically downloaded when CU is enabled
**Description:** Updates the servicing stack component before applying CU
**Storage:** `KB\` (root)
**Example:** `windows11.0-kb5034129-x64_2b2f5a8d7e3c9a1b4f6e8d0c2a5b7c9e1f3a5b7c.msu`
**Note:** Applied BEFORE CU for Windows 2016/LTSC editions

### 3. Preview Cumulative Updates (CUP)
**Parameter:** `-UpdatePreviewCU $true`
**Description:** Optional preview update (released mid-month)
**Storage:** `KB\` (root)

### 4. .NET Framework Updates
**Parameter:** `-UpdateLatestNet $true`
**Description:** Cumulative updates for .NET Framework 4.8/4.8.1
**Storage:**
- LTSC editions (2016/2019/2021): `KB\NET\`
- SAC editions: `KB\` (root)
**Example:** `windows11.0-kb5033375-x64-ndp481_*.msu`

### 5. Microcode Updates
**Parameter:** `-UpdateLatestMicrocode $true`
**Description:** CPU microcode/firmware updates
**Storage:** `KB\Microcode\`
**Supported:** Windows Server 2016, 2019 only

### 6. Windows Defender Updates
**Parameter:** `-UpdateLatestDefender $true`
**Description:** Latest antimalware definition and platform updates
**Storage:** `Apps\Defender\` (not KB\)
**File Types:** `.exe` (standalone installers)

### 7. Microsoft Edge Updates
**Parameter:** `-UpdateEdge $true`
**Description:** Latest Edge browser (stable channel)
**Storage:** `Apps\Edge\`
**File Types:** `.cab` (extracted to `.msi`)

### 8. Windows Malicious Software Removal Tool (MSRT)
**Parameter:** `-UpdateLatestMSRT $true`
**Description:** Microsoft's malware removal tool
**Storage:** `Apps\MSRT\`
**File Types:** `.exe`

---

## Workflow: From Search to Application

### Phase 1: Update Discovery (Lines 1847-1945)

**Function:** `Get-UpdateFileInfo` (Modules\FFU.Updates\FFU.Updates.psm1)

**Process:**
1. **Build search query** based on Windows version/SKU
   ```powershell
   # Example for Windows 11 24H2:
   $Name = "Cumulative Update for Windows 11 Version 24H2 for x64"
   ```

2. **Call Get-UpdateFileInfo** for each update type:
   ```powershell
   # Cumulative Update
   Get-UpdateFileInfo -Name $Name -WindowsArch $WindowsArch `
                      -Headers $Headers -UserAgent $UserAgent -Filter $Filter
   ```

3. **Get-UpdateFileInfo** flow:
   ```
   Get-UpdateFileInfo
   └─> Get-KBLink (searches Microsoft Update Catalog)
       ├─> Invoke-WebRequest to http://www.catalog.update.microsoft.com/Search.aspx?q=...
       ├─> Parse HTML results
       ├─> Extract KB article ID (e.g., "KB5034441")
       ├─> Apply filters (architecture, Windows version)
       └─> Return download URLs
   ```

4. **Collect update metadata:**
   ```powershell
   [PSCustomObject]@{
       Name = "windows11.0-kb5034441-x64_*.msu"  # Filename
       Url = "http://download.windowsupdate.com/..."  # Download URL
       KBArticleID = "KB5034441"  # KB number
   }
   ```

**Search Examples:**
- **CU:** `"Cumulative Update for Windows 11 Version 24H2 for x64"`
- **SSU:** `"Servicing Stack Update for Windows 11 Version 24H2 for x64"`
- **.NET:** `"Cumulative Update for .NET Framework 4.8.1 for Windows 11 Version 24H2 for x64"`
- **Defender:** `"Defender Update for Windows x64"` (no KB number)

---

### Phase 2: Update Download (Lines 2014-2083)

**Condition:** Only if no cached VHDX found and updates are required

**Process:**

1. **Create KB directory** (if it doesn't exist):
   ```powershell
   If (-not (Test-Path -Path $KBPath)) {
       New-Item -Path $KBPath -ItemType Directory -Force
   }
   ```

2. **Determine destination path** based on update type:
   ```powershell
   foreach ($update in $requiredUpdates) {
       $destinationPath = $KBPath  # Default

       # .NET updates for LTSC go to subdirectory
       if ($netUpdateInfos -and $isLTSC) {
           $destinationPath = "$KBPath\NET"
       }

       # Microcode updates go to subdirectory
       if ($microcodeUpdateInfos) {
           $destinationPath = "$KBPath\Microcode"
       }
   }
   ```

3. **Download using BITS** with retry:
   ```powershell
   Start-BitsTransferWithRetry -Source $update.Url -Destination $destinationPath
   ```

4. **Set file path variables** for later application:
   ```powershell
   # SSU file path
   $SSUFilePath = "$KBPath\$SSUFile"

   # CU file path (by KB article ID)
   $CUPath = Get-ChildItem -Path $KBPath -Filter "*$cuKbArticleId*" | Select -First 1

   # .NET file path
   if ($isLTSC) {
       $NETPath = "$KBPath\NET"
   } else {
       $NETPath = Get-ChildItem -Path $KBPath -Filter $NETFileName
   }
   ```

**Download Function:** `Start-BitsTransferWithRetry` (Modules\FFU.Core\FFU.Core.psm1)
- Uses Windows Background Intelligent Transfer Service (BITS)
- Automatic retry on network failures (up to 3 attempts)
- Resume capability for interrupted downloads
- Better network utilization than Invoke-WebRequest

---

### Phase 3: Update Application (Lines 2119-2157)

**Condition:** Mounted VHDX with Windows image at `$WindowsPartition` (e.g., `E:\`)

**Process:**

1. **Apply SSU first** (for specific Windows versions):
   ```powershell
   # Windows Server 2016 or LTSC editions
   if ($WindowsRelease -eq 2016 -or $isLTSC) {
       Add-WindowsPackageWithRetry -Path $WindowsPartition -PackagePath $SSUFilePath
   }
   ```

2. **Apply Cumulative Update**:
   ```powershell
   if ($UpdateLatestCU) {
       Add-WindowsPackageWithRetry -Path $WindowsPartition -PackagePath $CUPath
   }
   ```

3. **Apply Preview CU** (if enabled):
   ```powershell
   if ($UpdatePreviewCU) {
       Add-WindowsPackageWithRetry -Path $WindowsPartition -PackagePath $CUPPath
   }
   ```

4. **Apply .NET Framework updates**:
   ```powershell
   if ($UpdateLatestNet) {
       Add-WindowsPackageWithRetry -Path $WindowsPartition -PackagePath $NETPath
   }
   ```

5. **Apply Microcode updates** (Server 2016/2019):
   ```powershell
   if ($UpdateLatestMicrocode -and $WindowsRelease -in 2016, 2019) {
       Add-WindowsPackageWithRetry -Path $WindowsPartition -PackagePath $MicrocodePath
   }
   ```

**Application Order (Critical):**
1. **SSU** (Servicing Stack Update) - Must be first
2. **CU** (Cumulative Update) - Main update
3. **CUP** (Preview Update) - Optional
4. **.NET** (Framework updates)
5. **Microcode** (CPU firmware)

**Function:** `Add-WindowsPackageWithRetry` (BuildFFUVM.ps1:3012-3057)
- Wraps `Add-WindowsPackage` DISM cmdlet
- Pre-flight disk space validation (3x package size + 5GB)
- Automatic retry on transient failures (up to 2 retries)
- Enhanced error diagnostics
- DISM service initialization checks

---

## VHDX Caching (Optional)

**Parameter:** `-AllowVHDXCaching $true`

**Purpose:** Skip re-downloading updates if a cached VHDX with the same updates exists

**Process:**

### Cache Check (Lines 1957-2012)

1. **Search for cached VHDX**:
   ```powershell
   $vhdxCacheFolder = "$FFUDevelopmentPath\VHDXCache"
   $vhdxCacheFiles = Get-ChildItem -Path $vhdxCacheFolder -Filter "*.json"
   ```

2. **Compare cache metadata**:
   ```json
   {
       "WindowsRelease": 11,
       "WindowsVersion": "24h2",
       "WindowsSKU": "Pro",
       "SSU": "KB5034129",
       "CU": "KB5034441",
       "NET": "KB5033375",
       "LogicalSectorSizeBytes": 512
   }
   ```

3. **If match found**:
   - Copy cached VHDX instead of downloading updates
   - Skip update download phase entirely
   - Proceed directly to driver/app installation

4. **If no match**:
   - Download updates (Phase 2)
   - Apply updates (Phase 3)
   - Save VHDX to cache with metadata JSON

### Cache Cleanup (Lines 2619-2625)

**After successful FFU creation:**
```powershell
if ($AllowVHDXCaching) {
    # Remove KB directory (updates now baked into cached VHDX)
    Remove-Item -Path $KBPath -Recurse -Force
}
```

**Rationale:** Once updates are applied to the cached VHDX, the individual MSU files are no longer needed.

---

## Special Cases and Notes

### Defender Updates (Different Location)

**Storage:** `$FFUDevelopmentPath\Apps\Defender\` (NOT in KB\)

**Process:**
```powershell
$DefenderPath = "$AppsPath\Defender"

# Multiple Defender updates (platform + definitions)
foreach ($update in $defenderUpdates) {
    $KBFilePath = Save-KB -Name $update.Name -Path $DefenderPath `
                          -WindowsArch $WindowsArch -Headers $Headers `
                          -UserAgent $UserAgent -Filter $Filter
}
```

**Why separate?**
- Defender updates are `.exe` installers (not `.msu` packages)
- Applied during VM boot via orchestration script (not DISM offline)
- Updated frequently (daily), separate lifecycle from OS patches

### Edge Updates (Extracted to MSI)

**Storage:** `$FFUDevelopmentPath\Apps\Edge\`

**Process:**
1. Download Edge `.cab` file
2. Extract MSI from CAB:
   ```powershell
   expand.exe "$EdgeCABFilePath" -F:*.msi "$EdgePath"
   ```
3. Install MSI during VM orchestration

### MSRT Updates (Executable)

**Storage:** `$FFUDevelopmentPath\Apps\MSRT\`

**File Type:** `.exe` (not `.msu`)

**Application:** Run during VM orchestration, not DISM offline patching

---

## Architecture Filtering

**All update downloads are architecture-specific:**

```powershell
# In Save-KB function (FFU.Updates.psm1:610-638)
if ($link -match 'x64' -or $link -match 'amd64') {
    if ($WindowsArch -eq 'x64') {
        Start-BitsTransferWithRetry -Source $link -Destination $Path
    }
}
elseif ($link -match 'arm64') {
    if ($WindowsArch -eq 'arm64') {
        Start-BitsTransferWithRetry -Source $link -Destination $Path
    }
}
elseif ($link -match 'x86') {
    if ($WindowsArch -eq 'x86') {
        Start-BitsTransferWithRetry -Source $link -Destination $Path
    }
}
```

**Supported Architectures:**
- `x64` / `amd64` (Windows 11, Server 2016+)
- `x86` (Windows 10 32-bit, legacy)
- `arm64` (Windows 11 ARM)

---

## Error Handling and Validation

### Pre-Flight Disk Space Check

**Before applying MSU files:**
```powershell
# Test-MountedImageDiskSpace (BuildFFUVM.ps1:2917-2965)
$requiredSpace = ($packageSize * 3) + 5GB  # 3x package + 5GB buffer
$freeSpace = (Get-Volume -DriveLetter $driveLetter).SizeRemaining

if ($freeSpace -lt $requiredSpace) {
    throw "Insufficient disk space on $driveLetter\: Required $($requiredSpace/1GB)GB, Available $($freeSpace/1GB)GB"
}
```

### MSU File Integrity Validation

```powershell
# Check for 0-byte or corrupted files
if (-not (Test-Path $PackagePath) -or (Get-Item $PackagePath).Length -eq 0) {
    throw "MSU package file is missing or corrupted: $PackagePath"
}
```

### Automatic Retry Logic

```powershell
# Add-WindowsPackageWithRetry (BuildFFUVM.ps1:3012-3057)
$maxRetries = 2
$retryCount = 0

while ($retryCount -le $maxRetries) {
    try {
        Add-WindowsPackage -Path $Path -PackagePath $PackagePath
        break  # Success
    }
    catch {
        if ($retryCount -lt $maxRetries) {
            Start-Sleep -Seconds 30
            $retryCount++
        } else {
            throw  # Final failure
        }
    }
}
```

---

## Configuration Parameters

### Enable/Disable Update Types

```powershell
# BuildFFUVM.ps1 or config.json
[bool]$UpdateLatestCU = $true          # Cumulative Update
[bool]$UpdatePreviewCU = $false        # Preview CU
[bool]$UpdateLatestNet = $true         # .NET Framework
[bool]$UpdateLatestDefender = $true    # Windows Defender
[bool]$UpdateEdge = $true              # Microsoft Edge
[bool]$UpdateLatestMSRT = $true        # Malware Removal Tool
[bool]$UpdateLatestMicrocode = $false  # CPU Microcode (Server only)
[bool]$AllowVHDXCaching = $true        # Enable VHDX caching
```

### HTTP Headers and User Agent

**Required for Microsoft Update Catalog access:**
```json
"Headers": {
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    "Accept-Encoding": "gzip, deflate, br",
    "Accept-Language": "en-US,en;q=0.9",
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
}
```

**Purpose:** Mimics browser request to bypass catalog restrictions

---

## Performance Optimizations

### BITS Background Transfer

**Advantages:**
- Asynchronous download (doesn't block script)
- Automatic retry on network interruption
- Bandwidth throttling (doesn't saturate network)
- Resume capability for large files

### Parallel Downloads

Updates are downloaded **sequentially** (not parallel) to:
- Avoid overwhelming the Update Catalog server
- Prevent BITS queue saturation
- Maintain download reliability

### VHDX Caching

**Time Savings:**
- Skip 10-30 minutes of update downloads
- Skip 15-45 minutes of DISM package application
- **Total savings:** 25-75 minutes per build

**Storage Cost:** ~10-50GB per cached VHDX

---

## Troubleshooting

### "Update not found in catalog"

**Cause:** Search query doesn't match catalog entry

**Solution:** Check exact update name in Microsoft Update Catalog manually

### "Unable to find type [FFUConstants]"

**Cause:** Module not loaded at parse time

**Solution:** Ensure `using module` statement at script top (not `Import-Module`)

### "Insufficient disk space" during package application

**Cause:** MSU expansion requires 3x package size

**Solution:** Increase `-Disksize` parameter or free up host disk space

### "DISM failed with exit code -1" (expand.exe)

**Cause:** Corrupted MSU file or insufficient disk space

**Solution:** Delete KB file and re-download, or check disk space

### "BITS transfer failed"

**Cause:** Network interruption or proxy authentication

**Solution:** Check proxy settings, verify internet connectivity

---

## File Naming Conventions

**Microsoft Update Catalog naming pattern:**
```
windows{release}.{revision}-kb{kbnumber}-{arch}_{hash}.{extension}

Examples:
- windows11.0-kb5034441-x64_a866c6e0c0c98f27c9b75e14d5c85f4c9a67b111.msu
- windows11.0-kb5034129-x64_2b2f5a8d7e3c9a1b4f6e8d0c2a5b7c9e1f3a5b7c.msu
- windows10.0-kb5033375-x64-ndp481_6f8d9a1c2e4b7a5d3c8e0f2a4b6c8d0e2f4a6b8c.msu
```

**Components:**
- `windows11.0` = Windows 11 (version 11.0)
- `kb5034441` = KB article number
- `x64` = Architecture
- `{hash}` = SHA-256 hash (file integrity verification)
- `.msu` = Microsoft Update Standalone Package

---

## Related Modules

### FFU.Updates Module
**Location:** `Modules\FFU.Updates\FFU.Updates.psm1`

**Functions:**
- `Get-UpdateFileInfo` - Search catalog and return metadata
- `Get-KBLink` - Get download URLs from catalog
- `Save-KB` - Download update files with architecture filtering

### FFU.Core Module
**Location:** `Modules\FFU.Core\FFU.Core.psm1`

**Functions:**
- `Start-BitsTransferWithRetry` - Download with automatic retry
- `Test-MountedImageDiskSpace` - Pre-flight disk validation
- `Initialize-DISMService` - Ensure DISM is ready

---

## Summary

**Complete Workflow:**
1. **Discovery:** Search Microsoft Update Catalog for latest updates
2. **Download:** Save MSU/CAB/EXE files to `KB\` directory (with subdirectories for .NET/Microcode)
3. **Application:** Mount VHDX, apply updates via DISM in correct order (SSU → CU → NET)
4. **Caching (Optional):** Save updated VHDX to cache, delete KB files
5. **Reuse:** On next build, check cache first, skip download/apply if match found

**Key Directories:**
- `KB\` - Cumulative and Servicing Stack updates
- `KB\NET\` - .NET Framework updates (LTSC editions)
- `KB\Microcode\` - CPU microcode updates
- `Apps\Defender\` - Windows Defender updates
- `Apps\Edge\` - Microsoft Edge updates
- `Apps\MSRT\` - Malware Removal Tool

**Benefits:**
- Fully automated update integration
- No manual download/tracking required
- Reproducible builds with specific update versions
- VHDX caching for faster subsequent builds
- Architecture-specific filtering prevents mismatches

---

Generated: 2025-11-24
For: FFUBuilder project
Location: C:\claude\FFUBuilder\FFUDevelopment
