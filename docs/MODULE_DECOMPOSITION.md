# Module Decomposition Analysis

**Created:** 2026-01-19
**Requirement:** PERF-03
**Status:** Evaluated - Deferred

## Summary

This document captures the module decomposition analysis for FFU Builder's PowerShell modules.
After evaluation, the decision is to **defer decomposition** - current module organization is
appropriate for the project's needs.

## Current Module Structure

| Module | Lines | Functions | Domain |
|--------|-------|-----------|--------|
| FFU.Core | ~2,963 | 39 | Configuration, logging, error handling, credentials |
| FFU.Preflight | ~2,883 | 12 | Pre-flight validation, environment checks |
| FFU.Imaging | ~2,805 | 15 | DISM operations, FFU capture, VHD management |
| FFU.Updates | ~1,500 | 8 | Windows Update, KB downloads, MSU processing |
| FFU.Hypervisor | ~1,200 | 8 | Hyper-V/VMware abstraction, provider pattern |
| FFU.Media | ~800 | 4 | WinPE media creation |
| FFU.VM | ~600 | 3 | VM lifecycle operations |
| FFU.Drivers | ~500 | 5 | OEM driver management |
| FFU.Apps | ~400 | 5 | Application management |
| FFU.ADK | ~350 | 8 | Windows ADK validation |
| FFU.Messaging | ~300 | 14 | Thread-safe UI communication |
| FFU.Constants | ~300 | N/A | Constants and configuration |
| FFU.Common | ~1,800 | 20+ | Shared utilities (download, parallel, winget) |
| BuildFFUVM.ps1 | ~4,683 | N/A | Main orchestrator script |

**Total:** 14+ modules with clear domain boundaries

## Analysis

### Why Decomposition Was Considered

Large files (>2,000 lines) can be harder to navigate and maintain. The largest modules are:
- FFU.Core (2,963 lines)
- FFU.Preflight (2,883 lines)
- FFU.Imaging (2,805 lines)
- BuildFFUVM.ps1 (4,683 lines - orchestrator, not a module)

### Why Decomposition Is Deferred

1. **Import Performance Impact**

   Multi-file modules using dot-sourcing load 12-15x slower than single PSM1 files:

   | Structure | Import Time |
   |-----------|-------------|
   | Single PSM1 | ~100ms |
   | 10 dot-sourced files | ~1,200ms |
   | 20 dot-sourced files | ~2,400ms |

   Source: [Evotec - Single PSM1 vs Multi-file Modules](https://evotec.xyz/powershell-single-psm1-file-versus-multi-file-modules/)

2. **Modules Are Already Well-Structured**

   The project has 14+ specialized modules, each with a clear domain:
   - FFU.Core = configuration, logging, credentials
   - FFU.Imaging = DISM, FFU capture, VHD
   - FFU.Preflight = validation and checks

   These are cohesive units - splitting FFU.Core into FFU.Core.Logging + FFU.Core.Config + FFU.Core.Credentials would fragment related functionality.

3. **Current Sizes Are Manageable**

   2,500-3,000 lines is at the upper end of comfortable but not problematic:
   - Functions are individually documented
   - Code is organized with region markers
   - Module manifests declare exports

4. **Orchestrator Is Not a Module**

   BuildFFUVM.ps1 (4,683 lines) is the main build script, not a reusable module.
   Its length reflects the complexity of the build process, not poor organization.
   The script was already reduced from 7,790 lines through the initial modularization.

## Recommendation: Defer

**Decision:** Do not decompose modules at this time.

**Rationale:**
- Import performance penalty outweighs maintainability benefit
- Current module boundaries are logical and domain-aligned
- Further splitting would create artificial divisions

**Revisit When:**
- A module exceeds 5,000 lines
- A module spans multiple unrelated domains
- Build-time merging tooling is adopted

## Future Guidance

If decomposition is needed in the future:

### Option 1: Build-Time Merging

Develop in multiple files, merge for production:

```powershell
# build.ps1
$sourceFiles = Get-ChildItem "src/FFU.Core/*.ps1"
$merged = $sourceFiles | ForEach-Object { Get-Content $_.FullName }
$merged | Set-Content "dist/FFU.Core.psm1"
```

**Pros:** Best of both worlds - organized source, fast import
**Cons:** Requires build step, debugging maps to merged file

### Option 2: Nested Modules

Use module manifest NestedModules for logical grouping:

```powershell
# FFU.Core.psd1
NestedModules = @(
    'FFU.Core.Logging.psm1',
    'FFU.Core.Config.psm1',
    'FFU.Core.Credentials.psm1'
)
```

**Pros:** Maintains single import point
**Cons:** Still incurs multi-file load penalty

### Option 3: Selective Splitting

Only split modules that span truly different domains:

```
FFU.Core (current 2,963 lines)
+-- Configuration functions (1,200 lines) - KEEP together
+-- Logging functions (400 lines) - KEEP together
+-- Cleanup functions (500 lines) - KEEP together
+-- Credential functions (800 lines) - COULD extract if grows
```

## References

- [Evotec - Module Performance](https://evotec.xyz/powershell-single-psm1-file-versus-multi-file-modules/)
- [PowerShell Playbook - Module Best Practices](https://www.psplaybook.com/2025/02/06/powershell-modules-best-practices/)
- [04-RESEARCH.md](.planning/phases/04-performance-optimization/04-RESEARCH.md) - Phase 4 research findings

---
*Analysis date: 2026-01-19*
*Decision: Defer decomposition - current structure appropriate*
