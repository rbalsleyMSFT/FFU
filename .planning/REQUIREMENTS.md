# Requirements: FFU Builder Improvement Initiative

**Defined:** 2026-01-17
**Core Value:** Improve codebase quality, reliability, and maintainability

## v1 Requirements

Requirements for this improvement cycle. Derived from CONCERNS.md analysis.

### Tech Debt

- [x] **DEBT-01**: Remove deprecated static path properties from FFU.Constants (lines 256-277) ✓
- [x] **DEBT-02**: Audit -ErrorAction SilentlyContinue usage (254 occurrences - all appropriate for context) ✓
- [x] **DEBT-03**: Replace Write-Host with WriteLog/Write-Verbose in production modules (FFU.ADK, FFU.Core, FFU.Preflight) ✓
- [x] **DEBT-04**: Remove legacy logStreamReader field from BuildFFUVM_UI.ps1 ✓
- [x] **DEBT-05**: Document BuildFFUVM.ps1 param block coupling with FFU.Constants ✓

### Bug Fixes

- [x] **BUG-01**: Fix Issue #327 - Corporate proxy failures with Netskope/zScaler SSL inspection ✓
- [x] **BUG-02**: Fix Issue #301 - Unattend.xml extraction from MSU packages fails with DISM ✓
- [x] **BUG-03**: Fix Issue #298 - OS partition doesn't expand for large driver sets (>5GB) ✓
- [x] **BUG-04**: Fix Dell chipset driver extraction hang (FFUUI.Core.Drivers.Dell.psm1 lines 556-579) ✓

### Security

- [x] **SEC-01**: Improve Lenovo PSREF token handling - reduce browser automation exposure ✓
- [x] **SEC-02**: Use SecureString for temporary FFU capture user account password ✓
- [x] **SEC-03**: Add integrity verification for Apps orchestration scripts before execution ✓

### Performance

- [x] **PERF-01**: Optimize VHD flush operations - verified single-pass with Write-VolumeCache (~85% faster) ✓
- [x] **PERF-02**: Event-driven VM state monitoring for Hyper-V using CIM events (VMware keeps polling) ✓
- [x] **PERF-03**: Evaluate module decomposition for large files - DOCUMENTED (defer decomposition, see docs/MODULE_DECOMPOSITION.md) ✓

### Test Coverage

- [x] **TEST-01**: Add integration tests for VM creation (Hyper-V and VMware) ✓
- [x] **TEST-02**: Add integration tests for driver injection workflow ✓
- [x] **TEST-03**: Add integration tests for FFU capture process ✓
- [x] **TEST-04**: Add unit tests for UI event handlers (FFUUI.Core.Handlers.psm1 - 41 tests) ✓
- [x] **TEST-05**: Add tests for error recovery paths and cleanup handlers (56 tests) ✓
- [x] **TEST-06**: Add tests for VMware provider operations (32 tests) ✓

### Missing Features

- [x] **FEAT-01**: Implement graceful build cancellation with proper cleanup ✓
- [x] **FEAT-02**: Implement build progress checkpoint/resume capability ✓
- [ ] **FEAT-03**: Implement configuration file migration between versions

### Dependencies

- [ ] **DEP-01**: Implement vmrun.exe fallback for vmxtoolkit module failures
- [ ] **DEP-02**: Implement Lenovo catalog fallback using catalogv2.xml
- [ ] **DEP-03**: Enhance ADK WIMMount detection with automatic recovery

## v2 Requirements

Deferred to future cycle. Lower priority or higher complexity.

### Performance (Deferred)

- **PERF-04**: Implement parallel USB drive imaging with ForEach-Object -Parallel
- **PERF-05**: Add adaptive network throttling for driver downloads

### Test Coverage (Deferred)

- **TEST-07**: End-to-end build workflow tests (require actual VM infrastructure)
- **TEST-08**: Multi-driver-vendor combination tests

## Out of Scope

| Feature | Reason |
|---------|--------|
| Architecture rewrite | Risk too high; incremental improvement preferred |
| New OEM vendors | Current vendor coverage sufficient |
| Web/mobile UI | Desktop tool; WPF adequate |
| Real-time dashboard | Existing log monitoring works |
| Cloud deployment | On-premises tool by design |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| DEBT-01 | Phase 1 | Complete |
| DEBT-02 | Phase 1 | Complete |
| DEBT-03 | Phase 1 | Complete |
| DEBT-04 | Phase 1 | Complete |
| DEBT-05 | Phase 1 | Complete |
| BUG-01 | Phase 2 | Complete |
| BUG-02 | Phase 2 | Complete |
| BUG-03 | Phase 2 | Complete |
| BUG-04 | Phase 2 | Complete |
| SEC-01 | Phase 3 | Complete |
| SEC-02 | Phase 3 | Complete |
| SEC-03 | Phase 3 | Complete |
| PERF-01 | Phase 4 | Complete |
| PERF-02 | Phase 4 | Complete |
| PERF-03 | Phase 4 | Complete |
| TEST-01 | Phase 5 | Complete |
| TEST-02 | Phase 5 | Complete |
| TEST-03 | Phase 5 | Complete |
| TEST-04 | Phase 6 | Complete |
| TEST-05 | Phase 6 | Complete |
| TEST-06 | Phase 6 | Complete |
| FEAT-01 | Phase 7 | Complete |
| FEAT-02 | Phase 8 | Complete |
| FEAT-03 | Phase 9 | Pending |
| DEP-01 | Phase 10 | Pending |
| DEP-02 | Phase 10 | Pending |
| DEP-03 | Phase 10 | Pending |

**Coverage:**
- v1 requirements: 26 total
- Mapped to phases: 26
- Unmapped: 0 ✓

---
*Requirements defined: 2026-01-17*
*Last updated: 2026-01-19 - Phase 8 complete (FEAT-02)*
