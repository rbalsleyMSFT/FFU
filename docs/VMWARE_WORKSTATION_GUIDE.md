# VMware Workstation Pro Support for FFU Builder

## Overview

FFU Builder v1.6.0 introduces support for VMware Workstation Pro as an alternative hypervisor to Microsoft Hyper-V. This enables FFU image creation on systems that:
- Don't have Hyper-V available or enabled
- Run VMware Workstation Pro for other virtualization needs
- Require a consistent experience across different host environments

## Requirements

### VMware Workstation Pro
- **Version:** 17.0 or later (recommended: 17.5+)
- **Edition:** VMware Workstation Pro (not Player)
- **License:** Active license required for vmrest API access

### System Requirements
- Windows 10/11 Pro, Enterprise, or Education
- Administrator privileges
- 16GB+ RAM recommended (8GB minimum)
- 100GB+ free disk space

## Configuration

### UI Configuration

1. Launch FFU Builder UI (`BuildFFUVM_UI.ps1`)
2. Navigate to the **VM Settings** tab
3. Select **VMware Workstation Pro** from the **Hypervisor Type** dropdown
4. The status indicator shows availability:
   - 🟢 Green: VMware detected and available
   - 🟡 Orange: VMware detected but issues found
   - 🔴 Red: VMware not available

#### Configuring VMware REST API Credentials

When you select VMware Workstation Pro, a new row appears showing the REST API credential status:

| Status | Meaning |
|--------|---------|
| 🟢 **Configured (current user)** | Credentials are set up for your user profile |
| 🟡 **Not configured** | Click the button to set up credentials |

**To configure credentials:**

1. Click the **Configure Credentials...** button
2. A terminal window opens with `vmrest.exe -C`
3. Enter a username when prompted (e.g., `ffubuilder`)
4. Enter and confirm a password
5. Close the terminal and click OK in the dialog
6. The status updates to show "Configured (current user)"

> **Note:** Credentials are stored in your user profile at `%USERPROFILE%\vmrest.cfg` (VMware 17.x).

#### Enterprise Environments with Separate Admin Accounts

If your organization uses separate admin accounts for elevation (common in enterprise environments where UAC prompts require different credentials), you need to configure vmrest credentials for **both** accounts:

1. **For the UI status indicator:** Use the "Configure Credentials..." button (runs as your logged-in user)
2. **For the build process:** Open an elevated Command Prompt (running as the admin account) and run:
   ```cmd
   "C:\Program Files (x86)\VMware\VMware Workstation\vmrest.exe" -C
   ```

This is necessary because:
- Credentials are stored per-user in `%USERPROFILE%\vmrest.cfg`
- The UI runs as your logged-in user
- The build process runs elevated (as the admin account)
- Each account needs its own credentials configured

### Command Line Configuration

```powershell
# Use VMware explicitly
.\BuildFFUVM.ps1 -HypervisorType VMware -ConfigFile config.json

# Auto-detect best available hypervisor
.\BuildFFUVM.ps1 -HypervisorType Auto -ConfigFile config.json
```

### Config File Configuration

```json
{
    "$schema": "./ffubuilder-config.schema.json",
    "HypervisorType": "VMware",
    "VMwareSettings": {
        "WorkstationPath": "",
        "VMrestPort": 8697,
        "VMrestUsername": "",
        "VMrestPassword": "",
        "DefaultNetworkType": "bridged"
    },
    "VirtualDiskFormat": "VHD"
}
```

| Setting | Description | Default |
|---------|-------------|---------|
| `HypervisorType` | Hypervisor to use: `HyperV`, `VMware`, or `Auto` | `HyperV` |
| `VMwareSettings.WorkstationPath` | Path to VMware installation (auto-detect if empty) | Auto-detect |
| `VMwareSettings.VMrestPort` | REST API port for vmrest.exe | 8697 |
| `VMwareSettings.DefaultNetworkType` | Network adapter type: `bridged`, `nat`, `hostonly` | `bridged` |
| `VirtualDiskFormat` | Virtual disk format: `VHD` or `VHDX` | `VHDX` |

> **Note:** When using VMware, `VirtualDiskFormat` should be set to `VHD` (VMware doesn't support VHDX).

## How It Works

### Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    FFU Builder Application                       │
├─────────────────────────────────────────────────────────────────┤
│                    FFU.Hypervisor Module                         │
│  ┌─────────────────┐              ┌─────────────────┐           │
│  │  HyperVProvider │              │ VMwareProvider  │           │
│  └────────┬────────┘              └────────┬────────┘           │
│           │                                │                     │
│           ▼                                ▼                     │
│  ┌─────────────────┐              ┌─────────────────┐           │
│  │   Hyper-V API   │              │  vmrest.exe API │           │
│  │ (PowerShell)    │              │  (REST/HTTP)    │           │
│  └─────────────────┘              └─────────────────┘           │
└─────────────────────────────────────────────────────────────────┘
```

### VMware REST API (vmrest.exe)

FFU Builder uses VMware's REST API through `vmrest.exe`:

1. **Service Start:** `vmrest.exe` is started automatically on port 8697
2. **API Calls:** VM operations are performed via HTTP REST calls
3. **Authentication:** Uses configured credentials or defaults

### VM Lifecycle

| Operation | Hyper-V | VMware |
|-----------|---------|--------|
| Create VM | `New-VM` cmdlet | VMX file generation + `vmrest` registration |
| Start VM | `Start-VM` cmdlet | `PUT /vms/{id}/power {"state": "on"}` |
| Stop VM | `Stop-VM` cmdlet | `PUT /vms/{id}/power {"state": "off"}` |
| Get IP | `Get-VMNetworkAdapter` | `GET /vms/{id}/ip` |
| Remove VM | `Remove-VM` cmdlet | `DELETE /vms/{id}` + cleanup |

### Virtual Disk Operations

VMware support includes VHD operations without requiring Hyper-V:

```powershell
# These functions work via diskpart.exe, not Hyper-V cmdlets
New-VHDWithDiskpart -Path "C:\VMs\disk.vhd" -SizeGB 50 -Type VHD
Mount-VHDWithDiskpart -Path "C:\VMs\disk.vhd"
Dismount-VHDWithDiskpart -Path "C:\VMs\disk.vhd"
```

## End-to-End Build Workflow

### Pre-Flight Checks

Before starting a build, FFU Builder validates:

1. ✅ VMware Workstation Pro installation
2. ✅ vmrest.exe availability
3. ✅ REST API connectivity
4. ✅ Disk space for VHD and FFU files
5. ✅ Network adapter configuration

### Build Process

```
1. Configuration Loading
   └── Load config.json with HypervisorType=VMware

2. Provider Selection
   └── Get-HypervisorProvider -Type VMware
       └── Returns VMwareProvider instance

3. VM Creation
   └── VMwareProvider.CreateVM()
       ├── Generate VMX file for Windows 11 guest
       ├── Create VHD via diskpart
       ├── Register VM with vmrest
       └── Configure TPM, Secure Boot, network

4. Windows Installation
   └── Boot from Windows ISO
       └── Install Windows to VHD

5. Customization
   ├── Install drivers
   ├── Install applications
   └── Apply updates

6. FFU Capture
   └── Boot to WinPE
       └── Capture FFU from disk

7. Cleanup
   └── VMwareProvider.RemoveVM()
       ├── Unregister VM from vmrest
       ├── Delete VMX and related files
       └── Delete VHD
```

### Verification Steps

After build completion, verify:

1. **FFU File Created:**
   ```powershell
   Test-Path "C:\FFUDevelopment\FFU\*.ffu"
   ```

2. **FFU File Integrity:**
   ```powershell
   dism /Get-ImageInfo /ImageFile:"C:\FFUDevelopment\FFU\image.ffu"
   ```

3. **Logs Review:**
   ```powershell
   Get-Content "C:\FFUDevelopment\Logs\BuildFFUVM.log" -Tail 50
   ```

## Performance Comparison

### Benchmark Results (Reference System)

| Metric | Hyper-V | VMware | Notes |
|--------|---------|--------|-------|
| VM Creation | ~10s | ~15s | VMX generation + registration |
| Windows Install | ~8 min | ~9 min | Similar |
| FFU Capture | ~5 min | ~6 min | VHD format slightly slower |
| Total Build | ~45 min | ~50 min | 10-15% longer on VMware |

### Factors Affecting Performance

- **Disk I/O:** VMware may have different I/O patterns
- **Memory Management:** Hyper-V has native Windows integration
- **Network:** NAT vs Bridged can affect download speeds
- **Host Resources:** Available RAM and CPU cores

### Recommendations

- Use **bridged networking** for best performance during app installation
- Allocate **8GB+ RAM** to the build VM
- Use **SSD storage** for VHD files
- Close unnecessary host applications during build

## Troubleshooting

### Common Issues

#### VMware Not Detected

**Symptom:** Status shows "VMware Workstation not found"

**Solutions:**
1. Verify VMware Workstation Pro is installed (not Player)
2. Check registry: `HKLM:\SOFTWARE\VMware, Inc.\VMware Workstation`
3. Restart after installation

#### vmrest API Unavailable

**Symptom:** Build fails with "Cannot connect to vmrest API"

**Solutions:**
1. Verify vmrest.exe exists: `& "vmrest.exe" --version`
2. Check port 8697 is not in use: `netstat -an | findstr 8697`
3. Configure credentials: `vmrest.exe -C`

#### PowerShell 7+ HTTP Authentication Error

**Symptom:** `Invoke-RestMethod: The cmdlet cannot protect plain text secrets sent over unencrypted connections`

**Cause:** PowerShell 7+ refuses to send credentials over HTTP by default for security. VMware's vmrest uses HTTP (not HTTPS).

**Solution:** FFU Builder v1.6.3+ handles this automatically. If testing manually:
```powershell
# PowerShell 7+ requires -AllowUnencryptedAuthentication
Invoke-RestMethod -Uri "http://127.0.0.1:8697/api/vms" -Credential (Get-Credential) -AllowUnencryptedAuthentication

# PowerShell 5.1 works without the extra parameter
Invoke-RestMethod -Uri "http://127.0.0.1:8697/api/vms" -Credential (Get-Credential)
```

#### VHD Creation Fails

**Symptom:** "diskpart failed to create VHD"

**Solutions:**
1. Run as Administrator
2. Verify sufficient disk space
3. Check path doesn't have special characters

#### IP Address Not Found

**Symptom:** Build hangs waiting for VM IP address

**Solutions:**
1. Ensure VM has network adapter configured
2. Use bridged networking (not NAT) for reliability
3. Check VMware network services are running

### Log Files

| Log | Location | Purpose |
|-----|----------|---------|
| Build Log | `Logs\BuildFFUVM.log` | Main build operations |
| VMware Log | `VM\{name}\vmware.log` | VM-specific operations |
| DISM Log | `Windows\Logs\DISM\dism.log` | Image operations |

### Getting Help

1. Review `Logs\BuildFFUVM.log` for error details
2. Check VMware documentation for vmrest.exe
3. Report issues: https://github.com/rbalsleyMSFT/FFU/issues

## API Reference

### FFU.Hypervisor Module Functions

```powershell
# Get hypervisor provider
$provider = Get-HypervisorProvider -Type VMware

# Check availability
$available = Test-HypervisorAvailable -Type VMware -Detailed

# List all hypervisors
$hypervisors = Get-AvailableHypervisors

# VM Operations (via provider)
$vmInfo = $provider.CreateVM($config)
$provider.StartVM($vmInfo)
$provider.StopVM($vmInfo)
$provider.RemoveVM($vmInfo)

# Disk Operations (standalone)
New-HypervisorVirtualDisk -Path "disk.vhd" -SizeGB 50 -Provider $provider
Mount-HypervisorVirtualDisk -Path "disk.vhd" -Provider $provider
Dismount-HypervisorVirtualDisk -Path "disk.vhd" -Provider $provider
```

### VMwareProvider Properties

| Property | Type | Description |
|----------|------|-------------|
| `Name` | string | "VMware" |
| `Version` | string | VMware Workstation version |
| `Description` | string | Provider description |
| `VMwarePath` | string | Installation path |
| `Capabilities` | hashtable | Provider capabilities |

### Capabilities

```powershell
$provider.Capabilities
# Returns:
# @{
#     SupportsTPM = $true
#     SupportsSecureBoot = $true
#     SupportsGeneration2 = $true
#     SupportsDynamicMemory = $false
#     SupportsCheckpoints = $true
#     SupportsNestedVirtualization = $true
#     SupportedDiskFormats = @('VHD', 'VMDK')
#     MaxMemoryGB = 128
#     MaxProcessors = 32
# }
```

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.6.0 | 2026-01-07 | UI integration with hypervisor dropdown |
| 1.5.0 | 2026-01-07 | Full VMware provider implementation |
| 1.4.0 | 2026-01-06 | FFU.Hypervisor module foundation |
