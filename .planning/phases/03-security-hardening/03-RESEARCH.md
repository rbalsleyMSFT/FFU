# Phase 3: Security Hardening - Research

**Researched:** 2026-01-19
**Domain:** PowerShell credential management, script integrity verification, API token handling
**Confidence:** HIGH

## Summary

This research covers three security requirements for FFU Builder: improving Lenovo PSREF token handling (SEC-01), using SecureString throughout for FFU capture user passwords (SEC-02), and adding integrity verification for Apps orchestration scripts (SEC-03).

The current codebase already has **excellent foundations** for secure credential management, including `New-SecureRandomPassword` that generates directly to SecureString, proper BSTR cleanup patterns, and account expiry failsafes. The primary gaps are: (1) the Lenovo PSREF token requires browser automation due to JavaScript-generated cookies with no alternative API, (2) password must eventually be written as plaintext to CaptureFFU.ps1 for WinPE use (unavoidable), and (3) Apps orchestration scripts lack pre-execution verification.

**Primary recommendation:** Implement token caching with file-based persistence for SEC-01, ensure consistent SecureString flow until final script injection for SEC-02, and add SHA-256 hash verification before executing orchestration scripts for SEC-03.

## Standard Stack

The established libraries/tools for this domain:

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| System.Security.SecureString | .NET 4.x+ | In-memory password protection | Built into .NET, encrypts memory contents |
| System.Security.Cryptography.RNGCryptoServiceProvider | .NET 4.x+ | Cryptographic random generation | FIPS-compliant, hardware RNG when available |
| Get-FileHash | PowerShell 5.1+ | File integrity verification | Native cmdlet, supports SHA256/SHA384/SHA512 |
| System.Runtime.InteropServices.Marshal | .NET 4.x+ | SecureString to plaintext conversion | Standard pattern for secure conversion/cleanup |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| ConvertTo-SecureString | PowerShell 5.1+ | String to SecureString | Only for runtime conversion, never persist |
| Export-Clixml / Import-Clixml | PowerShell 5.1+ | DPAPI-encrypted credential storage | Token caching on Windows with DPAPI |
| System.IO.File.Encrypt | .NET 4.x+ | EFS file encryption | Additional layer for sensitive cache files |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| SecureString | Azure Key Vault / Secret Manager | Requires cloud connectivity, more complex |
| File-based token cache | Windows Credential Manager | More secure but requires different API |
| SHA256 hash verification | Code signing (Authenticode) | More robust but requires certificates |

**Installation:**
```powershell
# No additional installation required - all capabilities are native to PowerShell/Windows
# PSScriptAnalyzer already in use for code quality
```

## Architecture Patterns

### Recommended Project Structure for Security Artifacts
```
FFUDevelopment/
├── .security/                      # NEW: Security metadata folder
│   ├── orchestration-hashes.json   # Manifest of expected script hashes
│   └── token-cache/                # DPAPI-encrypted token cache
│       └── lenovo-psref.xml        # Encrypted token storage
├── Apps/
│   └── Orchestration/              # Scripts to be verified
│       ├── Orchestrator.ps1
│       ├── Install-Win32Apps.ps1
│       └── ...
└── Modules/
    └── FFU.Core/                   # Security functions here
```

### Pattern 1: SecureString Lifecycle Management
**What:** Maintain password as SecureString throughout the codebase, converting to plaintext only at the final point of use (script injection), then immediately clear from memory.
**When to use:** Any password handling in FFU Builder
**Example:**
```powershell
# Source: FFU.Core.psm1 (existing pattern)
# Generation - never touches plaintext
$securePassword = New-SecureRandomPassword -Length 32 -IncludeSpecialChars $false

# Pass as SecureString through all function calls
Set-CaptureFFU -Username $Username -Password $securePassword

# Convert only at final use point
$bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
try {
    $plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    # Use plainPassword for script injection
}
finally {
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    $plainPassword = $null
    [System.GC]::Collect()
}
```

### Pattern 2: Token Caching with Expiry
**What:** Cache authentication tokens with explicit expiry times to reduce repeated authentication
**When to use:** Lenovo PSREF token retrieval
**Example:**
```powershell
function Get-CachedToken {
    param([string]$TokenId, [int]$MaxAgeMinutes = 60)

    $cachePath = Join-Path $FFUDevelopmentPath ".security\token-cache\$TokenId.xml"

    if (Test-Path $cachePath) {
        $cached = Import-Clixml -Path $cachePath
        $age = (Get-Date) - $cached.Timestamp
        if ($age.TotalMinutes -lt $MaxAgeMinutes) {
            return $cached.Token
        }
    }
    return $null
}

function Set-CachedToken {
    param([string]$TokenId, [string]$Token)

    $cacheDir = Join-Path $FFUDevelopmentPath ".security\token-cache"
    if (-not (Test-Path $cacheDir)) {
        New-Item -Path $cacheDir -ItemType Directory -Force | Out-Null
    }

    $cachePath = Join-Path $cacheDir "$TokenId.xml"
    @{
        Token = $Token
        Timestamp = Get-Date
    } | Export-Clixml -Path $cachePath

    # Apply NTFS encryption
    (Get-Item $cachePath).Encrypt()
}
```

### Pattern 3: Pre-Execution Hash Verification
**What:** Calculate and verify SHA-256 hashes of scripts before execution
**When to use:** Apps orchestration scripts before running in VM
**Example:**
```powershell
function Test-ScriptIntegrity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptPath,

        [Parameter(Mandatory = $false)]
        [string]$ExpectedHash,

        [Parameter(Mandatory = $false)]
        [string]$ManifestPath
    )

    if (-not (Test-Path $ScriptPath)) {
        throw "Script not found: $ScriptPath"
    }

    $actualHash = (Get-FileHash -Path $ScriptPath -Algorithm SHA256).Hash

    # If manifest provided, look up expected hash
    if ($ManifestPath -and (Test-Path $ManifestPath)) {
        $manifest = Get-Content $ManifestPath -Raw | ConvertFrom-Json
        $scriptName = [System.IO.Path]::GetFileName($ScriptPath)
        $ExpectedHash = $manifest.scripts.$scriptName
    }

    if ([string]::IsNullOrEmpty($ExpectedHash)) {
        WriteLog "WARNING: No expected hash for $ScriptPath - skipping verification"
        return $true  # Or $false for strict mode
    }

    if ($actualHash -ne $ExpectedHash) {
        WriteLog "ERROR: Hash mismatch for $ScriptPath"
        WriteLog "  Expected: $ExpectedHash"
        WriteLog "  Actual:   $actualHash"
        return $false
    }

    WriteLog "Verified integrity of $ScriptPath"
    return $true
}
```

### Anti-Patterns to Avoid
- **Storing plaintext passwords in variables longer than necessary:** Convert and clear immediately
- **Passing plaintext through multiple function layers:** Keep as SecureString until final use
- **Caching tokens without expiry:** Always include timestamp and max age
- **Executing scripts without verification when verification is enabled:** Fail closed, not open
- **Hardcoding hashes in source code:** Use external manifest file for maintainability

## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Random password generation | Custom random logic | `New-SecureRandomPassword` (FFU.Core) | Already uses RNGCryptoServiceProvider, generates to SecureString |
| SecureString conversion | Manual pointer handling | `ConvertFrom-SecureStringToPlainText` (FFU.Core) | Already handles BSTR cleanup properly |
| File hashing | Custom hash calculation | `Get-FileHash -Algorithm SHA256` | Native, fast, reliable, supports multiple algorithms |
| DPAPI encryption | Custom encryption | `Export-Clixml` / `Import-Clixml` | Automatic DPAPI encryption on Windows |
| Memory cleanup | Manual GC | `Clear-PlainTextPassword`, `Remove-SecureStringFromMemory` | Already in FFU.Core with proper patterns |

**Key insight:** The codebase already has robust credential management utilities. The security hardening work is primarily about ensuring consistent usage of existing patterns rather than building new capabilities.

## Common Pitfalls

### Pitfall 1: SecureString Does Not Provide Complete Memory Protection
**What goes wrong:** Assuming SecureString makes passwords invisible in memory dumps
**Why it happens:** SecureString encrypts data but doesn't prevent temporary plaintext exposure during conversion
**How to avoid:**
- Keep plaintext lifetime as short as possible
- Clear variables immediately after use
- Call `[GC]::Collect()` after clearing sensitive data
- Understand SecureString protects against casual inspection, not forensic analysis
**Warning signs:** Long-lived plaintext variables, missing cleanup in finally blocks

### Pitfall 2: Token Caching Without Proper Security
**What goes wrong:** Caching tokens in plaintext files or world-readable locations
**Why it happens:** Convenience over security, forgetting tokens are credentials
**How to avoid:**
- Use DPAPI encryption via Export-Clixml
- Apply NTFS encryption for additional layer
- Store in user-specific location
- Include explicit expiry time
**Warning signs:** Tokens stored as plain JSON, tokens in temp directories, no expiry mechanism

### Pitfall 3: Hash Verification as Security Theater
**What goes wrong:** Implementing hash verification that can be easily bypassed
**Why it happens:** Verifying against hashes stored alongside scripts (attacker modifies both)
**How to avoid:**
- Store hash manifest separately from scripts
- Consider embedding known-good hashes in code for critical scripts
- Log verification failures prominently
- Consider making verification non-bypassable for production builds
**Warning signs:** Hash manifest in same directory as scripts, silent failures, optional verification

### Pitfall 4: CaptureFFU.ps1 Credential Exposure
**What goes wrong:** WinPE capture script contains plaintext credentials that persist
**Why it happens:** WinPE environment cannot use DPAPI or interactive credential prompts
**How to avoid:**
- This is a known, unavoidable limitation
- Mitigate with: short-lived user accounts, account expiry, post-capture sanitization
- Remove-SensitiveCaptureMedia already exists - ensure it's always called
- Consider generating unique password per build
**Warning signs:** Reusing same password across builds, not calling cleanup, backup files persisting

### Pitfall 5: Browser Automation Race Conditions
**What goes wrong:** Lenovo PSREF token retrieval fails intermittently
**Why it happens:** JavaScript execution timing, page load delays, token not yet in localStorage
**How to avoid:**
- Existing code already has retry loops - maintain them
- Cache successful tokens to reduce retrieval frequency
- Add fallback to catalogv2.xml for models it supports
- Consider increasing poll intervals if failures persist
**Warning signs:** Intermittent token retrieval failures, excessive browser process spawning

## Code Examples

Verified patterns from existing codebase:

### Secure Password Generation (Existing - FFU.Core.psm1)
```powershell
# Source: FFU.Core.psm1 lines 1580-1700
function New-SecureRandomPassword {
    param(
        [int]$Length = 32,
        [bool]$IncludeSpecialChars = $true
    )

    $securePassword = New-Object System.Security.SecureString
    $rng = [System.Security.Cryptography.RNGCryptoServiceProvider]::new()

    try {
        # Character sets
        $lowercase = 'abcdefghijklmnopqrstuvwxyz'
        $uppercase = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
        $digits = '0123456789'
        $special = '!@#$%^&*-_'

        $allChars = $lowercase + $uppercase + $digits
        if ($IncludeSpecialChars) { $allChars += $special }

        $bytes = [byte[]]::new(1)
        for ($i = 0; $i -lt $Length; $i++) {
            do {
                $rng.GetBytes($bytes)
                $randomIndex = $bytes[0] % $allChars.Length
            } while ($bytes[0] -ge (256 - (256 % $allChars.Length)))

            $securePassword.AppendChar($allChars[$randomIndex])
        }

        $securePassword.MakeReadOnly()
        return $securePassword
    }
    finally {
        $rng.Dispose()
    }
}
```

### Proper BSTR Cleanup (Existing - FFU.VM.psm1)
```powershell
# Source: FFU.VM.psm1 lines 114-147
$BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
try {
    $plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
    # Use $plainPassword here
}
finally {
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
    if ($plainPassword) {
        $plainPassword = $null
    }
}
```

### Hash Manifest Generation (New Pattern)
```powershell
function New-OrchestrationHashManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$OrchestrationPath,

        [Parameter(Mandatory = $true)]
        [string]$ManifestPath
    )

    $scripts = Get-ChildItem -Path $OrchestrationPath -Filter "*.ps1" -File
    $manifest = @{
        generated = (Get-Date).ToString('o')
        algorithm = 'SHA256'
        scripts = @{}
    }

    foreach ($script in $scripts) {
        $hash = (Get-FileHash -Path $script.FullName -Algorithm SHA256).Hash
        $manifest.scripts[$script.Name] = $hash
        WriteLog "Hashed $($script.Name): $hash"
    }

    $manifest | ConvertTo-Json -Depth 3 | Set-Content -Path $ManifestPath -Encoding UTF8
    WriteLog "Generated manifest at $ManifestPath with $($scripts.Count) scripts"
}
```

### Token Cache with Expiry (New Pattern)
```powershell
function Get-LenovoPSREFTokenCached {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FFUDevelopmentPath,

        [int]$CacheValidMinutes = 60,

        [switch]$ForceRefresh
    )

    $cacheDir = Join-Path $FFUDevelopmentPath ".security\token-cache"
    $cachePath = Join-Path $cacheDir "lenovo-psref.xml"

    # Check cache first (unless force refresh)
    if (-not $ForceRefresh -and (Test-Path $cachePath)) {
        try {
            $cached = Import-Clixml -Path $cachePath
            $age = (Get-Date) - [datetime]$cached.Timestamp

            if ($age.TotalMinutes -lt $CacheValidMinutes) {
                WriteLog "Using cached Lenovo PSREF token (age: $([int]$age.TotalMinutes) minutes)"
                return $cached.Token
            }
            WriteLog "Cached token expired, refreshing..."
        }
        catch {
            WriteLog "Cache read failed, refreshing: $($_.Exception.Message)"
        }
    }

    # Retrieve fresh token using existing browser automation
    WriteLog "Retrieving fresh Lenovo PSREF token via browser automation..."
    $token = Get-LenovoPSREFToken  # Existing function

    # Cache the token
    if (-not [string]::IsNullOrWhiteSpace($token)) {
        if (-not (Test-Path $cacheDir)) {
            New-Item -Path $cacheDir -ItemType Directory -Force | Out-Null
        }

        @{
            Token = $token
            Timestamp = (Get-Date).ToString('o')
        } | Export-Clixml -Path $cachePath

        # Apply NTFS encryption for additional security
        try {
            (Get-Item $cachePath).Encrypt()
        }
        catch {
            WriteLog "NTFS encryption not available: $($_.Exception.Message)"
        }

        WriteLog "Cached Lenovo PSREF token for $CacheValidMinutes minutes"
    }

    return $token
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Plaintext password variables | SecureString throughout | PowerShell 2.0+ | Encrypted in-memory storage |
| MD5/SHA1 for integrity | SHA256 minimum | ~2015 | Collision resistance |
| Manual random generation | RNGCryptoServiceProvider | .NET 2.0+ | True cryptographic randomness |
| Hardcoded tokens | Cached with expiry | Best practice | Reduced exposure window |
| No script verification | Hash verification before execution | Modern CI/CD | Prevent tampering |

**Deprecated/outdated:**
- MD5 for integrity verification: Use SHA256+
- ConvertFrom-SecureString with -Key for cross-machine portability: Weak encryption
- Storing credentials in .ps1 files: Use separate encrypted storage

## Open Questions

Things that couldn't be fully resolved:

1. **Lenovo PSREF API Direct Access**
   - What we know: Browser automation is currently required because token is JavaScript-generated
   - What's unclear: Whether Lenovo offers official API access with proper authentication
   - Recommendation: Proceed with token caching to minimize browser automation calls; document as known limitation

2. **WinPE Credential Handling**
   - What we know: WinPE cannot use DPAPI or interactive prompts; plaintext is unavoidable in CaptureFFU.ps1
   - What's unclear: Whether there's a way to use certificate-based auth or machine account instead
   - Recommendation: Focus on minimizing exposure time and ensuring cleanup

3. **Hash Manifest Trust Anchor**
   - What we know: Storing hashes alongside scripts allows attacker to modify both
   - What's unclear: Best balance between security and maintainability
   - Recommendation: Store manifest in .security/ folder separate from scripts; consider embedding critical hashes in code

## Sources

### Primary (HIGH confidence)
- PowerShell Practice and Style Guide - Security: https://poshcode.gitbook.io/powershell-practice-and-style/best-practices/security
- Microsoft Learn - Working with SecureStrings: https://learn.microsoft.com/en-us/archive/technet-wiki/4546.working-with-passwords-secure-strings-and-credentials-in-windows-powershell
- FFU.Core.psm1 - Existing secure credential functions (lines 1578-1800)
- FFU.VM.psm1 - Existing SecureString handling patterns (lines 73-270)

### Secondary (MEDIUM confidence)
- SecureString Discussion: https://github.com/PowerShell/PowerShell/discussions/24772
- File Hash Verification: https://www.ninjaone.com/script-hub/file-hash-verification-powershell/
- Code Integrity Guide 2025: https://dualite.dev/blog/code-integrity-guide
- Lenovo XClarity REST API Auth: https://pubs.lenovo.com/lxca_scripting/rest_apis_authorization_and_authentication

### Tertiary (LOW confidence)
- Lenovo PSREF token behavior: Observed through codebase analysis (no official documentation found)
- Token expiry period: Estimated 60 minutes based on typical session token lifetimes

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - Uses native PowerShell/.NET capabilities, well-documented
- Architecture: HIGH - Patterns derived from existing codebase and industry best practices
- Pitfalls: HIGH - Based on real security vulnerabilities and Microsoft guidance
- Lenovo PSREF specifics: MEDIUM - No official API documentation, based on reverse engineering

**Research date:** 2026-01-19
**Valid until:** 2026-02-19 (30 days - stable security patterns)

## Implementation Considerations

### SEC-01: Lenovo PSREF Token Handling
- **Current state:** Browser automation retrieves token on every request
- **Improvement:** Add caching layer with 60-minute expiry
- **Files affected:** `FFU.Common/FFU.Common.Drivers.psm1`, `FFUUI.Core/FFUUI.Core.Drivers.Lenovo.psm1`
- **Risk:** LOW - Additive change, existing code is fallback

### SEC-02: SecureString Throughout
- **Current state:** Already excellent - New-SecureRandomPassword, proper BSTR cleanup
- **Gap:** Verify no plaintext password variables persist longer than necessary
- **Files affected:** `BuildFFUVM.ps1`, `Modules/FFU.VM/FFU.VM.psm1`
- **Risk:** LOW - Mostly verification and minor cleanup

### SEC-03: Script Integrity Verification
- **Current state:** No verification - scripts executed without checks
- **Improvement:** Add Test-ScriptIntegrity function, generate hash manifest, verify before execution
- **Files affected:** `Apps/Orchestration/Orchestrator.ps1`, new FFU.Core functions
- **Risk:** MEDIUM - Need careful handling of manifest updates during development
