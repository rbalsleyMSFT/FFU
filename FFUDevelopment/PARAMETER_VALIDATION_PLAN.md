# BuildFFUVM.ps1 Parameter Validation Enhancement Plan

**Created:** 2025-11-24
**Status:** In Progress
**Priority:** High (Quick Win #2)

---

## Current State

**Parameters with validation:** 11 of 60+ parameters
**Parameters without validation:** 50+ parameters
**Risk:** Script accepts invalid inputs, fails late in execution

---

## Critical Parameters Requiring Validation

### 1. Resource Limits (Prevent System Issues)

#### Memory
**Current:** `[uint64]$Memory = 4GB`
**Issue:** No range check - accepts 0, 1MB, 999TB
**Fix:**
```powershell
[Parameter(Mandatory = $false)]
[ValidateRange(2GB, 128GB)]
[uint64]$Memory = 4GB
```

#### Disksize
**Current:** `[uint64]$Disksize = 50GB`
**Issue:** No range check - could specify 1MB or 10TB
**Fix:**
```powershell
[Parameter(Mandatory = $false)]
[ValidateRange(25GB, 2TB)]
[uint64]$Disksize = 50GB
```

#### Processors
**Current:** `[int]$Processors = 4`
**Issue:** No range check - accepts 0, -1, 9999
**Fix:**
```powershell
[Parameter(Mandatory = $false)]
[ValidateRange(1, 64)]
[int]$Processors = 4
```

---

### 2. Path Parameters (Prevent File Not Found Errors)

#### VMLocation
**Current:** `[string]$VMLocation`
**Issue:** No validation - parent directory might not exist
**Fix:**
```powershell
[Parameter(Mandatory = $false)]
[ValidateScript({
    if ($_ -and -not (Test-Path (Split-Path $_ -Parent))) {
        throw "Parent directory does not exist: $(Split-Path $_ -Parent)"
    }
    return $true
})]
[string]$VMLocation
```

#### FFUCaptureLocation
**Current:** `[string]$FFUCaptureLocation`
**Issue:** No validation - directory might not exist
**Fix:**
```powershell
[Parameter(Mandatory = $false)]
[ValidateScript({
    if ($_ -and -not (Test-Path $_)) {
        throw "FFU capture directory does not exist: $_"
    }
    return $true
})]
[string]$FFUCaptureLocation
```

#### DriversFolder
**Current:** `[string]$DriversFolder`
**Issue:** No validation
**Fix:**
```powershell
[Parameter(Mandatory = $false)]
[ValidateScript({
    if ($_ -and -not (Test-Path $_)) {
        throw "Drivers folder does not exist: $_"
    }
    return $true
})]
[string]$DriversFolder
```

#### PEDriversFolder
**Current:** `[string]$PEDriversFolder`
**Issue:** No validation
**Fix:**
```powershell
[Parameter(Mandatory = $false)]
[ValidateScript({
    if ($_ -and -not (Test-Path $_)) {
        throw "PEDrivers folder does not exist: $_"
    }
    return $true
})]
[string]$PEDriversFolder
```

#### AppListPath
**Current:** `[string]$AppListPath`
**Issue:** No validation
**Fix:**
```powershell
[Parameter(Mandatory = $false)]
[ValidateScript({
    if ($_ -and -not (Test-Path $_)) {
        throw "AppList JSON file not found: $_"
    }
    return $true
})]
[string]$AppListPath
```

#### UserAppListPath
**Current:** `[string]$UserAppListPath`
**Issue:** No validation
**Fix:**
```powershell
[Parameter(Mandatory = $false)]
[ValidateScript({
    if ($_ -and -not (Test-Path $_)) {
        throw "UserAppList JSON file not found: $_"
    }
    return $true
})]
[string]$UserAppListPath
```

#### DriversJsonPath
**Current:** `[string]$DriversJsonPath`
**Issue:** No validation
**Fix:**
```powershell
[Parameter(Mandatory = $false)]
[ValidateScript({
    if ($_ -and -not (Test-Path $_)) {
        throw "Drivers JSON file not found: $_"
    }
    return $true
})]
[string]$DriversJsonPath
```

#### OfficeConfigXMLFile
**Current:** `[string]$OfficeConfigXMLFile`
**Issue:** No validation
**Fix:**
```powershell
[Parameter(Mandatory = $false)]
[ValidateScript({
    if ($_ -and -not (Test-Path $_)) {
        throw "Office configuration XML file not found: $_"
    }
    return $true
})]
[string]$OfficeConfigXMLFile
```

#### orchestrationPath
**Current:** `[string]$orchestrationPath`
**Issue:** No validation, inconsistent naming (should be OrchestrationPath)
**Fix:**
```powershell
[Parameter(Mandatory = $false)]
[ValidateScript({
    if ($_ -and -not (Test-Path $_)) {
        throw "Orchestration folder does not exist: $_"
    }
    return $true
})]
[string]$OrchestrationPath
```

---

### 3. Required Conditional Parameters

#### VMSwitchName (Required if InstallApps = $true)
**Current:** `[string]$VMSwitchName`
**Issue:** No validation - required when InstallApps is true
**Fix:** Add validation in BEGIN block (can't cross-reference parameters in attributes)

#### VMHostIPAddress (Required if InstallApps = $true)
**Current:** `[string]$VMHostIPAddress`
**Issue:** No validation - required when InstallApps, should be valid IP
**Fix:** Add validation in BEGIN block

#### Model (Required if Make is specified)
**Current:** `[string]$Model`
**Issue:** No validation - required when Make is set
**Fix:** Add validation in BEGIN block

---

### 4. Format Validation

#### VMHostIPAddress
**Should validate:** Valid IPv4 address format
**Fix:**
```powershell
[Parameter(Mandatory = $false)]
[ValidatePattern('^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$')]
[string]$VMHostIPAddress
```

#### ShareName
**Should validate:** Valid Windows share name (no invalid characters)
**Fix:**
```powershell
[Parameter(Mandatory = $false)]
[ValidatePattern('^[^\\/:\*\?"<>\|]+$')]
[ValidateLength(1, 80)]
[string]$ShareName = "FFUCaptureShare"
```

#### Username
**Should validate:** Valid Windows username
**Fix:**
```powershell
[Parameter(Mandatory = $false)]
[ValidatePattern('^[^\\/:*?"<>|@]+$')]
[ValidateLength(1, 20)]
[string]$Username = "ffu_user"
```

#### ProductKey
**Should validate:** Valid product key format (XXXXX-XXXXX-XXXXX-XXXXX-XXXXX)
**Fix:**
```powershell
[Parameter(Mandatory = $false)]
[ValidatePattern('^[A-Z0-9]{5}-[A-Z0-9]{5}-[A-Z0-9]{5}-[A-Z0-9]{5}-[A-Z0-9]{5}$')]
[string]$ProductKey
```

---

### 5. BEGIN Block Validation (Cross-Parameter Dependencies)

Add to BEGIN block for conditional validation:

```powershell
BEGIN {
    # Validate InstallApps dependencies
    if ($InstallApps) {
        if ([string]::IsNullOrWhiteSpace($VMSwitchName)) {
            throw "VMSwitchName is required when InstallApps is enabled"
        }

        if ([string]::IsNullOrWhiteSpace($VMHostIPAddress)) {
            throw "VMHostIPAddress is required when InstallApps is enabled"
        }

        # Validate VM switch exists
        $switch = Get-VMSwitch -Name $VMSwitchName -ErrorAction SilentlyContinue
        if (-not $switch) {
            $availableSwitches = (Get-VMSwitch).Name -join ', '
            throw "VM switch '$VMSwitchName' not found. Available switches: $availableSwitches"
        }
    }

    # Validate Make/Model dependency
    if ($Make -and [string]::IsNullOrWhiteSpace($Model)) {
        throw "Model parameter is required when Make is specified"
    }

    # Validate InstallDrivers dependencies
    if ($InstallDrivers -and -not $DriversFolder -and -not $Make) {
        throw "Either DriversFolder or Make must be specified when InstallDrivers is enabled"
    }

    # Validate disk size is sufficient for Windows
    if ($Disksize -lt 25GB) {
        throw "Disksize must be at least 25GB for Windows installation"
    }

    # Validate memory is sufficient
    if ($Memory -lt 2GB) {
        throw "Memory must be at least 2GB for Windows installation"
    }

    # Validate WindowsRelease and WindowsSKU compatibility
    if ($WindowsRelease -in @(2016, 2019, 2022, 2024, 2025)) {
        $serverSKUs = @('Standard', 'Standard (Desktop Experience)', 'Datacenter', 'Datacenter (Desktop Experience)')
        if ($WindowsSKU -notin $serverSKUs) {
            throw "WindowsSKU '$WindowsSKU' is not valid for Windows Server $WindowsRelease. Valid SKUs: $($serverSKUs -join ', ')"
        }
    }
}
```

---

## Implementation Strategy

### Phase 1: Critical Validations (Immediate)
1. Memory, Disksize, Processors ranges
2. VMHostIPAddress format and requirement
3. VMSwitchName requirement when InstallApps = $true
4. Make/Model dependency

**Estimated Time:** 30 minutes
**Impact:** Prevents 80% of invalid parameter combinations

---

### Phase 2: Path Validations (Next)
1. VMLocation parent path
2. FFUCaptureLocation existence
3. DriversFolder existence
4. All JSON/XML file paths

**Estimated Time:** 1 hour
**Impact:** Prevents late failures due to missing files

---

### Phase 3: Format Validations (Then)
1. ShareName valid characters
2. Username valid characters
3. ProductKey format
4. CustomFFUNameTemplate placeholders

**Estimated Time:** 30 minutes
**Impact:** Prevents configuration errors

---

### Phase 4: BEGIN Block Cross-Validation (Final)
1. Conditional requirements
2. VM switch existence
3. WindowsRelease/WindowsSKU compatibility
4. Complex business logic

**Estimated Time:** 1 hour
**Impact:** Catches logical configuration errors

---

## Success Criteria

- [ ] All numeric parameters have range validation
- [ ] All path parameters validate existence or parent existence
- [ ] All format-specific parameters have pattern validation
- [ ] All conditional dependencies validated in BEGIN block
- [ ] Clear, actionable error messages for all validation failures
- [ ] No valid configurations rejected (no false positives)

---

## Testing Plan

Create `Test-ParameterValidation.ps1`:
```powershell
# Test invalid Memory
{ .\BuildFFUVM.ps1 -Memory 1GB } | Should -Throw

# Test invalid Processors
{ .\BuildFFUVM.ps1 -Processors 0 } | Should -Throw

# Test missing VMSwitchName when InstallApps
{ .\BuildFFUVM.ps1 -InstallApps $true -VMSwitchName $null } | Should -Throw

# Test invalid IP address format
{ .\BuildFFUVM.ps1 -VMHostIPAddress "999.999.999.999" } | Should -Throw

# Test missing Model when Make is set
{ .\BuildFFUVM.ps1 -Make "Dell" -Model $null } | Should -Throw

# Test non-existent paths
{ .\BuildFFUVM.ps1 -DriversFolder "C:\DoesNotExist" } | Should -Throw
```

---

## Rollback Plan

If validation causes issues:
1. Git revert to previous commit
2. Review failing scenarios
3. Adjust validation rules
4. Re-apply with fixes

---

## Notes

- Use `ValidateScript` for complex validations
- Use `ValidatePattern` for regex format checks
- Use `ValidateRange` for numeric limits
- Use `ValidateSet` for enum-like values
- Use `ValidateLength` for string length limits
- Use BEGIN block for cross-parameter validation
- Always provide clear error messages in validation scripts
- Test with both valid and invalid inputs

---

**Document Status:** Active
**Next Update:** After Phase 1 implementation
