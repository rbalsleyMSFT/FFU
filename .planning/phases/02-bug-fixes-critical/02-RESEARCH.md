# Phase 2: Bug Fixes - Critical Issues - Research

**Researched:** 2026-01-19
**Domain:** Corporate network proxy configuration, DISM MSU package handling, Hyper-V disk management, Dell driver extraction
**Confidence:** HIGH

## Summary

This research covers the four critical bugs assigned to Phase 2:

1. **BUG-01 (Issue #327)**: Corporate proxy failures with Netskope/zScaler SSL inspection - requires SSL certificate handling and improved proxy detection
2. **BUG-02 (Issue #301)**: Unattend.xml extraction from MSU packages - already partially implemented in FFU.Updates.psm1, needs verification and hardening
3. **BUG-03 (Issue #298)**: OS partition doesn't expand for large driver sets - requires Resize-VHD/Resize-Partition implementation
4. **BUG-04**: Dell chipset driver extraction hang - requires Stop-Process timeout handling

The codebase already has substantial foundation work in place for proxy handling (`FFUNetworkConfiguration` class in FFU.Common.Classes.psm1) and MSU extraction (`Add-WindowsPackageWithUnattend` in FFU.Updates.psm1). The remaining work focuses on hardening these implementations and adding the missing partition expansion and Dell driver timeout handling.

**Primary recommendation:** Implement fixes in dependency order: BUG-04 (isolated), BUG-01 (proxy infrastructure), BUG-02 (verification), BUG-03 (partition expansion).

## Standard Stack

### Core PowerShell Cmdlets
| Cmdlet | Purpose | Why Standard |
|--------|---------|--------------|
| Resize-VHD | Expand VHDX disk file | Native Hyper-V cmdlet for dynamic disk resize |
| Resize-Partition | Expand OS partition | Native Windows cmdlet for partition management |
| Get-PartitionSupportedSize | Query max expandable size | Required before Resize-Partition |
| Start-BitsTransfer | Download with proxy | Native Windows proxy-aware download |
| Invoke-WebRequest | HTTP requests with proxy | PowerShell 7+ proxy parameter support |
| Stop-Process | Kill hung processes | Native PowerShell process management |

### Existing FFU Builder Infrastructure
| Component | Location | Reuse |
|-----------|----------|-------|
| FFUNetworkConfiguration | FFU.Common.Classes.psm1 | Proxy detection/application class |
| Start-ResilientDownload | FFU.Common.Download.psm1 | Multi-method fallback downloads |
| Add-WindowsPackageWithUnattend | FFU.Updates.psm1 | MSU extraction with CAB fallback |
| Invoke-Process | FFU.Core.psm1 | Process execution with -Wait parameter |

### No Additional Libraries Required
All functionality can be implemented using native PowerShell/Windows cmdlets and existing FFU Builder modules.

## Architecture Patterns

### Pattern 1: SSL Certificate Trust Chain Handling
**What:** Configure SSL certificate validation for corporate proxy SSL inspection
**When to use:** Before any network operation when proxy with SSL inspection detected
**Example:**
```powershell
# Detect SSL-inspecting proxy by checking certificate issuer
function Test-SSLInspectionProxy {
    [CmdletBinding()]
    param([string]$TestUrl = "https://www.microsoft.com")

    try {
        $request = [System.Net.HttpWebRequest]::Create($TestUrl)
        $request.Method = "HEAD"
        $request.Timeout = 5000
        $response = $request.GetResponse()
        $cert = $request.ServicePoint.Certificate
        $response.Close()

        # Check if certificate issuer matches known SSL inspection proxies
        $issuer = $cert.Issuer
        $knownProxies = @('Netskope', 'Zscaler', 'Blue Coat', 'Forcepoint', 'goskope')

        foreach ($proxy in $knownProxies) {
            if ($issuer -match $proxy) {
                return [PSCustomObject]@{
                    IsSSLInspected = $true
                    ProxyType = $proxy
                    Issuer = $issuer
                }
            }
        }

        return [PSCustomObject]@{ IsSSLInspected = $false }
    }
    catch {
        return [PSCustomObject]@{
            IsSSLInspected = $false
            Error = $_.Exception.Message
        }
    }
}
```

### Pattern 2: Dynamic VHDX Expansion
**What:** Expand VHDX file and partition before driver injection
**When to use:** When estimated driver size exceeds available partition space
**Example:**
```powershell
function Expand-VHDXForDrivers {
    [CmdletBinding()]
    param(
        [string]$VHDXPath,
        [string]$DriversFolder,
        [uint64]$SafetyMarginGB = 5
    )

    # Calculate required space
    $driverSize = (Get-ChildItem -Path $DriversFolder -Recurse -File |
                   Measure-Object -Property Length -Sum).Sum
    $driverSizeGB = [math]::Ceiling($driverSize / 1GB)

    # Get current VHDX and partition info
    $vhdx = Get-VHD -Path $VHDXPath
    $currentSizeGB = [math]::Floor($vhdx.Size / 1GB)

    # Mount and check partition
    Mount-VHD -Path $VHDXPath -Passthru
    $disk = Get-VHD -Path $VHDXPath | Get-Disk
    $partition = Get-Partition -DiskNumber $disk.Number |
                 Where-Object { $_.Type -eq 'Basic' } |
                 Select-Object -First 1

    $partitionFreeGB = [math]::Floor(($partition.Size -
                       (Get-Volume -Partition $partition).SizeRemaining) / 1GB)

    if ($driverSizeGB + $SafetyMarginGB -gt $partitionFreeGB) {
        $newSizeGB = $currentSizeGB + $driverSizeGB + $SafetyMarginGB

        Dismount-VHD -Path $VHDXPath
        Resize-VHD -Path $VHDXPath -SizeBytes ($newSizeGB * 1GB)
        Mount-VHD -Path $VHDXPath -Passthru

        # Expand partition to fill new space
        $maxSize = (Get-PartitionSupportedSize -DiskNumber $disk.Number -PartitionNumber $partition.PartitionNumber).SizeMax
        Resize-Partition -DiskNumber $disk.Number -PartitionNumber $partition.PartitionNumber -Size $maxSize
    }

    Dismount-VHD -Path $VHDXPath
}
```

### Pattern 3: Process Timeout with Kill
**What:** Run process with timeout, kill if hung
**When to use:** Dell driver extraction that may hang
**Example:**
```powershell
function Invoke-ProcessWithTimeout {
    [CmdletBinding()]
    param(
        [string]$FilePath,
        [string]$ArgumentList,
        [int]$TimeoutSeconds = 60,
        [switch]$KillChildProcesses
    )

    $process = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -PassThru -NoNewWindow

    $completed = $process.WaitForExit($TimeoutSeconds * 1000)

    if (-not $completed) {
        WriteLog "WARNING: Process timed out after $TimeoutSeconds seconds"

        if ($KillChildProcesses) {
            # Kill child processes first
            $children = Get-CimInstance Win32_Process -Filter "ParentProcessId = $($process.Id)"
            foreach ($child in $children) {
                Stop-Process -Id $child.ProcessId -Force -ErrorAction SilentlyContinue
            }
        }

        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        return [PSCustomObject]@{ TimedOut = $true; ExitCode = -1 }
    }

    return [PSCustomObject]@{ TimedOut = $false; ExitCode = $process.ExitCode }
}
```

### Anti-Patterns to Avoid
- **Certificate skip without logging:** Never use `-SkipCertificateCheck` silently - always log when bypassing SSL validation
- **Infinite wait on driver extraction:** Always use timeout with `-Wait $false` for Dell/Intel drivers
- **Partition resize without validation:** Always check `Get-PartitionSupportedSize` before `Resize-Partition`
- **VHDX resize while mounted:** Always dismount VHDX before `Resize-VHD`

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Proxy detection | Manual registry/env parsing | `[FFUNetworkConfiguration]::DetectProxySettings()` | Already handles env vars, registry, WinHTTP |
| MSU extraction | Manual expand.exe calls | `Add-WindowsPackageWithUnattend` | Already handles CAB extraction, unattend.xml |
| VHDX resize | Custom diskpart scripts | `Resize-VHD` + `Resize-Partition` | Native cmdlets with proper error handling |
| Process timeout | Custom timers | `Start-Process -PassThru` + `WaitForExit()` | .NET built-in timeout support |
| Child process kill | Manual WMI queries | `Get-CimInstance Win32_Process -Filter` | Standard CIM approach |

## Common Pitfalls

### Pitfall 1: SSL Certificate Trust on Corporate Networks
**What goes wrong:** Downloads fail with SSL/TLS errors even when proxy configured correctly
**Why it happens:** Netskope/zScaler performs SSL inspection by MITM-ing HTTPS connections with their own certificates
**How to avoid:**
1. Detect SSL inspection using certificate issuer check
2. Ensure proxy root certificate is installed in Windows certificate store
3. Log warning when SSL inspection detected
4. Provide remediation guidance to user
**Warning signs:** "The remote certificate is invalid", "CERTIFICATE_VERIFY_FAILED"

### Pitfall 2: BITS Authentication in Background Jobs
**What goes wrong:** BITS downloads fail with 0x800704DD in ThreadJob/background jobs
**Why it happens:** BITS requires interactive session credentials; background jobs run in different context
**How to avoid:**
1. Use fallback chain: BITS -> WebRequest -> WebClient -> curl
2. Already implemented in `Start-ResilientDownload`
3. Detect 0x800704DD and skip BITS immediately
**Warning signs:** "Network credentials required" in non-interactive context

### Pitfall 3: VHDX Mounted During Resize
**What goes wrong:** `Resize-VHD` fails with "The process cannot access the file"
**Why it happens:** Hyper-V holds exclusive lock on mounted VHDX
**How to avoid:**
1. Always dismount VHDX before resize
2. Wait for dismount to complete (file lock release)
3. Re-mount after resize for partition expansion
**Warning signs:** File in use errors, access denied

### Pitfall 4: Dell Chipset Driver GUI Window
**What goes wrong:** Build hangs indefinitely during Dell driver extraction
**Why it happens:** Intel chipset driver opens GUI window waiting for user interaction even with /s switch
**How to avoid:**
1. Use `-Wait $false` for all Dell chipset/network extractions
2. Implement timeout (5-10 seconds)
3. Kill child processes if parent doesn't exit
**Warning signs:** Process never exits, child process spawned with GUI

### Pitfall 5: MSU vs CAB Application
**What goes wrong:** DISM fails with "failed to apply unattend.xml from MSU"
**Why it happens:** Some MSU packages have embedded unattend.xml that DISM can't process
**How to avoid:**
1. Extract CAB from MSU first using expand.exe
2. Apply CAB directly (bypasses unattend issue)
3. Already implemented in `Add-WindowsPackageWithUnattend`
**Warning signs:** 0x800f0805, 0x800f081f errors

## Code Examples

### BUG-01: Enhanced Proxy Detection with SSL Inspection Awareness
```powershell
# Source: Enhancement to FFUNetworkConfiguration class
static [FFUNetworkConfiguration] DetectProxySettingsWithSSL() {
    $config = [FFUNetworkConfiguration]::DetectProxySettings()

    # Test for SSL inspection
    if ($config.ProxyServer) {
        try {
            $testUrl = "https://www.microsoft.com"
            $request = [System.Net.HttpWebRequest]::Create($testUrl)
            $request.Method = "HEAD"
            $request.Timeout = 5000
            $request.Proxy = New-Object System.Net.WebProxy($config.ProxyServer)

            $response = $request.GetResponse()
            $cert = $request.ServicePoint.Certificate
            $response.Close()

            $issuer = $cert.Issuer
            $sslInspectors = @('Netskope', 'Zscaler', 'goskope', 'Blue Coat', 'Forcepoint')

            foreach ($inspector in $sslInspectors) {
                if ($issuer -match $inspector) {
                    $config | Add-Member -NotePropertyName 'SSLInspectionDetected' -NotePropertyValue $true
                    $config | Add-Member -NotePropertyName 'SSLInspectorType' -NotePropertyValue $inspector
                    WriteLog "WARNING: SSL inspection detected ($inspector). Ensure proxy root certificate is trusted."
                    break
                }
            }
        }
        catch {
            WriteLog "WARNING: Could not verify SSL inspection status: $($_.Exception.Message)"
        }
    }

    return $config
}
```

### BUG-03: VHDX Expansion for Large Driver Sets
```powershell
# Source: New function for FFU.Imaging module
function Expand-FFUPartitionForDrivers {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$VHDXPath,

        [Parameter(Mandatory = $true)]
        [string]$DriversFolder,

        [Parameter()]
        [uint64]$SafetyMarginGB = 5
    )

    # Calculate driver folder size
    $driverBytes = (Get-ChildItem -Path $DriversFolder -Recurse -File -ErrorAction SilentlyContinue |
                    Measure-Object -Property Length -Sum).Sum
    $driverSizeGB = [math]::Ceiling($driverBytes / 1GB)

    WriteLog "Driver folder size: ${driverSizeGB}GB"

    if ($driverSizeGB -lt 5) {
        WriteLog "Driver set is under 5GB, no expansion needed"
        return
    }

    # Get current VHDX info
    $vhdx = Get-VHD -Path $VHDXPath
    $currentSizeGB = [math]::Floor($vhdx.Size / 1GB)

    # Calculate new required size
    $requiredSizeGB = $currentSizeGB + $driverSizeGB + $SafetyMarginGB
    WriteLog "Current VHDX: ${currentSizeGB}GB, Required: ${requiredSizeGB}GB"

    # Dismount if mounted
    $wasMounted = $false
    if ($vhdx.Attached) {
        WriteLog "Dismounting VHDX for resize..."
        Dismount-VHD -Path $VHDXPath
        $wasMounted = $true
        Start-Sleep -Seconds 2  # Wait for file lock release
    }

    # Resize VHDX
    WriteLog "Expanding VHDX to ${requiredSizeGB}GB..."
    Resize-VHD -Path $VHDXPath -SizeBytes ($requiredSizeGB * 1GB)

    # Mount and expand partition
    WriteLog "Mounting and expanding partition..."
    $disk = Mount-VHD -Path $VHDXPath -Passthru | Get-Disk

    $osPartition = Get-Partition -DiskNumber $disk.Number |
                   Where-Object { $_.Type -eq 'Basic' -and $_.DriveLetter } |
                   Select-Object -First 1

    if ($osPartition) {
        $maxSize = (Get-PartitionSupportedSize -DiskNumber $disk.Number -PartitionNumber $osPartition.PartitionNumber).SizeMax
        $currentPartitionSizeGB = [math]::Floor($osPartition.Size / 1GB)
        $maxSizeGB = [math]::Floor($maxSize / 1GB)

        WriteLog "Partition current: ${currentPartitionSizeGB}GB, Max available: ${maxSizeGB}GB"

        if ($maxSize -gt $osPartition.Size) {
            Resize-Partition -DiskNumber $disk.Number -PartitionNumber $osPartition.PartitionNumber -Size $maxSize
            WriteLog "Partition expanded to ${maxSizeGB}GB"
        }
    }

    if (-not $wasMounted) {
        Dismount-VHD -Path $VHDXPath
    }

    WriteLog "VHDX expansion complete"
}
```

### BUG-04: Dell Driver Extraction with Timeout
```powershell
# Source: Enhancement to FFU.Drivers Get-DellDrivers
# Dell Chipset driver extraction with timeout handling
if ($driver.Category -eq "Chipset") {
    WriteLog "Extracting Chipset driver with timeout protection: $driverFilePath"

    $process = Start-Process -FilePath $driverFilePath -ArgumentList $arguments -PassThru -NoNewWindow

    # Wait with timeout (30 seconds for extraction)
    $timeoutSeconds = 30
    $completed = $process.WaitForExit($timeoutSeconds * 1000)

    if (-not $completed) {
        WriteLog "WARNING: Chipset driver extraction timed out after ${timeoutSeconds}s - killing process"

        # Kill child processes first (Intel GUI windows)
        $childProcesses = Get-CimInstance Win32_Process -Filter "ParentProcessId = $($process.Id)"
        foreach ($child in $childProcesses) {
            WriteLog "Stopping child process: $($child.Name) (PID: $($child.ProcessId))"
            Stop-Process -Id $child.ProcessId -Force -ErrorAction SilentlyContinue
        }

        # Kill parent
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1  # Allow cleanup
    }
    else {
        WriteLog "Chipset driver extraction completed with exit code: $($process.ExitCode)"
    }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Manual proxy env vars | Auto-detect + env + registry | PowerShell 7.0+ | Better corporate network support |
| MSU direct application | CAB extraction from MSU | Windows 11 24H2 | Fixes checkpoint CU issues |
| Fixed VHDX size | Dynamic expansion | Always available | Supports large driver sets |
| `-Wait $true` for all | `-Wait $false` + timeout | Dell driver issue | Prevents hang |

**Deprecated/outdated:**
- Using `-SkipCertificateCheck` without logging (security concern)
- Assuming BITS works in all contexts (fails in ThreadJob)
- Fixed 50GB VHDX assumption (driver sets can exceed available space)

## Open Questions

1. **WPAD Auto-Discovery**
   - What we know: PowerShell 7+ uses HttpClient.DefaultProxy which supports WPAD
   - What's unclear: Whether WPAD detection works in ThreadJob context
   - Recommendation: Test WPAD in ThreadJob; implement manual fallback if needed

2. **Netskope Client Detection**
   - What we know: Netskope client installs root certificate automatically
   - What's unclear: Whether Netskope "Protect Client resources" setting blocks PowerShell
   - Recommendation: Document workaround (disable protect setting or add exclusion)

3. **Driver Size Estimation Accuracy**
   - What we know: Drivers compress differently when injected vs on disk
   - What's unclear: Exact compression ratio for DISM driver injection
   - Recommendation: Use 1.5x safety factor in size calculation

## Sources

### Primary (HIGH confidence)
- [Microsoft Learn: Resize-VHD](https://learn.microsoft.com/en-us/powershell/module/hyper-v/resize-vhd) - VHDX resize cmdlet documentation
- [Microsoft Learn: Start-BitsTransfer](https://learn.microsoft.com/en-us/powershell/module/bitstransfer/start-bitstransfer) - BITS proxy parameters
- [Microsoft Learn: Invoke-WebRequest](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/invoke-webrequest) - PowerShell 7 proxy support

### Secondary (MEDIUM confidence)
- [Netskope Community: CLI Tools SSL Interception](https://community.netskope.com/next-gen-swg-2/configuring-cli-based-tools-and-development-frameworks-to-work-with-netskope-ssl-interception-7015) - Netskope configuration guidance
- [Zscaler SSL Inspection Engineering](https://matthewlboyd.com/2025/10/09/zscaler-ssl-inspection-engineering-heavy/) - SSL inspection bypass strategies
- [Dell Community: DUP Silent Install](https://www.dell.com/community/en/conversations/enterprise-client/best-way-to-silently-install-dup-drivers/647f5254f4ccf8a8deb7b11e) - Dell driver extraction issues
- [Windows OS Hub: PowerShell Proxy](https://woshub.com/using-powershell-behind-a-proxy/) - Comprehensive proxy configuration guide

### Tertiary (LOW confidence - verify before use)
- [Computer Help Community: MSU Unattend Error](http://computerhelp.community/threads/an-error-occurred-applying-the-unattend-xml-file-from-the-msu-package.864022/) - MSU extraction workarounds

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - Using native PowerShell/Windows cmdlets
- Architecture: HIGH - Patterns verified against existing codebase
- Pitfalls: HIGH - Derived from documented issues and codebase comments

**Research date:** 2026-01-19
**Valid until:** 2026-02-19 (30 days - stable Windows/PowerShell APIs)
