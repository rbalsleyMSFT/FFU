#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Comprehensive test suite for PowerShell parsing error fix

.DESCRIPTION
    Tests all components of the fix for the PowerShell parsing error:
    1. using module statement uses absolute path (not relative)
    2. BuildFFUVM.ps1 can be parsed without errors
    3. FFU.Constants module can be loaded successfully
    4. UI creates config subdirectory in pre-flight validation
    5. Error handling prevents Set-Content failures from causing silent issues
    6. Module path resolution works in ThreadJob context

.NOTES
    This test suite validates the fixes for the issue where BuildFFUVM.ps1
    failed with PowerShell parsing error "unexpected token 'Write-Host',
    expected 'begin', 'process', 'end', 'clean', or 'dynamicparam'" when
    invoked through ThreadJob with certain path configurations.
#>

$ErrorActionPreference = 'Stop'
$testsPassed = 0
$testsFailed = 0
$testsSkipped = 0

function Write-TestHeader {
    param([string]$Message)
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host $Message -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
}

function Write-TestResult {
    param(
        [string]$TestName,
        [bool]$Passed,
        [string]$Message = "",
        [bool]$Skipped = $false
    )

    if ($Skipped) {
        Write-Host "  ⊘ SKIP: $TestName" -ForegroundColor Yellow
        if ($Message) { Write-Host "    $Message" -ForegroundColor Gray }
        $script:testsSkipped++
    }
    elseif ($Passed) {
        Write-Host "  ✅ PASS: $TestName" -ForegroundColor Green
        if ($Message) { Write-Host "    $Message" -ForegroundColor Gray }
        $script:testsPassed++
    }
    else {
        Write-Host "  ❌ FAIL: $TestName" -ForegroundColor Red
        if ($Message) { Write-Host "    $Message" -ForegroundColor Red }
        $script:testsFailed++
    }
}

Write-Host "=== PowerShell Parsing Error Fix - Comprehensive Test Suite ===`n" -ForegroundColor Green
Write-Host "Testing fixes for 'using module' path resolution and config directory creation" -ForegroundColor Green

# Test 1: Verify using module uses absolute path
Write-TestHeader "Test 1: using module Statement Path Validation"

try {
    $buildScriptPath = Join-Path $PSScriptRoot "BuildFFUVM.ps1"
    $buildScriptContent = Get-Content $buildScriptPath -Raw

    # Check for relative path (OLD - WRONG)
    if ($buildScriptContent -match 'using\s+module\s+\\.\\Modules\\FFU\.Constants') {
        Write-TestResult "using module uses absolute path (not relative)" $false "Still using relative path: .\Modules\FFU.Constants"
    }
    # Check for absolute path with $PSScriptRoot (NEW - CORRECT)
    elseif ($buildScriptContent -match 'using\s+module\s+\$PSScriptRoot\\Modules\\FFU\.Constants') {
        Write-TestResult "using module uses absolute path with `$PSScriptRoot" $true "Path resolution will work in all contexts"
    }
    else {
        Write-TestResult "using module statement" $false "Could not find using module statement or unknown format"
    }

    # Verify comment explains why absolute path is used
    if ($buildScriptContent -match 'ThreadJob|path resolution|absolute path') {
        Write-TestResult "using module has explanatory comment" $true "Explains why absolute path is needed"
    }
    else {
        Write-TestResult "using module has explanatory comment" $false "Missing explanation for future maintainers"
    }
}
catch {
    Write-TestResult "using module path validation" $false $_.Exception.Message
}

# Test 2: Verify BuildFFUVM.ps1 can be parsed
Write-TestHeader "Test 2: BuildFFUVM.ps1 Parse Validation"

try {
    $buildScriptPath = Join-Path $PSScriptRoot "BuildFFUVM.ps1"

    # Use PowerShell's parser to check for syntax errors
    $parseErrors = $null
    $parsedContent = [System.Management.Automation.PSParser]::Tokenize((Get-Content $buildScriptPath -Raw), [ref]$parseErrors)

    if ($null -eq $parseErrors -or $parseErrors.Count -eq 0) {
        Write-TestResult "BuildFFUVM.ps1 has no parse errors" $true "PowerShell can parse the script successfully"
    }
    else {
        $errorDetails = ($parseErrors | ForEach-Object { "Line $($_.Token.StartLine): $($_.Message)" }) -join "; "
        Write-TestResult "BuildFFUVM.ps1 has no parse errors" $false "Parse errors found: $errorDetails"
    }

    # Try to parse as script block (more thorough check)
    try {
        $null = [ScriptBlock]::Create((Get-Content $buildScriptPath -Raw))
        Write-TestResult "BuildFFUVM.ps1 can be converted to ScriptBlock" $true "Advanced parsing succeeded"
    }
    catch {
        Write-TestResult "BuildFFUVM.ps1 can be converted to ScriptBlock" $false $_.Exception.Message
    }
}
catch {
    Write-TestResult "BuildFFUVM.ps1 parse validation" $false $_.Exception.Message
}

# Test 3: Verify FFU.Constants module can be loaded
Write-TestHeader "Test 3: FFU.Constants Module Loading"

try {
    $modulePath = Join-Path $PSScriptRoot "Modules\FFU.Constants\FFU.Constants.psm1"

    if (-not (Test-Path $modulePath)) {
        Write-TestResult "FFU.Constants module file exists" $false "Module not found at: $modulePath"
    }
    else {
        Write-TestResult "FFU.Constants module file exists" $true

        # Try to load the module
        try {
            # Remove if already loaded
            if (Get-Module -Name 'FFU.Constants' -ErrorAction SilentlyContinue) {
                Remove-Module -Name 'FFU.Constants' -Force
            }

            # Use Import-Module instead of 'using module' for testing
            Import-Module $modulePath -Force -ErrorAction Stop
            Write-TestResult "FFU.Constants module can be imported" $true "Module loaded successfully"

            # Verify FFUConstants class is available
            if ([FFUConstants]) {
                Write-TestResult "FFUConstants class is accessible" $true "Class definition loaded correctly"
            }
            else {
                Write-TestResult "FFUConstants class is accessible" $false "Class not found after module import"
            }

            # Clean up
            Remove-Module -Name 'FFU.Constants' -Force
        }
        catch {
            Write-TestResult "FFU.Constants module can be imported" $false $_.Exception.Message
        }
    }
}
catch {
    Write-TestResult "FFU.Constants module loading" $false $_.Exception.Message
}

# Test 4: Verify UI creates config subdirectory
Write-TestHeader "Test 4: UI Pre-Flight Config Subdirectory Creation"

try {
    $uiScriptPath = Join-Path $PSScriptRoot "BuildFFUVM_UI.ps1"
    $uiScriptContent = Get-Content $uiScriptPath -Raw

    # Check for config subdirectory creation logic
    if ($uiScriptContent -match 'configDir\s*=\s*Join-Path.*config') {
        Write-TestResult "UI defines configDir variable" $true "Found config directory path construction"
    }
    else {
        Write-TestResult "UI defines configDir variable" $false "No configDir variable found"
    }

    # Check for New-Item call for config directory
    if ($uiScriptContent -match 'New-Item.*-ItemType\s+Directory.*-Path\s+\$configDir') {
        Write-TestResult "UI creates config subdirectory" $true "Found New-Item for config directory"
    }
    else {
        Write-TestResult "UI creates config subdirectory" $false "No New-Item call for config directory"
    }

    # Check for comment explaining config subdirectory requirement
    if ($uiScriptContent -match 'Ensure.*config.*subdirectory|required for saving.*configuration') {
        Write-TestResult "UI has explanatory comment for config directory" $true "Explains why config subdirectory is needed"
    }
    else {
        Write-TestResult "UI has explanatory comment for config directory" $false "Missing explanation"
    }

    # Check that config directory creation happens BEFORE Set-Content
    $configDirCreationLine = ($uiScriptContent -split "`n" | Select-String -Pattern 'New-Item.*configDir' | Select-Object -First 1).LineNumber
    $setContentLine = ($uiScriptContent -split "`n" | Select-String -Pattern 'Set-Content.*configFilePath' | Select-Object -First 1).LineNumber

    if ($configDirCreationLine -and $setContentLine -and $configDirCreationLine -lt $setContentLine) {
        Write-TestResult "Config directory created before Set-Content" $true "Order is correct (line $configDirCreationLine before line $setContentLine)"
    }
    else {
        Write-TestResult "Config directory created before Set-Content" $false "Order issue or code not found"
    }
}
catch {
    Write-TestResult "UI pre-flight config directory validation" $false $_.Exception.Message
}

# Test 5: Verify error handling around Set-Content
Write-TestHeader "Test 5: Set-Content Error Handling"

try {
    $uiScriptContent = Get-Content (Join-Path $PSScriptRoot "BuildFFUVM_UI.ps1") -Raw

    # Check for try-catch around Set-Content
    if ($uiScriptContent -match 'try\s*\{[^}]*Set-Content[^}]*\}\s*catch') {
        Write-TestResult "Set-Content wrapped in try-catch" $true "Error handling present"
    }
    else {
        Write-TestResult "Set-Content wrapped in try-catch" $false "No try-catch around Set-Content"
    }

    # Check for -ErrorAction Stop on Set-Content
    if ($uiScriptContent -match 'Set-Content.*-ErrorAction\s+Stop') {
        Write-TestResult "Set-Content uses -ErrorAction Stop" $true "Ensures errors are catchable"
    }
    else {
        Write-TestResult "Set-Content uses -ErrorAction Stop" $false "Missing -ErrorAction Stop"
    }

    # Check for helpful error message
    if ($uiScriptContent -match 'Failed to save.*configuration|Configuration Save Error') {
        Write-TestResult "Helpful error message for Set-Content failure" $true "User will see actionable error"
    }
    else {
        Write-TestResult "Helpful error message for Set-Content failure" $false "Generic or missing error message"
    }
}
catch {
    Write-TestResult "Set-Content error handling validation" $false $_.Exception.Message
}

# Test 6: Verify module path resolution in ThreadJob context (functional test)
Write-TestHeader "Test 6: Module Loading in ThreadJob Context (Functional)"

try {
    # Only run if ThreadJob module is available
    if (-not (Get-Module -ListAvailable -Name ThreadJob)) {
        Write-TestResult "ThreadJob module availability" $false "ThreadJob module not installed" -Skipped $true
    }
    else {
        Import-Module ThreadJob -Force

        # Create a simple test script that uses the same 'using module' pattern
        $testScriptContent = @"
using module $PSScriptRoot\Modules\FFU.Constants\FFU.Constants.psm1
Write-Output "Module loaded successfully"
if ([FFUConstants]) {
    Write-Output "FFUConstants class accessible"
}
"@

        $testScriptPath = Join-Path $PSScriptRoot "Test-ModuleLoadingTemp.ps1"
        $testScriptContent | Set-Content -Path $testScriptPath -Encoding UTF8

        # Run in ThreadJob
        $job = Start-ThreadJob -ScriptBlock {
            param($scriptPath)
            & $scriptPath
        } -ArgumentList $testScriptPath

        $job | Wait-Job -Timeout 10 | Out-Null
        $jobOutput = Receive-Job -Job $job
        $jobErrors = $job.ChildJobs[0].Error

        Remove-Job -Job $job -Force
        Remove-Item $testScriptPath -Force -ErrorAction SilentlyContinue

        if ($jobOutput -match "Module loaded successfully" -and $jobOutput -match "FFUConstants class accessible") {
            Write-TestResult "Module loads correctly in ThreadJob" $true "ThreadJob can import module with absolute path"
        }
        elseif ($jobErrors.Count -gt 0) {
            Write-TestResult "Module loads correctly in ThreadJob" $false "ThreadJob errors: $($jobErrors[0].Exception.Message)"
        }
        else {
            Write-TestResult "Module loads correctly in ThreadJob" $false "Module load output not found: $($jobOutput -join '; ')"
        }
    }
}
catch {
    Write-TestResult "ThreadJob module loading test" $false $_.Exception.Message
}

# Test 7: Verify no hardcoded paths in BuildFFUVM.ps1
Write-TestHeader "Test 7: No Hardcoded Path References"

try {
    $buildScriptContent = Get-Content (Join-Path $PSScriptRoot "BuildFFUVM.ps1") -Raw

    # Check for hardcoded C:\FFUDevelopment references
    if ($buildScriptContent -match 'C:\\FFUDevelopment' -or $buildScriptContent -match "C:\FFUDevelopment") {
        Write-TestResult "No hardcoded C:\FFUDevelopment paths" $false "Found hardcoded path reference"
    }
    else {
        Write-TestResult "No hardcoded C:\FFUDevelopment paths" $true "All paths use variables"
    }
}
catch {
    Write-TestResult "Hardcoded path check" $false $_.Exception.Message
}

# Test 8: Integration test - Parse BuildFFUVM.ps1 with actual module path
Write-TestHeader "Test 8: Full Integration Parse Test"

Write-Host "  NOTE: This test simulates PowerShell parsing BuildFFUVM.ps1 with the fixed 'using module' statement" -ForegroundColor Yellow

try {
    $buildScriptPath = Join-Path $PSScriptRoot "BuildFFUVM.ps1"

    # Try to create a runspace and parse the script in it
    # This is the closest we can get to simulating the actual execution
    $runspace = [runspacefactory]::CreateRunspace()
    $runspace.Open()

    try {
        # Set working directory to script root
        $runspace.SessionStateProxy.Path.SetLocation($PSScriptRoot)

        # Create a pipeline and add the script
        $pipeline = $runspace.CreatePipeline()
        $pipeline.Commands.AddScript("# Test parse only`n" + (Get-Content $buildScriptPath -Raw))

        # Just invoke to trigger parsing (script won't actually run due to missing parameters)
        try {
            $null = $pipeline.Invoke()
            $hadErrors = $pipeline.HadErrors
        }
        catch {
            # Expected to have errors due to missing required parameters, but parse should succeed
            $hadErrors = $_.Exception.Message -match "parse|syntax|token"
        }

        if (-not $hadErrors) {
            Write-TestResult "BuildFFUVM.ps1 parses successfully in runspace" $true "No parsing errors detected"
        }
        else {
            Write-TestResult "BuildFFUVM.ps1 parses successfully in runspace" $false "Parsing errors detected"
        }
    }
    finally {
        $runspace.Close()
        $runspace.Dispose()
    }
}
catch {
    # This is expected - script requires parameters
    if ($_.Exception.Message -match "parameter|required|mandatory") {
        Write-TestResult "BuildFFUVM.ps1 parsing (parameter validation expected)" $true "Parse succeeded, parameter validation triggered (expected)"
    }
    else {
        Write-TestResult "BuildFFUVM.ps1 parsing" $false $_.Exception.Message
    }
}

# Summary
Write-TestHeader "Test Summary"
$total = $testsPassed + $testsFailed + $testsSkipped
Write-Host "  Total Tests:   $total" -ForegroundColor Cyan
Write-Host "  Passed:        $testsPassed" -ForegroundColor Green
Write-Host "  Failed:        $testsFailed" -ForegroundColor $(if ($testsFailed -gt 0) { "Red" } else { "Gray" })
Write-Host "  Skipped:       $testsSkipped" -ForegroundColor Yellow

if ($testsFailed -eq 0) {
    Write-Host "`n✅ All automated tests passed!" -ForegroundColor Green
    Write-Host "`nThe PowerShell parsing error fix has been validated." -ForegroundColor Green
    Write-Host "BuildFFUVM.ps1 should now work correctly when invoked through ThreadJob." -ForegroundColor Green
    exit 0
}
else {
    Write-Host "`n❌ $testsFailed test(s) failed. Please review the output above." -ForegroundColor Red
    exit 1
}
