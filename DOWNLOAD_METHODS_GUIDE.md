# Download Methods Guide - FFU Builder

## Overview

The FFU Builder now supports **multiple download methods** with automatic fallback to ensure downloads work even when BITS fails with authentication error `0x800704DD`.

---

## Download Methods (In Order)

### 1. **BITS (Background Intelligent Transfer Service)** - PRIMARY
**Pros**:
- Resume capability (automatic retry on network interruption)
- Bandwidth throttling
- Low impact on system performance
- Optimized for large files

**Cons**:
- ❌ Requires network credentials
- ❌ Fails with 0x800704DD when credentials unavailable
- ❌ Doesn't work in Start-Job context (unless using ThreadJob)

**When it works**:
- User logged into network
- ThreadJob is used (preserves credentials)
- Explicit credentials provided

---

### 2. **Invoke-WebRequest** - FALLBACK #1
**Pros**:
- ✅ Works with UseDefaultCredentials
- ✅ No special service required
- ✅ Supports authentication
- ✅ Works in any PowerShell context

**Cons**:
- No automatic resume
- Higher memory usage for large files
- No bandwidth throttling

**When it works**:
- Always (unless URL is invalid or network is down)
- Best fallback for most scenarios

---

### 3. **System.Net.WebClient** - FALLBACK #2
**Pros**:
- ✅ Very reliable
- ✅ Simple synchronous download
- ✅ Works with credentials
- ✅ Lower-level than Invoke-WebRequest

**Cons**:
- No resume capability
- No progress reporting
- Deprecated in .NET 6+ (but still works)

**When it works**:
- Extremely reliable fallback
- Works when Invoke-WebRequest has issues

---

### 4. **curl.exe** - FALLBACK #3 (Last Resort)
**Pros**:
- ✅ Native Windows utility (since Win10 1803)
- ✅ Very robust
- ✅ Follows redirects automatically
- ✅ Built-in retry logic

**Cons**:
- Requires curl.exe in PATH
- Less integrated with PowerShell
- No credential object support

**When it works**:
- Final fallback when all PowerShell methods fail
- Works on all modern Windows systems

---

## How It Works

### Automatic Fallback Flow

```
┌─────────────────────────────────────────────┐
│  Start-BitsTransferWithRetry Called         │
└───────────────┬─────────────────────────────┘
                │
                ▼
    ┌───────────────────────┐
    │  UseResilientDownload │ Yes
    │       = true?         ├──────────────────────┐
    └───────────┬───────────┘                      │
                │ No                               │
                │ (Legacy mode)                    │
                ▼                                  ▼
    ┌───────────────────────┐        ┌────────────────────────┐
    │  Try BITS only        │        │ Start-ResilientDownload│
    │  (3 retries)          │        └────────┬───────────────┘
    └───────────┬───────────┘                 │
                │                              │
                ▼                              ▼
    ┌───────────────────────┐        ┌────────────────────────┐
    │  BITS Success?        │        │  Try Method 1: BITS    │
    └───┬───────────────┬───┘        │  (3 retries each)      │
        │ Yes           │ No          └────────┬───────────────┘
        │               │                      │
        ▼               ▼                      ▼
    ┌────────┐   ┌──────────┐      ┌──────────────────────────┐
    │  Done  │   │ ERROR    │      │  BITS Failed?            │
    └────────┘   └──────────┘      └────┬───────────────┬─────┘
                                        │ 0x800704DD    │ Other
                                        │ detected      │ error
                                        ▼               ▼
                                   ┌─────────────────────────┐
                                   │ Skip BITS, go to Fallback│
                                   └────────┬────────────────┘
                                            │
                                            ▼
                                   ┌────────────────────────┐
                                   │ Try Method 2:          │
                                   │ Invoke-WebRequest      │
                                   │ (3 retries)            │
                                   └────────┬───────────────┘
                                            │
                                            ▼
                                   ┌────────────────────────┐
                                   │ Success?               │
                                   └────┬──────────────┬────┘
                                        │ Yes          │ No
                                        ▼              ▼
                                   ┌────────┐   ┌─────────────────┐
                                   │  Done  │   │ Try Method 3:   │
                                   └────────┘   │ WebClient       │
                                                │ (3 retries)     │
                                                └────────┬────────┘
                                                         │
                                                         ▼
                                                ┌────────────────────┐
                                                │ Success?           │
                                                └────┬──────────┬────┘
                                                     │ Yes      │ No
                                                     ▼          ▼
                                                ┌────────┐  ┌────────────┐
                                                │  Done  │  │ Try Method 4│
                                                └────────┘  │ curl.exe    │
                                                            │ (3 retries) │
                                                            └────┬────────┘
                                                                 │
                                                                 ▼
                                                            ┌─────────────┐
                                                            │ Success?    │
                                                            └──┬──────┬───┘
                                                               │ Yes  │ No
                                                               ▼      ▼
                                                          ┌────────┐ ┌────────┐
                                                          │  Done  │ │ ERROR  │
                                                          └────────┘ └────────┘
```

---

## Usage Examples

### Example 1: Automatic Resilient Download (Default)

```powershell
# This now automatically tries all methods
Start-BitsTransferWithRetry -Source "https://example.com/file.zip" -Destination "C:\temp\file.zip"

# Log output will show:
# "Using resilient multi-method download system"
# "Attempting download using method: BITS"
# If BITS fails with 0x800704DD:
# "BITS authentication error 0x800704DD detected - falling back"
# "Attempting download using method: WebRequest"
# "SUCCESS: Downloaded using Invoke-WebRequest"
```

---

### Example 2: Legacy BITS-Only Mode

```powershell
# Disable resilient mode for BITS-only behavior
Start-BitsTransferWithRetry -Source $url -Destination $dest -UseResilientDownload $false

# This behaves like the old version (BITS only, no fallback)
```

---

### Example 3: Direct Resilient Download

```powershell
# Use the new function directly
Import-Module .\FFU.Common\FFU.Common.Download.psm1

Start-ResilientDownload -Source "https://example.com/large-file.iso" `
                        -Destination "C:\downloads\file.iso" `
                        -Retries 5

# Tries all 4 methods with 5 retries each
```

---

### Example 4: Skip BITS Entirely

```powershell
# If you know BITS won't work, skip it
Start-ResilientDownload -Source $url -Destination $dest -SkipBITS

# Goes straight to Invoke-WebRequest
```

---

### Example 5: With Credentials

```powershell
$cred = Get-Credential
Start-BitsTransferWithRetry -Source $url -Destination $dest -Credential $cred

# Credentials are passed to all download methods that support them
```

---

## Configuration Options

### Global Settings

You can configure default behavior by modifying `FFU.Common.Download.psm1`:

```powershell
# Change default retry count
[int]$Retries = 5  # Default is 3

# Change preferred method order in Start-ResilientDownload
# Edit the $methodOrder array
```

---

## Troubleshooting

### Issue: "All download methods failed"

**Cause**: Either the URL is invalid or network connectivity is broken

**Solution**:
1. Check the URL in a browser
2. Test network connectivity: `Test-NetConnection google.com -Port 443`
3. Check firewall/proxy settings
4. Review the log for specific error messages from each method

---

### Issue: "Using resilient multi-method download system" not appearing

**Cause**: FFU.Common.Download module not loaded

**Solution**:
```powershell
# Verify module is loaded
Get-Module FFU.Common

# Check if function exists
Get-Command Start-ResilientDownload

# Manually import if needed
Import-Module .\FFU.Common -Force
```

---

### Issue: Downloads work but are very slow

**Cause**:
- BITS failed, fell back to slower method
- Network is actually slow

**Check logs for**:
```
"Attempting download using method: WebRequest"  # Slower than BITS
"Attempting download using method: WebClient"   # Slower
"Attempting download using method: Curl"        # Can be slow
```

**Solution**: Fix BITS authentication (use ThreadJob) for best performance

---

## Performance Comparison

| Method | Speed | Resume | Memory | Reliability |
|--------|-------|--------|--------|-------------|
| **BITS** | ⭐⭐⭐⭐⭐ Fastest | ✅ Yes | ⭐⭐⭐⭐⭐ Low | ⭐⭐⭐ Needs auth |
| **Invoke-WebRequest** | ⭐⭐⭐⭐ Fast | ❌ No | ⭐⭐⭐ Medium | ⭐⭐⭐⭐ Good |
| **WebClient** | ⭐⭐⭐ Medium | ❌ No | ⭐⭐⭐⭐ Low | ⭐⭐⭐⭐⭐ Excellent |
| **curl.exe** | ⭐⭐⭐ Medium | ❌ No | ⭐⭐⭐⭐ Low | ⭐⭐⭐⭐ Good |

---

## Log Messages Reference

### Success Messages

```
"Using resilient multi-method download system"
"Attempting download using method: BITS"
"BITS download successful (XXXXX bytes)"
"SUCCESS: Downloaded using BITS"
```

### Fallback Messages

```
"BITS authentication error 0x800704DD detected - network credentials not available"
"Skipping BITS and falling back to alternate download methods"
"Method BITS failed: [error message]"
"Attempting download using method: WebRequest"
```

### Warning Messages

```
"WARNING: Start-ResilientDownload not available, falling back to BITS-only mode"
"RECOMMENDATION: Enable -UseResilientDownload for automatic fallback"
```

### Error Messages

```
"All download methods failed for [URL]"
"Attempted methods: BITS, WebRequest, WebClient, Curl"
"HTTP client error detected - file may not exist"
```

---

## Best Practices

### ✅ DO:
- Use default resilient mode (`UseResilientDownload = $true`)
- Check logs to see which method succeeded
- Use ThreadJob for background jobs to enable BITS
- Provide credentials when downloading from authenticated sources

### ❌ DON'T:
- Disable resilient mode unless you have a specific reason
- Assume BITS will always work
- Ignore fallback warnings in logs
- Use Start-Job for background downloads (causes 0x800704DD)

---

## Migration Guide

### From Old Code:
```powershell
Start-BitsTransfer -Source $url -Destination $dest
```

### To New Code (Resilient):
```powershell
Start-BitsTransferWithRetry -Source $url -Destination $dest
# That's it! Automatic fallback is now enabled by default
```

---

## FAQ

**Q: Will this slow down my downloads?**
A: No. BITS is still tried first. Fallback only happens if BITS fails.

**Q: Can I disable specific fallback methods?**
A: Yes, modify the `$methodOrder` array in `FFU.Common.Download.psm1`

**Q: Does this work with large files (>5GB)?**
A: Yes, all methods support large files. BITS is most efficient for very large files.

**Q: What about proxy support?**
A: WebRequest and WebClient support default credentials which work with most proxies. Full proxy configuration is part of Issue #327.

**Q: Will this fix the 0x800704DD error?**
A: Yes! When BITS fails with 0x800704DD, it automatically falls back to methods that don't require BITS credentials.

---

## Related Documentation

- **ISSUE_BITS_AUTHENTICATION.md** - Root cause analysis of 0x800704DD
- **TESTING_GUIDE.md** - How to test the FFU Builder
- **DESIGN.md** - Overall design and architecture

---

**Created**: 2025-10-24
**Version**: 1.0
**Status**: Production Ready
