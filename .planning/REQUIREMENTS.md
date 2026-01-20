# Requirements: FFU Builder v1.8.1

**Defined:** 2026-01-20
**Core Value:** Enable rapid, reliable Windows deployment through pre-configured FFU images with minimal manual intervention.

## v1 Requirements

Requirements for v1.8.1 release. Each maps to roadmap phases.

### Windows Updates

- [ ] **UPD-01**: Build process excludes preview/beta Windows Updates by default (GA releases only)
- [ ] **UPD-02**: User can opt-in to include preview updates via UI checkbox in Updates tab
- [ ] **UPD-03**: `IncludePreviewUpdates` setting persisted in configuration file
- [ ] **UPD-04**: Config migration handles new `IncludePreviewUpdates` property (defaults to false)

### VHDX Operations

- [ ] **VHDX-01**: OS partition drive letter persists through unattend file copy and verification
- [ ] **VHDX-02**: Drive letter stability works with Hyper-V provider
- [ ] **VHDX-03**: Drive letter stability works with VMware provider

## v2 Requirements

Deferred to future release. Tracked but not in current roadmap.

### Driver Operations

- **DRV-01**: HP driver extraction handles exit code 1168 gracefully
- **DRV-02**: Dell CatalogPC.xml auto-download when missing
- **DRV-03**: expand.exe fallback for large MSU files (>2GB)

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| HP driver exit code 1168 fix | Deferred to v2 — requires investigation |
| Dell catalog auto-download | Deferred to v2 — lower priority |
| expand.exe large file handling | Deferred to v2 — fallback works |
| New Windows Update sources | Out of scope — Microsoft Update Catalog sufficient |
| Preview update channel selection | Out of scope — binary opt-in sufficient for v1 |

## Traceability

Which phases cover which requirements. Updated by create-roadmap.

| Requirement | Phase | Status |
|-------------|-------|--------|
| UPD-01 | 11 | Pending |
| UPD-02 | 11 | Pending |
| UPD-03 | 11 | Pending |
| UPD-04 | 11 | Pending |
| VHDX-01 | 12 | Pending |
| VHDX-02 | 12 | Pending |
| VHDX-03 | 12 | Pending |

**Coverage:**
- v1 requirements: 7 total
- Mapped to phases: 7 (100%)
- Unmapped: 0 ✓

---
*Requirements defined: 2026-01-20*
*Last updated: 2026-01-20 after initial definition*
