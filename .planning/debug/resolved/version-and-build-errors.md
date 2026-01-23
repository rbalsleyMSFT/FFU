---
status: resolved
trigger: "UI version display not updating + build fails with user interaction prompt error"
created: 2026-01-20T08:00:00Z
updated: 2026-01-20T08:40:00Z
---

## Current Focus

hypothesis: CONFIRMED - Build error caused by Read-Host in config migration code (line 748 of BuildFFUVM.ps1)
test: Verified Read-Host call exists in config migration path
expecting: Build fails immediately when config migration is triggered in background job
next_action: Fix by skipping interactive prompts when MessagingContext is present

## Symptoms

expected:
  - Title bar should show current version from version.json (v1.8.0)
  - Build should run without prompts in background job
actual:
  - Title bar shows outdated/wrong version
  - Build fails immediately with user interaction error
errors: |
  1/20/2026 7:40:41 AM [ERROR] Build failed: A command that prompts the user failed because
  the host program or the command type does not support user interaction. The host was
  attempting to request confirmation with the following message: | CurrentProgress=0,
  CancellationRequested=False, MessageCount=1, LastError=,
  LogFilePath=C:\FFUDevelopment\FFUDevelopment.log, EndTime=, MessageQueue=, BuildState=Running,
  FileLoggingEnabled=True, ErrorCount=0, StartTime=01/20/2026 13:40:40, Version=1.0.0,
  CurrentOperation=, CurrentPhase=
reproduction:
  - Issue 1: Launch BuildFFUVM_UI.ps1, observe title bar
  - Issue 2: Start a build from the UI
started: After v1.8.0 milestone completion

## Eliminated

## Evidence

- timestamp: 2026-01-20T08:05:00Z
  checked: version.json
  found: Version is "1.7.26" (not 1.8.0), buildDate is "2026-01-20"
  implication: version.json has correct recent version, UI should read it

- timestamp: 2026-01-20T08:06:00Z
  checked: BuildFFUVM_UI.ps1 lines 35-50
  found: Version loading works correctly - reads from version.json, stores in $script:FFUBuilderVersion
  implication: UI version loading is correct

- timestamp: 2026-01-20T08:07:00Z
  checked: BuildFFUVM_UI.ps1 line 184
  found: Title set as "FFU Builder UI v$($script:uiState.Version.Number)" in Add_Loaded handler
  implication: Title bar should show correct version from version.json

- timestamp: 2026-01-20T08:08:00Z
  checked: FFUUI.Core.Initialize.psm1 line 777
  found: About tab shows fallback "1.0.0" if State.Version.Number is missing
  implication: Error message shows "Version=1.0.0" - BUT this is unrelated (see next finding)

- timestamp: 2026-01-20T08:15:00Z
  checked: FFU.Messaging.psm1 line 203
  found: Version='1.0.0' in error is from MessagingContext, not FFU Builder version
  implication: The "Version=1.0.0" in error is messaging protocol version, not related to Issue 1

- timestamp: 2026-01-20T08:18:00Z
  checked: BuildFFUVM.ps1 line 748
  found: Read-Host "Save migrated configuration? (Y/N)" in config migration code path
  implication: ROOT CAUSE - This Read-Host fails in background job (non-interactive context)

- timestamp: 2026-01-20T08:20:00Z
  checked: BuildFFUVM.ps1 lines 720-763
  found: Config migration happens early in script (before main build)
  implication: Explains why build fails immediately - migration check runs before anything else

## Resolution

root_cause: |
  Issue 1 (Version Display): version.json was not updated to 1.8.0 when v1.8.0 milestone was completed.
  The code correctly reads from version.json - this was a release management oversight, not a code bug.

  Issue 2 (Build Failure): Read-Host call at line 748 of BuildFFUVM.ps1 in config migration code
  fails in non-interactive background job context. When UI launches build via ThreadJob, Read-Host
  cannot prompt user, causing PowerShell to throw "host program does not support user interaction" error.

fix: |
  1. Updated version.json from "1.7.26" to "1.8.0"
  2. Modified BuildFFUVM.ps1 config migration section to detect non-interactive mode (MessagingContext present)
     and auto-accept migration instead of prompting with Read-Host

verification: |
  1. Version test: version.json contains "1.8.0" - PASSED
  2. isNonInteractive variable check in BuildFFUVM.ps1 - PASSED
  3. Auto-accept migration message in BuildFFUVM.ps1 - PASSED
  4. PowerShell syntax validation - PASSED
  5. PSScriptAnalyzer - No new errors (72 pre-existing warnings, all PSAvoidUsingWriteHost)

files_changed:
  - FFUDevelopment/version.json (version bump to 1.8.0)
  - FFUDevelopment/BuildFFUVM.ps1 (non-interactive mode detection in config migration)
