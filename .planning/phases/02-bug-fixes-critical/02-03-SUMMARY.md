---
phase: 02-bug-fixes-critical
plan: 03
subsystem: imaging
tags: [vhdx, partition, drivers, dism, expansion, bug-fix]
dependency-graph:
  requires: []
  provides: [vhdx-expansion, partition-expansion, driver-size-calculation]
  affects: [driver-injection-workflow]
tech-stack:
  added: []
  patterns: [Resize-VHD, Get-PartitionSupportedSize, Resize-Partition, driver-threshold-check]
key-files:
  created: []
  modified:
    - FFUDevelopment/Modules/FFU.Imaging/FFU.Imaging.psm1
    - FFUDevelopment/Modules/FFU.Imaging/FFU.Imaging.psd1
decisions:
  - id: THRESHOLD_5GB
    summary: "5GB threshold triggers expansion based on typical large OEM driver set sizes"
    rationale: "Dell/HP enterprise driver packs often exceed 5GB; smaller consumer packs rarely approach this"
  - id: COMPRESSION_FACTOR_1_5X
    summary: "1.5x compression factor accounts for DISM Add-WindowsDriver expansion"
    rationale: "DISM extracts INF drivers during injection, often doubling file count with metadata"
  - id: SAFETY_MARGIN_5GB
    summary: "5GB safety margin provides buffer for OS updates and other operations"
    rationale: "Leaves headroom for future additions without re-expansion"
metrics:
  duration: "~8 minutes"
  completed: 2026-01-19
---

# Phase 2 Plan 3: Add VHDX/Partition Expansion for Large Driver Sets Summary

**One-liner:** Auto-expanding VHDX and OS partition when driver sets exceed 5GB threshold using Resize-VHD and Get-PartitionSupportedSize

## What Was Done

### Task 1: Create Expand-FFUPartitionForDrivers Function
Added new function `Expand-FFUPartitionForDrivers` to FFU.Imaging module (lines 2623-2780). The function:

1. **Calculates driver folder size** using Get-ChildItem recursive file enumeration
2. **Checks threshold** (default 5GB) to determine if expansion is needed
3. **Dismounts VHDX** before resize (Resize-VHD requires exclusive access)
4. **Expands VHDX file** to accommodate driver size + compression factor + safety margin
5. **Mounts and expands partition** using Get-PartitionSupportedSize for safe maximum
6. **Handles mount state** - restores original state on completion or error

**Key implementation details:**
```powershell
# Calculate required space with compression factor and safety margin
$compressionFactor = 1.5
$requiredDriverSpace = [math]::Ceiling($driverSizeGB * $compressionFactor)
$requiredSizeGB = $currentSizeGB + $requiredDriverSpace + $SafetyMarginGB

# Resize VHDX
Resize-VHD -Path $VHDXPath -SizeBytes ($requiredSizeGB * 1GB)

# Get maximum supported partition size and expand
$supportedSize = Get-PartitionSupportedSize -DiskNumber $disk.Number -PartitionNumber $osPartition.PartitionNumber
Resize-Partition -DiskNumber $disk.Number -PartitionNumber $osPartition.PartitionNumber -Size $supportedSize.SizeMax
```

**Parameters:**
| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| VHDXPath | string | (required) | Path to VHDX file to expand |
| DriversFolder | string | (required) | Path to drivers folder to measure |
| ThresholdGB | int | 5 | Minimum driver size that triggers expansion |
| SafetyMarginGB | int | 5 | Additional space beyond driver size |

### Task 2: Update Module Manifest
- FFU.Imaging: 1.0.9 -> 1.0.10
- Added `Expand-FFUPartitionForDrivers` to FunctionsToExport array
- Added detailed release notes documenting BUG-03 fix

## Commits

| Hash | Type | Description |
|------|------|-------------|
| 987c32c | feat | Add Expand-FFUPartitionForDrivers for large driver sets |

## Verification Results

| Check | Status |
|-------|--------|
| Module loads without errors | PASS |
| Function exported | PASS |
| Manifest version is 1.0.10 | PASS |
| Resize-VHD pattern present | PASS |
| Get-PartitionSupportedSize pattern present | PASS |
| Resize-Partition pattern present | PASS |
| Help synopsis available | PASS |
| Required parameters present | PASS |

## Decisions Made

| Decision | Rationale |
|----------|-----------|
| 5GB threshold | Large OEM driver packs (Dell, HP enterprise) typically exceed 5GB; consumer packs rarely reach this |
| 1.5x compression factor | DISM driver injection extracts INF files and creates metadata, often increasing consumed space |
| 5GB safety margin | Provides buffer for OS updates and additional operations without re-expansion |
| Dismount before resize | Resize-VHD cmdlet requires exclusive file access; VHDX must be detached |
| Get-PartitionSupportedSize | Safely determines maximum partition size without overflow or alignment issues |

## Deviations from Plan

None - plan executed exactly as written.

## Next Phase Readiness

- Expand-FFUPartitionForDrivers function ready for integration into driver injection workflow
- Function can be called before DISM Add-WindowsDriver operations
- Supports both pre-mounted and unmounted VHDX scenarios (preserves mount state)

## Files Modified

1. `FFUDevelopment/Modules/FFU.Imaging/FFU.Imaging.psm1` - Added Expand-FFUPartitionForDrivers function (158 lines)
2. `FFUDevelopment/Modules/FFU.Imaging/FFU.Imaging.psd1` - Version bump + export + release notes
