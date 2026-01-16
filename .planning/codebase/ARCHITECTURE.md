# Architecture

**Analysis Date:** 2026-01-16

## Pattern Overview

**Overall:** Modular PowerShell Architecture with WPF UI, Background Job Pattern, and Provider Abstraction

**Key Characteristics:**
- Event-driven WPF UI with background job execution for long-running builds
- 15+ specialized PowerShell modules with explicit dependency hierarchy
- Provider pattern for hypervisor abstraction (Hyper-V, VMware Workstation)
- Thread-safe messaging via ConcurrentQueue for UI/job communication
- JSON-based configuration with schema validation
- Tiered pre-flight validation system with remediation guidance

## Layers

**Presentation Layer (UI):**
- Purpose: WPF-based graphical interface for build configuration
- Location: `FFUDevelopment/BuildFFUVM_UI.ps1`, `FFUDevelopment/BuildFFUVM_UI.xaml`
- Contains: XAML layout, UI state management, event handlers, control initialization
- Depends on: FFUUI.Core, FFU.Common, FFU.Messaging
- Used by: End users configuring FFU builds

**UI Framework Layer:**
- Purpose: Modular UI logic separated by concern
- Location: `FFUDevelopment/FFUUI.Core/`
- Contains:
  - `FFUUI.Core.psm1` - Core UI helpers, VM switch detection, data retrieval
  - `FFUUI.Core.Initialize.psm1` - Control initialization, default values
  - `FFUUI.Core.Handlers.psm1` - Event handler registration
  - `FFUUI.Core.Config.psm1` - Configuration save/load
  - `FFUUI.Core.Shared.psm1` - Shared utilities
  - `FFUUI.Core.Drivers.*.psm1` - OEM-specific driver UI logic
  - `FFUUI.Core.Applications.psm1` - App management UI
  - `FFUUI.Core.Winget.psm1` - WinGet integration UI
- Depends on: FFU.Common, FFU.Messaging
- Used by: BuildFFUVM_UI.ps1

**Build Orchestration Layer:**
- Purpose: Core build script that coordinates all FFU creation operations
- Location: `FFUDevelopment/BuildFFUVM.ps1`
- Contains: Parameter validation, config loading, build workflow orchestration
- Depends on: All FFU.* modules (Core, ADK, Apps, Drivers, Hypervisor, Imaging, Media, Preflight, Updates, VM)
- Used by: UI (via background job) or direct CLI execution

**Module Layer:**
- Purpose: Specialized functionality organized by domain
- Location: `FFUDevelopment/Modules/`
- Contains: 13 PowerShell modules with explicit dependencies
- Depends on: FFU.Constants (foundation), FFU.Core (utilities)
- Used by: BuildFFUVM.ps1, FFUUI.Core

**Business Logic Layer:**
- Purpose: Shared utilities and logging across UI and build script
- Location: `FFUDevelopment/FFU.Common/`
- Contains:
  - `FFU.Common.Core.psm1` - WriteLog, process execution, BITS transfers
  - `FFU.Common.Download.psm1` - Resilient download (BITS -> WebRequest -> WebClient -> curl)
  - `FFU.Common.ParallelDownload.psm1` - Concurrent downloads
  - `FFU.Common.Parallel.psm1` - Runspace-based parallel execution
  - `FFU.Common.Classes.psm1` - Shared class definitions
- Depends on: FFU.Messaging (optional, for queue integration)
- Used by: All layers

**WinPE Runtime Layer:**
- Purpose: Scripts that run inside WinPE for FFU capture/deploy
- Location: `FFUDevelopment/WinPECaptureFFUFiles/`, `FFUDevelopment/WinPEDeployFFUFiles/`
- Contains: CaptureFFU.ps1, DeployFFU.ps1, startnet.cmd
- Depends on: Minimal (runs in WinPE environment)
- Used by: WinPE boot media during capture/deployment

**VM Guest Layer:**
- Purpose: Scripts that run inside the build VM for app installation
- Location: `FFUDevelopment/Apps/Orchestration/`
- Contains: Orchestrator.ps1, Install-Win32Apps.ps1, Run-Sysprep.ps1, etc.
- Depends on: None (self-contained for VM execution)
- Used by: Build VM during app installation phase

## Data Flow

**FFU Build Flow (UI-initiated):**

1. User configures build in WPF UI (BuildFFUVM_UI.ps1)
2. UI creates MessagingContext for real-time updates
3. UI launches BuildFFUVM.ps1 as ThreadJob with parameters
4. BuildFFUVM.ps1 loads modules, runs pre-flight validation
5. FFU.Imaging creates VHDX, partitions, applies Windows image
6. FFU.Hypervisor creates VM via provider (Hyper-V or VMware)
7. VM boots, runs Orchestrator.ps1 for app installation
8. VM shuts down, capture media boots
9. CaptureFFU.ps1 captures disk to FFU, uploads to share
10. BuildFFUVM.ps1 cleans up resources, signals completion
11. UI receives completion via MessagingContext

**Configuration Flow:**

1. User modifies UI controls
2. UI updates internal state object (`$script:uiState`)
3. User saves config -> `Export-FFUConfiguration` writes JSON
4. User loads config -> `Import-FFUConfiguration` populates UI
5. Build start -> config validated against JSON schema
6. BuildFFUVM.ps1 receives config as parameters or `-ConfigFile`

**State Management:**
- UI state: `$script:uiState` object with Controls, Data, Flags, Defaults
- Build state: FFU.Messaging `FFUBuildState` enum (NotStarted, Running, Completed, Failed)
- Module state: Script-scoped variables within each module

## Key Abstractions

**IHypervisorProvider Interface:**
- Purpose: Abstract hypervisor operations for multi-platform support
- Examples: `FFUDevelopment/Modules/FFU.Hypervisor/Classes/IHypervisorProvider.ps1`
- Pattern: Provider pattern with HyperVProvider and VMwareProvider implementations
- Methods: CreateVM, StartVM, StopVM, RemoveVM, GetVMIPAddress, AttachISO, etc.

**VMConfiguration Class:**
- Purpose: Standardized VM configuration across hypervisors
- Examples: `FFUDevelopment/Modules/FFU.Hypervisor/Classes/VMConfiguration.ps1`
- Pattern: Factory method (`NewFFUBuildVM`) for common configurations

**VMInfo Class:**
- Purpose: Unified VM information regardless of hypervisor
- Examples: `FFUDevelopment/Modules/FFU.Hypervisor/Classes/VMInfo.ps1`
- Pattern: Data transfer object with VMState enum

**FFUMessage Class:**
- Purpose: Structured message for UI/job communication
- Examples: `FFUDevelopment/Modules/FFU.Messaging/FFU.Messaging.psm1`
- Pattern: Queue-based messaging with severity levels

**FFUConstants Class:**
- Purpose: Centralized configuration values with dynamic path resolution
- Examples: `FFUDevelopment/Modules/FFU.Constants/FFU.Constants.psm1`
- Pattern: Static class with GetBasePath(), GetDefaultVMDir(), etc.

**FFUCheckResult Object:**
- Purpose: Standardized pre-flight validation results
- Examples: `FFUDevelopment/Modules/FFU.Preflight/FFU.Preflight.psm1`
- Pattern: Factory function `New-FFUCheckResult` with Status, Message, Remediation

## Entry Points

**Primary UI Entry:**
- Location: `FFUDevelopment/BuildFFUVM_UI.ps1`
- Triggers: User double-click or `.\BuildFFUVM_UI.ps1` in PowerShell
- Responsibilities: Load XAML, initialize modules, display window, handle events

**CLI Build Entry:**
- Location: `FFUDevelopment/BuildFFUVM.ps1`
- Triggers: Direct execution with parameters or `-ConfigFile`
- Responsibilities: Validate params, load config, orchestrate entire build

**WinPE Media Creator:**
- Location: `FFUDevelopment/Create-PEMedia.ps1`
- Triggers: Manual execution for standalone WinPE creation
- Responsibilities: Create capture/deploy WinPE media

**USB Tool Creator:**
- Location: `FFUDevelopment/USBImagingToolCreator.ps1`
- Triggers: Post-build for USB deployment media
- Responsibilities: Partition USB, copy FFU and deploy tools

## Error Handling

**Strategy:** Hierarchical with cleanup registration

**Patterns:**
- `Invoke-WithErrorHandling`: Wrapper with retry logic (3 attempts default)
- `Invoke-WithCleanup`: Guaranteed finally block execution
- `Test-ExternalCommandSuccess`: Exit code validation with robocopy special handling
- `Register-CleanupAction`: LIFO cleanup registry for resource management
- `Invoke-WimMountWithErrorHandling`: DISM-specific error detection (0x800704DB)

**Cleanup Registration System:**
- Register resources as created: `Register-VMCleanup`, `Register-VHDXCleanup`, etc.
- On failure: `Invoke-FailureCleanup` processes registry in reverse order
- Selective cleanup by ResourceType (VM, VHDX, DISM, ISO, TempFile, Share, User)

## Cross-Cutting Concerns

**Logging:**
- Primary: `WriteLog` function in FFU.Common.Core.psm1
- Dual output: File (persistent) + MessagingQueue (real-time UI)
- Thread-safe: Mutex-protected file writes
- Levels: Debug, Info, Progress, Success, Warning, Error, Critical

**Validation:**
- Pre-flight: FFU.Preflight module with tiered checks
  - Tier 1: CRITICAL (Admin, PowerShell 7+, Hyper-V) - Blocking
  - Tier 2: FEATURE-DEPENDENT (ADK, Disk, Network) - Blocking
  - Tier 3: RECOMMENDED (AV Exclusions) - Warnings
  - Tier 4: CLEANUP (DISM Cleanup) - Pre-remediation
- Config: `Test-FFUConfiguration` validates against JSON schema

**Authentication:**
- WinPE capture: Temporary `ffu_user` account with random password
- 4-hour expiry failsafe, auto-cleanup after capture
- Secure password generation via `New-SecureRandomPassword`

## Module Dependency Hierarchy

```
FFU.Constants (v1.1.0) - Foundation, no dependencies
└── FFU.Core (v1.0.13) - Requires FFU.Constants
    ├── FFU.ADK (v1.0.0)
    ├── FFU.Apps (v1.0.0)
    ├── FFU.Drivers (v1.0.5)
    ├── FFU.Imaging (v1.0.9)
    ├── FFU.Updates (v1.0.2)
    ├── FFU.VM (v1.0.6)
    ├── FFU.Preflight (v1.0.9)
    └── FFU.Media (v1.3.2) - Also requires FFU.ADK

FFU.Hypervisor (v1.2.9) - Standalone with internal classes
FFU.Messaging (v1.0.0) - Standalone, no dependencies
FFU.BuildTest (v1.1.0) - Testing utilities
```

---

*Architecture analysis: 2026-01-16*
