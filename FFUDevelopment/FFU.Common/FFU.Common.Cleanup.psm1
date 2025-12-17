# Provides shared cleanup functionality for both UI and build script.

function Invoke-FFUPostBuildCleanup {
    param(
        [string]$RootPath,
        [string]$AppsPath,
        [string]$DriversPath,
        [string]$FFUCapturePath,
        [string]$CaptureISOPath,
        [string]$DeployISOPath,
        [string]$AppsISOPath,
        [string]$KBPath,
        [bool]$RemoveCaptureISO = $false,
        [bool]$RemoveDeployISO = $false,
        [bool]$RemoveAppsISO = $false,
        [bool]$RemoveDrivers = $false,
        [bool]$RemoveFFU = $false,
        [bool]$RemoveApps = $false,
        [bool]$RemoveUpdates = $false
    )
    $originalProgressPreference = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'
    try {
        WriteLog "CommonCleanup: Starting cleanup (CaptureISO=$RemoveCaptureISO DeployISO=$RemoveDeployISO AppsISO=$RemoveAppsISO Drivers=$RemoveDrivers FFU=$RemoveFFU Apps=$RemoveApps Updates=$RemoveUpdates KBPath=$KBPath)."

        # Primary ISO paths (new naming/location)
        if ($RemoveCaptureISO -and -not [string]::IsNullOrWhiteSpace($CaptureISOPath) -and (Test-Path -LiteralPath $CaptureISOPath)) {
            WriteLog "CommonCleanup: Removing $CaptureISOPath"
            try { Remove-Item -LiteralPath $CaptureISOPath -Force -ErrorAction Stop } catch { WriteLog "CommonCleanup: Failed removing $CaptureISOPath : $($_.Exception.Message)" }
        }
        if ($RemoveDeployISO -and -not [string]::IsNullOrWhiteSpace($DeployISOPath) -and (Test-Path -LiteralPath $DeployISOPath)) {
            WriteLog "CommonCleanup: Removing $DeployISOPath"
            try { Remove-Item -LiteralPath $DeployISOPath -Force -ErrorAction Stop } catch { WriteLog "CommonCleanup: Failed removing $DeployISOPath : $($_.Exception.Message)" }
        }
        if ($RemoveAppsISO -and -not [string]::IsNullOrWhiteSpace($AppsISOPath) -and (Test-Path -LiteralPath $AppsISOPath)) {
            WriteLog "CommonCleanup: Removing $AppsISOPath"
            try { Remove-Item -LiteralPath $AppsISOPath -Force -ErrorAction Stop } catch { WriteLog "CommonCleanup: Failed removing $AppsISOPath : $($_.Exception.Message)" }
        }

        # Legacy / root-level WinPE ISOs (pattern-based)
        if ($RemoveCaptureISO) {
            Get-ChildItem -LiteralPath $RootPath -Filter 'WinPE_FFU_Capture*.iso' -ErrorAction SilentlyContinue | ForEach-Object {
                try { WriteLog "CommonCleanup: Removing legacy capture ISO $($_.FullName)"; Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop } catch { WriteLog "CommonCleanup: Failed removing legacy capture ISO $($_.FullName) : $($_.Exception.Message)" }
            }
        }
        if ($RemoveDeployISO) {
            Get-ChildItem -LiteralPath $RootPath -Filter 'WinPE_FFU_Deploy*.iso' -ErrorAction SilentlyContinue | ForEach-Object {
                try { WriteLog "CommonCleanup: Removing legacy deploy ISO $($_.FullName)"; Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop } catch { WriteLog "CommonCleanup: Failed removing legacy deploy ISO $($_.FullName) : $($_.Exception.Message)" }
            }
        }

        if ($RemoveDrivers -and -not [string]::IsNullOrWhiteSpace($DriversPath) -and (Test-Path -LiteralPath $DriversPath -PathType Container)) {
            WriteLog "CommonCleanup: Removing contents of $DriversPath (preserving Drivers.json and DriverMapping.json)"
            try {
                # Preserve drivers json files
                $driverItems = Get-ChildItem -LiteralPath $DriversPath -Force -ErrorAction SilentlyContinue | Where-Object { @('Drivers.json', 'DriverMapping.json') -notcontains $_.Name }
                if ($driverItems) {
                    $driverItems | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
                }
            }
            catch { WriteLog "CommonCleanup: Driver content cleanup issue: $($_.Exception.Message)" }
        }

        if ($RemoveFFU -and -not [string]::IsNullOrWhiteSpace($FFUCapturePath) -and (Test-Path -LiteralPath $FFUCapturePath -PathType Container)) {
            WriteLog "CommonCleanup: Removing FFU files in $FFUCapturePath"
            Get-ChildItem -LiteralPath $FFUCapturePath -Filter *.ffu -ErrorAction SilentlyContinue | ForEach-Object {
                try { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop } catch { WriteLog "CommonCleanup: Failed removing FFU $($_.FullName) : $($_.Exception.Message)" }
            }
        }

        if ($RemoveApps -and -not [string]::IsNullOrWhiteSpace($AppsPath) -and (Test-Path -LiteralPath $AppsPath -PathType Container)) {
            $win32 = Join-Path $AppsPath 'Win32'
            $store = Join-Path $AppsPath 'MSStore'
            if (Test-Path -LiteralPath $win32) {
                WriteLog "CommonCleanup: Removing $win32"
                try { Remove-Item -LiteralPath $win32 -Recurse -Force -ErrorAction Stop } catch { WriteLog "CommonCleanup: Failed removing $win32 : $($_.Exception.Message)" }
            }
            if (Test-Path -LiteralPath $store) {
                WriteLog "CommonCleanup: Removing $store"
                try { Remove-Item -LiteralPath $store -Recurse -Force -ErrorAction Stop } catch { WriteLog "CommonCleanup: Failed removing $store : $($_.Exception.Message)" }
            }
            $office = Join-Path $AppsPath 'Office'
            if ((Test-Path -LiteralPath $office) -and $InstallOffice) {
                WriteLog "CommonCleanup: Checking for Office artifacts in $office"
                $officeSub = Join-Path $office 'Office'
                if (Test-Path -LiteralPath $officeSub) {
                    WriteLog "CommonCleanup: Removing $officeSub"
                    try { Remove-Item -LiteralPath $officeSub -Recurse -Force -ErrorAction Stop } catch { WriteLog "CommonCleanup: Failed removing $officeSub : $($_.Exception.Message)" }
                }
                $setupExe = Join-Path $office 'setup.exe'
                if (Test-Path -LiteralPath $setupExe) {
                    WriteLog "CommonCleanup: Removing $setupExe"
                    try { Remove-Item -LiteralPath $setupExe -Force -ErrorAction Stop } catch { WriteLog "CommonCleanup: Failed removing $setupExe : $($_.Exception.Message)" }
                }
            }
        }

        if ($RemoveUpdates) {
            if (-not [string]::IsNullOrWhiteSpace($AppsPath) -and (Test-Path -LiteralPath $AppsPath)) {
                # Remove per-run app update payloads stored under Apps
                $appUpdateDirs = @('Defender', 'Edge', 'MSRT', 'OneDrive')
                foreach ($d in $appUpdateDirs) {
                    $target = Join-Path $AppsPath $d
                    if (Test-Path -LiteralPath $target) {
                        WriteLog "CommonCleanup: Removing update folder $target"
                        try { Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction Stop } catch { WriteLog "CommonCleanup: Failed removing $target : $($_.Exception.Message)" }
                    }
                }
            }
            if (-not [string]::IsNullOrWhiteSpace($KBPath) -and (Test-Path -LiteralPath $KBPath)) {
                # Remove Windows/.NET CU downloads stored under KB
                WriteLog "CommonCleanup: Removing downloaded updates in $KBPath"
                try { Remove-Item -LiteralPath $KBPath -Recurse -Force -ErrorAction Stop } catch { WriteLog "CommonCleanup: Failed removing $KBPath : $($_.Exception.Message)" }
            }
        }

        WriteLog "CommonCleanup: Completed."
    }
    catch {
        WriteLog "CommonCleanup: Fatal cleanup error $($_.Exception.Message)"
    }
    finally {
        $ProgressPreference = $originalProgressPreference
    }
}

Export-ModuleMember -Function Invoke-FFUPostBuildCleanup