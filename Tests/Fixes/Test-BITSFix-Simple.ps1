#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Simple test to verify BITS authentication fix
#>

Write-Host "`n=====================================================================" -ForegroundColor Cyan
Write-Host " BITS Authentication Fix - Simple Test" -ForegroundColor Cyan
Write-Host "=====================================================================" -ForegroundColor Cyan

# Change to FFUDevelopment directory
Set-Location "$PSScriptRoot\FFUDevelopment"

Write-Host "`n[Test 1] Checking ThreadJob module..." -ForegroundColor Yellow

if (Get-Module -ListAvailable -Name ThreadJob) {
    Write-Host "  PASS: ThreadJob module is available" -ForegroundColor Green
    Import-Module ThreadJob -Force
}
else {
    Write-Host "  INFO: ThreadJob not found, attempting install..." -ForegroundColor Yellow
    try {
        Install-Module -Name ThreadJob -Force -Scope CurrentUser
        Write-Host "  PASS: ThreadJob installed successfully" -ForegroundColor Green
        Import-Module ThreadJob -Force
    }
    catch {
        Write-Host "  FAIL: Could not install ThreadJob: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "  The fix will not work without ThreadJob" -ForegroundColor Red
        exit 1
    }
}

Write-Host "`n[Test 2] Loading FFU.Common module..." -ForegroundColor Yellow

try {
    Import-Module ".\FFU.Common" -Force
    Write-Host "  PASS: FFU.Common module loaded" -ForegroundColor Green
}
catch {
    Write-Host "  FAIL: Could not load FFU.Common: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host "`n[Test 3] Verifying Start-BitsTransferWithRetry enhancements..." -ForegroundColor Yellow

$func = Get-Command Start-BitsTransferWithRetry -ErrorAction SilentlyContinue
if ($func) {
    $hasCredential = $func.Parameters.ContainsKey('Credential')
    $hasAuth = $func.Parameters.ContainsKey('Authentication')

    if ($hasCredential -and $hasAuth) {
        Write-Host "  PASS: New parameters added (Credential, Authentication)" -ForegroundColor Green
    }
    else {
        Write-Host "  FAIL: Missing new parameters" -ForegroundColor Red
        Write-Host "    Credential: $hasCredential, Authentication: $hasAuth" -ForegroundColor Gray
    }
}
else {
    Write-Host "  FAIL: Function not found" -ForegroundColor Red
}

Write-Host "`n[Test 4] Testing credential inheritance..." -ForegroundColor Yellow

$credTest = {
    $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    @{
        User = $id.Name
        Auth = $id.AuthenticationType
        HasAuth = ($id.AuthenticationType -in @('Kerberos', 'NTLM', 'Negotiate'))
    }
}

# Test with Start-Job (old way - should fail)
Write-Host "  Testing Start-Job (old method)..." -ForegroundColor Gray
$oldResult = Start-Job -ScriptBlock $credTest | Wait-Job | Receive-Job -AutoRemoveJob

Write-Host "    User: $($oldResult.User)" -ForegroundColor Gray
Write-Host "    Auth Type: $($oldResult.Auth)" -ForegroundColor Gray
Write-Host "    Has Network Auth: $($oldResult.HasAuth)" -ForegroundColor Gray

if ($oldResult.HasAuth) {
    Write-Host "  UNEXPECTED: Start-Job has credentials (unusual but okay)" -ForegroundColor Yellow
}
else {
    Write-Host "  EXPECTED: Start-Job lacks network credentials" -ForegroundColor Gray
}

# Test with Start-ThreadJob (new way - should work)
Write-Host "`n  Testing Start-ThreadJob (fixed method)..." -ForegroundColor Gray
$newResult = Start-ThreadJob -ScriptBlock $credTest | Wait-Job | Receive-Job -AutoRemoveJob

Write-Host "    User: $($newResult.User)" -ForegroundColor Gray
Write-Host "    Auth Type: $($newResult.Auth)" -ForegroundColor Gray
Write-Host "    Has Network Auth: $($newResult.HasAuth)" -ForegroundColor Gray

if ($newResult.HasAuth) {
    Write-Host "  PASS: Start-ThreadJob preserves network credentials!" -ForegroundColor Green
}
else {
    Write-Host "  FAIL: Start-ThreadJob missing credentials" -ForegroundColor Red
}

Write-Host "`n[Test 5] Checking BuildFFUVM_UI.ps1 modifications..." -ForegroundColor Yellow

$uiContent = Get-Content ".\BuildFFUVM_UI.ps1" -Raw

if ($uiContent -match 'Import-Module ThreadJob') {
    Write-Host "  PASS: ThreadJob import added" -ForegroundColor Green
}
else {
    Write-Host "  FAIL: ThreadJob import not found" -ForegroundColor Red
}

$threadJobCount = ([regex]::Matches($uiContent, 'Start-ThreadJob')).Count
if ($threadJobCount -ge 2) {
    Write-Host "  PASS: Start-ThreadJob used ($threadJobCount occurrences)" -ForegroundColor Green
}
else {
    Write-Host "  FAIL: Start-ThreadJob not used enough ($threadJobCount occurrences)" -ForegroundColor Red
}

if ($uiContent -match 'Get-Command Start-ThreadJob') {
    Write-Host "  PASS: Fallback logic present" -ForegroundColor Green
}
else {
    Write-Host "  FAIL: No fallback logic" -ForegroundColor Red
}

Write-Host "`n=====================================================================" -ForegroundColor Cyan
Write-Host " Test Complete" -ForegroundColor Cyan
Write-Host "=====================================================================" -ForegroundColor Cyan
Write-Host "`nThe fix has been applied. To fully test:" -ForegroundColor White
Write-Host "  1. Run BuildFFUVM_UI.ps1" -ForegroundColor Gray
Write-Host "  2. Configure a build with driver downloads" -ForegroundColor Gray
Write-Host "  3. Check for 'ThreadJob' messages in the log" -ForegroundColor Gray
Write-Host "  4. Verify downloads complete without 0x800704DD errors" -ForegroundColor Gray
Write-Host ""
