# FIXED: CaptureFFU.ps1 Network Ping Timeout

**Status:** Implemented (Solution 2 - Non-blocking ping)
**Date Identified:** 2025-12-17
**Date Fixed:** 2026-01-08
**Reported By:** User testing on separate machine
**Fixed In:** v1.6.3

## Symptom

When executing FFU Builder, the WinPE VM produces:
```
[Request interrupted by user]
[56s] Waiting for host connectivity (192.168.29.223)...
[TIMEOUT] Network failed to become ready within 60 seconds.
Current network state: Adapters found - Ethernet: Up.
IP Addresses: -192.168.29.31 on Microsoft Hyper-V Network Adapter.
X:\CaptureFFU.ps1 : CaptureFFU.ps1 network connection error: Network initialization failed - network is not ready after 60 seconds.
```

## Environment

- VM IP: 192.168.29.31
- Host IP: 192.168.29.223 (same subnet - correct)
- Hyper-V Switch: External (correct configuration)
- Network adapter: Up with valid IP (not APIPA)

## Root Cause Analysis

The `Wait-For-NetworkReady` function in `CaptureFFU.ps1` requires a successful ping to the host before proceeding. The error message **"[Request interrupted by user]"** from ping.exe indicates something is actively terminating the ping process.

**Most likely cause:** Windows Firewall on the host blocking incoming ICMP (ping) requests.

The ping check is at lines 393-400 of `WinPECaptureFFUFiles\CaptureFFU.ps1`:
```powershell
$ping = Test-HostConnection -ComputerName $HostIP -Count 1 -Quiet
if (-not $ping) {
    Write-Host "  [$elapsed`s] Waiting for host connectivity ($HostIP)..." -ForegroundColor Yellow
    Start-Sleep -Seconds 2
    continue  # Blocks progress until ping succeeds
}
```

## Proposed Solutions

### Solution 1: Enable ICMP on Host Firewall (Recommended)

Run on the HOST machine (elevated PowerShell):
```powershell
# Enable ICMPv4 Echo Request (ping) for all profiles
New-NetFirewallRule -DisplayName "Allow ICMPv4-In" -Protocol ICMPv4 -IcmpType 8 -Direction Inbound -Action Allow -Profile Any

# Or enable the built-in rule
Enable-NetFirewallRule -Name "FPS-ICMP4-ERQ-In"
```

**Quick test to confirm firewall is the issue:**
```powershell
# Temporarily disable firewall
Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False

# Run FFU build - if it works, firewall was the issue

# Re-enable firewall
Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True

# Add permanent ICMP rule
New-NetFirewallRule -DisplayName "Allow ICMPv4-In" -Protocol ICMPv4 -IcmpType 8 -Direction Inbound -Action Allow
```

### Solution 2: Code Change - Make Ping Check Non-Blocking

Modify `Wait-For-NetworkReady` to treat ping failure as a warning rather than blocking:

**File:** `FFUDevelopment/WinPECaptureFFUFiles/CaptureFFU.ps1`
**Lines:** 393-400

**Current code:**
```powershell
# Check 4: Host is reachable via ping
$ping = Test-HostConnection -ComputerName $HostIP -Count 1 -Quiet
if (-not $ping) {
    Write-Host "  [$elapsed`s] Waiting for host connectivity ($HostIP)..." -ForegroundColor Yellow
    Start-Sleep -Seconds 2
    continue
}
```

**Proposed change:**
```powershell
# Check 4: Host is reachable via ping (non-blocking - ICMP may be blocked)
$ping = Test-HostConnection -ComputerName $HostIP -Count 1 -Quiet
if (-not $ping) {
    # Only warn on first occurrence, don't block
    if (-not $script:pingWarningShown) {
        Write-Host "  [$elapsed`s] Warning: Ping to host failed (ICMP may be blocked by firewall)" -ForegroundColor Yellow
        Write-Host "  [$elapsed`s] Proceeding to SMB connection - will provide better error if host unreachable" -ForegroundColor Yellow
        $script:pingWarningShown = $true
    }
    # Don't continue - proceed to success and let SMB connection handle errors
}
```

**Rationale:**
- Many corporate environments block ICMP but allow SMB
- The SMB connection attempt provides more specific error messages
- Ping is an optimization, not a hard requirement

## Testing Required

1. Confirm Solution 1 (firewall rule) resolves the issue
2. If ICMP must remain blocked in user's environment, implement Solution 2
3. Test Solution 2 in environment where:
   - ICMP is blocked (ping fails)
   - SMB is allowed (connection should succeed)
   - SMB is blocked (should show proper SMB error, not ping timeout)

## Related Files

- `FFUDevelopment/WinPECaptureFFUFiles/CaptureFFU.ps1` - Main capture script
- `FFUDevelopment/WinPECaptureFFUFiles/startnet.cmd` - WinPE startup script

## Notes

- The "[Request interrupted by user]" ping error is unusual - typically indicates firewall/security software actively blocking
- The network configuration is correct (same subnet, External switch)
- The issue is not with DHCP, IP assignment, or Hyper-V configuration
