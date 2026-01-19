# Phase 8: Feature - Progress Checkpoint/Resume - Research

**Researched:** 2026-01-19
**Domain:** Build State Persistence, Checkpoint/Resume Pattern, JSON Serialization
**Confidence:** HIGH

## Summary

Implementing checkpoint/resume for FFUBuilder requires persisting build state to disk at strategic phase boundaries, then detecting and loading that state on restart to continue from where the build left off. The codebase already has several relevant patterns:

1. **Cancellation checkpoints (Phase 7)** - 8 strategic checkpoints already exist in BuildFFUVM.ps1 that mark phase boundaries
2. **VHDX caching** - Existing JSON-based state persistence pattern (`VhdxCacheItem` class)
3. **Cleanup registry** - In-memory resource tracking that could be extended for persistence
4. **JSON configuration** - Existing `ConvertTo-Json`/`ConvertFrom-Json` patterns throughout codebase

The implementation strategy is to create a `BuildCheckpoint` class that captures build state at each phase boundary, serialize it to JSON in the FFUDevelopmentPath, and add resume detection logic at script startup. The existing cancellation checkpoint locations are ideal for state persistence.

**Primary recommendation:** Create a new FFU.Checkpoint module with `Save-FFUBuildCheckpoint`, `Get-FFUBuildCheckpoint`, and `Resume-FFUBuild` functions. Store checkpoint data in `{FFUDevelopmentPath}/.ffubuilder/checkpoint.json`. Use the existing 8 cancellation checkpoint locations as persistence points.

## Current State Analysis

### What Already Exists

| Component | Location | Reusability |
|-----------|----------|-------------|
| 8 cancellation checkpoints | BuildFFUVM.ps1 lines 1721, 2341, 3541, 3825, 4293, 4369, 4467, 4562, 4588 | HIGH - Perfect phase boundary markers |
| JSON serialization patterns | Throughout codebase | HIGH - `ConvertTo-Json -Depth 10` pattern |
| VHDX cache persistence | BuildFFUVM.ps1 lines 3651-3657 | MEDIUM - Similar state persistence model |
| Cleanup registry | FFU.Core.psm1 lines 2167-2364 | MEDIUM - Resource tracking could be persisted |
| Messaging context | FFU.Messaging.psm1 | MEDIUM - Build state enum already exists |
| Progress tracking | Set-Progress calls | HIGH - 23+ progress points with percentages |

### What Is Missing

| Gap | Impact | Required Work |
|-----|--------|---------------|
| State persistence to disk | Cannot resume after restart | Create checkpoint file writer |
| State detection on startup | Cannot detect resumable state | Add startup state detection |
| Partial artifact detection | May miss completed artifacts | Add file existence checks |
| Resume decision logic | User choice to resume vs fresh | Add resume prompt/flag |
| Cleanup registry persistence | Resources lost on crash | Serialize registry to checkpoint |

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| ConvertTo-Json | PowerShell built-in | State serialization | Native, well-tested, handles nested objects |
| ConvertFrom-Json | PowerShell built-in | State deserialization | Native, `-AsHashtable` for PS7+ |
| [PSCustomObject] | PowerShell built-in | Structured state storage | Serializable, type-safe |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Test-Path | PowerShell built-in | Checkpoint file detection | Startup resume check |
| Get-FileHash | PowerShell built-in | State integrity verification | Optional validation |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| JSON file | SQLite database | JSON is simpler, human-readable, sufficient for single build state |
| Single checkpoint file | Multiple phase files | Single file easier to manage, atomic writes |
| PSCustomObject | Class definition | PSCustomObject serializes better with ConvertTo-Json |

## Architecture Patterns

### Recommended State File Structure

```json
{
  "version": "1.0",
  "buildId": "FFU-20260119-1234",
  "timestamp": "2026-01-19T15:30:00Z",
  "lastCompletedPhase": "VHDX_CREATION",
  "lastCheckpointPhase": "VM_SETUP",
  "percentComplete": 45,
  "configuration": {
    "FFUDevelopmentPath": "C:\\FFUDevelopment",
    "WindowsRelease": 11,
    "WindowsVersion": "24H2",
    "WindowsSKU": "Pro",
    "InstallApps": true,
    "HypervisorType": "HyperV"
  },
  "artifacts": {
    "vhdxPath": "C:\\FFUDevelopment\\VM\\FFU-1234\\FFU-1234.vhdx",
    "vhdxCreated": true,
    "vmName": "FFU-1234",
    "vmCreated": false,
    "driversDownloaded": true,
    "appsIsoCreated": true,
    "captureIsoCreated": false,
    "ffuCaptured": false
  },
  "cleanupRegistry": [
    {
      "id": "abc123",
      "name": "Remove VHDX",
      "resourceType": "VHDX",
      "resourceId": "C:\\FFUDevelopment\\VM\\FFU-1234\\FFU-1234.vhdx"
    }
  ],
  "paths": {
    "VHDXPath": "C:\\FFUDevelopment\\VM\\FFU-1234\\FFU-1234.vhdx",
    "VMPath": "C:\\FFUDevelopment\\VM\\FFU-1234",
    "DriversFolder": "C:\\FFUDevelopment\\Drivers",
    "AppsISO": "C:\\FFUDevelopment\\Apps\\Apps.iso"
  }
}
```

### Build Phases Enumeration

```powershell
enum FFUBuildPhase {
    NotStarted = 0
    PreflightValidation = 1
    DriverDownload = 2
    UpdatesDownload = 3
    AppsPreparation = 4
    VHDXCreation = 5
    WindowsUpdates = 6
    VMSetup = 7
    VMStart = 8
    AppInstallation = 9
    VMShutdown = 10
    FFUCapture = 11
    DeploymentMedia = 12
    USBCreation = 13
    Cleanup = 14
    Completed = 15
}
```

### Checkpoint Location Mapping

| Existing Checkpoint | Line | Phase | What to Persist |
|---------------------|------|-------|-----------------|
| CHECKPOINT 1 | 1721 | PreflightValidation | Configuration validated |
| CHECKPOINT 2 | 2341 | DriverDownload | Drivers downloaded, paths |
| CHECKPOINT 3 | 3541 | VHDXCreation | VHDX path, before creation |
| CHECKPOINT 4 | 3825 | VMSetup | VHDX created, updates applied |
| CHECKPOINT 5 | 4293 | VMStart | VM configured, before start |
| CHECKPOINT 6a | 4369 | FFUCapture (pre-apps) | VM ready for capture |
| CHECKPOINT 6b | 4467 | FFUCapture (post-apps) | Apps installed, VM shutdown |
| CHECKPOINT 7 | 4562 | DeploymentMedia | FFU captured |
| CHECKPOINT 8 | 4588 | USBCreation | Deploy ISO created |

### Resume Decision Flow

```
Script Startup
    |
    +-- Check for checkpoint file
        |
        +-- No file --> Fresh build
        |
        +-- File exists -->
            |
            +-- Validate checkpoint (version, paths exist)
            |
            +-- If valid:
            |   +-- Check artifacts exist
            |   +-- Prompt user: Resume or Fresh build?
            |   +-- If Resume: Load state, skip completed phases
            |   +-- If Fresh: Delete checkpoint, start fresh
            |
            +-- If invalid:
                +-- Log warning
                +-- Delete corrupt checkpoint
                +-- Fresh build
```

### Checkpoint Save Pattern

```powershell
function Save-FFUBuildCheckpoint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [FFUBuildPhase]$CompletedPhase,

        [Parameter(Mandatory)]
        [hashtable]$Configuration,

        [Parameter(Mandatory)]
        [hashtable]$Artifacts,

        [Parameter(Mandatory)]
        [hashtable]$Paths,

        [Parameter()]
        [string]$FFUDevelopmentPath
    )

    $checkpointPath = Join-Path $FFUDevelopmentPath ".ffubuilder\checkpoint.json"

    $checkpoint = [PSCustomObject]@{
        version = "1.0"
        buildId = $Configuration.VMName
        timestamp = (Get-Date).ToUniversalTime().ToString("o")
        lastCompletedPhase = $CompletedPhase.ToString()
        configuration = $Configuration
        artifacts = $Artifacts
        paths = $Paths
        cleanupRegistry = Get-CleanupRegistry | ForEach-Object {
            [PSCustomObject]@{
                id = $_.Id
                name = $_.Name
                resourceType = $_.ResourceType
                resourceId = $_.ResourceId
                # Note: Action scriptblock cannot be serialized
            }
        }
    }

    # Atomic write: write to temp, then rename
    $tempPath = "$checkpointPath.tmp"
    $checkpoint | ConvertTo-Json -Depth 10 | Set-Content -Path $tempPath -Encoding UTF8
    Move-Item -Path $tempPath -Destination $checkpointPath -Force

    WriteLog "Checkpoint saved: Phase $CompletedPhase"
}
```

### Resume Pattern

```powershell
function Resume-FFUBuild {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FFUDevelopmentPath,

        [Parameter()]
        [switch]$Force  # Skip user prompt
    )

    $checkpointPath = Join-Path $FFUDevelopmentPath ".ffubuilder\checkpoint.json"

    if (-not (Test-Path $checkpointPath)) {
        return $null  # No checkpoint, fresh build
    }

    try {
        $checkpoint = Get-Content $checkpointPath -Raw | ConvertFrom-Json -AsHashtable

        # Validate checkpoint version
        if ($checkpoint.version -ne "1.0") {
            WriteLog "WARNING: Checkpoint version mismatch, starting fresh"
            Remove-Item $checkpointPath -Force
            return $null
        }

        # Validate artifacts still exist
        $artifactsValid = Test-CheckpointArtifacts -Checkpoint $checkpoint
        if (-not $artifactsValid) {
            WriteLog "WARNING: Checkpoint artifacts missing, starting fresh"
            Remove-Item $checkpointPath -Force
            return $null
        }

        # User prompt (unless Force)
        if (-not $Force) {
            $lastPhase = $checkpoint.lastCompletedPhase
            $timestamp = $checkpoint.timestamp
            WriteLog "Found checkpoint from $timestamp at phase: $lastPhase"
            # In UI mode, show dialog; in CLI mode, use Read-Host
        }

        return $checkpoint
    }
    catch {
        WriteLog "WARNING: Failed to load checkpoint: $_"
        Remove-Item $checkpointPath -Force -ErrorAction SilentlyContinue
        return $null
    }
}
```

### Anti-Patterns to Avoid

- **Persisting scriptblocks:** Cannot serialize Action scriptblocks from cleanup registry; must recreate on resume
- **Absolute paths without validation:** Always verify paths exist before resuming
- **Single write without atomic rename:** Use temp file + rename to prevent corruption
- **Persisting sensitive data:** Never checkpoint passwords or credentials
- **Resuming mid-operation:** Only checkpoint at phase boundaries, never mid-DISM or mid-download

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| JSON serialization | Custom serializer | ConvertTo-Json -Depth 10 | Native, handles nested objects |
| Atomic file writes | Direct Set-Content | Temp file + Move-Item | Prevents corruption on crash |
| State validation | Manual property checks | JSON schema validation | More robust, self-documenting |
| Phase ordering | String comparisons | Enum with integer values | Type-safe, orderable |

**Key insight:** The existing cleanup registry pattern shows how to track resources, but it's in-memory only. The checkpoint system extends this to disk persistence, minus the non-serializable scriptblock actions.

## Common Pitfalls

### Pitfall 1: Stale Checkpoint After Manual Cleanup
**What goes wrong:** User manually deletes VM/VHDX, but checkpoint still references them
**Why it happens:** Checkpoint not updated when user intervenes outside script
**How to avoid:** Always validate artifact existence before resuming
**Warning signs:** "File not found" errors after resume

### Pitfall 2: Version Mismatch After Script Update
**What goes wrong:** Old checkpoint incompatible with new script version
**Why it happens:** Checkpoint format or phase names changed
**How to avoid:** Include version field, validate on load, fail gracefully
**Warning signs:** Resume behaves unexpectedly or fails

### Pitfall 3: Credential Persistence Security Risk
**What goes wrong:** Checkpoint contains plaintext credentials
**Why it happens:** Accidentally serializing capture user password
**How to avoid:** Explicitly exclude sensitive fields from checkpoint
**Warning signs:** Passwords visible in checkpoint.json file

### Pitfall 4: Partial Phase Completion
**What goes wrong:** Phase partially completes, checkpoint says complete
**Why it happens:** Checkpoint saved before phase fully finished
**How to avoid:** Only save checkpoint AFTER phase fully completes
**Warning signs:** Missing files despite checkpoint showing phase complete

### Pitfall 5: Orphaned Resources on Failed Resume
**What goes wrong:** Resume fails, leaving VMs/VHDXs from original attempt
**Why it happens:** Cleanup registry not restored properly
**How to avoid:** Restore cleanup registry from checkpoint before any operations
**Warning signs:** Multiple orphaned VMs with similar names

## Code Examples

### Example 1: Checkpoint State Class

```powershell
# Source: New class for FFU.Checkpoint module
class FFUBuildCheckpoint {
    [string]$Version = "1.0"
    [string]$BuildId
    [datetime]$Timestamp
    [string]$LastCompletedPhase
    [int]$PercentComplete
    [hashtable]$Configuration
    [hashtable]$Artifacts
    [hashtable]$Paths
    [array]$CleanupEntries

    FFUBuildCheckpoint() {
        $this.Timestamp = [datetime]::UtcNow
        $this.Configuration = @{}
        $this.Artifacts = @{}
        $this.Paths = @{}
        $this.CleanupEntries = @()
    }

    [void] SetArtifactComplete([string]$ArtifactName) {
        $this.Artifacts[$ArtifactName] = $true
    }

    [bool] IsArtifactComplete([string]$ArtifactName) {
        return $this.Artifacts.ContainsKey($ArtifactName) -and $this.Artifacts[$ArtifactName]
    }

    [string] ToJson() {
        return $this | ConvertTo-Json -Depth 10
    }

    static [FFUBuildCheckpoint] FromJson([string]$Json) {
        $data = $Json | ConvertFrom-Json -AsHashtable
        $checkpoint = [FFUBuildCheckpoint]::new()
        $checkpoint.Version = $data.Version
        $checkpoint.BuildId = $data.BuildId
        $checkpoint.Timestamp = [datetime]::Parse($data.Timestamp)
        $checkpoint.LastCompletedPhase = $data.LastCompletedPhase
        $checkpoint.PercentComplete = $data.PercentComplete
        $checkpoint.Configuration = $data.Configuration
        $checkpoint.Artifacts = $data.Artifacts
        $checkpoint.Paths = $data.Paths
        $checkpoint.CleanupEntries = $data.CleanupEntries
        return $checkpoint
    }
}
```

### Example 2: Integration with Existing Checkpoints

```powershell
# Source: Pattern for BuildFFUVM.ps1 integration
# After each existing cancellation checkpoint, add state persistence

# Example at CHECKPOINT 4 (line ~3825)
# === CANCELLATION CHECKPOINT 4: After VHDX Creation, Before VM Setup ===
if (Test-BuildCancellation -MessagingContext $MessagingContext -PhaseName "VM Setup" -InvokeCleanup) {
    WriteLog "Build cancelled by user at: VM Setup"
    return
}

# NEW: Persist checkpoint state
if ($script:CheckpointEnabled) {
    Save-FFUBuildCheckpoint -CompletedPhase 'VMSetup' `
        -Configuration @{
            FFUDevelopmentPath = $FFUDevelopmentPath
            WindowsRelease = $WindowsRelease
            WindowsVersion = $WindowsVersion
            WindowsSKU = $WindowsSKU
            InstallApps = $InstallApps
            HypervisorType = $HypervisorType
            VMName = $VMName
        } `
        -Artifacts @{
            vhdxCreated = $true
            driversDownloaded = $driversDownloaded
            updatesApplied = ($UpdateLatestCU -or $UpdateLatestNet)
        } `
        -Paths @{
            VHDXPath = $VHDXPath
            VMPath = $VMPath
            DriversFolder = $DriversFolder
        } `
        -FFUDevelopmentPath $FFUDevelopmentPath
}
```

### Example 3: Resume Detection at Script Startup

```powershell
# Source: Pattern for BuildFFUVM.ps1 BEGIN block
BEGIN {
    # Check for existing checkpoint (before any work)
    $checkpointPath = Join-Path $FFUDevelopmentPath ".ffubuilder\checkpoint.json"
    $script:ResumeCheckpoint = $null
    $script:CheckpointEnabled = $true  # Can be disabled via parameter

    if (Test-Path $checkpointPath) {
        WriteLog "Found existing build checkpoint"

        try {
            $script:ResumeCheckpoint = Get-FFUBuildCheckpoint -FFUDevelopmentPath $FFUDevelopmentPath

            if ($null -ne $script:ResumeCheckpoint) {
                $lastPhase = $script:ResumeCheckpoint.LastCompletedPhase
                $timestamp = $script:ResumeCheckpoint.Timestamp

                WriteLog "Checkpoint from $timestamp at phase: $lastPhase"

                # UI mode: Send message to show resume dialog
                if ($MessagingContext) {
                    Write-FFUMessage -Context $MessagingContext `
                        -Message "Found interrupted build. Resume from $lastPhase?" `
                        -Level Warning `
                        -Data @{ CheckpointPhase = $lastPhase; Action = 'PromptResume' }
                }
                # CLI mode: Prompt via console
                else {
                    $response = Read-Host "Resume from phase '$lastPhase'? (Y/N)"
                    if ($response -ne 'Y') {
                        WriteLog "User chose fresh build"
                        Remove-Item $checkpointPath -Force
                        $script:ResumeCheckpoint = $null
                    }
                }
            }
        }
        catch {
            WriteLog "WARNING: Failed to load checkpoint, starting fresh: $_"
            Remove-Item $checkpointPath -Force -ErrorAction SilentlyContinue
        }
    }
}
```

### Example 4: Phase Skip Logic

```powershell
# Source: Pattern for skipping completed phases
function Test-PhaseAlreadyComplete {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PhaseName,

        [Parameter()]
        [hashtable]$Checkpoint
    )

    if ($null -eq $Checkpoint) {
        return $false
    }

    $phaseOrder = @{
        'PreflightValidation' = 1
        'DriverDownload' = 2
        'VHDXCreation' = 3
        'VMSetup' = 4
        'VMStart' = 5
        'FFUCapture' = 6
        'DeploymentMedia' = 7
        'USBCreation' = 8
    }

    $currentPhaseOrder = $phaseOrder[$PhaseName]
    $checkpointPhaseOrder = $phaseOrder[$Checkpoint.LastCompletedPhase]

    if ($currentPhaseOrder -le $checkpointPhaseOrder) {
        WriteLog "Skipping phase '$PhaseName' - already completed in checkpoint"
        return $true
    }

    return $false
}

# Usage in BuildFFUVM.ps1:
if (-not (Test-PhaseAlreadyComplete -PhaseName 'DriverDownload' -Checkpoint $script:ResumeCheckpoint)) {
    # ... driver download code ...
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| PowerShell Workflow checkpoints | File-based JSON checkpoints | PS7 deprecated workflows | Must use custom solution |
| In-memory only state | Persisted state files | Industry standard | Enables resume after crash |
| Full script restart | Phase-aware resume | Modern build systems | Saves hours on long builds |

**Deprecated/outdated:**
- PowerShell Workflow and `Checkpoint-Workflow`: Removed in PowerShell 7, not available
- PSSerializer (CliXml): More complex, less readable than JSON, depth limit of 48

## Risk Assessment

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Checkpoint file corruption | LOW | MEDIUM | Atomic writes with temp file + rename |
| State/artifact mismatch | MEDIUM | LOW | Validate artifacts exist before resume |
| Version incompatibility | LOW | LOW | Include version, validate on load |
| Security (credential leak) | LOW | HIGH | Explicitly exclude sensitive fields |
| User confusion on resume | MEDIUM | LOW | Clear prompts explaining options |

## Open Questions

### 1. UI Integration for Resume Prompt
- **What we know:** CLI can use Read-Host, UI needs different approach
- **What's unclear:** Best UX pattern - dialog box? Banner? Automatic?
- **Recommendation:** Start with CLI support; UI can show modal dialog via FFU.Messaging

### 2. Checkpoint File Location
- **What we know:** FFUDevelopmentPath is the logical place
- **What's unclear:** Should checkpoint be in .ffubuilder subfolder or root?
- **Recommendation:** Use `.ffubuilder/checkpoint.json` for organization, matches pattern of hidden config folders

### 3. Multiple Concurrent Builds
- **What we know:** VMName includes random suffix for uniqueness
- **What's unclear:** How to handle multiple checkpoints if user runs multiple builds
- **Recommendation:** Include BuildId in checkpoint filename: `.ffubuilder/checkpoint-{VMName}.json`

### 4. Cleanup Registry Restoration
- **What we know:** Scriptblocks cannot be serialized
- **What's unclear:** How to restore cleanup actions on resume
- **Recommendation:** Re-register cleanup actions based on artifacts, don't persist scriptblocks

## Sources

### Primary (HIGH confidence)
- BuildFFUVM.ps1 - Existing 8 cancellation checkpoints (lines 1721, 2341, 3541, 3825, 4293, 4369, 4467, 4562, 4588)
- FFU.Core.psm1 - Cleanup registry implementation (lines 2167-2364)
- FFU.Messaging.psm1 - FFUBuildState enum, messaging patterns
- FFU.Common.Classes.psm1 - Existing class patterns

### Secondary (MEDIUM confidence)
- [Microsoft Learn: ConvertTo-Json](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/convertto-json)
- [Microsoft Learn: ConvertFrom-Json](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/convertfrom-json)
- [Microsoft Learn: Everything about hashtables](https://learn.microsoft.com/en-us/powershell/scripting/learn/deep-dives/everything-about-hashtable)
- [4sysops: Convert JSON to hashtable](https://4sysops.com/archives/convert-json-to-a-powershell-hash-table/)

### Tertiary (LOW confidence)
- [Microsoft Learn: Checkpointing and Resuming Workflows (Agent Framework)](https://learn.microsoft.com/en-us/agent-framework/tutorials/workflows/checkpointing-and-resuming) - Concepts applicable, not PowerShell-specific
- [NURC: Checkpointing Jobs](https://rc-docs.northeastern.edu/en/explorer-main/best-practices/checkpointing.html) - General checkpointing best practices

## Metadata

**Confidence breakdown:**
- Architecture patterns: HIGH - Based on existing codebase patterns and PowerShell built-ins
- Standard stack: HIGH - Using native PowerShell JSON cmdlets
- Pitfalls: MEDIUM - Derived from code analysis and general patterns
- Implementation recommendations: HIGH - Clear scope from existing checkpoint infrastructure

**Research date:** 2026-01-19
**Valid until:** 90 days (stable domain, uses native PowerShell features)
