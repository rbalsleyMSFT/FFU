# Roadmap: FFU Builder Improvement Initiative

**Created:** 2026-01-17
**Phases:** 10
**Target:** Comprehensive codebase improvement

## Milestone: v1.8.0 - Codebase Health

### Phase 1: Tech Debt Cleanup ✓
**Goal:** Remove deprecated code, improve code quality patterns
**Requirements:** DEBT-01, DEBT-02, DEBT-03, DEBT-04, DEBT-05
**Plans:** 5 plans
**Status:** COMPLETE (2026-01-18)
**Success Criteria:**
1. ✓ FFU.Constants has no deprecated static path properties
2. ✓ -ErrorAction SilentlyContinue audited (254 usages all appropriate - best practices confirmed)
3. ✓ Write-Host replaced with proper output streams in production modules
4. ✓ Legacy logStreamReader removed from UI
5. ✓ Param block coupling documented in CLAUDE.md

Plans:
- [x] 01-01-PLAN.md - Document param coupling, remove logStreamReader (Wave 1)
- [x] 01-02-PLAN.md - Remove deprecated FFU.Constants properties (Wave 1)
- [x] 01-03-PLAN.md - Replace Write-Host in FFU.ADK and FFU.Core (Wave 2)
- [x] 01-04-PLAN.md - Replace Write-Host in FFU.Preflight (Wave 2)
- [x] 01-05-PLAN.md - Audit SilentlyContinue usage (Wave 2)

### Phase 2: Bug Fixes - Critical Issues ✓
**Goal:** Fix known bugs affecting corporate users and build reliability
**Requirements:** BUG-01, BUG-02, BUG-03, BUG-04
**Plans:** 4 plans
**Status:** COMPLETE (2026-01-19)

**Success Criteria:**
1. ✓ Proxy detection and configuration works with Netskope/zScaler
2. ✓ Unattend.xml extraction from MSU packages succeeds
3. ✓ OS partition auto-expands for driver sets >5GB
4. ✓ Dell chipset driver extraction completes without hang

Plans:
- [x] 02-01-PLAN.md - Fix Dell chipset driver extraction hang (BUG-04) (Wave 1)
- [x] 02-02-PLAN.md - Add SSL inspection detection for corporate proxies (BUG-01) (Wave 1)
- [x] 02-03-PLAN.md - Add VHDX/partition expansion for large drivers (BUG-03) (Wave 1)
- [x] 02-04-PLAN.md - Verify and harden MSU unattend.xml extraction (BUG-02) (Wave 2)

### Phase 3: Security Hardening ✓
**Goal:** Improve security posture for credential handling and script execution
**Requirements:** SEC-01, SEC-02, SEC-03
**Plans:** 3 plans
**Status:** COMPLETE (2026-01-19)

**Success Criteria:**
1. ✓ Lenovo PSREF token cached securely with reduced browser automation
2. ✓ FFU capture user password handled as SecureString throughout
3. ✓ Apps orchestration scripts verified before execution

Plans:
- [x] 03-01-PLAN.md - Implement Lenovo PSREF token caching (SEC-01) (Wave 1)
- [x] 03-02-PLAN.md - Audit and harden SecureString password flow (SEC-02) (Wave 1)
- [x] 03-03-PLAN.md - Add script integrity verification (SEC-03) (Wave 1)

### Phase 4: Performance Optimization
**Goal:** Reduce unnecessary delays and improve build throughput
**Requirements:** PERF-01, PERF-02, PERF-03
**Success Criteria:**
1. VHD flush time reduced by 50%+ while maintaining data integrity
2. At least 20 Start-Sleep instances replaced with event-driven sync
3. Module decomposition plan documented (or initial extraction done)

### Phase 5: Integration Tests - Core Operations
**Goal:** Add test coverage for VM and imaging operations
**Requirements:** TEST-01, TEST-02, TEST-03
**Success Criteria:**
1. Integration tests exist for Hyper-V VM creation/removal
2. Integration tests exist for driver injection workflow
3. Integration tests exist for FFU capture (mock or conditional)

### Phase 6: Integration Tests - UI and Error Handling
**Goal:** Add test coverage for UI handlers and error recovery
**Requirements:** TEST-04, TEST-05, TEST-06
**Success Criteria:**
1. Unit tests cover FFUUI.Core.Handlers.psm1 key functions
2. Tests verify cleanup handlers are called on failure
3. VMware provider has test coverage (mocked or conditional)

### Phase 7: Feature - Build Cancellation
**Goal:** Allow users to gracefully cancel in-progress builds
**Requirements:** FEAT-01
**Success Criteria:**
1. Cancel button in UI triggers graceful build termination
2. Cleanup handlers execute on cancellation
3. VMs, shares, and user accounts cleaned up after cancel

### Phase 8: Feature - Progress Checkpoint/Resume
**Goal:** Allow builds to resume after interruption
**Requirements:** FEAT-02
**Success Criteria:**
1. Build state checkpointed at major stages
2. Resume from checkpoint detects existing state
3. Partial builds can continue without full restart

### Phase 9: Feature - Config Migration
**Goal:** Automatically migrate config files between versions
**Requirements:** FEAT-03
**Success Criteria:**
1. Config schema includes version field
2. Migration functions transform old configs to new format
3. User prompted to migrate on version mismatch

### Phase 10: Dependency Resilience
**Goal:** Add fallbacks for at-risk external dependencies
**Requirements:** DEP-01, DEP-02, DEP-03
**Success Criteria:**
1. vmrun.exe fallback works when vmxtoolkit fails
2. Lenovo catalogv2.xml fallback provides partial driver coverage
3. ADK WIMMount auto-recovery handles more failure scenarios

---

## Phase Summary

| # | Phase | Requirements | Plans |
|---|-------|--------------|-------|
| 1 | Tech Debt Cleanup ✓ | 5 | 5 plans (COMPLETE) |
| 2 | Bug Fixes - Critical ✓ | 4 | 4 plans (COMPLETE) |
| 3 | Security Hardening ✓ | 3 | 3 plans (COMPLETE) |
| 4 | Performance Optimization | 3 | TBD |
| 5 | Integration Tests - Core | 3 | TBD |
| 6 | Integration Tests - UI/Error | 3 | TBD |
| 7 | Feature - Build Cancellation | 1 | TBD |
| 8 | Feature - Progress Checkpoint | 1 | TBD |
| 9 | Feature - Config Migration | 1 | TBD |
| 10 | Dependency Resilience | 3 | TBD |

**Total:** 26 requirements across 10 phases

---
*Roadmap created: 2026-01-17*
*Phase 1 planned: 2026-01-17*
*Phase 1 complete: 2026-01-18*
*Phase 2 planned: 2026-01-19*
*Phase 2 complete: 2026-01-19*
*Phase 3 planned: 2026-01-19*
*Phase 3 complete: 2026-01-19*
