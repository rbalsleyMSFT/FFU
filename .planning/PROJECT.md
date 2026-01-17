# FFU Builder - Codebase Improvement Initiative

## What This Is

A comprehensive improvement initiative for FFU Builder, a PowerShell-based Windows deployment tool that creates pre-configured Windows 11 images (FFU format) deployable in under 2 minutes. This initiative addresses tech debt, known bugs, test coverage gaps, and missing features identified during codebase analysis.

## Core Value

Improve codebase quality, reliability, and maintainability while ensuring FFU Builder remains a robust tool for rapid Windows deployment.

## Requirements

### Validated

- ✓ Modular architecture with 11 PowerShell modules — existing
- ✓ WPF-based UI with background job execution — existing
- ✓ Hyper-V and VMware Workstation Pro support — existing
- ✓ OEM driver integration (Dell, HP, Lenovo, Microsoft) — existing
- ✓ Pre-flight validation system with tiered checks — existing
- ✓ Thread-safe UI/job messaging via FFU.Messaging — existing

### Active

#### Tech Debt Cleanup
- [ ] Remove deprecated static path properties from FFU.Constants
- [ ] Audit and reduce -ErrorAction SilentlyContinue usage (336 occurrences)
- [ ] Replace Write-Host with proper output streams (50+ occurrences)
- [ ] Remove legacy logStreamReader from UI
- [ ] Document BuildFFUVM.ps1 param block coupling with FFU.Constants

#### Bug Fixes
- [ ] Fix Issue #327: Corporate proxy failures with Netskope/zScaler
- [ ] Fix Issue #301: Unattend.xml extraction from MSU packages
- [ ] Fix Issue #298: OS partition size limitations with large drivers
- [ ] Address Dell chipset driver extraction hang

#### Test Coverage
- [ ] Add integration tests for VM creation operations
- [ ] Add integration tests for driver injection
- [ ] Add integration tests for FFU capture
- [ ] Add tests for UI event handlers (FFUUI.Core.Handlers.psm1)
- [ ] Add tests for error recovery paths and cleanup handlers
- [ ] Add tests for VMware provider operations

#### Missing Features
- [ ] Implement graceful build cancellation
- [ ] Implement build progress checkpoint/resume
- [ ] Implement configuration file migration between versions

### Out of Scope

- Major architectural rewrites — focus on incremental improvements
- New OEM vendor support — current vendors sufficient
- Mobile/web UI — desktop WPF application only
- Real-time monitoring dashboard — existing log monitoring adequate

## Context

FFU Builder is a mature codebase with 98.8% PowerShell, 11 modules totaling ~15,000 lines of code. The codebase has evolved organically and accumulated tech debt that impacts maintainability and debugging. Known bugs affect users in corporate environments. Test coverage exists for unit tests but lacks integration tests for core operations.

Key files:
- `BuildFFUVM.ps1` — Core build orchestrator (4,677 lines)
- `BuildFFUVM_UI.ps1` — WPF UI host
- `Modules/` — 11 specialized modules
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
| Comprehensive improvement scope | Address all concern categories in single initiative | — Pending |
| YOLO mode workflow | Fast iteration, auto-approve execution | — Pending |

---
*Last updated: 2026-01-17 after initialization*
