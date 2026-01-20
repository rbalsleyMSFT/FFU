# Project Milestones: FFU Builder

## v1.8.1 Bug Fixes (Shipped: 2026-01-20)

**Delivered:** Critical bug fixes for Windows Update preview filtering and VHDX drive letter stability discovered during v1.8.0 testing.

**Phases completed:** 11-13 (5 plans total)

**Key accomplishments:**

- Added Windows Update preview filtering with config schema, UI checkbox, and build script exclusion logic (GA releases only by default)
- Implemented config migration to add `IncludePreviewUpdates=false` default for existing configs (schema v1.0 → v1.1)
- Created `Set-OSPartitionDriveLetter` utility function with GPT type detection and retry logic for guaranteed drive letter assignment
- Enhanced Hyper-V and VMware providers with mount validation, accessibility verification, and NoteProperty drive letter attachment
- Fixed UI default initialization gap ensuring fresh launches initialize `IncludePreviewUpdates` checkbox correctly

**Stats:**

- 31 files created/modified
- 62,055 lines of PowerShell
- 3 phases, 5 plans, 7 requirements
- 1 day (2026-01-20)

**Git range:** `065910e` → `bd7c593`

**What's next:** Define requirements for next improvement cycle

---

## v1.8.0 Codebase Health (Shipped: 2026-01-20)

**Delivered:** Comprehensive codebase improvement addressing tech debt, critical bugs, security hardening, performance optimization, test coverage, and three new features for build management.

**Phases completed:** 1-10 (33 plans total)

**Key accomplishments:**

- Removed deprecated FFU.Constants properties and cleaned up Write-Host usage across modules
- Fixed Dell driver extraction hang, corporate proxy SSL inspection detection, and VHDX auto-expansion for large drivers
- Added Lenovo PSREF token caching with DPAPI encryption, SecureString password flow, and SHA-256 script integrity verification
- Optimized VHD flush by 85% using Write-VolumeCache and added event-driven Hyper-V VM monitoring
- Created 535+ Pester tests covering VM, drivers, imaging, UI handlers, cleanup, VMware, cancellation, checkpoint, and migration
- Implemented graceful build cancellation with cleanup, progress checkpoint/resume, and configuration file migration

**Stats:**

- 153 files created/modified
- 61,795 lines of PowerShell
- 10 phases, 33 plans, 26 requirements
- 4 days from 2026-01-17 to 2026-01-20

**Git range:** `0f105e1` → `a64f07c`

**What's next:** Define requirements for next improvement cycle

---
