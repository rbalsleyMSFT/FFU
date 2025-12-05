<#
.SYNOPSIS
    Diagnostic script to identify why updates are re-downloaded despite RemoveUpdates=false

.DESCRIPTION
    Checks the actual state of update folders, Apps.iso, and config files to identify
    the root cause of repeated update downloads.
#>

param(
    [string]$FFUDevelopmentPath = "C:\FFUDevelopment"
)

Write-Host "=== Update Download Issue Diagnostic ===" -ForegroundColor Cyan
Write-Host ""

# Check config file
$configPath = Join-Path $FFUDevelopmentPath "config\FFUConfig.json"
if (Test-Path $configPath) {
    Write-Host "Found config file: $configPath" -ForegroundColor Green
    $config = Get-Content $configPath -Raw | ConvertFrom-Json
    Write-Host "  RemoveUpdates setting: $($config.RemoveUpdates)" -ForegroundColor $(if ($config.RemoveUpdates) { "Red" } else { "Green" })
    Write-Host "  UpdateLatestDefender: $($config.UpdateLatestDefender)"
    Write-Host "  UpdateLatestMSRT: $($config.UpdateLatestMSRT)"
    Write-Host "  UpdateEdge: $($config.UpdateEdge)"
    Write-Host "  UpdateOneDrive: $($config.UpdateOneDrive)"
} else {
    Write-Host "Config file not found at: $configPath" -ForegroundColor Yellow
}
Write-Host ""

# Check Apps folder structure
$appsPath = Join-Path $FFUDevelopmentPath "Apps"
$updateFolders = @('Defender', 'MSRT', 'Edge', 'OneDrive', '.NET', 'CU', 'Microcode')

Write-Host "Checking Apps folder: $appsPath" -ForegroundColor Cyan
if (Test-Path $appsPath) {
    Write-Host "  Apps folder exists" -ForegroundColor Green

    foreach ($folder in $updateFolders) {
        $folderPath = Join-Path $appsPath $folder
        if (Test-Path $folderPath) {
            $files = Get-ChildItem -Path $folderPath -Recurse -File -ErrorAction SilentlyContinue
            $totalSize = ($files | Measure-Object -Property Length -Sum).Sum
            $fileSizeMB = [math]::Round($totalSize / 1MB, 2)

            if ($files.Count -eq 0) {
                Write-Host "  [$folder] EXISTS but EMPTY (0 files)" -ForegroundColor Red
                Write-Host "    ^ This causes re-downloads! Folder exists but size check fails." -ForegroundColor Red
            } elseif ($totalSize -lt 1MB) {
                Write-Host "  [$folder] EXISTS with $($files.Count) files, but SIZE TOO SMALL ($fileSizeMB MB < 1 MB)" -ForegroundColor Yellow
                Write-Host "    ^ This causes re-downloads! Size check requires > 1MB." -ForegroundColor Yellow
            } else {
                Write-Host "  [$folder] EXISTS with $($files.Count) files ($fileSizeMB MB) - should skip download" -ForegroundColor Green
            }

            # List files
            if ($files.Count -gt 0 -and $files.Count -le 10) {
                foreach ($file in $files) {
                    $sizeMB = [math]::Round($file.Length / 1MB, 2)
                    Write-Host "    - $($file.Name) ($sizeMB MB, Modified: $($file.LastWriteTime))" -ForegroundColor Gray
                }
            }
        } else {
            Write-Host "  [$folder] DOES NOT EXIST - will download" -ForegroundColor Yellow
        }
    }
} else {
    Write-Host "  Apps folder does not exist!" -ForegroundColor Red
}
Write-Host ""

# Check Apps.iso
$appsISO = Join-Path $FFUDevelopmentPath "Apps\Apps.iso"
if (Test-Path $appsISO) {
    $isoFile = Get-Item $appsISO
    $isoSizeGB = [math]::Round($isoFile.Length / 1GB, 2)
    Write-Host "Apps.iso exists: $appsISO" -ForegroundColor Green
    Write-Host "  Size: $isoSizeGB GB" -ForegroundColor Gray
    Write-Host "  Last Modified: $($isoFile.LastWriteTime)" -ForegroundColor Gray
} else {
    Write-Host "Apps.iso does not exist" -ForegroundColor Yellow
}
Write-Host ""

# Check for Remove-Updates function
Write-Host "Checking for Remove-Updates function bug..." -ForegroundColor Cyan
$vmModulePath = Join-Path $FFUDevelopmentPath "Modules\FFU.VM\FFU.VM.psm1"
if (Test-Path $vmModulePath) {
    $vmModuleContent = Get-Content $vmModulePath -Raw
    if ($vmModuleContent -match "Remove-Updates") {
        Write-Host "  FFU.VM module CALLS Remove-Updates function" -ForegroundColor Yellow

        # Check if function exists
        $modulesPath = Join-Path $FFUDevelopmentPath "Modules"
        $functionsFound = Get-ChildItem -Path $modulesPath -Recurse -Filter *.psm1 |
            Select-String -Pattern "^function Remove-Updates" -SimpleMatch

        if ($functionsFound) {
            Write-Host "  Remove-Updates function FOUND in: $($functionsFound.Path)" -ForegroundColor Green
        } else {
            Write-Host "  Remove-Updates function NOT FOUND in any module!" -ForegroundColor Red
            Write-Host "    ^ This is a BUG! Function is called but doesn't exist." -ForegroundColor Red
            Write-Host "    ^ However, this might be caught by try-catch and not cause the re-download issue." -ForegroundColor Yellow
        }
    }
}
Write-Host ""

# Summary and recommendations
Write-Host "=== DIAGNOSIS SUMMARY ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Possible causes of repeated downloads:" -ForegroundColor White
Write-Host "  1. Update folders exist but are EMPTY (size = 0)" -ForegroundColor Gray
Write-Host "  2. Update folders have files but SIZE < 1MB" -ForegroundColor Gray
Write-Host "  3. Folders are deleted by Remove-DisabledArtifacts (if update flags change between runs)" -ForegroundColor Gray
Write-Host "  4. Apps.iso cleanup removes folders during rebuild" -ForegroundColor Gray
Write-Host "  5. Remove-Updates function missing (causes error but might be silently caught)" -ForegroundColor Gray
Write-Host ""
Write-Host "To resolve:" -ForegroundColor Yellow
Write-Host "  - Check the output above for RED or YELLOW warnings" -ForegroundColor Yellow
Write-Host "  - If folders are empty, find what's deleting the files but not the folders" -ForegroundColor Yellow
Write-Host "  - If size < 1MB, check why downloads are incomplete or being partially deleted" -ForegroundColor Yellow
Write-Host ""
