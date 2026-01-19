---
phase: 03
plan: 03
subsystem: security
tags: [integrity, verification, sha256, orchestration, scripts]

dependency-graph:
  requires: [phase-03-research]
  provides: [script-integrity-verification, hash-manifest-system]
  affects: [orchestration-security, vm-script-execution]

tech-stack:
  added: []
  patterns:
    - SHA256 hash verification
    - JSON manifest for integrity hashes
    - Pre-execution script verification

key-files:
  created:
    - FFUDevelopment/.security/orchestration-hashes.json
  modified:
    - FFUDevelopment/Modules/FFU.Core/FFU.Core.psm1
    - FFUDevelopment/Modules/FFU.Core/FFU.Core.psd1
    - FFUDevelopment/Apps/Orchestration/Orchestrator.ps1

decisions:
  - decision: Use SHA-256 for hash algorithm
    rationale: Industry standard, collision-resistant, native PowerShell support via Get-FileHash
  - decision: Store manifest in .security folder
    rationale: Separate from scripts (attacker would need to modify both), clear purpose
  - decision: Inline verification in Orchestrator.ps1
    rationale: FFU.Core module not available inside VM where orchestration scripts run
  - decision: Self-verification halts, individual script failure continues
    rationale: Orchestrator tampering is critical (halt), individual script tampering allows recovery
  - decision: Permissive mode when no hash available
    rationale: Development flexibility - scripts without hashes still execute with warning

metrics:
  duration: 5m
  completed: 2026-01-19
---

# Phase 3 Plan 03: Script Integrity Verification Summary

**One-liner:** SHA-256 hash verification for orchestration scripts with manifest-based validation before execution.

## What Changed

### FFU.Core Module (v1.0.15)
Added three script integrity verification functions:

1. **Test-ScriptIntegrity** - Verifies a script file against expected SHA-256 hash
   - Supports direct hash or manifest lookup
   - Configurable FailOnMismatch behavior
   - Safe logging (WriteLog or Write-Verbose fallback)

2. **New-OrchestrationHashManifest** - Generates hash manifest for all orchestration scripts
   - Calculates SHA-256 for all .ps1 files in a directory
   - Creates JSON manifest with algorithm, version, generated timestamp

3. **Update-OrchestrationHashManifest** - Updates specific scripts' hashes
   - Selective update without regenerating entire manifest
   - Creates manifest if it doesn't exist

### Hash Manifest (.security/orchestration-hashes.json)
Initial manifest generated with SHA-256 hashes for 6 orchestration scripts:
- `Orchestrator.ps1`
- `Install-StoreApps.ps1`
- `Install-Win32Apps.ps1`
- `Invoke-AppsScript.ps1`
- `Run-DiskCleanup.ps1`
- `Run-Sysprep.ps1`

### Orchestrator.ps1 Verification
Added integrity verification throughout the orchestration script:

1. **Self-verification on startup** - Orchestrator.ps1 verifies its own hash before proceeding
   - Failure: Script halts with exit code 1
   - Prevents execution of tampered orchestrator

2. **Script loop verification** - Each script in the main loop is verified before execution
   - Failure: Script is skipped, others continue

3. **Special script verification** - Invoke-AppsScript.ps1, Run-DiskCleanup.ps1, Run-Sysprep.ps1
   - Failure: Individual script skipped

4. **Configurable flag** - `$verifyIntegrity = $true` can disable all verification

## Security Rationale

Orchestration scripts run inside the FFU build VM with full system access. Without integrity verification, a compromised script could:
- Install malware during image creation
- Exfiltrate credentials written to capture scripts
- Modify system configuration maliciously

The hash verification system provides:
- **Detection** of script tampering before execution
- **Clear logging** of verification status and failures
- **Fail-safe behavior** (self-verification halts entire process)
- **Graceful degradation** (individual script failures don't stop build)

## Usage

### Generate/Regenerate Manifest
```powershell
Import-Module FFU.Core -Force
New-OrchestrationHashManifest -OrchestrationPath "C:\FFUDevelopment\Apps\Orchestration" `
                              -ManifestPath "C:\FFUDevelopment\.security\orchestration-hashes.json"
```

### Update After Script Modification
```powershell
Import-Module FFU.Core -Force
Update-OrchestrationHashManifest -OrchestrationPath "C:\FFUDevelopment\Apps\Orchestration" `
                                  -ManifestPath "C:\FFUDevelopment\.security\orchestration-hashes.json" `
                                  -ScriptNames @("Orchestrator.ps1")
```

### Verify Individual Script
```powershell
Import-Module FFU.Core -Force
Test-ScriptIntegrity -ScriptPath "C:\FFUDevelopment\Apps\Orchestration\Orchestrator.ps1" `
                     -ManifestPath "C:\FFUDevelopment\.security\orchestration-hashes.json"
```

## Commits

| Commit | Type | Description |
|--------|------|-------------|
| 4db4397 | feat | Add script integrity verification functions to FFU.Core |
| bccb196 | feat | Generate initial hash manifest for orchestration scripts |
| 8f0e885 | feat | Add integrity verification to Orchestrator.ps1 |

## Deviations from Plan

None - plan executed exactly as written.

## Next Phase Readiness

**Ready for:** SEC-01 (Lenovo PSREF token caching) and SEC-02 (SecureString audit)

**Dependencies satisfied:** Script integrity verification complete, can be used as pattern for other integrity checks.

**Blockers:** None
