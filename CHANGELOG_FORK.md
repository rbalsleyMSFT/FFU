# FFU Builder Fork - Changelog

**Fork Branch:** `feature/improvements-and-fixes`
**Upstream Repository:** https://github.com/rbalsleyMSFT/FFU/tree/UI_2510
**Versioning:** [Semantic Versioning](https://semver.org/) (MAJOR.MINOR.BUILD)

This changelog documents all enhancements and fixes made in this fork, separate from the upstream FFU project.

---

## [1.0.4] - 2025-12-03

### Enhancements
- **Comprehensive Parameter Validation** (BUILD)
  - **Issue:** BuildFFUVM.ps1 had minimal parameter validation, causing late failures with cryptic errors
  - **Solution:** Added validation attributes to 15+ parameters
  - **Validation Types Added:**
    - ValidateScript: Path existence for file/folder parameters
    - ValidatePattern: Regex for ShareName, Username, WindowsVersion
    - ValidateRange: MaxUSBDrives (0-100)
    - ValidateNotNullOrEmpty: FFUPrefix, ShareName, Username, WindowsVersion
    - Array validation: AdditionalFFUFiles (each file validated)
  - Files: `BuildFFUVM.ps1`
  - Test: `Tests/Test-ParameterValidation.ps1` (37 tests)
  - **Full Documentation:** [PARAMETER_VALIDATION_FIX.md](docs/fixes/PARAMETER_VALIDATION_FIX.md)

---

## [1.0.3] - 2025-12-03

### Bug Fixes
- **FFU.VM Module Export Fix** (BUILD)
  - **Root Cause:** Functions defined in .psm1 and listed in .psd1 FunctionsToExport, but NOT included in Export-ModuleMember statement
  - **Symptom:** "Remove-SensitiveCaptureMedia is not recognized as the name of a cmdlet"
  - **Solution:** Added Set-LocalUserAccountExpiry and Remove-SensitiveCaptureMedia to Export-ModuleMember
  - Files: `Modules/FFU.VM/FFU.VM.psm1`
  - Test: `Tests/Test-ModuleExportFix.ps1` (13 tests)
  - **Full Documentation:** [MODULE_EXPORT_FIX.md](docs/fixes/MODULE_EXPORT_FIX.md)

---

## [1.0.2] - 2025-12-03

### Bug Fixes
- **DISM Error 0x80070228 - Enhanced Fix with Direct CAB Application** (BUILD)
  - **Root Cause:** UUP packages trigger Windows Update Agent to download content, fails on offline images
  - **Solution:** Extract CAB files from MSU and apply directly - bypasses UpdateAgent
  - Files: `FFU.Updates.psm1`
  - Test: `Tests/Test-CheckpointUpdateFix.ps1` (12 tests)
  - **Full Documentation:** [CHECKPOINT_UPDATE_0x80070228_FIX.md](docs/fixes/CHECKPOINT_UPDATE_0x80070228_FIX.md)
  - Reference: https://learn.microsoft.com/en-us/answers/questions/3855149/

---

## [1.0.1] - 2025-12-03 (Superseded by 1.0.2)

### Bug Fixes
- **DISM Error 0x80070228 - Initial Fix Attempt** (BUILD)
  - Initial fix using isolated MSU directory approach
  - Prevented multi-MSU conflicts but didn't fully address UUP download issue
  - Superseded by 1.0.2 which uses direct CAB application

---

## [1.0.0] - 2025-12-03

### Major Features

#### Modular Architecture (2025-11-20)
Complete refactoring of monolithic `BuildFFUVM.ps1` into 9 specialized modules:

| Module | Functions | Purpose |
|--------|-----------|---------|
| FFU.Core | 18 | Core functionality, configuration, session tracking |
| FFU.Constants | - | Centralized configuration values |
| FFU.ADK | 8 | Windows ADK management and validation |
| FFU.Apps | 5 | Application management, Office deployment |
| FFU.Drivers | 5 | OEM driver management (Dell, HP, Lenovo, Microsoft) |
| FFU.Imaging | 15 | DISM operations, partitioning, FFU creation |
| FFU.Media | 4 | WinPE media creation |
| FFU.Updates | 8 | Windows Update handling, KB downloads |
| FFU.VM | 10 | Hyper-V VM lifecycle management |

**Metrics:**
- Original: 7,790 lines
- After: 2,404 lines (69% reduction)
- Functions extracted: 64
- 100% backward compatible

**Documentation:** `docs/summaries/MODULARIZATION_PHASE2-4_SUMMARY.md`

#### UI Version Display (2025-12-03)
- Added version display in window title bar
- Added About tab with version, build date, and project info
- Files: `BuildFFUVM_UI.ps1`, `BuildFFUVM_UI.xaml`, `FFUUI.Core.Initialize.psm1`
- Design: `docs/designs/UI-VERSION-DISPLAY-DESIGN.md`

#### Credential Security Improvements (2025-12-03)
- Added 4-hour account expiry failsafe for temporary FFU user
- Added SecureString disposal after credential use
- Added sensitive media cleanup function
- Added comprehensive security documentation to CaptureFFU.ps1
- Files: `FFU.VM.psm1`, `BuildFFUVM.ps1`, `CaptureFFU.ps1`
- Test: `Tests/Test-CredentialSecurity.ps1`

---

### Bug Fixes (November 2025)

#### Critical Fixes

| Fix | Date | Description | Documentation |
|-----|------|-------------|---------------|
| PowerShell TelemetryAPI Error | 2025-11-24 | Fixed PS7 "Could not load type TelemetryAPI" with .NET DirectoryServices | [POWERSHELL_CROSSVERSION_FIX.md](docs/fixes/POWERSHELL_CROSSVERSION_FIX.md) |
| Empty ShortenedWindowsSKU | 2025-11-24 | Fixed "Cannot bind argument" error with graceful fallback | [SHORTENED_SKU_INITIALIZATION_FIX_SUMMARY.md](docs/fixes/SHORTENED_SKU_INITIALIZATION_FIX_SUMMARY.md) |
| Set-CaptureFFU Missing | 2025-11-23 | Implemented missing function for WinPE capture | [SET_CAPTUREFFU_FIX_SUMMARY.md](docs/fixes/SET_CAPTUREFFU_FIX_SUMMARY.md) |
| MSU Extraction Error | 2025-11-23 | Fixed expand.exe failures with enhanced error handling | [MSU_PACKAGE_FIX_SUMMARY.md](docs/fixes/MSU_PACKAGE_FIX_SUMMARY.md) |
| Filter Parameter Null | 2025-11-22 | Fixed null error in FFU.Updates module | [FILTER_PARAMETER_FIX_SUMMARY.md](docs/fixes/FILTER_PARAMETER_FIX_SUMMARY.md) |
| copype WIM Mount Failures | 2025-11-17 | Added DISM cleanup and retry logic | [COPYPE_WIM_MOUNT_FIX.md](docs/fixes/COPYPE_WIM_MOUNT_FIX.md) |
| WinPE boot.wim Creation | 2025-11-07 | Added ADK pre-flight validation | [WINPE_BOOTWIM_CREATION_FIX.md](docs/fixes/WINPE_BOOTWIM_CREATION_FIX.md) |

#### High Priority Fixes

| Fix | Date | Description | Documentation |
|-----|------|-------------|---------------|
| Log Monitoring Failure | 2025-11-24 | Fixed UI log path null with defense-in-depth | [LOG_MONITORING_FIX_SUMMARY.md](docs/fixes/LOG_MONITORING_FIX_SUMMARY.md) |
| WriteLog Empty String | 2025-11-24 | Fixed parameter binding errors | [WRITELOG_PATH_VALIDATION_FIX.md](docs/fixes/WRITELOG_PATH_VALIDATION_FIX.md) |
| FFU Constants Module | 2025-11-24 | Centralized configuration (Quick Win #4) | [FFUCONSTANTS_FIX_SUMMARY.md](docs/fixes/FFUCONSTANTS_FIX_SUMMARY.md) |
| cmd.exe Path Quoting | 2025-11-24 | Fixed 'C:\Program' not recognized errors | [CMD_PATH_QUOTING_FIX.md](docs/fixes/CMD_PATH_QUOTING_FIX.md) |
| FFU Optimization Error 1167 | 2025-11-24 | Fixed "Device Not Connected" with scratch dir | [FFU_OPTIMIZATION_ERROR_1167_FIX.md](docs/fixes/FFU_OPTIMIZATION_ERROR_1167_FIX.md) |
| Expand-WindowsImage 0x8007048F | 2025-11-24 | Fixed VHDX creation failures with retry | [EXPAND_WINDOWSIMAGE_FIX.md](docs/fixes/EXPAND_WINDOWSIMAGE_FIX.md) |
| Get-Office Null Path | 2025-11-21 | Added required parameters | [DEFENDER_ORCHESTRATION_FIX_SUMMARY.md](docs/fixes/DEFENDER_ORCHESTRATION_FIX_SUMMARY.md) |
| New-AppsISO Null Path | 2025-11-21 | Added required parameters | [DEFENDER_ORCHESTRATION_FIX_SUMMARY.md](docs/fixes/DEFENDER_ORCHESTRATION_FIX_SUMMARY.md) |

---

### Bug Fixes (October 2025)

#### BITS and Download Fixes

| Fix | Date | Description | Documentation |
|-----|------|-------------|---------------|
| BITS Authentication 0x800704DD | 2025-10-24 | Fixed in background jobs | `ISSUE_BITS_AUTHENTICATION.md` |
| Multi-Method Download Fallback | 2025-10-24 | Added fallback system for BITS failures | `FALLBACK_SYSTEM_SUMMARY.md` |
| ESD Download Timeout | 2025-10-26 | Fixed timeout and WinPE mount failures | `ESD_DOWNLOAD_FIX.md` |
| Boolean Coercion Bug | 2025-10-24 | Fixed in Save-KB and Lenovo driver download | `CRITICAL_BUG_FIX_EDGE.md` |

#### DISM and Imaging Fixes

| Fix | Date | Description | Documentation |
|-----|------|-------------|---------------|
| DISM Service Timing | 2025-10-30 | Enhanced initialization timing | `DISM_SERVICE_TIMING_ENHANCEMENT.md` |
| DISM Service Dependency | 2025-10-29 | Fixed service dependency error | `DISM_SERVICE_FIX.md` |
| MSU Unattend.xml Extraction | 2025-10-29 | Fixed Issue #301 | `MSU_UNATTEND_FIX.md` |
| WinPE Mount Failures | 2025-10-26 | Fixed mount failures | `WINPE_MOUNT_FIX.md` |

---

### Enhancements

#### Architecture Improvements
- **Foundational Classes** (2025-10-24): Added FFUConfiguration, FFUConstants, FFULogger, FFUNetworkConfiguration, FFUPaths, FFUPreflightValidator
- **Proxy Support** (2025-10-24): Comprehensive proxy detection and configuration
- **Error Handling Standardization**: Consistent patterns across all modules
- **Cross-Version Compatibility**: Works in both PS5.1 and PS7+

#### Documentation
- 25+ detailed fix summaries in `docs/fixes/`
- 6 analysis documents in `docs/analysis/`
- 3 implementation plans in `docs/plans/`
- Executive summary: `docs/summaries/EXECUTIVE_SUMMARY_WEEK_2025-11-20.md`
- Architecture evaluation: `docs/summaries/ARCHITECTURE_ISSUES_PRIORITIZED.md`

#### Testing
- 38+ test scripts created
- 200+ individual test cases
- 100% pass rate maintained
- Categories: Unit, Integration, Syntax Validation, UI Integration

---

## Pre-Fork Changes (Upstream)

The following are notable changes from the upstream repository before this fork:

### 2509.1 UI Preview (September-October 2025)
- Windows 11 25H2 mapping
- JSON output standardization
- Multi-FFU USB build support
- Exit-code overrides for Winget apps
- Restore defaults feature
- Dynamic PE drivers option
- Auto-loading previous configuration

### 2507.1 UI Preview (July 2025)
- Complete UI overhaul
- Winget app support
- ARM64 support
- Configuration file support
- VHDX caching support
- Custom FFU naming

See `ChangeLog.md` for complete upstream history.

---

## Quick Reference

### Files Modified (This Fork)

**Core Scripts:**
- `BuildFFUVM.ps1` - Main orchestrator (reduced from 7,790 to 2,404 lines)
- `BuildFFUVM_UI.ps1` - WPF UI host (version display added)
- `BuildFFUVM_UI.xaml` - UI definition (About tab added)
- `Create-PEMedia.ps1` - WinPE media creator
- `USBImagingToolCreator.ps1` - USB tool generator
- `CaptureFFU.ps1` - FFU capture script (security documentation)
- `ApplyFFU.ps1` - FFU deployment script

**New Modules:**
- `Modules/FFU.Core/` - Core functionality
- `Modules/FFU.Constants/` - Configuration constants
- `Modules/FFU.ADK/` - ADK management
- `Modules/FFU.Apps/` - Application management
- `Modules/FFU.Drivers/` - Driver management
- `Modules/FFU.Imaging/` - Imaging operations
- `Modules/FFU.Media/` - Media creation
- `Modules/FFU.Updates/` - Update handling
- `Modules/FFU.VM/` - VM lifecycle

**Common Modules:**
- `FFU.Common/FFU.Common.Core.psm1`
- `FFU.Common/FFU.Common.Winget.psm1`
- `FFUUI.Core/FFUUI.Core.*.psm1`

### Test Coverage

| Category | Test Files | Pass Rate |
|----------|------------|-----------|
| Module Integration | 8 | 100% |
| UI Integration | 3 | 100% |
| Syntax Validation | 5 | 100% |
| Unit Tests | 15+ | 100% |
| Fix Verification | 7+ | 100% |

### Known Remaining Issues

See `docs/summaries/ARCHITECTURE_ISSUES_PRIORITIZED.md` for:
- 4 Medium priority issues for future improvement
- Recommended enhancements

---

## Contributing

When making changes to this fork:

1. **Determine version increment:**
   - MAJOR (X.0.0): Breaking changes
   - MINOR (0.X.0): New features
   - BUILD (0.0.X): Bug fixes

2. **Update version:**
   - Edit `$script:FFUBuilderVersion` in `BuildFFUVM_UI.ps1`
   - Update "Current Version" in `CLAUDE.md`

3. **Document the change:**
   - Add entry to this changelog
   - Update Version History table in `CLAUDE.md`
   - Create detailed summary in `docs/fixes/` if applicable

4. **Create tests:**
   - Add test script in `Tests/`
   - Verify 100% pass rate

---

*Last Updated: 2025-12-03*
