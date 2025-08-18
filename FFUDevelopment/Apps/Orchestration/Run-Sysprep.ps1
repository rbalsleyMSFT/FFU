#The below lines will remove the unattend.xml that gets the machine into audit mode. If not removed, the OS will get stuck booting to audit mode each time.
#Also kills the sysprep process in order to automate sysprep generalize
Write-Host "Removing existing unattend.xml files and stopping sysprep process if running..."
Remove-Item -Path "C:\windows\panther\unattend\unattend.xml" -Force -ErrorAction SilentlyContinue
Remove-Item -Path "C:\windows\panther\unattend.xml" -Force -ErrorAction SilentlyContinue
Stop-Process -Name "sysprep" -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 10

# Detect and remediate per-user, non-provisioned Appx packages that would block Sysprep.
Write-Host "Checking for per-user Appx packages not provisioned for all users (potential Sysprep blockers)..."

# Build hash set of provisioned package families (DisplayName_PublisherId).
$provFamilies = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
Get-AppxProvisionedPackage -Online | ForEach-Object {
    $family = '{0}_{1}' -f $_.DisplayName, $_.PublisherId
    [void]$provFamilies.Add($family)
}

# Collect current user Appx packages excluding frameworks, resource packs, and non-removable packages.
$userApps = Get-AppxPackage -User $env:USERNAME | Where-Object {
    $_.Status -eq 'Ok' -and
    -not $_.IsFramework -and
    -not $_.IsResourcePackage -and
    -not $_.NonRemovable
}

# Identify packages not provisioned (per-user only).
$notProvisioned = foreach ($pkg in $userApps) {
    if (-not $provFamilies.Contains($pkg.PackageFamilyName)) {
        [PSCustomObject]@{
            Name              = $pkg.Name
            PackageFamilyName = $pkg.PackageFamilyName
            Version           = $pkg.Version
            SignatureKind     = $pkg.SignatureKind
            PackageFullName   = $pkg.PackageFullName
        }
    }
}

if ($notProvisioned) {
    Write-Host "Found $($notProvisioned.Count) per-user Appx package(s) not provisioned for all users:"
    $notProvisioned | Sort-Object PackageFamilyName | Format-Table -AutoSize -Property Name,PackageFamilyName,Version
    Write-Host "Attempting removal of per-user, non-provisioned Appx packages..."
    foreach ($pkg in $notProvisioned) {
        try {
            Write-Host "Removing $($pkg.PackageFullName)..."
            Remove-AppxPackage -Package $pkg.PackageFullName -ErrorAction Stop
        }
        catch {
            Write-Warning "Failed to remove $($pkg.PackageFullName): $($_.Exception.Message)"
        }
    }

    # Re-check after attempted removals.
    $remaining = @()
    $currentUserApps = Get-AppxPackage -User $env:USERNAME | Where-Object {
        $_.Status -eq 'Ok' -and
        -not $_.IsFramework -and
        -not $_.IsResourcePackage -and
        -not $_.NonRemovable
    }
    foreach ($pkg in $currentUserApps) {
        if (-not $provFamilies.Contains($pkg.PackageFamilyName)) {
            $remaining += $pkg
        }
    }

    if ($remaining.Count -gt 0) {
        Write-Error "Unable to remove all per-user, non-provisioned Appx packages. Sysprep cannot continue."
        $remaining | Sort-Object PackageFamilyName | Format-Table -AutoSize -Property Name,PackageFamilyName,Version
        throw "Sysprep aborted due to unresolved per-user Appx packages. Resolve manually and re-run."
    }
    else {
        Write-Host "All per-user, non-provisioned Appx packages were successfully removed."
    }
}
else {
    Write-Host "No per-user, non-provisioned Appx packages detected."
}

# If an Unattend.xml has been provided on the mounted Apps ISO (D:\Unattend\Unattend.xml),
# pass it to sysprep; otherwise, run without /unattend.
$unattendOnAppsIso = "D:\Unattend\Unattend.xml"
if (Test-Path -Path $unattendOnAppsIso) {
    Write-Host "Using $unattendOnAppsIso from Apps ISO..."
    & "C:\windows\system32\sysprep\sysprep.exe" /quiet /generalize /oobe /unattend:$unattendOnAppsIso
}
else {
    & "C:\windows\system32\sysprep\sysprep.exe" /quiet /generalize /oobe
}
