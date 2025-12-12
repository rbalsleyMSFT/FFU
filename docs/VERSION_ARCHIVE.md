# Version History Archive

This file contains archived version history for FFU Builder. For the most recent versions, see [CLAUDE.md](../CLAUDE.md).

> **Note:** Only versions prior to the 10 most recent are archived here. See `version.json` for authoritative version data.

---

## Archived Versions

| Version | Date | Type | Description |
|---------|------|------|-------------|
| 1.2.7 | 2025-12-10 | PATCH | Module loading failure fix - Early PSModulePath setup and defensive error handlers |
| 1.2.0 | 2025-12-09 | MINOR | Centralized versioning with version.json, module version display in About dialog |
| 1.1.0 | 2025-12-08 | MINOR | Parallel Windows Update downloads - concurrent KB downloads with PS7/PS5.1 support and multi-method fallback |
| 1.0.5 | 2025-12-04 | PATCH | Secure credential management - cryptographic password generation, SecureString handling |
| 1.0.4 | 2025-12-03 | PATCH | Add comprehensive parameter validation to BuildFFUVM.ps1 (15 parameters) |
| 1.0.3 | 2025-12-03 | PATCH | Fix FFU.VM module export - Add missing functions to Export-ModuleMember |
| 1.0.2 | 2025-12-03 | PATCH | Enhanced fix for 0x80070228 - Direct CAB application bypasses UUP download requirement |
| 1.0.1 | 2025-12-03 | PATCH | Fix DISM error 0x80070228 for Windows 11 24H2/25H2 checkpoint cumulative updates |
| 1.0.0 | 2025-12-03 | MAJOR | Initial modularized release with 8 modules, UI version display, credential security |

---

## Version Migration Guide

When a new version is released:
1. If the Version History table in CLAUDE.md exceeds 10 entries
2. Move the oldest entries to this archive file
3. Maintain the table header format for consistency
4. Keep entries in chronological order (newest at top in CLAUDE.md, oldest at top here)
