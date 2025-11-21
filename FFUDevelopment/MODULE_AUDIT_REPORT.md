# FFU Builder Module Audit Report
## Script-Scope Variable Dependency Analysis

**Date**: 2025-11-21
**Auditor**: Claude Code
**Scope**: All PowerShell modules in FFUDevelopment/Modules/

## Executive Summary

Comprehensive audit of 8 PowerShell modules identified **32 functions with script-scope variable dependencies** similar to the issues fixed in FFU.Apps (Get-Office, New-AppsISO, Remove-DisabledArtifacts).

### High-Level Findings

| Module | Total Functions | Functions with Issues | Risk Level |
|--------|----------------|----------------------|------------|
| FFU.Core | 14 | 7 (50%) | **HIGH** |
| FFU.ADK | 8 | 3 (38%) | **MEDIUM** |
| FFU.Drivers | 5 | 5 (100%) | **CRITICAL** |
| FFU.Updates | 5 | 5 (100%) | **CRITICAL** |
| FFU.VM | 3 | 3 (100%) | **CRITICAL** |
| FFU.Imaging | 13 | 7 (54%) | **HIGH** |
| FFU.Media | 4 | 1 (25%) | **MEDIUM** |
| **TOTAL** | **52** | **32 (62%)** | **HIGH** |

### Risk Assessment

- **CRITICAL**: Functions will fail immediately with "Cannot bind argument to parameter" errors
- **HIGH**: Functions may fail under certain conditions or configurations
- **MEDIUM**: Functions may work in some scenarios but fail in others

---

## Detailed Findings by Module

### 1. FFU.Core Module (7 issues)

**Risk Level**: HIGH
**Module Path**: `FFUDevelopment/Modules/FFU.Core/FFU.Core.psm1`

#### 1.1 LogVariableValues (line 31)
**Severity**: LOW (logging utility)
**Script-Scope Variables**:
- `$version` (line 61)

**Impact**: Will fail to log version information

**Recommendation**: Add `$version` parameter or remove version logging

---

#### 1.2 New-FFUFileName (line 189) ⚠️
**Severity**: CRITICAL
**Script-Scope Variables**:
- `$installationType` (line 194)
- `$winverinfo` (lines 194, 195)
- `$WindowsRelease` (lines 195, 200)
- `$CustomFFUNameTemplate` (lines 200-223)
- `$WindowsVersion` (line 202)
- `$shortenedWindowsSKU` (line 204)

**Impact**: FFU file naming will fail, breaking the entire build process

**Recommendation**: HIGH PRIORITY - Add all 6 variables as parameters

---

#### 1.3 Export-ConfigFile (line 227)
**Severity**: MEDIUM
**Script-Scope Variables**:
- `$ExportConfigFile` (line 248)

**Impact**: Configuration export will fail

**Recommendation**: Add `$ExportConfigFile` as mandatory parameter

---

#### 1.4 New-RunSession (line 251)
**Severity**: LOW
**Script-Scope Variables**:
- `$OfficePath` (line 290)

**Impact**: Office XML backup will be skipped (non-critical)

**Recommendation**: Add `$OfficePath` as optional parameter with null check

---

#### 1.5 Remove-InProgressItems (line 353) ⚠️
**Severity**: HIGH
**Script-Scope Variables**:
- `$DriversFolder` (lines 387, 389, 465, 531)
- `$OfficePath` (lines 417, 418, 422)

**Impact**: Cleanup operations will fail, leaving stale downloads

**Recommendation**: Add both variables as parameters

---

#### 1.6 Cleanup-CurrentRunDownloads (line 511) ⚠️
**Severity**: CRITICAL
**Script-Scope Variables** (10 total):
- `$AppsPath` (line 519)
- `$DefenderPath` (line 520, 665)
- `$MSRTPath` (line 521, 665)
- `$OneDrivePath` (line 522, 665)
- `$EdgePath` (line 523, 665)
- `$KBPath` (line 524)
- `$DriversFolder` (lines 525, 531, 532, 718)
- `$orchestrationPath` (lines 526, 644, 645, 654, 719)
- `$OfficePath` (lines 624, 625, 627)
- `$PSScriptRoot` (line 676)

**Impact**: Cleanup operations will fail catastrophically

**Recommendation**: HIGH PRIORITY - Add all 10 variables as parameters

---

#### 1.7 Restore-RunJsonBackups (line 699)
**Severity**: MEDIUM
**Script-Scope Variables**:
- `$DriversFolder` (line 718)
- `$orchestrationPath` (line 719)

**Impact**: JSON backup restoration will fail

**Recommendation**: Add both variables as parameters

---

### 2. FFU.ADK Module (3 issues)

**Risk Level**: MEDIUM
**Module Path**: `FFUDevelopment/Modules/FFU.ADK/FFU.ADK.psm1`

#### 2.1 Get-ODTURL (line 543)
**Severity**: MEDIUM
**Script-Scope Variables**:
- `$Headers` (lines 562, 586)
- `$UserAgent` (lines 562, 586)

**Impact**: ODT download URL retrieval will fail

**Recommendation**: Add `$Headers` and `$UserAgent` as mandatory parameters

**Notes**: Similar to Get-Office fix already completed

---

#### 2.2 Confirm-ADKVersionIsLatest (line 712)
**Severity**: LOW
**Script-Scope Variables**:
- `$Headers` (line 733)
- `$UserAgent` (line 733)

**Impact**: Version check will fail (non-critical)

**Recommendation**: Add `$Headers` and `$UserAgent` as parameters

---

#### 2.3 Get-ADK (line 762) ⚠️
**Severity**: HIGH
**Script-Scope Variables**:
- `$UpdateADK` (line 764)

**Impact**: ADK installation/update logic will fail

**Recommendation**: Add `$UpdateADK` as mandatory boolean parameter

---

### 3. FFU.Drivers Module (5 issues) ⚠️⚠️⚠️

**Risk Level**: CRITICAL
**Module Path**: `FFUDevelopment/Modules/FFU.Drivers/FFU.Drivers.psm1`

**⚠️ All driver download functions will fail without these fixes**

#### 3.1 Get-MicrosoftDrivers (line 18) ⚠️
**Severity**: CRITICAL
**Script-Scope Variables**:
- `$Headers` (line 31)
- `$UserAgent` (line 31)
- `$DriversFolder` (lines 171, 178, 187)
- `$FFUDevelopmentPath` (line 189)
- `$Make` (line 178)
- `$Model` (line 100, 132, 133) - ALREADY HAS PARAMETER but uses it

**Impact**: Microsoft Surface driver downloads will fail

**Recommendation**: Add 5 missing parameters (Model is already present)

**Call Site**: BuildFFUVM.ps1 (search for `Get-MicrosoftDrivers`)

---

#### 3.2 Get-HPDrivers (line 230) ⚠️
**Severity**: CRITICAL
**Script-Scope Variables**:
- `$DriversFolder` (9 references: lines 249, 253, 379, 380, 391, 417, 426, 439, 455)
- `$Make` (line 249)
- `$FFUDevelopmentPath` (line 433)

**Impact**: HP driver downloads will fail

**Recommendation**: Add 3 missing parameters (already has Make, Model, WindowsArch, WindowsRelease, WindowsVersion)

**Call Site**: BuildFFUVM.ps1 (search for `Get-HPDrivers`)

---

#### 3.3 Get-LenovoDrivers (line 459) ⚠️
**Severity**: CRITICAL
**Script-Scope Variables**:
- Nested function `Get-LenovoPSREF` (line 471) uses:
  - `$Headers` (line 488, 494)
  - `$UserAgent` (line 494)
- Main function uses:
  - `$DriversFolder` (7 references: lines 570, 571, 578, 605, 646, 657, 670)
  - `$Make` (line 570)
  - `$FFUDevelopmentPath` (line 664)

**Impact**: Lenovo driver downloads will fail

**Recommendation**: Add Headers, UserAgent to nested function; add 3 missing parameters to main function

**Call Site**: BuildFFUVM.ps1 (search for `Get-LenovoDrivers`)

---

#### 3.4 Get-DellDrivers (line 701) ⚠️
**Severity**: CRITICAL
**Script-Scope Variables**:
- `$DriversFolder` (9 references: lines 712, 718, 726, 731, 744, 832, 841, 860)
- `$Make` (line 718)
- `$FFUDevelopmentPath` (line 849)
- `$isServer` (line 887)

**Impact**: Dell driver downloads will fail

**Recommendation**: Add 4 missing parameters (already has Model, WindowsArch, WindowsRelease)

**Call Site**: BuildFFUVM.ps1 (search for `Get-DellDrivers`)

---

#### 3.5 Copy-Drivers (line 932)
**Severity**: MEDIUM
**Script-Scope Variables**:
- `$WindowsArch` (line 983)

**Impact**: WinPE driver filtering will fail

**Recommendation**: Add `$WindowsArch` as parameter

**Call Site**: FFU.Media module (line 485)

---

### 4. FFU.Updates Module (5 issues)

**Risk Level**: CRITICAL
**Module Path**: `FFUDevelopment/Modules/FFU.Updates/FFU.Updates.psm1`

#### 4.1 Get-ProductsCab (line 24)
**Severity**: MEDIUM
**Script-Scope Variables**:
- `$UserAgent` (line 89)

**Impact**: Windows 11 products.cab download will fail

**Recommendation**: Add `$UserAgent` as mandatory parameter

---

#### 4.2 Get-WindowsESD (line 114) ⚠️
**Severity**: CRITICAL
**Script-Scope Variables**:
- `$PSScriptRoot` (lines 136, 175, 188)
- `$Headers` (line 142)
- `$UserAgent` (line 142)
- `$WindowsVersion` (line 152)
- `$FFUDevelopmentPath` (line 194)

**Impact**: Windows ESD download will fail (breaks entire build for Windows 11)

**Recommendation**: HIGH PRIORITY - Add all 5 parameters

---

#### 4.3 Get-KBLink (line 218)
**Severity**: HIGH
**Script-Scope Variables**:
- `$Headers` (lines 225, 269)
- `$UserAgent` (lines 225, 269)
- `$Filter` (line 253)

**Impact**: KB update URL retrieval will fail

**Recommendation**: Add all 3 parameters

---

#### 4.4 Get-UpdateFileInfo (line 286)
**Severity**: MEDIUM
**Script-Scope Variables**:
- `$WindowsArch` (lines 300, 302, 304)

**Impact**: Update architecture filtering will fail

**Recommendation**: Add `$WindowsArch` as parameter

---

#### 4.5 Save-KB (line 328)
**Severity**: HIGH
**Script-Scope Variables**:
- `$WindowsArch` (lines 343, 353, 362, 384)

**Impact**: KB download will fail

**Recommendation**: Add `$WindowsArch` as parameter

---

### 5. FFU.VM Module (3 issues) ⚠️⚠️⚠️

**Risk Level**: CRITICAL
**Module Path**: `FFUDevelopment/Modules/FFU.VM/FFU.VM.psm1`

#### 5.1 New-FFUVM (line 20) ⚠️
**Severity**: CRITICAL
**Script-Scope Variables** (6 total):
- `$VMName` (13 references)
- `$VMPath` (line 22)
- `$memory` (line 22)
- `$VHDXPath` (line 22)
- `$processors` (line 23)
- `$AppsISO` (line 26)

**Impact**: VM creation will fail completely

**Recommendation**: URGENT - Add all 6 parameters

**Call Site**: BuildFFUVM.ps1 (search for `New-FFUVM`)

---

#### 5.2 Remove-FFUVM (line 50) ⚠️
**Severity**: HIGH
**Script-Scope Variables**:
- `$VMPath` (lines 66, 67, 82, 83)
- `$InstallApps` (line 80)
- `$vhdxDisk` (line 80)
- `$FFUDevelopmentPath` (lines 98, 100)

**Impact**: VM cleanup will fail, leaving orphaned VMs

**Recommendation**: Add 4 parameters (VMName is already a parameter)

---

#### 5.3 Get-FFUEnvironment (line 109) ⚠️
**Severity**: CRITICAL
**Script-Scope Variables** (10 total):
- `$FFUDevelopmentPath` (7 references)
- `$CleanupCurrentRunDownloads` (line 117)
- `$VMLocation` (lines 173, 174, 177)
- `$UserName` (line 225)
- `$RemoveApps` (line 231)
- `$AppsPath` (line 232)
- `$RemoveUpdates` (line 236)
- `$KBPath` (lines 241, 242)
- `$AppsISO` (lines 247, 248)

**Impact**: Environment cleanup will fail, leading to build failures

**Recommendation**: HIGH PRIORITY - Add all 10 parameters

---

### 6. FFU.Imaging Module (7 issues)

**Risk Level**: HIGH
**Module Path**: `FFUDevelopment/Modules/FFU.Imaging/FFU.Imaging.psm1`

#### 6.1 Get-WimFromISO (line 70)
**Severity**: MEDIUM
**Script-Scope Variables**:
- `$isoPath` (line 72)

**Impact**: ISO mounting will fail

**Recommendation**: Add `$isoPath` as mandatory parameter

---

#### 6.2 Get-Index (line 88)
**Severity**: MEDIUM
**Script-Scope Variables**:
- `$ISOPath` (line 102)

**Impact**: Image index selection logic may fail

**Recommendation**: Add `$ISOPath` as optional parameter with null check

---

#### 6.3 New-ScratchVhdx (line 157)
**Severity**: HIGH
**Script-Scope Variables**:
- `$disksize` (line 169)

**Impact**: VHDX creation will fail

**Recommendation**: Add `$disksize` parameter or fix to use `$SizeBytes` parameter

**Notes**: Function already has `$SizeBytes` parameter but uses undefined `$disksize` variable

---

#### 6.4 New-OSPartition (line 211)
**Severity**: LOW
**Script-Scope Variables**:
- `$CompactOS` (line 240)

**Impact**: CompactOS feature may not work

**Recommendation**: Add `$CompactOS` as boolean parameter

---

#### 6.5 Enable-WindowsFeaturesByName (line 322)
**Severity**: HIGH
**Script-Scope Variables**:
- `$WindowsPartition` (line 335)

**Impact**: Windows feature enablement will fail

**Recommendation**: Add `$WindowsPartition` as mandatory parameter

---

#### 6.6 New-FFU (line 379) ⚠️
**Severity**: CRITICAL
**Script-Scope Variables** (17 total):
- `$InstallApps` (lines 385, 422, 441, 546)
- `$CaptureISO` (lines 387, 390)
- `$VMName` (8 references)
- `$VMSwitchName` (line 391)
- `$FFUCaptureLocation` (lines 409, 433, 458)
- `$AllowVHDXCaching` (lines 422, 441)
- `$CustomFFUNameTemplate` (lines 426, 444)
- `$shortenedWindowsSKU` (4 references)
- `$VHDXPath` (lines 439, 463)
- `$DandIEnv` (3 references)
- `$vhdxDisk` (lines 437, 461)
- `$cachedVHDXInfo` (3 references)
- `$installationType` (line 450)
- `$InstallDrivers` (lines 468, 474)
- `$Optimize` (lines 468, 503)
- `$FFUDevelopmentPath` (6 references)
- `$DriversFolder` (line 489)

**Impact**: FFU creation will fail completely

**Recommendation**: URGENT - Add all 17 parameters

---

#### 6.7 Remove-FFU (line 516)
**Severity**: HIGH
**Script-Scope Variables**:
- `$InstallApps` (line 546)
- `$vhdxDisk` (line 546)
- `$VMPath` (lines 532, 533, 548, 549)
- `$FFUDevelopmentPath` (lines 564, 565)

**Impact**: FFU cleanup will fail

**Recommendation**: Add 4 parameters (VMName is already a parameter)

---

### 7. FFU.Media Module (1 issue)

**Risk Level**: MEDIUM
**Module Path**: `FFUDevelopment/Modules/FFU.Media/FFU.Media.psm1`

#### 7.1 New-PEMedia (line 364) ⚠️
**Severity**: CRITICAL
**Script-Scope Variables** (13 total):
- `$adkPath` (5 references)
- `$FFUDevelopmentPath` (4 references)
- `$WindowsArch` (6 references)
- `$CaptureISO` (line 457)
- `$DeployISO` (line 501)
- `$CopyPEDrivers` (2 references)
- `$UseDriversAsPEDrivers` (2 references)
- `$PEDriversFolder` (4 references)
- `$DriversFolder` (2 references)
- `$Capture` (2 references)
- `$Deploy` (5 references)
- `$CompressDownloadedDriversToWim` (line 541)

**Impact**: WinPE media creation will fail

**Recommendation**: HIGH PRIORITY - Add all 13 parameters (function already has Capture and Deploy, but they're passed as boolean parameters)

---

## Prioritized Remediation Plan

### Phase 1: CRITICAL (Immediate - Blocks Core Functionality)

**Priority Order**:

1. **FFU.VM Module** (All 3 functions)
   - New-FFUVM
   - Remove-FFUVM
   - Get-FFUEnvironment

2. **FFU.Drivers Module** (All 5 functions)
   - Get-MicrosoftDrivers
   - Get-HPDrivers
   - Get-LenovoDrivers
   - Get-DellDrivers
   - Copy-Drivers

3. **FFU.Imaging Module** (2 functions)
   - New-FFU
   - New-ScratchVhdx (bug fix)

4. **FFU.Updates Module** (1 function)
   - Get-WindowsESD

### Phase 2: HIGH (Important - May Cause Build Failures)

1. **FFU.Core Module**
   - New-FFUFileName
   - Cleanup-CurrentRunDownloads
   - Remove-InProgressItems

2. **FFU.Imaging Module**
   - Enable-WindowsFeaturesByName
   - Remove-FFU

3. **FFU.Media Module**
   - New-PEMedia

4. **FFU.Updates Module**
   - Get-KBLink
   - Save-KB

5. **FFU.ADK Module**
   - Get-ADK

### Phase 3: MEDIUM (Moderate - Degrades Functionality)

1. **FFU.Core Module**
   - Export-ConfigFile
   - Restore-RunJsonBackups

2. **FFU.ADK Module**
   - Get-ODTURL (actually used by Get-Office which we already fixed, but should still be fixed for consistency)

3. **FFU.Imaging Module**
   - Get-WimFromISO
   - Get-Index

4. **FFU.Updates Module**
   - Get-ProductsCab
   - Get-UpdateFileInfo

### Phase 4: LOW (Minor - Logging/Optional Features)

1. **FFU.Core Module**
   - LogVariableValues
   - New-RunSession

2. **FFU.Imaging Module**
   - New-OSPartition (CompactOS feature)

3. **FFU.ADK Module**
   - Confirm-ADKVersionIsLatest

---

## Implementation Pattern

Based on the successful fixes for FFU.Apps (Get-Office, New-AppsISO, Remove-DisabledArtifacts), use this pattern:

### Step 1: Update Function Signature

```powershell
function Get-Example {
    <#
    .SYNOPSIS
    Brief description

    .PARAMETER ParamName
    Description of parameter

    .EXAMPLE
    Get-Example -Param1 "value" -Param2 "value"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Param1,

        [Parameter(Mandatory = $false)]
        [string]$Param2 = "default"
    )

    # Function body using $Param1 and $Param2 instead of script-scope variables
}
```

### Step 2: Update Call Sites in BuildFFUVM.ps1

Search for all invocations of the function and update them to pass parameters:

```powershell
# Before:
Get-Example

# After:
Get-Example -Param1 $scriptVar1 -Param2 $scriptVar2
```

### Step 3: Create Validation Test

Create `Test-FunctionName.ps1` to validate:
- Function exists
- All required parameters are mandatory
- Optional parameters are optional
- Parameter binding works (function fails at execution, not parameter binding)
- Help documentation exists

### Step 4: Update Module Manifest

Ensure function is exported in the .psd1 file:

```powershell
FunctionsToExport = @(
    'Get-Example',
    # ... other functions
)
```

---

## Testing Strategy

### Unit Tests

For each fixed function, create a test file:

```
FFUDevelopment/
├── Test-FunctionName.ps1
└── Tests/
    ├── Unit/
    │   ├── Test-FFU.Core.ps1
    │   ├── Test-FFU.Drivers.ps1
    │   └── ... (one per module)
    └── Integration/
        └── Test-BuildFFUVM-FullRun.ps1
```

### Smoke Tests

After Phase 1 completion, run basic build:

```powershell
.\BuildFFUVM.ps1 -ConfigFile "config.json" -Verbose -WhatIf
```

### Full Integration Test

After Phase 2 completion, run full build:

```powershell
.\BuildFFUVM.ps1 -WindowsRelease 11 -WindowsSKU "Pro" -OEM "Dell" -Model "Latitude 7490" -InstallApps $true
```

---

## Risk Mitigation

### Backup Strategy

Before making changes:
1. Create branch: `git checkout -b fix/module-parameterization`
2. Backup modules: `Copy-Item FFUDevelopment/Modules FFUDevelopment/Modules.backup -Recurse`

### Rollback Plan

If issues arise:
1. `git checkout main`
2. `git branch -D fix/module-parameterization`

### Incremental Deployment

Fix and test one module at a time in order:
1. FFU.VM (smallest, most critical)
2. FFU.Drivers (high impact)
3. FFU.Imaging (complex)
4. FFU.Core (foundational)
5. FFU.Updates (moderate complexity)
6. FFU.Media (moderate complexity)
7. FFU.ADK (low impact)

---

## Estimated Effort

| Phase | Functions | Estimated Hours | Priority |
|-------|-----------|----------------|----------|
| Phase 1 (CRITICAL) | 11 | 16-20 hours | NOW |
| Phase 2 (HIGH) | 10 | 12-16 hours | SOON |
| Phase 3 (MEDIUM) | 7 | 8-12 hours | LATER |
| Phase 4 (LOW) | 4 | 4-6 hours | OPTIONAL |
| **TOTAL** | **32** | **40-54 hours** | - |

### Breakdown by Task

- Function signature updates: 30 min each × 32 = 16 hours
- Call site updates: 20 min each × 32 = 10.7 hours
- Test creation: 45 min each × 32 = 24 hours
- Documentation updates: 15 min each × 32 = 8 hours
- **Subtotal**: 58.7 hours
- **Testing & validation**: -15% (parallel execution)
- **TOTAL**: ~50 hours

---

## Appendix A: Module Function Count Summary

| Module | Functions | Exported | Issues | Pass Rate |
|--------|-----------|----------|--------|-----------|
| FFU.Core | 14 | 14 | 7 | 50% |
| FFU.ADK | 8 | 8 | 3 | 63% |
| FFU.Drivers | 5 | 5 | 5 | 0% ⚠️ |
| FFU.Updates | 8 | 8 | 5 | 38% |
| FFU.VM | 3 | 3 | 3 | 0% ⚠️ |
| FFU.Imaging | 13 | 13 | 7 | 46% |
| FFU.Media | 4 | 4 | 1 | 75% |
| **TOTAL** | **55** | **55** | **32** | **42%** |

---

## Appendix B: Call Site Analysis

Functions likely called from BuildFFUVM.ps1:

- FFU.VM: New-FFUVM, Remove-FFUVM, Get-FFUEnvironment
- FFU.Drivers: Get-MicrosoftDrivers, Get-HPDrivers, Get-LenovoDrivers, Get-DellDrivers
- FFU.Imaging: Get-WimFromISO, Get-Index, New-ScratchVhdx, New-SystemPartition, New-MSRPartition, New-OSPartition, New-RecoveryPartition, Add-BootFiles, New-FFU, Remove-FFU
- FFU.Core: New-FFUFileName, Export-ConfigFile, New-RunSession, Cleanup-CurrentRunDownloads, etc.
- FFU.Updates: Get-WindowsESD, Get-KBLink, Save-KB
- FFU.Media: New-PEMedia
- FFU.ADK: Test-ADKPrerequisites, Get-ADK

**Recommendation**: Use `Grep -pattern "FunctionName" -path "BuildFFUVM.ps1" -output_mode content` to locate all call sites for each function before making changes.

---

## Appendix C: Similar Patterns Across Modules

**Common Variables Needing Parameterization**:

- **Paths**: `$FFUDevelopmentPath`, `$DriversFolder`, `$OfficePath`, `$AppsPath`, `$VMPath`, `$VHDXPath`
- **Network**: `$Headers`, `$UserAgent`
- **Architecture**: `$WindowsArch`, `$WindowsRelease`, `$WindowsVersion`, `$WindowsSKU`
- **Configuration**: `$InstallApps`, `$UpdateADK`, `$CopyPEDrivers`, `$CompactOS`
- **VM Settings**: `$VMName`, `$memory`, `$processors`, `$VMSwitchName`

**Suggested Approach**: Create a parameter set pattern that can be reused across multiple functions.

---

## Conclusion

This audit reveals that **62% of module functions** have script-scope variable dependencies that will cause runtime failures similar to the issues we fixed in FFU.Apps. The highest risk modules are:

1. **FFU.Drivers** (100% failure rate - all driver downloads broken)
2. **FFU.VM** (100% failure rate - all VM operations broken)
3. **FFU.Imaging** (54% failure rate - FFU creation broken)

**Immediate Action Required**: Fix Phase 1 CRITICAL functions (11 functions in 3 modules) to restore basic build functionality.

**Long-term Goal**: Complete all 4 phases to achieve 100% module encapsulation and eliminate all script-scope dependencies.
