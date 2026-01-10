# Version History Archive

This file contains archived version history for FFU Builder. For the most recent versions, see [CLAUDE.md](../CLAUDE.md).

> **Note:** Only versions prior to the 10 most recent are archived here. See `version.json` for authoritative version data.

---

## Archived Versions

| Version | Date | Type | Description |
|---------|------|------|-------------|
| 1.3.6 | 2025-12-12 | PATCH | **SUPERSEDED by v1.3.8** - WimMount warning fix was incorrect; native DISM cmdlets DO require WIMMount service |
| 1.3.5 | 2025-12-11 | PATCH | Native DISM fix - Replace ADK dism.exe with PowerShell cmdlets (Mount-WindowsImage/Dismount-WindowsImage) in ApplyFFU.ps1 to avoid WIMMount filter driver errors |
| 1.3.4 | 2025-12-11 | PATCH | Defense-in-depth fix for log monitoring - Restore messaging context after FFU.Common -Force import |
| 1.3.3 | 2025-12-11 | PATCH | UI Monitor tab fix - Integrate WriteLog with messaging queue for real-time UI updates |
| 1.3.2 | 2025-12-11 | PATCH | DISM WIM mount error 0x800704DB pre-flight validation with Test-FFUWimMount remediation |
| 1.3.1 | 2025-12-11 | PATCH | Config schema validation fix - Added AdditionalFFUFiles property and 7 deprecated properties (AppsPath, CopyOfficeConfigXML, DownloadDrivers, InstallWingetApps, OfficePath, Threads, Verbose) with backward compatibility warnings |
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
