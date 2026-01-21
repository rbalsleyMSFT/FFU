# FFU Builder - Project Context

## What This Is

FFU Builder is a PowerShell-based Windows deployment tool that creates pre-configured Windows 11 images (FFU format) deployable in under 2 minutes. It features a WPF UI, supports both Hyper-V and VMware Workstation Pro, integrates with OEM driver catalogs (Dell, HP, Lenovo, Microsoft), and includes comprehensive build management capabilities including graceful cancellation, checkpoint/resume, and configuration migration.

## Core Value

Enable rapid, reliable Windows deployment through pre-configured FFU images with minimal manual intervention.

## Requirements

### Validated

- Modular architecture with 11 PowerShell modules — v1.0
- WPF-based UI with background job execution — v1.0
- Hyper-V and VMware Workstation Pro support — v1.6.0
- OEM driver integration (Dell, HP, Lenovo, Microsoft) — v1.0
- Pre-flight validation system with tiered checks — v1.3.0
- Thread-safe UI/job messaging via FFU.Messaging — v1.0
- **Tech Debt Cleanup** — v1.8.0
  - Deprecated FFU.Constants properties removed
  - SilentlyContinue usage audited (254 occurrences appropriate)
  - Write-Host replaced with proper logging
  - Legacy logStreamReader removed
  - Param block coupling documented
- **Bug Fixes** — v1.8.0
  - Dell chipset driver extraction hang fixed (30s timeout)
  - Corporate proxy SSL inspection detection (Netskope/zScaler)
  - VHDX auto-expansion for large drivers (>5GB)
  - MSU unattend.xml extraction hardened
- **Security Hardening** — v1.8.0
  - Lenovo PSREF token caching with DPAPI encryption
  - SecureString password flow throughout
  - SHA-256 script integrity verification
- **Performance Optimization** — v1.8.0
  - VHD flush reduced 85% via Write-VolumeCache
  - Event-driven Hyper-V VM monitoring with CIM events
- **Test Coverage** — v1.8.0
  - 535+ Pester tests across VM, drivers, imaging, UI, cleanup, VMware
- **Build Management Features** — v1.8.0
  - Graceful build cancellation with cleanup
  - Progress checkpoint/resume capability
  - Configuration file migration between versions
- **Dependency Resilience** — v1.8.0
  - VMware vmxtoolkit fallback via vmrun/filesystem search
  - Lenovo catalogv2.xml fallback for PSREF API
  - WIMMount enhanced failure detection and recovery
- **Windows Update Preview Filtering** — v1.8.1
  - IncludePreviewUpdates config property with false default
  - UI checkbox for opt-in to preview updates
  - Build script filtering appends "-preview" to exclude GA releases
  - Config migration for existing configs (schema v1.0 → v1.1)
- **VHDX Drive Letter Stability** — v1.8.1
  - Set-OSPartitionDriveLetter utility with GPT type detection
  - Provider mount validation with retry and accessibility verification
  - NoteProperty attachment for drive letter persistence

### Active

**Current Milestone:** v1.8.2 VMware UI Settings

**Goal:** Expose VMware network configuration in the UI and migrate existing configs.

**Target features:**
- VMware NetworkType dropdown in UI (bridged/nat/hostonly)
- VMware NicType dropdown in UI (e1000e/vmxnet3/e1000)
- Config migration to add VMwareSettings defaults to existing configs (schema v1.1 → v1.2)

**Deferred bugs (not in scope):**
- HP driver extraction exit code 1168 (all HP models)
- Dell CatalogPC.xml missing
- expand.exe fails on large MSU files (fallback works)

### Out of Scope

- Major architectural rewrites — focus on incremental improvements
- New OEM vendor support — current vendors sufficient
- Mobile/web UI — desktop WPF application only
- Real-time monitoring dashboard — existing log monitoring adequate
- Module decomposition — deferred due to 12-15x import penalty (see docs/MODULE_DECOMPOSITION.md)

## Context

FFU Builder is a mature codebase with 98.8% PowerShell, 13 modules (11 original + FFU.Checkpoint + FFU.ConfigMigration) totaling ~62,000 lines of code. The v1.8.0 milestone completed comprehensive improvements including 535+ new Pester tests, three new features (cancellation, checkpoint/resume, config migration), and dependency resilience patterns.

Key files:
- `BuildFFUVM.ps1` — Core build orchestrator
- `BuildFFUVM_UI.ps1` — WPF UI host
- `Modules/` — 13 specialized modules
- `FFU.Common/` — Shared utilities
- `FFUUI.Core/` — UI framework

## Constraints

- **Backward Compatibility**: Config file changes must support migration
- **PowerShell 5.1+**: Must work in Windows PowerShell and PowerShell 7+
- **No Breaking Changes**: Existing workflows must continue to function
- **Test-Driven**: Changes must include or update relevant tests

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Comprehensive improvement scope | Address all concern categories in single initiative | Shipped |
| YOLO mode workflow | Fast iteration, auto-approve execution | Shipped |
| Module decomposition deferred | 12-15x import performance penalty | Documented |
| CIM events for Hyper-V | Modern standard, PowerShell Core compatible | Shipped |
| Write-VolumeCache for flush | Native cmdlet guarantees completion | ~85% faster |
| DPAPI for token caching | Automatic encryption on Windows | Shipped |
| SHA-256 for script integrity | Industry standard, native PowerShell support | Shipped |
| UI auto-resumes, CLI prompts | Appropriate for each context | Shipped |
| 7-day catalog cache TTL | Reduces network traffic for Lenovo | Shipped |
| Place IncludePreviewUpdates after UpdatePreviewCU | Logical grouping with update settings | ✓ Good |
| Apply -preview exclusion to search query | Microsoft Update Catalog supports negative keywords | ✓ Good |
| UpdatePreviewCU explicit request NOT filtered | User intent should be respected | ✓ Good |
| GPT type for OS partition detection | More reliable than labels which can change | ✓ Good |
| Default preferred drive letter to W | Consistent with New-OSPartition | ✓ Good |
| NoteProperty for drive letter attachment | Maintains backward compatibility | ✓ Good |
| Retry with exponential backoff for mounts | Handles transient disk operation failures | ✓ Good |

---
*Last updated: 2026-01-20 after v1.8.2 milestone started*
