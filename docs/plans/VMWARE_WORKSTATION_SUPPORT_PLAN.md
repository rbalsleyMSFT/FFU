# Feature Plan: VMware Workstation Pro Support

**Document Version:** 1.0
**Created:** 2025-12-17
**Status:** Approved for Implementation
**Priority:** HIGH
**Estimated Effort:** 40-60 hours

---

## Executive Summary

Add VMware Workstation Pro 17.x as a fully supported hypervisor platform for FFU Builder, achieving full feature parity with the existing Hyper-V implementation. This addresses reliability concerns with Hyper-V and expands the user base to include Windows Home users, Linux developers, and organizations with existing VMware infrastructure.

---

## Table of Contents

1. [Requirements Summary](#1-requirements-summary)
2. [Architecture Design](#2-architecture-design)
3. [Implementation Milestones](#3-implementation-milestones)
4. [Technical Specifications](#4-technical-specifications)
5. [File Changes](#5-file-changes)
6. [Testing Strategy](#6-testing-strategy)
7. [Acceptance Criteria](#7-acceptance-criteria)
8. [Risk Assessment](#8-risk-assessment)
9. [Rollback Plan](#9-rollback-plan)

---

## 1. Requirements Summary

### 1.1 Business Requirements

| Requirement | Description |
|-------------|-------------|
| **Primary Goal** | Full feature parity with Hyper-V using VMware Workstation Pro |
| **Target Users** | Windows Home users, Linux developers, VMware organizations |
| **Priority** | HIGH - Hyper-V reliability issues make this critical |
| **Success Criteria** | All FFU Builder workflows work identically on VMware |

### 1.2 Functional Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-01 | Create VMs using VMware Workstation Pro 17.x REST API | Must Have |
| FR-02 | Start, stop, and remove VMs programmatically | Must Have |
| FR-03 | Attach ISO files to VMs for WinPE boot | Must Have |
| FR-04 | Configure VM networking (Bridged mode for FFU capture) | Must Have |
| FR-05 | Retrieve VM IP addresses for network operations | Must Have |
| FR-06 | Work with VHD format directly (no VHDX for VMware) | Must Have |
| FR-07 | Support hypervisor selection via UI dropdown | Must Have |
| FR-08 | Support hypervisor selection via CLI parameter | Must Have |
| FR-09 | Support hypervisor selection via config file | Must Have |
| FR-10 | Auto-detect available hypervisors | Should Have |
| FR-11 | Work without Hyper-V installed | Must Have |

### 1.3 Non-Functional Requirements

| ID | Requirement | Target |
|----|-------------|--------|
| NFR-01 | VMware build time within 10% of Hyper-V build time | Performance |
| NFR-02 | No external dependencies beyond VMware Workstation | Simplicity |
| NFR-03 | Maintain backward compatibility with Hyper-V workflows | Compatibility |
| NFR-04 | Support VMware Workstation Pro 17.x only | Scope |
| NFR-05 | 80%+ test coverage for new VMware code | Quality |

### 1.4 Constraints

| Constraint | Description |
|------------|-------------|
| VMware Version | Only VMware Workstation Pro 17.x supported |
| Disk Format | Use VHD format for VMware (not VHDX) |
| Hyper-V Independence | Must work on systems without Hyper-V |
| No Convert-VHD | Cannot rely on Hyper-V cmdlets for disk operations |

---

## 2. Architecture Design

### 2.1 Provider Pattern Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     BuildFFUVM.ps1                          │
│                   (Orchestration Layer)                     │
└─────────────────────────────┬───────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                  IHypervisorProvider                        │
│                   (Abstract Interface)                      │
│  ┌────────────────────────────────────────────────────────┐ │
│  │ Methods:                                                │ │
│  │   - New-VM([VMConfiguration]) → [VM]                   │ │
│  │   - Start-VM([VM]) → [void]                            │ │
│  │   - Stop-VM([VM]) → [void]                             │ │
│  │   - Remove-VM([VM]) → [void]                           │ │
│  │   - Get-VMIP([VM]) → [string]                          │ │
│  │   - Add-VMDvdDrive([VM], [ISOPath]) → [void]           │ │
│  │   - New-VirtualDisk([Path], [SizeGB]) → [string]       │ │
│  │   - Mount-VirtualDisk([Path]) → [string]               │ │
│  │   - Dismount-VirtualDisk([Path]) → [void]              │ │
│  │   - Test-HypervisorAvailable() → [bool]                │ │
│  └────────────────────────────────────────────────────────┘ │
└─────────────────────────────┬───────────────────────────────┘
                              │
              ┌───────────────┴───────────────┐
              ▼                               ▼
┌─────────────────────────┐     ┌─────────────────────────┐
│    HyperVProvider       │     │    VMwareProvider       │
│  (Existing Hyper-V)     │     │  (New VMware Support)   │
├─────────────────────────┤     ├─────────────────────────┤
│ - Uses Hyper-V module   │     │ - Uses vmrest REST API  │
│ - Native VHDX support   │     │ - VHD format only       │
│ - PowerShell cmdlets    │     │ - Invoke-RestMethod     │
│ - Windows 10/11 Pro+    │     │ - VMware 17.x required  │
└─────────────────────────┘     └─────────────────────────┘
```

### 2.2 Module Structure

```
FFUDevelopment/
└── Modules/
    └── FFU.Hypervisor/                    # NEW MODULE
        ├── FFU.Hypervisor.psd1            # Module manifest
        ├── FFU.Hypervisor.psm1            # Module loader
        ├── Classes/
        │   ├── IHypervisorProvider.ps1    # Interface definition
        │   ├── VMConfiguration.ps1         # VM config class
        │   └── VMInfo.ps1                  # VM info class
        ├── Providers/
        │   ├── HyperVProvider.ps1          # Hyper-V implementation
        │   └── VMwareProvider.ps1          # VMware implementation
        ├── Private/
        │   ├── Start-VMrestService.ps1     # VMware REST API service
        │   ├── Invoke-VMwareRestMethod.ps1 # REST API wrapper
        │   ├── Get-VMwareVMList.ps1        # List VMs
        │   └── ConvertTo-VMwareVMX.ps1     # VMX file generation
        └── Public/
            ├── Get-HypervisorProvider.ps1  # Factory function
            ├── Test-HypervisorAvailable.ps1# Availability check
            └── Get-AvailableHypervisors.ps1# List available
```

### 2.3 Configuration Schema Update

```json
{
    "$schema": "./ffubuilder-config.schema.json",
    "HypervisorType": "VMware",           // NEW: "HyperV" or "VMware"
    "VMwareSettings": {                    // NEW: VMware-specific settings
        "WorkstationPath": "C:\\Program Files (x86)\\VMware\\VMware Workstation",
        "VMrestPort": 8697,
        "VMrestUsername": "admin",
        "VMrestPassword": "",
        "DefaultNetworkType": "bridged"
    },
    "VirtualDiskFormat": "VHD",           // NEW: "VHD" or "VHDX" (VHDX only for Hyper-V)
    // ... existing settings ...
}
```

### 2.4 UI Changes

```
┌─────────────────────────────────────────────────────────────┐
│  FFU Builder UI - Settings Tab                              │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Hypervisor Settings                                        │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ Hypervisor Type: [▼ VMware Workstation Pro      ]   │   │
│  │                     ○ Hyper-V                        │   │
│  │                     ● VMware Workstation Pro         │   │
│  │                     ○ Auto-detect                    │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  VMware Settings (visible when VMware selected)            │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ Installation Path: [C:\Program Files (x86)\VMware\] │   │
│  │ REST API Port:     [8697                          ] │   │
│  │ Network Type:      [▼ Bridged                     ] │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## 3. Implementation Milestones

### Milestone 1: Foundation (Week 1) - 15 hours

**Goal:** Create provider pattern infrastructure and abstract existing Hyper-V code

| Task | Hours | Description |
|------|-------|-------------|
| 1.1 | 3 | Create FFU.Hypervisor module structure |
| 1.2 | 4 | Define IHypervisorProvider interface and supporting classes |
| 1.3 | 5 | Implement HyperVProvider (wrap existing Hyper-V code) |
| 1.4 | 2 | Create Get-HypervisorProvider factory function |
| 1.5 | 1 | Update BuildFFUVM.ps1 to use provider pattern |

**Deliverables:**
- [ ] `Modules/FFU.Hypervisor/` module created
- [ ] `IHypervisorProvider` interface defined
- [ ] `HyperVProvider` implemented (refactored from existing code)
- [ ] Existing Hyper-V functionality unchanged (regression test)

**Exit Criteria:**
- All existing Pester tests pass
- FFU build completes successfully with Hyper-V provider
- No changes to external behavior

---

### Milestone 2: VMware Provider Core (Week 2) - 20 hours

**Goal:** Implement VMware provider with REST API integration

| Task | Hours | Description |
|------|-------|-------------|
| 2.1 | 3 | Implement Start-VMrestService (auto-start vmrest.exe) |
| 2.2 | 4 | Implement Invoke-VMwareRestMethod (REST API wrapper) |
| 2.3 | 5 | Implement VM lifecycle methods (create, start, stop, remove) |
| 2.4 | 4 | Implement disk operations (create VHD, mount via diskpart) |
| 2.5 | 2 | Implement network configuration (bridged adapter) |
| 2.6 | 2 | Implement IP address retrieval |

**Deliverables:**
- [ ] `VMwareProvider` class implemented
- [ ] REST API wrapper functions working
- [ ] VM lifecycle operations functional
- [ ] VHD disk operations working without Hyper-V

**Exit Criteria:**
- Can create, start, stop, and remove VMware VM via PowerShell
- Can attach ISO to VMware VM
- Can retrieve VM IP address

---

### Milestone 3: Integration (Week 3) - 15 hours

**Goal:** Integrate VMware provider into FFU Builder workflow

| Task | Hours | Description |
|------|-------|-------------|
| 3.1 | 3 | Update BuildFFUVM.ps1 for hypervisor selection |
| 3.2 | 3 | Add -HypervisorType parameter to CLI |
| 3.3 | 3 | Add HypervisorType to config schema |
| 3.4 | 4 | Update UI with hypervisor dropdown |
| 3.5 | 2 | Implement auto-detection of available hypervisors |

**Deliverables:**
- [ ] BuildFFUVM.ps1 supports `-HypervisorType` parameter
- [ ] Config file supports `HypervisorType` setting
- [ ] UI has hypervisor selection dropdown
- [ ] Auto-detection works correctly

**Exit Criteria:**
- User can select VMware via UI, CLI, or config
- Auto-detect correctly identifies available hypervisors

---

### Milestone 4: Testing & Polish (Week 4) - 10 hours

**Goal:** Comprehensive testing and documentation

| Task | Hours | Description |
|------|-------|-------------|
| 4.1 | 4 | Create Pester tests for FFU.Hypervisor module |
| 4.2 | 2 | End-to-end testing: Full FFU build with VMware |
| 4.3 | 2 | Performance comparison: VMware vs Hyper-V |
| 4.4 | 2 | Update documentation (CLAUDE.md, README) |

**Deliverables:**
- [ ] 80%+ test coverage for FFU.Hypervisor module
- [ ] Successful end-to-end FFU build with VMware
- [ ] Performance benchmarks documented
- [ ] User documentation complete

**Exit Criteria:**
- All tests pass
- Full FFU build workflow works on VMware
- Documentation updated

---

## 4. Technical Specifications

### 4.1 VMware REST API Reference

**Base URL:** `http://127.0.0.1:8697/api`

| Operation | Method | Endpoint | Description |
|-----------|--------|----------|-------------|
| List VMs | GET | `/vms` | Get all registered VMs |
| Get VM | GET | `/vms/{id}` | Get VM details |
| Create VM | POST | `/vms` | Clone or create VM |
| Power On | PUT | `/vms/{id}/power` | `{"command": "on"}` |
| Power Off | PUT | `/vms/{id}/power` | `{"command": "off"}` |
| Get IP | GET | `/vms/{id}/ip` | Get VM IP address |
| Delete VM | DELETE | `/vms/{id}` | Remove VM |

**Authentication:** Basic auth (configured during vmrest setup)

### 4.2 VMX File Generation

```powershell
function New-VMwareVMX {
    param(
        [string]$VMName,
        [string]$VMPath,
        [int]$MemoryMB = 8192,
        [int]$CPUs = 4,
        [string]$DiskPath,
        [string]$ISOPath
    )

    $vmxContent = @"
.encoding = "UTF-8"
config.version = "8"
virtualHW.version = "21"
displayName = "$VMName"
guestOS = "windows11-64"
memsize = "$MemoryMB"
numvcpus = "$CPUs"
firmware = "efi"
uefi.secureBoot.enabled = "TRUE"

# Virtual disk
scsi0.present = "TRUE"
scsi0.virtualDev = "lsisas1068"
scsi0:0.present = "TRUE"
scsi0:0.fileName = "$DiskPath"

# CD-ROM with ISO
sata0.present = "TRUE"
sata0:0.present = "TRUE"
sata0:0.deviceType = "cdrom-image"
sata0:0.fileName = "$ISOPath"
sata0:0.startConnected = "TRUE"

# Network
ethernet0.present = "TRUE"
ethernet0.connectionType = "bridged"
ethernet0.virtualDev = "e1000e"
ethernet0.startConnected = "TRUE"

# TPM (required for Windows 11)
vtpm.present = "TRUE"
"@

    $vmxPath = Join-Path $VMPath "$VMName.vmx"
    $vmxContent | Out-File -FilePath $vmxPath -Encoding UTF8
    return $vmxPath
}
```

### 4.3 VHD Operations Without Hyper-V

Since we cannot use `Convert-VHD` or Hyper-V disk cmdlets, use these alternatives:

**Create VHD:**
```powershell
function New-VHDWithDiskpart {
    param(
        [string]$Path,
        [int]$SizeGB
    )

    $diskpartScript = @"
create vdisk file="$Path" maximum=$($SizeGB * 1024) type=expandable
attach vdisk
create partition primary
format fs=ntfs quick
assign letter=V
detach vdisk
"@

    $scriptPath = [System.IO.Path]::GetTempFileName()
    $diskpartScript | Out-File -FilePath $scriptPath -Encoding ASCII

    $result = & diskpart /s $scriptPath
    Remove-Item $scriptPath

    return $Path
}
```

**Mount VHD:**
```powershell
function Mount-VHDWithDiskpart {
    param([string]$Path)

    $diskpartScript = @"
select vdisk file="$Path"
attach vdisk
"@
    # ... execute diskpart
}
```

### 4.4 Provider Interface Definition

```powershell
class IHypervisorProvider {
    [string] $Name
    [string] $Version

    # VM Lifecycle
    [VMInfo] CreateVM([VMConfiguration]$config) { throw "Not implemented" }
    [void] StartVM([VMInfo]$vm) { throw "Not implemented" }
    [void] StopVM([VMInfo]$vm, [bool]$force) { throw "Not implemented" }
    [void] RemoveVM([VMInfo]$vm, [bool]$removeDisks) { throw "Not implemented" }

    # VM Information
    [string] GetVMIPAddress([VMInfo]$vm) { throw "Not implemented" }
    [string] GetVMState([VMInfo]$vm) { throw "Not implemented" }

    # Disk Operations
    [string] NewVirtualDisk([string]$path, [int]$sizeGB, [string]$format) { throw "Not implemented" }
    [string] MountVirtualDisk([string]$path) { throw "Not implemented" }
    [void] DismountVirtualDisk([string]$path) { throw "Not implemented" }

    # Media
    [void] AttachISO([VMInfo]$vm, [string]$isoPath) { throw "Not implemented" }
    [void] DetachISO([VMInfo]$vm) { throw "Not implemented" }

    # Availability
    [bool] TestAvailable() { throw "Not implemented" }
    [hashtable] GetCapabilities() { throw "Not implemented" }
}
```

---

## 5. File Changes

### 5.1 New Files

| File | Description |
|------|-------------|
| `Modules/FFU.Hypervisor/FFU.Hypervisor.psd1` | Module manifest |
| `Modules/FFU.Hypervisor/FFU.Hypervisor.psm1` | Module loader |
| `Modules/FFU.Hypervisor/Classes/IHypervisorProvider.ps1` | Interface |
| `Modules/FFU.Hypervisor/Classes/VMConfiguration.ps1` | Config class |
| `Modules/FFU.Hypervisor/Classes/VMInfo.ps1` | VM info class |
| `Modules/FFU.Hypervisor/Providers/HyperVProvider.ps1` | Hyper-V impl |
| `Modules/FFU.Hypervisor/Providers/VMwareProvider.ps1` | VMware impl |
| `Modules/FFU.Hypervisor/Private/Start-VMrestService.ps1` | vmrest helper |
| `Modules/FFU.Hypervisor/Private/Invoke-VMwareRestMethod.ps1` | REST wrapper |
| `Modules/FFU.Hypervisor/Public/Get-HypervisorProvider.ps1` | Factory |
| `Modules/FFU.Hypervisor/Public/Test-HypervisorAvailable.ps1` | Check |
| `Tests/Unit/FFU.Hypervisor.Tests.ps1` | Unit tests |

### 5.2 Modified Files

| File | Changes |
|------|---------|
| `BuildFFUVM.ps1` | Add `-HypervisorType` param, use provider pattern |
| `BuildFFUVM_UI.ps1` | Add hypervisor dropdown |
| `BuildFFUVM_UI.xaml` | Add hypervisor selection UI |
| `config/ffubuilder-config.schema.json` | Add hypervisor settings |
| `Modules/FFU.VM/FFU.VM.psm1` | Refactor to use provider |
| `version.json` | Add FFU.Hypervisor module, bump version |
| `CLAUDE.md` | Document VMware support |

### 5.3 Version Updates

| Component | Current | New |
|-----------|---------|-----|
| FFU Builder | 1.3.12 | 1.4.0 (MINOR - new feature) |
| FFU.Hypervisor | N/A | 1.0.0 (new module) |
| FFU.VM | 1.0.2 | 1.1.0 (refactored) |

---

## 6. Testing Strategy

### 6.1 Unit Tests

```powershell
Describe 'FFU.Hypervisor Module' {
    Describe 'Get-HypervisorProvider' {
        It 'Returns HyperVProvider when type is HyperV' {
            $provider = Get-HypervisorProvider -Type 'HyperV'
            $provider | Should -BeOfType [HyperVProvider]
        }

        It 'Returns VMwareProvider when type is VMware' {
            $provider = Get-HypervisorProvider -Type 'VMware'
            $provider | Should -BeOfType [VMwareProvider]
        }

        It 'Auto-detects available hypervisor' {
            $provider = Get-HypervisorProvider -Type 'Auto'
            $provider | Should -Not -BeNullOrEmpty
        }
    }

    Describe 'VMwareProvider' {
        BeforeAll {
            Mock Start-VMrestService { return $true }
            Mock Invoke-VMwareRestMethod { return @{ id = 'test-vm' } }
        }

        It 'Creates VM via REST API' {
            $config = [VMConfiguration]::new('TestVM', 8192, 4)
            $vm = $provider.CreateVM($config)
            $vm.Id | Should -Be 'test-vm'
        }
    }
}
```

### 6.2 Integration Tests

| Test | Description | Pass Criteria |
|------|-------------|---------------|
| IT-01 | Create VMware VM | VM appears in VMware UI |
| IT-02 | Start/Stop VM | VM starts and stops correctly |
| IT-03 | Attach ISO | ISO mounts and VM boots from it |
| IT-04 | Network connectivity | VM gets IP, can ping host |
| IT-05 | Full FFU build | FFU captured successfully |
| IT-06 | Cleanup | VM and disks removed properly |

### 6.3 Regression Tests

All existing Hyper-V tests must continue to pass after refactoring.

---

## 7. Acceptance Criteria

### 7.1 Functional Acceptance

| ID | Criteria | Verification |
|----|----------|--------------|
| AC-01 | User can select VMware via UI dropdown | Manual test |
| AC-02 | User can select VMware via `-HypervisorType VMware` | CLI test |
| AC-03 | User can select VMware via config file | Config test |
| AC-04 | VMware VM created with correct specs | VMware UI |
| AC-05 | Windows installs successfully in VMware VM | Boot test |
| AC-06 | FFU capture completes via network share | File exists |
| AC-07 | VM and disks cleaned up after capture | File check |
| AC-08 | Works on system without Hyper-V | Test on Win Home |

### 7.2 Non-Functional Acceptance

| ID | Criteria | Target | Verification |
|----|----------|--------|--------------|
| AC-09 | Build time | Within 10% of Hyper-V | Benchmark |
| AC-10 | Test coverage | 80%+ | Pester coverage |
| AC-11 | No regressions | All existing tests pass | CI |

### 7.3 Documentation Acceptance

| ID | Criteria | Verification |
|----|----------|--------------|
| AC-12 | CLAUDE.md updated | Review |
| AC-13 | VMware setup guide created | Review |
| AC-14 | Config schema updated | JSON validation |

---

## 8. Risk Assessment

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| VMware REST API limitations | Medium | High | Early spike to validate all required operations |
| VHD operations without Hyper-V unreliable | Low | High | Thorough testing with diskpart approach |
| UI changes break existing workflows | Low | Medium | Extensive regression testing |
| VMware version incompatibility | Low | Medium | Document supported version, test thoroughly |
| Performance significantly worse than Hyper-V | Low | Medium | Benchmark early, optimize if needed |

---

## 9. Rollback Plan

If VMware support causes issues:

1. **Feature Flag**: Add `"EnableVMwareSupport": false` config option to disable
2. **Module Isolation**: FFU.Hypervisor module can be excluded from import
3. **Git Revert**: All changes in feature branch, easy to revert
4. **Backward Compatibility**: Hyper-V remains default, no breaking changes

---

## Appendix A: VMware Workstation Installation

### Prerequisites

1. Download VMware Workstation Pro 17.x from vmware.com (free)
2. Install with default options
3. Configure vmrest:
   ```cmd
   "C:\Program Files (x86)\VMware\VMware Workstation\vmrest.exe" -C
   ```
4. Set username/password when prompted
5. Start vmrest service (FFU Builder does this automatically)

### Verification

```powershell
# Test vmrest is accessible
Invoke-RestMethod -Uri "http://127.0.0.1:8697/api/vms" -Method Get -Credential (Get-Credential)
```

---

## Appendix B: Decision Log

| Date | Decision | Rationale |
|------|----------|-----------|
| 2025-12-17 | Use VHD format for VMware | Avoid VHDX conversion, works without Hyper-V |
| 2025-12-17 | VMware 17.x only | Current version, free for commercial use |
| 2025-12-17 | All selection methods (UI/CLI/Config) | Maximum flexibility |
| 2025-12-17 | Provider pattern | Clean separation, easy to add more hypervisors |

---

## Appendix C: Reference Documents

- [Hyper-V Alternatives Research](../research/hyperv_alternatives_2025-11-25.md)
- [VMware Workstation REST API Docs](https://docs.vmware.com/en/VMware-Workstation-Pro/17/com.vmware.ws.using.doc/GUID-9FAAA4DD-1320-450D-B684-2845B311640F.html)
- [VMware Workstation Pro Download](https://www.vmware.com/products/workstation-pro.html)

---

**Document Approval:**

| Role | Name | Date | Signature |
|------|------|------|-----------|
| Author | Claude | 2025-12-17 | ✓ |
| Reviewer | | | |
| Approver | | | |
