# ============================================================
# WinPE Mount + Optional Component Injection Script
# ============================================================

$WinPERoot = "C:\WinPE_amd64"
$ADKRoot   = "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit"

# ---- Derived paths (no need to edit below this line) -------
$MountDir  = "$WinPERoot\mount"
$BootWim   = "$WinPERoot\media\sources\boot.wim"
$OCs       = "$ADKRoot\Windows Preinstallation Environment\amd64\WinPE_OCs"
$DISM      = "$ADKRoot\Deployment Tools\amd64\DISM\dism.exe"

# ---- Packages to inject (order matters) --------------------
$Packages = @(
    "WinPE-WMI.cab",
    "WinPE-NetFX.cab",
    "WinPE-Scripting.cab",
    "WinPE-PowerShell.cab",
    "WinPE-StorageWMI.cab"
)

# ============================================================
# Mount
# ============================================================
Write-Host "`n[1/3] Mounting boot.wim..." -ForegroundColor Cyan
& "$DISM" /Mount-Image /ImageFile:"$BootWim" /Index:1 /MountDir:"$MountDir"

if ($LASTEXITCODE -ne 0) {
    Write-Host "Mount failed. Aborting." -ForegroundColor Red
    exit 1
}

# ============================================================
# Inject optional components
# ============================================================
Write-Host "`n[2/3] Injecting optional components..." -ForegroundColor Cyan

foreach ($pkg in $Packages) {
    $pkgPath = "$OCs\$pkg"
    Write-Host "  Adding $pkg..." -ForegroundColor Gray

    if (-not (Test-Path $pkgPath)) {
        Write-Host "  ERROR: Package not found at $pkgPath" -ForegroundColor Red
        Write-Host "  Discarding mount and aborting." -ForegroundColor Red
        & "$DISM" /Unmount-Image /MountDir:"$MountDir" /Discard
        exit 1
    }

    & "$DISM" /Image:"$MountDir" /Add-Package /PackagePath:"$pkgPath"

    if ($LASTEXITCODE -ne 0) {
        Write-Host "  ERROR: Failed to add $pkg" -ForegroundColor Red
        Write-Host "  Discarding mount and aborting." -ForegroundColor Red
        & "$DISM" /Unmount-Image /MountDir:"$MountDir" /Discard
        exit 1
    }

    Write-Host "  OK" -ForegroundColor Green
}

# ============================================================
# Commit
# ============================================================
Write-Host "`n[3/3] Committing and unmounting..." -ForegroundColor Cyan
& "$DISM" /Unmount-Image /MountDir:"$MountDir" /Commit

if ($LASTEXITCODE -eq 0) {
    Write-Host "`nDone! WinPE image updated successfully." -ForegroundColor Green
} else {
    Write-Host "`nUnmount/commit failed. Check C:\Windows\Logs\DISM\dism.log" -ForegroundColor Red
    exit 1
}