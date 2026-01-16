# Coding Conventions

**Analysis Date:** 2026-01-16

## Naming Patterns

**Files:**
- PowerShell modules: `FFU.<ModuleName>.psm1` (e.g., `FFU.Core.psm1`, `FFU.Imaging.psm1`)
- Module manifests: `FFU.<ModuleName>.psd1` (matching .psm1 name)
- Test files: `FFU.<ModuleName>.Tests.ps1` or `<Feature>.Tests.ps1`
- Scripts: PascalCase with verb-noun style (e.g., `BuildFFUVM.ps1`, `CaptureFFU.ps1`)

**Functions:**
- Follow PowerShell approved verbs strictly (Get-, Set-, New-, Remove-, Test-, Invoke-, etc.)
- Use `-FFU` prefix for project-specific functions: `Test-FFUConfiguration`, `Invoke-FFUPreflight`
- PascalCase for function names: `Get-ShortenedWindowsSKU`, `New-VMConfiguration`
- Deprecated functions renamed with aliases for backward compatibility (see v1.0.11 pattern in `FFU.Core.psd1`)

**Variables:**
- camelCase for local variables: `$modulePath`, `$requiredGB`, `$cleanupRan`
- PascalCase for parameters: `-WindowsSKU`, `-ConfigFile`, `-FFUDevelopmentPath`
- Script-scope variables prefixed with `$script:`: `$script:HypervisorModule`
- Constants class: `[FFUConstants]::CONSTANT_NAME` (SCREAMING_SNAKE_CASE)

**Types/Classes:**
- PascalCase for class names: `FFUConstants`, `VMConfiguration`, `VMInfo`
- Interface-style: `IHypervisorProvider` (prefix with I)
- Enum values: PascalCase in enums (e.g., `VMState::Running`)

## Code Style

**Formatting:**
- No dedicated formatting tool (PSScriptAnalyzer used for style)
- 4-space indentation (PowerShell standard)
- One True Brace Style (OTBS): opening brace on same line as statement
- Line length: implicit 115 char recommendation per CLAUDE.md

**Linting:**
- PSScriptAnalyzer for code quality
- Run: `Invoke-ScriptAnalyzer -Path .\FFUDevelopment -Recurse -ReportSummary`
- Approved verbs enforced (renamed 3 functions in v1.0.11 with backward-compat aliases)

**Example - Function Structure:**
```powershell
function Get-ShortenedWindowsSKU {
    <#
    .SYNOPSIS
    Converts Windows SKU names to shortened versions for FFU file names

    .DESCRIPTION
    Maps full Windows edition names to shortened abbreviations for use in FFU file naming.
    Handles 30+ known Windows SKU variations.

    .PARAMETER WindowsSKU
    Full Windows SKU/edition name (e.g., "Pro", "Enterprise", "Education")

    .EXAMPLE
    Get-ShortenedWindowsSKU -WindowsSKU "Professional"
    Returns: "Pro"

    .NOTES
    Enhanced with parameter validation and default case to prevent empty return values.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$WindowsSKU
    )

    # Implementation...
}
```

## Import Organization

**Order in Module Files (.psm1):**
1. Module header comment block with .SYNOPSIS, .DESCRIPTION, .NOTES
2. `#Requires` statements (version, modules, admin)
3. `using module` statements for class imports
4. `Import-Module` statements for dependencies
5. Helper/private functions
6. Public exported functions

**Example from `FFU.Imaging.psm1`:**
```powershell
#Requires -Version 7.0
#Requires -RunAsAdministrator

# Import constants module
using module ..\FFU.Constants\FFU.Constants.psm1

# Import dependencies
Import-Module "$PSScriptRoot\..\FFU.Core" -Force
```

**Path Aliases:**
- `$PSScriptRoot` - current module directory
- Relative paths from module: `"$PSScriptRoot\..\FFU.Core"`
- Join-Path for cross-platform: `Join-Path $ProjectRoot 'FFUDevelopment\Modules'`

## Error Handling

**Patterns:**

1. **Standard try/catch with logging:**
```powershell
try {
    $dismInfo = Get-WindowsEdition -Path $MountPath -ErrorAction Stop
    WriteLog "DISM service initialized. Image edition: $($dismInfo.Edition)"
    $true
}
catch {
    WriteLog "WARNING: DISM service initialization check failed: $($_.Exception.Message)"
    # Recovery logic...
}
```

2. **Invoke-WithErrorHandling wrapper (from FFU.Core):**
```powershell
$result = Invoke-WithErrorHandling -OperationName 'TestOp' -ScriptBlock {
    return 'Success'
}
```

3. **Invoke-WithCleanup for guaranteed cleanup:**
```powershell
Invoke-WithCleanup -ScriptBlock {
    # Main operation
} -CleanupBlock {
    # Always runs, even on failure
}
```

4. **Test-ExternalCommandSuccess for external tools:**
- Validates exit codes with special handling for robocopy (success codes 0-7)
- Use for DISM, diskpart, robocopy operations

**Error Action Preferences:**
- Use `-ErrorAction Stop` when errors should halt execution
- Use `-ErrorAction SilentlyContinue` for optional/expected failures
- Never suppress errors silently in production code paths

## Logging

**Framework:** Custom `WriteLog` function (not standard logger)

**Patterns:**
```powershell
WriteLog "DISM service initialized. Image edition: $($dismInfo.Edition)"
WriteLog "WARNING: DISM service initialization check failed: $($_.Exception.Message)"
WriteLog "ERROR: DISM service failed to initialize after retry"
WriteLog "[VAR]$variableName`: $variableValue"  # Variable logging format
```

**When to Log:**
- Function entry for key operations
- Success confirmations
- Warning conditions (with WARNING: prefix)
- Error conditions (with ERROR: prefix)
- Variable state during diagnostics (with [VAR] prefix)

**Safe Logging Pattern (for modules that may not have WriteLog):**
```powershell
try {
    WriteLog $message
}
catch {
    Write-Verbose $message
}
```

## Comments

**When to Comment:**
- Complex logic that isn't self-documenting
- Workarounds with reasoning (reference issue numbers)
- Default case explanations in switch statements
- Magic numbers/values with rationale

**JSDoc/PowerShell Comment-Based Help:**
- REQUIRED on all exported functions
- Include: .SYNOPSIS, .DESCRIPTION, .PARAMETER, .EXAMPLE, .OUTPUTS, .NOTES
- .NOTES section documents version changes and renames

**Example:**
```powershell
# DEFAULT CASE - Return original SKU if no match found
# This prevents empty string returns and allows builds to continue with unknown SKUs
default {
    Write-Warning "Unknown Windows SKU '$WindowsSKU' - using original name in FFU filename"
    $WindowsSKU
}
```

## Function Design

**Size:**
- Functions should do one thing well
- Extract helper functions for repeated logic
- Large modules split into logical sections with region markers

**Parameters:**
- Use `[CmdletBinding()]` on ALL functions
- Explicit parameter types: `[string]`, `[int]`, `[bool]`, `[hashtable]`
- Use `[Parameter(Mandatory = $true)]` for required params
- Provide defaults for optional parameters
- Use validation attributes: `[ValidateNotNullOrEmpty()]`, `[ValidateSet()]`, `[ValidateRange()]`, `[ValidateScript()]`, `[ValidatePattern()]`

**Common Validation Patterns:**
```powershell
[ValidateSet('x64', 'arm64')]
[ValidateSet(10, 11)]
[ValidateRange(1, 999)]
[ValidateScript({ Test-Path $_ -PathType Leaf })]
[ValidatePattern('^[A-Z]$')]
```

**Return Values:**
- Use `[OutputType([typename])]` attribute
- Return explicit types: `[bool]`, `[string]`, `[PSCustomObject]`, `[hashtable]`
- For void functions: `[OutputType([void])]`
- Return `$true`/`$false` for success/failure, not `$null`

## Module Design

**Exports:**
- Explicit `FunctionsToExport` array in .psd1 (never use wildcards)
- Empty arrays for unused exports: `CmdletsToExport = @()`, `VariablesToExport = @()`
- Backward compatibility aliases in `AliasesToExport`

**Barrel Files:**
- Each module has one .psm1 file that exports all public functions
- No index/barrel pattern - all functions in single module file or using `Export-ModuleMember`

**RequiredModules Pattern:**
```powershell
RequiredModules = @(
    @{ModuleName = 'FFU.Core'; ModuleVersion = '1.0.0'}
)
```

**Module Metadata in .psd1:**
- Version: SemVer (MAJOR.MINOR.PATCH)
- GUID: unique per module
- ReleaseNotes: detailed changelog in PSData section
- Tags for discoverability

## Constants Usage

**Access Pattern:**
```powershell
# Import via using statement
using module ..\FFU.Constants\FFU.Constants.psm1

# Access static methods for paths
$basePath = [FFUConstants]::GetBasePath()
$vmDir = [FFUConstants]::GetDefaultVMDir()

# Access constants
Start-Sleep -Seconds ([FFUConstants]::DISM_SERVICE_WAIT)
```

**Never hardcode:**
- File paths (use `[FFUConstants]::GetDefaultWorkingDir()`)
- Timeout values
- Retry counts
- Magic numbers

---

*Convention analysis: 2026-01-16*
