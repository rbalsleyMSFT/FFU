# Technology Stack

**Analysis Date:** 2026-01-16

## Languages

**Primary:**
- PowerShell 7.0+ - Core build logic, module system, UI host (`FFUDevelopment/BuildFFUVM.ps1`, `FFUDevelopment/Modules/`)

**Secondary:**
- XAML - WPF UI layout (`FFUDevelopment/BuildFFUVM_UI.xaml`)
- JSON - Configuration, app lists, version management (`FFUDevelopment/config/*.json`, `FFUDevelopment/version.json`)
- XML - Office deployment configs, unattend.xml, driver catalogs (`FFUDevelopment/unattend/*.xml`)

## Runtime

**Environment:**
- Windows PowerShell 7.0+ (required, declared via `#Requires -Version 7.0`)
- Windows 10/11 (required for Hyper-V, DISM, WinPE)

**Package Manager:**
- None - No npm/pip/nuget package managers used
- PowerShell modules loaded from local `FFUDevelopment/Modules/` folder
- Lockfile: Not applicable

## Frameworks

**Core:**
- Windows Presentation Foundation (WPF) - UI framework, loaded via `PresentationCore`, `PresentationFramework` assemblies
- .NET Framework/.NET Core - Underlying runtime for PowerShell 7.0+

**Testing:**
- Pester 5.x - PowerShell unit testing (`Tests/Unit/*.Tests.ps1`)
- PSScriptAnalyzer - Static code analysis and linting

**Build/Dev:**
- Windows ADK with Deployment Tools - WinPE creation, DISM operations (`FFUDevelopment/Modules/FFU.ADK/`)
- DISM (Deployment Image Servicing and Management) - Image manipulation
- oscdimg.exe - ISO creation for WinPE media

## Key Dependencies

**Critical (Windows Features):**
- Hyper-V - Required Windows optional feature for VM-based builds
- WIMMount - Filter driver for WIM image mounting
- BITS (Background Intelligent Transfer Service) - Primary download method

**Infrastructure:**
- VMware Workstation Pro 17.x - Alternative hypervisor (optional, via `FFU.Hypervisor`)
- Windows ADK + WinPE add-on - Deployment toolkit (auto-installed by script)

**External Tools:**
- expand.exe - Cabinet extraction (Windows built-in)
- diskpart.exe - Disk partitioning operations
- vmrun.exe / vmware-vmx.exe - VMware VM control (when using VMware hypervisor)
- curl.exe - Fallback download method (Windows 10 1803+ built-in)

## Module Architecture

**Core Modules (16 total):**

| Module | Version | Purpose | Location |
|--------|---------|---------|----------|
| FFU.Constants | 1.1.0 | Centralized configuration constants | `Modules/FFU.Constants/` |
| FFU.Core | 1.0.13 | Config, logging, error handling, credentials | `Modules/FFU.Core/` |
| FFU.Hypervisor | 1.2.9 | Hyper-V/VMware abstraction layer | `Modules/FFU.Hypervisor/` |
| FFU.VM | 1.0.6 | VM lifecycle management | `Modules/FFU.VM/` |
| FFU.ADK | 1.0.0 | Windows ADK validation/installation | `Modules/FFU.ADK/` |
| FFU.Media | 1.3.2 | WinPE media creation | `Modules/FFU.Media/` |
| FFU.Imaging | 1.0.9 | DISM operations, FFU capture | `Modules/FFU.Imaging/` |
| FFU.Updates | 1.0.2 | Windows Update catalog, MSU handling | `Modules/FFU.Updates/` |
| FFU.Drivers | 1.0.5 | OEM driver management | `Modules/FFU.Drivers/` |
| FFU.Apps | 1.0.0 | Application management | `Modules/FFU.Apps/` |
| FFU.Messaging | 1.0.0 | Thread-safe UI/job communication | `Modules/FFU.Messaging/` |
| FFU.Preflight | 1.0.9 | Pre-flight validation system | `Modules/FFU.Preflight/` |
| FFU.BuildTest | 1.1.0 | Build testing utilities | `Modules/FFU.BuildTest/` |
| FFU.Common | 0.0.7 | Shared utilities (logging, downloads) | `FFU.Common/` |
| FFU.Common.Logging | 1.0.0 | Structured logging | `FFU.Common/FFU.Common.Logging.psd1` |
| FFUUI.Core | 0.0.11 | WPF UI framework | `FFUUI.Core/` |

**Module Dependencies:**
```
FFU.Constants (v1.1.0) - Foundation, no dependencies
    -> FFU.Core (v1.0.13)
        -> FFU.ADK, FFU.Apps, FFU.Drivers, FFU.Imaging, FFU.Updates, FFU.VM
            -> FFU.Media (requires FFU.Core + FFU.ADK)
                -> FFU.Hypervisor (requires FFU.Core)
```

## Configuration

**Environment:**
- No `.env` files - Configuration via JSON files and script parameters
- Key configs: `FFUDevelopment/config/*.json`
- Schema validation: `FFUDevelopment/config/ffubuilder-config.schema.json`

**Build:**
- Entry point: `FFUDevelopment/BuildFFUVM.ps1` (core orchestrator)
- UI launcher: `FFUDevelopment/BuildFFUVM_UI.ps1`
- Module path: Dynamically added to `$env:PSModulePath` at runtime

**Configuration Schema:**
```json
{
  "HypervisorType": "HyperV|VMware|Auto",
  "WindowsRelease": 10|11|2016|2019|2022|2024|2025,
  "WindowsSKU": "Pro|Enterprise|Education|...",
  "WindowsArch": "x64|arm64|x86",
  "Memory": <bytes>,
  "Disksize": <bytes>,
  "VMSwitchName": "<string>",
  "InstallApps": true|false,
  "InstallOffice": true|false,
  "InstallDrivers": true|false,
  ...
}
```

## Platform Requirements

**Development:**
- Windows 10/11 (x64) with Administrator privileges
- PowerShell 7.0+ installed
- Hyper-V enabled OR VMware Workstation Pro 17.x
- 50GB+ free disk space recommended
- Windows ADK (auto-installed if missing)

**Production:**
- Same as development (builds run locally)
- Target deployment: Physical Windows devices via USB/FFU imaging

## Version Management

**Single Source of Truth:** `FFUDevelopment/version.json`

```json
{
  "version": "1.7.19",
  "buildDate": "2026-01-16",
  "versioningPolicy": {
    "scheme": "SemVer",
    "majorBump": "Breaking changes OR major milestones",
    "minorBump": "New features OR significant improvements",
    "patchBump": "Bug fixes OR module version changes"
  },
  "modules": { ... }
}
```

**Version Bump Rule:** Any module version change triggers main version PATCH bump.

---

*Stack analysis: 2026-01-16*
