---
phase: 10-dependency-resilience
plan: 02
subsystem: drivers
tags: [lenovo, psref, fallback, catalogv2, resilience]

dependency-graph:
  requires:
    - phase-03 (SEC-01 Lenovo PSREF token caching)
  provides:
    - Lenovo driver discovery resilience
    - catalogv2.xml fallback mechanism
    - Enterprise model coverage backup
  affects:
    - UI driver search (Get-LenovoDriversModelList)
    - Lenovo driver downloads

tech-stack:
  added: []
  patterns:
    - XML catalog parsing with caching
    - Tiered fallback pattern (API -> catalog)
    - Module composition (nested import)

key-files:
  created:
    - FFUDevelopment/FFUUI.Core/FFUUI.Core.Drivers.Lenovo.CatalogFallback.psm1
    - Tests/Unit/FFU.Drivers.Lenovo.CatalogFallback.Tests.ps1
  modified:
    - FFUDevelopment/FFUUI.Core/FFUUI.Core.Drivers.Lenovo.psm1

decisions:
  - id: catalog-xml-source
    choice: "Use https://download.lenovo.com/cdrt/td/catalogv2.xml"
    rationale: "Official Lenovo enterprise driver catalog, publicly accessible"
  - id: cache-ttl-7-days
    choice: "7-day TTL for catalog cache (10080 minutes)"
    rationale: "Catalog updates infrequently; reduces network traffic"
  - id: two-tier-caching
    choice: "Memory cache + file cache"
    rationale: "Fast access for repeated searches, persistence across sessions"
  - id: fallback-flag
    choice: "IsFallback property on results"
    rationale: "UI/downstream can detect and warn about partial coverage"
  - id: graceful-module-check
    choice: "Get-Command check before calling fallback"
    rationale: "Allows older installations without fallback module to work"

metrics:
  duration: ~9 minutes
  completed: 2026-01-20
---

# Phase 10 Plan 02: Lenovo catalogv2.xml Fallback Summary

Lenovo driver discovery now falls back to catalogv2.xml when PSREF API fails, providing enterprise model coverage (ThinkPad, ThinkCentre, ThinkStation) even without browser-based authentication.

## What Was Built

### New Module: FFUUI.Core.Drivers.Lenovo.CatalogFallback

Created a standalone fallback module with 4 exported functions:

| Function | Purpose |
|----------|---------|
| `Get-LenovoCatalogV2` | Downloads and caches catalogv2.xml with 7-day TTL |
| `Get-LenovoCatalogV2Models` | Searches for models by name or machine type |
| `Get-LenovoCatalogV2DriverUrl` | Returns SCCM driver pack URL for machine type |
| `Reset-LenovoCatalogV2Cache` | Clears in-memory cache for testing/refresh |

### Caching Strategy

**Two-tier caching implementation:**
1. **Memory cache**: Fast lookups for repeated searches within session
2. **File cache**: Persistence across sessions in `.cache/catalogv2.xml`

**Cache TTL**: 10080 minutes (7 days) - balances freshness vs. network traffic.

### Fallback Integration

Updated `Get-LenovoDriversModelList` with two fallback points:

1. **On PSREF API error (401/403)**: Falls back to catalogv2.xml
2. **On empty PSREF results**: Checks catalogv2.xml for enterprise-only models

Users are informed when operating in fallback mode with partial coverage warning.

## Commits

| Task | Commit | Description |
|------|--------|-------------|
| 1 | 1213a20 | Create catalog fallback module (included in prior 10-01 commit) |
| 2 | ce9f37e | Integrate fallback into Get-LenovoDriversModelList |
| 3 | 1e640ef | Add 34 Pester tests for fallback functionality |

## Test Coverage

**34 Pester tests** covering:

- Catalog download and caching behavior
- Model search by name and machine type
- Driver URL lookup with version matching
- Fallback chain integration
- Module documentation and exports

## Technical Details

### catalogv2.xml Structure

```xml
<Products>
  <Product>
    <Model name="ThinkPad L490">
      <Types>
        <Type mtm="20Q6">
          <SCCM os="win10" version="22H2">
            https://download.lenovo.com/.../drivers.exe
          </SCCM>
        </Type>
      </Types>
    </Model>
  </Product>
</Products>
```

### Search Algorithm

1. First searches by model name (`Model.name -like "*$SearchTerm*"`)
2. If no results, searches by machine type (`Type.mtm -like "*$SearchTerm*"`)
3. Returns array with Make, Model, ProductName, MachineType, IsFallback

### Coverage Limitations

**INCLUDED in catalogv2.xml:**
- ThinkPad (enterprise laptops)
- ThinkCentre (enterprise desktops)
- ThinkStation (workstations)

**NOT INCLUDED in catalogv2.xml:**
- 300w, 500w education models
- 100e, 300e Chromebooks
- Consumer IdeaPad/IdeaCentre models

## Deviations from Plan

### Task 1 Pre-existing

The catalog fallback module was already created in a prior 10-01 commit. Verified the module meets all requirements and proceeded with integration.

## Next Phase Readiness

This completes plan 10-02 of Phase 10 (Dependency Resilience). Ready for plan 10-03 (WimMount recovery).

## Files Modified

| File | Change |
|------|--------|
| `FFUUI.Core.Drivers.Lenovo.CatalogFallback.psm1` | **NEW** - 417 lines, 4 functions |
| `FFUUI.Core.Drivers.Lenovo.psm1` | +71 lines - fallback integration |
| `FFU.Drivers.Lenovo.CatalogFallback.Tests.ps1` | **NEW** - 384 lines, 34 tests |
