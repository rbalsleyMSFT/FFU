# Codebase Structure

**Analysis Date:** 2026-01-16

## Directory Layout

```
FFUBuilder/
├── .claude/                    # Claude Code agent configurations
│   ├── agents/                 # Specialized agent definitions
│   ├── commands/               # Custom slash commands
│   └── skills/                 # PowerShell best practices
├── .planning/                  # GSD planning documents
│   └── codebase/               # Codebase analysis (this document)
├── docs/                       # Documentation
│   ├── analysis/               # Code analysis documents
│   ├── designs/                # Design documents
│   ├── fixes/                  # Issue fix summaries
│   ├── guides/                 # User guides
│   ├── pending/                # Pending documentation
│   ├── plans/                  # Implementation plans
│   ├── research/               # Research notes
│   └── summaries/              # Summary documents
├── FFUDevelopment/             # Main application code
│   ├── Apps/                   # Application deployment
│   │   ├── Office/             # Microsoft Office deployment files
│   │   └── Orchestration/      # VM-side orchestration scripts
│   ├── Autopilot/              # Autopilot configuration files
│   ├── BuildFFUUnattend/       # Unattend.xml templates
│   ├── config/                 # Configuration files and schema
│   │   └── test/               # Test configuration files
│   ├── Diagnostics/            # Diagnostic utilities
│   ├── Docs/                   # Legacy documentation
│   │   └── Archive/            # Archived docs
│   ├── Drivers/                # Downloaded OEM drivers (runtime)
│   ├── FFU/                    # Output FFU files (runtime)
│   ├── FFU.Common/             # Shared business logic module
│   ├── FFUUI.Core/             # WPF UI framework module
│   ├── Modules/                # PowerShell modules (15 total)
│   │   ├── FFU.ADK/            # Windows ADK management
│   │   ├── FFU.Apps/           # Application management
│   │   ├── FFU.BuildTest/      # Build testing utilities
│   │   ├── FFU.Constants/      # Centralized constants
│   │   ├── FFU.Core/           # Core utilities
│   │   ├── FFU.Drivers/        # OEM driver management
│   │   ├── FFU.Hypervisor/     # Hypervisor abstraction
│   │   │   ├── Classes/        # Interface and data classes
│   │   │   ├── Private/        # Internal helper functions
│   │   │   ├── Providers/      # Hypervisor implementations
│   │   │   └── Public/         # Exported public functions
│   │   ├── FFU.Imaging/        # DISM and FFU operations
│   │   ├── FFU.Media/          # WinPE media creation
│   │   ├── FFU.Messaging/      # Thread-safe UI messaging
│   │   │   └── Examples/       # Usage examples
│   │   ├── FFU.Preflight/      # Pre-flight validation
│   │   ├── FFU.Updates/        # Windows Update handling
│   │   └── FFU.VM/             # VM lifecycle management
│   ├── PEDrivers/              # WinPE drivers (user-provided)
│   ├── PPKG/                   # Provisioning packages
│   ├── Tests/                  # Legacy tests (FFUDevelopment)
│   ├── unattend/               # Unattend.xml files
│   ├── VM/                     # VM files (runtime)
│   ├── WinPECaptureFFUFiles/   # WinPE capture scripts
│   │   └── Windows/System32/   # WinPE startnet.cmd
│   └── WinPEDeployFFUFiles/    # WinPE deploy scripts
│       └── Windows/System32/   # WinPE startnet.cmd
├── image/                      # Project images
│   └── ChangeLog/              # Changelog images
└── Tests/                      # Main test suite
    ├── Coverage/               # Code coverage reports
    ├── Diagnostics/            # Diagnostic tests
    ├── Fixes/                  # Fix validation tests
    ├── Integration/            # Integration tests
    ├── Modules/                # Module-specific tests
    ├── Results/                # Test result outputs
    └── Unit/                   # Unit tests (Pester)
```

## Directory Purposes

**FFUDevelopment/Modules/:**
- Purpose: PowerShell modules providing domain-specific functionality
- Contains: 15 modules with .psd1 manifests and .psm1 implementations
- Key files:
  - `FFU.Core/FFU.Core.psm1` - Configuration, error handling, cleanup
  - `FFU.Hypervisor/FFU.Hypervisor.psm1` - Multi-platform VM abstraction
  - `FFU.Imaging/FFU.Imaging.psm1` - DISM operations, FFU capture
  - `FFU.Preflight/FFU.Preflight.psm1` - Build environment validation

**FFUDevelopment/FFU.Common/:**
- Purpose: Shared utilities used by both UI and build script
- Contains: Logging, downloads, parallel execution, class definitions
- Key files:
  - `FFU.Common.Core.psm1` - WriteLog, Invoke-Process, BITS transfers
  - `FFU.Common.Download.psm1` - Resilient download with fallbacks
  - `FFU.Common.ParallelDownload.psm1` - Concurrent download manager

**FFUDevelopment/FFUUI.Core/:**
- Purpose: WPF UI framework separated by concern
- Contains: 13 sub-modules for UI logic
- Key files:
  - `FFUUI.Core.psm1` - Core UI helpers, data retrieval
  - `FFUUI.Core.Initialize.psm1` - Control initialization
  - `FFUUI.Core.Handlers.psm1` - Event handler registration
  - `FFUUI.Core.Config.psm1` - Configuration save/load
  - `FFUUI.Core.Drivers.Dell.psm1` - Dell driver UI logic

**FFUDevelopment/Apps/Orchestration/:**
- Purpose: Scripts that run inside build VM for customization
- Contains: Installation and cleanup scripts
- Key files:
  - `Orchestrator.ps1` - Main VM orchestration entry point
  - `Install-Win32Apps.ps1` - WinGet app installation
  - `Run-Sysprep.ps1` - System preparation
  - `Run-DiskCleanup.ps1` - Pre-capture cleanup

**FFUDevelopment/WinPECaptureFFUFiles/:**
- Purpose: WinPE scripts for FFU capture phase
- Contains: Capture script and boot configuration
- Key files:
  - `CaptureFFU.ps1` - Captures disk to FFU, uploads to share
  - `Windows/System32/startnet.cmd` - WinPE boot script

**Tests/Unit/:**
- Purpose: Pester unit tests for all modules
- Contains: Module-specific test files
- Key files:
  - `Invoke-PesterTests.ps1` - Test runner with coverage
  - `FFU.Core.Tests.ps1` - FFU.Core module tests
  - `FFU.Hypervisor.Tests.ps1` - Hypervisor provider tests

## Key File Locations

**Entry Points:**
- `FFUDevelopment/BuildFFUVM_UI.ps1`: WPF UI launcher (primary user interface)
- `FFUDevelopment/BuildFFUVM.ps1`: Core build orchestrator (CLI or background job)
- `FFUDevelopment/Create-PEMedia.ps1`: Standalone WinPE media creator
- `FFUDevelopment/USBImagingToolCreator.ps1`: USB deployment tool generator

**Configuration:**
- `FFUDevelopment/version.json`: Single source of truth for versioning
- `FFUDevelopment/config/ffubuilder-config.schema.json`: JSON schema for config validation
- `FFUDevelopment/config/test/test-minimal.json`: Minimal test configuration
- `FFUDevelopment/config/test/test-standard.json`: Standard test configuration

**Core Logic:**
- `FFUDevelopment/Modules/FFU.Core/FFU.Core.psm1`: Error handling, cleanup, credentials
- `FFUDevelopment/Modules/FFU.Hypervisor/FFU.Hypervisor.psm1`: VM provider abstraction
- `FFUDevelopment/Modules/FFU.Imaging/FFU.Imaging.psm1`: DISM, partitioning, FFU capture
- `FFUDevelopment/Modules/FFU.Preflight/FFU.Preflight.psm1`: Environment validation

**Testing:**
- `Tests/Unit/Invoke-PesterTests.ps1`: Main test runner
- `Tests/Unit/*.Tests.ps1`: Module unit tests
- `Tests/Integration/*.ps1`: Integration test scripts

## Naming Conventions

**Files:**
- PowerShell scripts: `Verb-Noun.ps1` (e.g., `Invoke-PesterTests.ps1`)
- PowerShell modules: `ModuleName.psm1` with matching `ModuleName.psd1`
- Test files: `ModuleName.Tests.ps1` (Pester convention)
- Configuration: `kebab-case.json` (e.g., `ffubuilder-config.schema.json`)
- XAML: `PascalCase.xaml` (e.g., `BuildFFUVM_UI.xaml`)

**Directories:**
- Module directories: Match module name (`FFU.Core/`)
- Sub-module directories: PascalCase (`Classes/`, `Providers/`, `Private/`, `Public/`)
- Runtime directories: PascalCase (`Drivers/`, `FFU/`, `VM/`)
- Documentation: lowercase (`docs/`, `analysis/`, `fixes/`)

**Functions:**
- Exported: `Verb-FFUNoun` (e.g., `Test-FFUConfiguration`, `New-HypervisorVM`)
- Private: `Verb-Noun` without FFU prefix
- Aliases for deprecated functions: `OldName` pointing to `New-ApprovedVerbName`

**Classes:**
- Interface: `IName` (e.g., `IHypervisorProvider`)
- Data classes: `PascalCase` (e.g., `VMConfiguration`, `VMInfo`, `FFUMessage`)
- Constants: `FFUConstants` (static class)

## Where to Add New Code

**New Feature Module:**
- Create: `FFUDevelopment/Modules/FFU.NewFeature/`
- Required files:
  - `FFU.NewFeature.psd1` - Module manifest with RequiredModules
  - `FFU.NewFeature.psm1` - Module implementation
- Update: `FFUDevelopment/version.json` with new module entry
- Update: `CLAUDE.md` if architecture changes

**New UI Tab/Feature:**
- Logic: Add sub-module `FFUDevelopment/FFUUI.Core/FFUUI.Core.NewFeature.psm1`
- Layout: Add XAML in `FFUDevelopment/BuildFFUVM_UI.xaml`
- Initialization: Update `FFUUI.Core.Initialize.psm1`
- Events: Update `FFUUI.Core.Handlers.psm1`

**New Hypervisor Provider:**
- Interface: Implement `IHypervisorProvider` class methods
- Create: `FFUDevelopment/Modules/FFU.Hypervisor/Providers/NewProvider.ps1`
- Update: `FFU.Hypervisor.psm1` to dot-source new provider
- Update: `Get-HypervisorProvider` to support new provider type

**New Build Feature:**
- Add parameter: `FFUDevelopment/BuildFFUVM.ps1` param block
- Add logic: Appropriate module or new module
- Add validation: `FFU.Preflight` if environment check needed
- Add schema: `FFUDevelopment/config/ffubuilder-config.schema.json`

**New Test:**
- Unit test: `Tests/Unit/FFU.ModuleName.Tests.ps1`
- Integration test: `Tests/Integration/Test-FeatureName.ps1`
- Use template: `Tests/Unit/_Template.Tests.ps1`

**Utilities:**
- Shared helpers: `FFUDevelopment/FFU.Common/FFU.Common.*.psm1`
- Module-specific: Private function in module's psm1

## Special Directories

**FFUDevelopment/Drivers/:**
- Purpose: Downloaded OEM driver packages
- Generated: Yes (during build)
- Committed: No (empty in repo)

**FFUDevelopment/FFU/:**
- Purpose: Output FFU image files
- Generated: Yes (build output)
- Committed: No (empty in repo)

**FFUDevelopment/VM/:**
- Purpose: Hyper-V/VMware VM files during build
- Generated: Yes (temporary)
- Committed: No (empty in repo)

**Tests/Coverage/:**
- Purpose: Pester code coverage reports
- Generated: Yes (test output)
- Committed: No

**Tests/Results/:**
- Purpose: Test execution results
- Generated: Yes (test output)
- Committed: No

**.planning/codebase/:**
- Purpose: GSD codebase analysis documents
- Generated: Yes (by mapping agents)
- Committed: Yes (reference for planning)

## Import Order Requirements

When importing modules, follow this order to satisfy dependencies:

```powershell
# 1. Foundation (no dependencies)
Import-Module FFU.Constants -Force
Import-Module FFU.Messaging -Force  # Standalone

# 2. Core utilities (depends on Constants)
Import-Module FFU.Core -Force

# 3. Specialized modules (depend on Core)
Import-Module FFU.ADK -Force
Import-Module FFU.Apps -Force
Import-Module FFU.Drivers -Force
Import-Module FFU.Imaging -Force
Import-Module FFU.Updates -Force
Import-Module FFU.VM -Force
Import-Module FFU.Preflight -Force

# 4. Media (depends on Core AND ADK)
Import-Module FFU.Media -Force

# 5. Hypervisor (standalone with internal classes)
Import-Module FFU.Hypervisor -Force
```

Note: RequiredModules in .psd1 manifests handle automatic dependency loading.

---

*Structure analysis: 2026-01-16*
