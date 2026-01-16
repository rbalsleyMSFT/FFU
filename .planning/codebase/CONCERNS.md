# Codebase Concerns

**Analysis Date:** 2026-01-16

## Tech Debt

**Deprecated Static Path Properties:**
- Issue: `FFU.Constants.psm1` contains deprecated static path properties (lines 256-277) alongside newer dynamic methods
- Files: `FFUDevelopment/Modules/FFU.Constants/FFU.Constants.psm1`
- Impact: Dual patterns create confusion; developers may use old static properties instead of dynamic `Get*Dir()` methods
- Fix approach: Remove deprecated properties in next major version; update all callers to use `GetDefaultWorkingDir()`, `GetDefaultVMDir()`, etc.

**Hardcoded Param Block Defaults:**
- Issue: `BuildFFUVM.ps1` param block (lines 8-18) uses hardcoded values that must manually sync with FFU.Constants
- Files: `FFUDevelopment/BuildFFUVM.ps1`
- Impact: If FFU.Constants values change, param defaults won't match; requires manual synchronization
- Fix approach: Document the coupling clearly; consider refactoring to validate at runtime rather than compile-time defaults

**Legacy Log Stream Reader:**
- Issue: UI maintains deprecated `logStreamReader` field (line 67) marked "Legacy: kept for backward compatibility"
- Files: `FFUDevelopment/BuildFFUVM_UI.ps1`
- Impact: Dead code path; adds complexity to log monitoring logic
- Fix approach: Remove legacy stream reader after verifying FFU.Messaging queue is stable in production

**Excessive `-ErrorAction SilentlyContinue` Usage:**
- Issue: 336 occurrences across 27 modules suppress errors that may indicate real problems
- Files: All modules in `FFUDevelopment/Modules/`, `FFUDevelopment/FFU.Common/`, `FFUDevelopment/FFUUI.Core/`
- Impact: Silent failures make debugging difficult; errors go undetected in production
- Fix approach: Audit each usage; replace with proper try/catch where error handling is needed; remove where errors should propagate

**Write-Host Usage in Modules:**
- Issue: 50+ occurrences of `Write-Host` in production modules instead of proper output streams
- Files: `FFUDevelopment/Modules/FFU.BuildTest/FFU.BuildTest.psm1`, `FFUDevelopment/FFU.Common/*.psm1`
- Impact: Cannot be captured/redirected; breaks PowerShell pipeline conventions; pollutes console
- Fix approach: Replace with `Write-Output`, `Write-Verbose`, or use `WriteLog` function consistently

## Known Bugs

**Issue #327: Corporate Proxy Failures:**
- Symptoms: Driver downloads fail with network errors behind Netskope/zScaler corporate proxies
- Files: `FFUDevelopment/FFU.Common/FFU.Common.Download.psm1`, `FFUDevelopment/FFU.Common/FFU.Common.Drivers.psm1`
- Trigger: Running FFU Builder on corporate network with SSL inspection
- Workaround: Manually configure proxy via environment variables (`$env:HTTP_PROXY`, `$env:HTTPS_PROXY`)

**Issue #301: Unattend.xml Extraction from MSU:**
- Symptoms: DISM fails to apply unattend.xml from update packages
- Files: `FFUDevelopment/Modules/FFU.Updates/FFU.Updates.psm1`
- Trigger: Extracting unattend files from Windows Update MSU packages
- Workaround: Use `Get-UnattendFromMSU` function for robust extraction with validation

**Issue #298: OS Partition Size Limitations:**
- Symptoms: OS partition doesn't expand when injecting large driver sets
- Files: `FFUDevelopment/Modules/FFU.Imaging/FFU.Imaging.psm1`
- Trigger: Injecting >5GB of drivers into FFU
- Workaround: Call `Expand-FFUPartition` before driver injection to resize VHDX dynamically

**Dell Chipset Driver Extraction Hang:**
- Symptoms: Build hangs indefinitely during Dell driver extraction
- Files: `FFUDevelopment/FFUUI.Core/FFUUI.Core.Drivers.Dell.psm1` (lines 556-579)
- Trigger: Using `-Wait $true` for Dell chipset driver installers
- Workaround: Always use `-Wait:$false` for Dell driver extraction; implemented via Start-Sleep polling

## Security Considerations

**Lenovo PSREF Token Retrieval via Browser Automation:**
- Risk: Edge DevTools remote debugging (port exposure, temp profile creation) to scrape auth tokens
- Files: `FFUDevelopment/FFU.Common/FFU.Common.Drivers.psm1` (lines 270-600)
- Current mitigation: Uses random port; temp profile cleaned up in finally block
- Recommendations: Implement proper OAuth flow; consider caching token securely; add rate limiting

**Temporary User Account Expiry:**
- Risk: FFU capture user account created with plaintext password in CaptureFFU.ps1
- Files: `FFUDevelopment/Modules/FFU.VM/FFU.VM.psm1` (lines 1238-1266)
- Current mitigation: Account expires after 4 hours; password sanitized post-capture (line 4629-4630 in BuildFFUVM.ps1)
- Recommendations: Use SecureString throughout; implement immediate account cleanup on build completion

**Script Execution in VM:**
- Risk: Apps orchestration scripts run with elevated privileges inside build VM
- Files: `FFUDevelopment/Apps/Orchestration/Invoke-AppsScript.ps1`, `Install-Win32Apps.ps1`, `Install-StoreApps.ps1`
- Current mitigation: VM is ephemeral; isolated from host network
- Recommendations: Add integrity verification for script files before execution

## Performance Bottlenecks

**Sequential VHD Flush Operations:**
- Problem: Triple-pass flush before VHD dismount adds 1.5+ seconds delay
- Files: `FFUDevelopment/Modules/FFU.Imaging/FFU.Imaging.psm1` (lines 1137-1179)
- Cause: Conservative approach to ensure data integrity after unattend.xml writes
- Improvement path: Reduce to single flush with verification; use async I/O completion events

**Start-Sleep Polling Pattern:**
- Problem: 56+ instances of `Start-Sleep` for synchronization, causing unnecessary delays
- Files: Throughout codebase - `BuildFFUVM.ps1`, `FFU.Common.*.psm1`, `FFU.*.psm1`
- Cause: Polling-based synchronization instead of event-driven
- Improvement path: Replace with `Wait-Process`, `WaitForExit()`, event-based callbacks, or async/await patterns

**Large Module File Sizes:**
- Problem: Several modules exceed 1000 lines, impacting load time
- Files:
  - `FFUDevelopment/BuildFFUVM.ps1` (4677 lines)
  - `FFUDevelopment/Modules/FFU.Core/FFU.Core.psm1` (2674 lines)
  - `FFUDevelopment/Modules/FFU.Preflight/FFU.Preflight.psm1` (2650 lines)
  - `FFUDevelopment/Modules/FFU.Imaging/FFU.Imaging.psm1` (2639 lines)
- Cause: Organic growth without further decomposition
- Improvement path: Extract related functions into sub-modules; lazy-load rarely-used functions

## Fragile Areas

**Module Dependency Chain:**
- Files: All modules in `FFUDevelopment/Modules/`
- Why fragile: Deep dependency chain (FFU.Media -> FFU.ADK -> FFU.Core -> FFU.Constants) causes cascading failures if any module fails to load
- Safe modification: Always test module imports in clean session; run `Test-UIIntegration.ps1` after changes
- Test coverage: `Tests/Unit/Module.Dependencies.Tests.ps1` (117 tests), but no integration test for load failures

**ThreadJob/Background Job Module Loading:**
- Files: `FFUDevelopment/BuildFFUVM_UI.ps1` (lines 602-700), `FFUDevelopment/BuildFFUVM.ps1` (lines 626-637)
- Why fragile: PSModulePath manipulation required; working directory must be set correctly; `using module` statements fail with relative paths
- Safe modification: Always test changes via UI launch (not direct script execution); verify with `BuildFFUVM.ModuleLoading.Tests.ps1`
- Test coverage: 25 tests, but real-world ThreadJob behavior differs from mocked tests

**WIMMount Service/Filter Driver:**
- Files: `FFUDevelopment/Modules/FFU.Preflight/FFU.Preflight.psm1` (Test-FFUWimMount), `FFUDevelopment/Modules/FFU.Media/FFU.Media.psm1`
- Why fragile: ADK updates can corrupt WIMMount filter driver registration; Windows updates can affect service
- Safe modification: Run full pre-flight validation before testing WIM operations; check `fltmc filters` output
- Test coverage: Multiple test files exist but cannot verify actual filter driver state in CI

**Unattend.xml Path Resolution:**
- Files: `FFUDevelopment/BuildFFUVM.ps1` (lines 3949-3971)
- Why fragile: Drive letters can change during VHD mount/unmount; requires re-querying disk state
- Safe modification: Always refresh drive letter from disk state before file operations; add DEBUG logging
- Test coverage: Limited - real-world VHD operations needed

## Scaling Limits

**USB Drive Processing:**
- Current capacity: Processes drives sequentially with no parallelization
- Limit: 4+ USB drives takes proportionally longer; no concurrent imaging
- Scaling path: Implement parallel imaging with `ForEach-Object -Parallel` for FFU application

**Driver Download Concurrency:**
- Current capacity: `FFU.Common.ParallelDownload.psm1` supports concurrent downloads
- Limit: Default thread count may overwhelm network connections on slow links
- Scaling path: Add adaptive throttling based on network speed detection

## Dependencies at Risk

**vmxtoolkit PowerShell Module:**
- Risk: Third-party module for VMware automation; not actively maintained
- Impact: VMware provider relies on vmxtoolkit for some operations
- Migration plan: Fall back to vmrun.exe direct commands; implement native VMX file manipulation

**Lenovo PSREF API:**
- Risk: Undocumented API; authentication mechanism uses scraped JWT token
- Impact: Any Lenovo site changes break driver catalog retrieval
- Migration plan: Implement fallback to catalogv2.xml (partial coverage); cache last-known-good catalog

**Windows ADK:**
- Risk: ADK updates have historically broken WIMMount filter driver
- Impact: Builds fail with 0x800704db errors after ADK updates
- Migration plan: Pre-flight validation detects issues; native DISM cmdlets used as fallback in ApplyFFU.ps1

## Missing Critical Features

**Build Cancellation:**
- Problem: No graceful cancellation of in-progress builds
- Blocks: User cannot abort long-running builds without killing PowerShell process

**Build Progress Persistence:**
- Problem: No checkpoint/resume capability for multi-hour builds
- Blocks: Network failure or system restart requires complete rebuild from scratch

**Configuration Migration:**
- Problem: No automated migration for config file format changes between versions
- Blocks: Users must manually update config files after major version upgrades

## Test Coverage Gaps

**Integration Tests:**
- What's not tested: Actual VM creation, driver injection, FFU capture
- Files: `FFUDevelopment/Modules/FFU.VM/FFU.VM.psm1`, `FFUDevelopment/Modules/FFU.Imaging/FFU.Imaging.psm1`
- Risk: Module functions pass unit tests but fail with real Hyper-V/VMware operations
- Priority: High - These are core operations

**UI Event Handler Testing:**
- What's not tested: WPF event handlers, UI state management
- Files: `FFUDevelopment/FFUUI.Core/FFUUI.Core.Handlers.psm1` (1073 lines with 0 test coverage)
- Risk: UI bugs go undetected; regressions in button handlers
- Priority: Medium - Manual testing catches most issues

**Error Recovery Paths:**
- What's not tested: Cleanup handlers, failure recovery, partial build state
- Files: `FFUDevelopment/Modules/FFU.Core/FFU.Core.psm1` (cleanup registration), `FFUDevelopment/Modules/FFU.VM/FFU.VM.psm1` (environment cleanup)
- Risk: Failed builds leave orphaned VMs, shares, or user accounts
- Priority: High - Impacts subsequent build attempts

**VMware Provider:**
- What's not tested: Real VMware Workstation operations (requires VMware installation)
- Files: `FFUDevelopment/Modules/FFU.Hypervisor/Providers/VMwareProvider.ps1` (956 lines)
- Risk: VMware-specific code paths untested in CI
- Priority: Medium - VMware support is new feature

---

*Concerns audit: 2026-01-16*
