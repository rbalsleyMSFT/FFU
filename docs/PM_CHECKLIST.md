# FFUBuilder Project Management Checklist

This checklist must be followed for every code modification in the FFUBuilder project.

## Pre-Implementation Checklist

Before starting any code changes, verify:

- [ ] **Task Understanding**
  - [ ] Clear understanding of what needs to be changed
  - [ ] Identified all affected modules/files
  - [ ] Noted current version numbers of affected modules

- [ ] **Planning**
  - [ ] Determined which subagent(s) to use:
    - `powershell-architect` - For code implementation
    - `pester-test-developer` - For test creation
    - `intune-troubleshooter` - For Intune issues
    - `autopilot-deployment-expert` - For Autopilot issues
  - [ ] Identified if new cleanup registrations are needed
  - [ ] Identified if error handling patterns apply

## During Implementation Checklist

While making changes, ensure:

- [ ] **Code Quality**
  - [ ] Using try/catch with specific exception types (not just generic catch)
  - [ ] Adding -ErrorAction Stop to critical cmdlets
  - [ ] Following existing code patterns in the module
  - [ ] Using WriteLog for all significant operations

- [ ] **Resource Management**
  - [ ] Register-VMCleanup for new VM operations
  - [ ] Register-VHDXCleanup for new VHDX mounts
  - [ ] Register-DISMMountCleanup for new DISM mounts
  - [ ] Register-ISOCleanup for new ISO mounts
  - [ ] Register-TempFileCleanup for new temp files
  - [ ] Register-NetworkShareCleanup for new shares
  - [ ] Register-UserAccountCleanup for new user accounts

- [ ] **Error Handling Patterns**
  ```powershell
  try {
      SomeOperation -ErrorAction Stop
      WriteLog "Operation succeeded"
  }
  catch [Specific.Exception.Type] {
      WriteLog "Specific error: $($_.Exception.Message)"
      throw "User-friendly error message"
  }
  catch {
      WriteLog "Unexpected error: $($_.Exception.Message)"
      throw
  }
  ```

## Post-Implementation Checklist

After completing code changes, verify:

- [ ] **Version Management**
  - [ ] Updated ModuleVersion in affected .psd1 file(s)
  - [ ] Added release notes to ReleaseNotes in .psd1 file(s)
  - [ ] Version follows semantic versioning (MAJOR.MINOR.BUILD)

- [ ] **Testing**
  - [ ] Created Pester tests for new functionality
  - [ ] Updated existing tests if behavior changed
  - [ ] All tests pass: `Invoke-Pester -Path "Tests\Unit\*.Tests.ps1"`
  - [ ] Test file follows naming: `ModuleName.FeatureName.Tests.ps1`

- [ ] **Documentation**
  - [ ] CLAUDE.md updated if architecture/patterns changed
  - [ ] Release notes describe the change clearly
  - [ ] Any new functions have proper comment-based help

- [ ] **Final Verification**
  - [ ] Module imports without errors
  - [ ] No PSScriptAnalyzer warnings on changed code
  - [ ] Changes work as expected when tested manually

## Module Version Locations

| Module | Manifest Path |
|--------|---------------|
| FFU.Core | `Modules\FFU.Core\FFU.Core.psd1` |
| FFU.VM | `Modules\FFU.VM\FFU.VM.psd1` |
| FFU.Updates | `Modules\FFU.Updates\FFU.Updates.psd1` |
| FFU.Drivers | `Modules\FFU.Drivers\FFU.Drivers.psd1` |
| FFU.Apps | `Modules\FFU.Apps\FFU.Apps.psd1` |
| FFU.Imaging | `Modules\FFU.Imaging\FFU.Imaging.psd1` |
| FFU.Media | `Modules\FFU.Media\FFU.Media.psd1` |
| FFU.ADK | `Modules\FFU.ADK\FFU.ADK.psd1` |
| FFU.Constants | `Modules\FFU.Constants\FFU.Constants.psd1` |
| FFUUI.Core | `FFUUI.Core\FFUUI.Core.psd1` |
| FFU.Common | `FFU.Common\FFU.Common.psd1` |
| FFU.Common.Logging | `FFU.Common\FFU.Common.Logging.psd1` |

## Test File Locations

| Category | Path |
|----------|------|
| Unit Tests | `Tests\Unit\*.Tests.ps1` |
| Integration Tests | `Tests\Integration\*.Tests.ps1` |
| Module Tests | `Tests\Modules\*.ps1` |

## Common Mistakes to Avoid

1. **Forgetting version updates** - Always update .psd1 ModuleVersion
2. **Missing release notes** - Always add ReleaseNotes entry
3. **No tests** - Always create Pester tests for changes
4. **Generic catch blocks** - Catch specific exception types first
5. **Missing -ErrorAction Stop** - Critical cmdlets need this
6. **No cleanup registration** - Resources need cleanup on failure
7. **Not running tests** - Always run full test suite before completing

## Quick Reference Commands

```powershell
# Run all unit tests
Invoke-Pester -Path "C:\claude\FFUBuilder\Tests\Unit" -Output Detailed

# Run specific module tests
Invoke-Pester -Path "C:\claude\FFUBuilder\Tests\Unit\FFU.VM*.Tests.ps1"

# Check module version
(Import-PowerShellDataFile "Modules\FFU.VM\FFU.VM.psd1").ModuleVersion

# Verify module imports
Import-Module ".\Modules\FFU.VM" -Force -Verbose
```
