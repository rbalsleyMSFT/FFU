# Implement Feature with Full Agent Coordination

Execute a complete implementation workflow using all appropriate subagents, coordinated through the PM Agent.

## Workflow Protocol

**ALL work flows through the `pm-agent`** for tracking, PDCA documentation, and session continuity.

---

## Phase 1: Planning & Context Restoration

### 1.1 PM Agent Initialization
```
Invoke pm-agent to:
1. Read docs/memory/{pm_context,last_session,next_actions}.md
2. Check git status and current branch
3. Output status: 🟢 [branch] | [n]M [n]D
```

### 1.2 Requirements Analysis
```
Invoke requirements-analyst to:
1. Parse the task requirements from $ARGUMENTS
2. Identify affected components (Public/, Private/, UI/, Classes/)
3. List dependencies and integration points
4. Define success criteria
5. Ask clarifying questions if requirements are ambiguous
```

### 1.3 Architecture Design
```
Invoke powershell-architect OR system-architect to:
1. Evaluate solution approaches with trade-offs
2. Check existing patterns in docs/patterns/ and CLAUDE.md
3. Review related implementations in the codebase
4. Recommend optimal approach with justification
5. Identify potential breaking changes
```

**CHECKPOINT**: Confirm approach with user before proceeding.

---

## Phase 2: Pre-Implementation Testing

### 2.1 Baseline Regression Tests
```
Invoke pester-test-developer to:
1. Identify existing tests for affected components
2. Run baseline regression suite:
   pwsh -Command "& ./run-tests.ps1"
3. Document baseline state in docs/memory/checkpoint.json:
   - Total tests: [count]
   - Passing: [count]
   - Coverage: [percent]%
```

### 2.2 Create Regression Safety Net
```
If modifying existing functionality:
1. Ensure tests exist for current behavior
2. Create additional regression tests if coverage < 80%
3. Document expected behavior before changes
```

---

## Phase 3: Implementation

### 3.1 For PowerShell Functions (Public/ or Private/)
```
Invoke powershell-module to:
1. Create/modify function following project standards:
   - #Requires -Version 7.0
   - Complete comment-based help
   - CmdletBinding and OutputType attributes
   - Parameter validation
   - Error handling with try/catch
2. Follow naming: Verb-W32Noun (Public) or Verb-Noun (Private)
3. One function per file
```

### 3.2 For WPF/XAML UI (UI/)
```
Invoke wpf-xaml to:
1. Create XAML following MahApps.Metro patterns
2. Create companion .ps1 file
3. Handle PowerShell + WPF integration:
   - Remove x:Class for PowerShell compatibility
   - Wire event handlers via FindName()
   - Use Dispatcher for async operations
4. Validate color contrast (avoid white-on-light issues)
```

### 3.3 For Database Changes
```
Invoke database-architect to:
1. Design schema changes with migrations
2. Use parameterized queries (PSSQLite)
3. Update Initialize-W32Database.ps1 if needed
4. Ensure backward compatibility
```

### 3.4 For Source Plugins (Private/Sources/)
```
Invoke package-source to:
1. Create class following W32SourcePlugin pattern
2. Implement required methods: Search(), GetLatestVersion(), DownloadInstaller()
3. Update W32Enums.ps1 SourceType if needed
4. Handle serialization constraint (no cross-runspace usage)
```

### 3.5 For Graph API/Intune (Private/Publishers/)
```
Invoke intune-graph to:
1. Follow Microsoft Graph SDK patterns
2. Handle authentication and token refresh
3. Implement proper error handling for API calls
4. Use batch operations where applicable
```

---

## Phase 4: Testing (After EACH Component)

### 4.1 Create/Update Tests
```
Invoke pester-test-developer to:
1. Create tests in matching structure:
   Public/Verb-W32Noun.ps1 → Tests/Unit/Public/Verb-W32Noun.Tests.ps1
   Private/X/Y.ps1 → Tests/Unit/Private/X/Y.Tests.ps1
   UI/Pages/X.ps1 → Tests/Unit/UI/Pages/X.Tests.ps1
2. Cover:
   - Parameter validation
   - Happy path behavior
   - Error conditions
   - Edge cases
3. Mock external dependencies:
   - Invoke-SqliteQuery
   - Invoke-MgGraphRequest
   - File system operations
   - External tools (winget, choco)
```

### 4.2 Run Regression Suite
```
After EACH breaking change:
pwsh -Command "& ./run-tests.ps1"

If tests fail:
1. HALT implementation
2. Report failure details
3. Fix before continuing
```

### 4.3 Automated Verification (BLOCKING) - FFUBuilder Specific

**MANDATORY: After ANY code changes, invoke verify-app before proceeding**

```
Invoke verify-app (via general-purpose agent) to:
1. Run full regression with coverage:
   .\Tests\Unit\Invoke-PesterTests.ps1 -EnableCodeCoverage -OutputVerbosity Minimal

2. Run static analysis:
   Invoke-ScriptAnalyzer -Path .\FFUDevelopment -Recurse -Severity Error,Warning

3. Validate module imports:
   Import-Module FFU.Core -Force -ErrorAction Stop
   Get-Command -Module FFU.Core | Measure-Object

4. Output structured verification report:
   VERIFICATION_STATUS: [PASS|FAIL|BLOCKED]
   SUMMARY: Tests, Coverage, PSScriptAnalyzer, Module Import
   BLOCKING_ISSUES: [list]
   WARNINGS: [list]
   RECOMMENDATION: [Continue|Fix Required|Review Needed]
```

**HALT CONDITIONS** (do not proceed if any):
- Any Pester test failures (not skipped - actual failures)
- New PSScriptAnalyzer errors (warnings allowed)
- Module import failures
- Code coverage decreased from baseline

**IF HALTED:**
1. Report specific failures with file:line references
2. Return to Phase 3 to fix issues
3. Re-run verification until PASS

**ON PASS:**
1. Log verification results
2. Continue to Phase 4.4 (if applicable) or Phase 5 (Code Review)

### 4.4 Full Build Verification (OPTIONAL - Long Running)

**When to run:** After significant changes to build logic, hypervisor integration, imaging code, or VM lifecycle.

**NOT required for:** UI-only changes, documentation, test-only changes, config updates.

```
Invoke verify-app (via general-purpose agent) with build execution:
1. Copy FFUDevelopment to test drive:
   Copy-FFUDevelopmentToTestDrive -SourcePath $PWD -TestDriveLetter "D" -CleanFirst

2. Run minimal build on primary hypervisor:
   Invoke-FFUTestBuild -ConfigType Minimal -Hypervisor HyperV -TestDriveLetter "D"

3. Validate build output:
   Test-FFUBuildOutput -FFUPath "D:\FFUDevelopment_Test\FFU" -ExpectedSKU "Pro"

4. Generate structured report:
   Get-FFUBuildVerificationReport -BuildResult $result

5. (Optional) Run standard build if time permits:
   Invoke-FFUTestBuild -ConfigType Standard -Hypervisor HyperV -TestDriveLetter "D"

6. (Optional) Test alternate hypervisor:
   Invoke-FFUTestBuild -ConfigType Minimal -Hypervisor VMware -TestDriveLetter "D"
```

**HALT CONDITIONS:**
- Build exits with non-zero exit code
- FFU file not created
- FFU file size outside expected range
- Pre-flight validation fails

**Duration Estimates:**
| Config | Duration |
|--------|----------|
| Minimal | ~20 minutes |
| Standard | ~45 minutes |
| Both Hypervisors | ~90 minutes |

---

## Phase 5: Code Review

### 5.1 Automated Review
```
Invoke code-reviewer to:
1. Run PSScriptAnalyzer:
   Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
2. Check security (no hardcoded secrets, command injection)
3. Verify error handling patterns
4. Check performance anti-patterns (no += on arrays in loops)
5. Validate documentation completeness
```

### 5.2 Review Output Format
```
## Code Review: [Component]
- **Overall**: Pass/Needs Changes/Fail
- **Critical Issues**: [count]
- **Warnings**: [count]

### Critical Issues (Must Fix)
[List with file, line, issue, fix]

### Pre-Commit Checklist
- [ ] No PSScriptAnalyzer errors
- [ ] No hardcoded secrets
- [ ] Complete comment-based help
- [ ] Tests exist and pass
- [ ] No TODO/FIXME unaddressed
```

---

## Phase 6: Documentation

### 6.1 Code Documentation
```
Invoke docs-writer to:
1. Verify comment-based help is complete
2. Generate/update markdown docs:
   Update-MarkdownHelp -Path ./docs/cmdlets
3. Update relevant guides in docs/
```

### 6.2 Changelog Update
```
Update CHANGELOG.md following Keep a Changelog format:
## [Unreleased]
### Added
- [New feature description]
### Changed
- [Modified behavior]
### Fixed
- [Bug fix with root cause]
```

---

## Phase 7: Finalization

### 7.1 Final Regression Run
```
pwsh -Command "& ./run-tests.ps1"
Verify:
- All tests pass
- Coverage >= 80%
- No regressions from baseline
```

### 7.2 Version Bump (if applicable)
```
If breaking change or significant feature:
1. Update ModuleVersion in W32AppFactory.psd1
2. Update ReleaseNotes in PrivateData.PSData
3. Follow SemVer: MAJOR.MINOR.PATCH
   - Current: 0.9.6-alpha
```

### 7.3 PM Agent Session End
```
Invoke pm-agent to:
1. Write docs/memory/{last_session,next_actions,pm_context}.md
2. Create docs/pdca/[feature]/check.md with evaluation
3. If success: Extract pattern to docs/patterns/
4. If failure: Document in docs/mistakes/
5. Update session_summary.json
```

---

## Agent Quick Reference

| Task | Agent | Key Files |
|------|-------|-----------|
| Session context | `pm-agent` | docs/memory/*.md |
| Requirements | `requirements-analyst` | - |
| Architecture | `powershell-architect` | CLAUDE.md, docs/patterns/ |
| PowerShell code | `powershell-module` | Public/, Private/ |
| Pester tests | `pester-test-developer` | Tests/ |
| **Verification (BLOCKING)** | `verify-app` | Tests/, FFUDevelopment/ |
| **Build Verification (OPTIONAL)** | `verify-app` | FFU.BuildTest, config/test/ |
| WPF/XAML UI | `wpf-xaml` | UI/ |
| Code review | `code-reviewer` | PSScriptAnalyzerSettings.psd1 |
| Documentation | `docs-writer` | docs/cmdlets/ |
| Database | `database-architect` | Private/Helpers/Initialize-W32Database.ps1 |
| Source plugins | `package-source` | Private/Sources/ |
| Graph API | `intune-graph` | Private/Publishers/ |
| CI/CD | `cicd-actions` | .github/workflows/ |

---

## Rules

- **STOP and ask** for clarification on ambiguous requirements
- **HALT on test failure** - report and fix before continuing
- **No commits** without code-reviewer sign-off
- **Version bump** required for breaking changes
- **PowerShell 7.0+ ONLY** - use modern features (ternary, null-coalescing)
- **80% test coverage** minimum for new code

---

## Arguments

$ARGUMENTS

If no arguments provided, ask: "What feature or fix would you like to implement?"

---

## Example Invocations

```
/implement Add a new LocalFileSystem source plugin that monitors a folder for new installers
```

```
/implement Fix the dashboard tile rendering issue where icons show as "Object[] Array"
```

```
/implement Add retry logic with exponential backoff to all Graph API calls in Publish-W32App
```
