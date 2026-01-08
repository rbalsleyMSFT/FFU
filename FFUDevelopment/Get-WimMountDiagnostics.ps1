<#
.SYNOPSIS
    Comprehensive WIM Mount troubleshooting script for error 0x800704DB diagnostics.

.DESCRIPTION
    Gathers extensive diagnostic data to identify why WIM mount operations fail with
    error 0x800704DB (WIM Filter driver service missing or not registered).

    This script checks:
    - WIMMount filter driver registration and status
    - WIMMount service configuration
    - Related services (fltmgr, BITS, TrustedInstaller)
    - Registry entries for WIM/DISM components
    - ADK installation status
    - Filter driver stack and altitudes
    - System file integrity
    - Pending operations
    - Security software that might interfere
    - Disk and file system status
    - Recent event log entries

.PARAMETER OutputPath
    Path for the output file. Default: C:\FFUDevelopment\Wim_troubleshooting.txt

.EXAMPLE
    .\Get-WimMountDiagnostics.ps1

.EXAMPLE
    .\Get-WimMountDiagnostics.ps1 -OutputPath "D:\Diagnostics\wim_diag.txt"

.NOTES
    Must be run as Administrator for complete diagnostics.
    Version: 1.0.0
    Author: FFU Builder Diagnostics
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$OutputPath = "C:\FFUDevelopment\Wim_troubleshooting.txt"
)

#region Helper Functions
function Write-Section {
    param([string]$Title)
    $separator = "=" * 80
    @"

$separator
$Title
$separator

"@
}

function Write-SubSection {
    param([string]$Title)
    @"

--- $Title ---

"@
}

function Safe-Execute {
    param(
        [scriptblock]$ScriptBlock,
        [string]$Description
    )
    try {
        $result = & $ScriptBlock
        if ($null -eq $result) {
            return "[No data returned]"
        }
        return $result
    }
    catch {
        return "[ERROR executing '$Description': $($_.Exception.Message)]"
    }
}

function Add-DiagnosticLine {
    param(
        [System.Text.StringBuilder]$Builder,
        [object]$Content
    )
    $text = $Content | Out-String
    $null = $Builder.AppendLine($text)
}
#endregion

#region Main Script
$ErrorActionPreference = 'Continue'
$diagnosticData = [System.Text.StringBuilder]::new()

# Header
$null = $diagnosticData.AppendLine(@"
################################################################################
#                    WIM MOUNT DIAGNOSTIC REPORT                               #
#                    Error 0x800704DB Investigation                            #
################################################################################

Report Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Computer Name: $env:COMPUTERNAME
User Context: $env:USERNAME
Running as Admin: $([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
PowerShell Version: $($PSVersionTable.PSVersion)
OS Version: $([Environment]::OSVersion.VersionString)

"@)

#region 1. WIMMount Filter Driver Status
$null = $diagnosticData.AppendLine((Write-Section "1. WIMMOUNT FILTER DRIVER STATUS"))

# Check if WimMount filter is loaded
$null = $diagnosticData.AppendLine((Write-SubSection "1.1 Filter Driver List (fltmc filters)"))
$fltmcOutput = Safe-Execute { fltmc filters 2>&1 } "fltmc filters"
Add-DiagnosticLine -Builder $diagnosticData -Content $fltmcOutput

# Specifically look for WimMount in the filter list
$null = $diagnosticData.AppendLine((Write-SubSection "1.2 WimMount Filter Search"))
$wimMountFilter = Safe-Execute {
    $filters = fltmc filters 2>&1
    $wimLine = $filters | Select-String -Pattern "WimMount|wimmount|WIM" -AllMatches
    if ($wimLine) {
        "WimMount filter FOUND in filter list:`n$($wimLine | Out-String)"
    } else {
        "WARNING: WimMount filter NOT FOUND in active filter list!"
    }
} "WimMount filter search"
$null = $diagnosticData.AppendLine($wimMountFilter)

# Check filter instances
$null = $diagnosticData.AppendLine((Write-SubSection "1.3 Filter Instances"))
$filterInstances = Safe-Execute { fltmc instances 2>&1 } "fltmc instances"
Add-DiagnosticLine -Builder $diagnosticData -Content $filterInstances

# Check attached volumes for WimMount
$null = $diagnosticData.AppendLine((Write-SubSection "1.4 Volumes with WimMount Attached"))
$wimVolumes = Safe-Execute {
    $volumes = fltmc volumes 2>&1
    $volumes
} "fltmc volumes"
Add-DiagnosticLine -Builder $diagnosticData -Content $wimVolumes
#endregion

#region 2. WIMMount Service Status
$null = $diagnosticData.AppendLine((Write-Section "2. WIMMOUNT SERVICE STATUS"))

# Check WimMount minifilter driver service
$null = $diagnosticData.AppendLine((Write-SubSection "2.1 WimMount Service (sc query)"))
$scQuery = Safe-Execute { sc.exe query wimmount 2>&1 } "sc query wimmount"
Add-DiagnosticLine -Builder $diagnosticData -Content $scQuery

# Get-Service for WimMount
$null = $diagnosticData.AppendLine((Write-SubSection "2.2 WimMount via Get-Service"))
$wimService = Safe-Execute {
    $svc = Get-Service -Name "wimmount" -ErrorAction SilentlyContinue
    if ($svc) {
        "Service Name: $($svc.Name)"
        "Display Name: $($svc.DisplayName)"
        "Status: $($svc.Status)"
        "Start Type: $($svc.StartType)"
        "Can Stop: $($svc.CanStop)"
    } else {
        "WARNING: WimMount service NOT FOUND via Get-Service!"
    }
} "Get-Service wimmount"
Add-DiagnosticLine -Builder $diagnosticData -Content $wimService

# Check service configuration
$null = $diagnosticData.AppendLine((Write-SubSection "2.3 WimMount Service Configuration (sc qc)"))
$scQc = Safe-Execute { sc.exe qc wimmount 2>&1 } "sc qc wimmount"
Add-DiagnosticLine -Builder $diagnosticData -Content $scQc

# WimMount driver file existence
$null = $diagnosticData.AppendLine((Write-SubSection "2.4 WimMount Driver File"))
$driverPaths = @(
    "$env:SystemRoot\System32\drivers\wimmount.sys"
    "$env:SystemRoot\SysWOW64\drivers\wimmount.sys"
)
foreach ($path in $driverPaths) {
    $fileInfo = Safe-Execute {
        if (Test-Path $path) {
            $file = Get-Item $path
            "File: $path"
            "  Exists: True"
            "  Size: $($file.Length) bytes"
            "  Version: $($file.VersionInfo.FileVersion)"
            "  Created: $($file.CreationTime)"
            "  Modified: $($file.LastWriteTime)"
        } else {
            "File: $path - NOT FOUND"
        }
    } "Check $path"
    Add-DiagnosticLine -Builder $diagnosticData -Content $fileInfo
}
#endregion

#region 3. Related Services
$null = $diagnosticData.AppendLine((Write-Section "3. RELATED SERVICES STATUS"))

$relatedServices = @(
    @{Name='fltmgr'; Description='Filter Manager'},
    @{Name='BITS'; Description='Background Intelligent Transfer'},
    @{Name='TrustedInstaller'; Description='Windows Modules Installer'},
    @{Name='wuauserv'; Description='Windows Update'},
    @{Name='msiserver'; Description='Windows Installer'},
    @{Name='CryptSvc'; Description='Cryptographic Services'},
    @{Name='DcomLaunch'; Description='DCOM Server Process Launcher'}
)

foreach ($svc in $relatedServices) {
    $svcStatus = Safe-Execute {
        $service = Get-Service -Name $svc.Name -ErrorAction SilentlyContinue
        if ($service) {
            "$($svc.Description) ($($svc.Name)): $($service.Status) [StartType: $($service.StartType)]"
        } else {
            "$($svc.Description) ($($svc.Name)): NOT FOUND"
        }
    } "Get-Service $($svc.Name)"
    $null = $diagnosticData.AppendLine($svcStatus)
}
#endregion

#region 4. Registry Analysis
$null = $diagnosticData.AppendLine((Write-Section "4. REGISTRY ANALYSIS"))

# WimMount service registry
$null = $diagnosticData.AppendLine((Write-SubSection "4.1 WimMount Service Registry"))
$wimMountReg = Safe-Execute {
    $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\WimMount"
    if (Test-Path $regPath) {
        Get-ItemProperty -Path $regPath | Format-List
    } else {
        "WARNING: WimMount service registry key NOT FOUND at $regPath"
    }
} "WimMount registry"
Add-DiagnosticLine -Builder $diagnosticData -Content $wimMountReg

# Filter manager instances for WimMount
$null = $diagnosticData.AppendLine((Write-SubSection "4.2 WimMount Filter Registration"))
$filterReg = Safe-Execute {
    $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\WimMount\Instances"
    if (Test-Path $regPath) {
        "Instances key exists"
        Get-ChildItem -Path $regPath -Recurse | ForEach-Object {
            $_.PSPath
            Get-ItemProperty -Path $_.PSPath | Format-List
        }
    } else {
        "WARNING: WimMount Instances registry key NOT FOUND"
    }
} "WimMount filter registration"
Add-DiagnosticLine -Builder $diagnosticData -Content $filterReg

# Check FltMgr registry
$null = $diagnosticData.AppendLine((Write-SubSection "4.3 Filter Manager Registry"))
$fltMgrReg = Safe-Execute {
    $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\FltMgr"
    if (Test-Path $regPath) {
        $props = Get-ItemProperty -Path $regPath
        "Start Type: $($props.Start)"
        "Type: $($props.Type)"
        "ImagePath: $($props.ImagePath)"
    } else {
        "WARNING: FltMgr registry key NOT FOUND"
    }
} "FltMgr registry"
$null = $diagnosticData.AppendLine($fltMgrReg)

# DISM registry settings
$null = $diagnosticData.AppendLine((Write-SubSection "4.4 DISM Configuration Registry"))
$dismReg = Safe-Execute {
    $regPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing"
        "HKLM:\SOFTWARE\Microsoft\Dism"
    )
    foreach ($path in $regPaths) {
        "Registry Path: $path"
        if (Test-Path $path) {
            Get-ItemProperty -Path $path -ErrorAction SilentlyContinue | Format-List
        } else {
            "  NOT FOUND"
        }
    }
} "DISM registry"
Add-DiagnosticLine -Builder $diagnosticData -Content $dismReg

# Pending file operations
$null = $diagnosticData.AppendLine((Write-SubSection "4.5 Pending File Rename Operations"))
$pendingOps = Safe-Execute {
    $regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager"
    $pending = Get-ItemProperty -Path $regPath -Name PendingFileRenameOperations -ErrorAction SilentlyContinue
    if ($pending.PendingFileRenameOperations) {
        "Pending operations found:"
        $pending.PendingFileRenameOperations | Where-Object { $_ } | ForEach-Object { "  $_" }
    } else {
        "No pending file rename operations"
    }
} "Pending operations"
$null = $diagnosticData.AppendLine($pendingOps)

# Check for reboot pending
$null = $diagnosticData.AppendLine((Write-SubSection "4.6 Reboot Pending Check"))
$rebootPending = Safe-Execute {
    $rebootRequired = $false
    $reasons = @()

    # CBS reboot pending
    if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending") {
        $rebootRequired = $true
        $reasons += "CBS RebootPending key exists"
    }

    # Windows Update reboot
    if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired") {
        $rebootRequired = $true
        $reasons += "Windows Update RebootRequired key exists"
    }

    # Pending file rename
    $pfro = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name PendingFileRenameOperations -EA SilentlyContinue
    if ($pfro.PendingFileRenameOperations) {
        $rebootRequired = $true
        $reasons += "PendingFileRenameOperations exist"
    }

    if ($rebootRequired) {
        "WARNING: REBOOT PENDING - This may cause WIM mount issues!"
        "Reasons:"
        $reasons | ForEach-Object { "  - $_" }
    } else {
        "No reboot pending detected"
    }
} "Reboot check"
$null = $diagnosticData.AppendLine($rebootPending)
#endregion

#region 5. Windows ADK Status
$null = $diagnosticData.AppendLine((Write-Section "5. WINDOWS ADK STATUS"))

$null = $diagnosticData.AppendLine((Write-SubSection "5.1 ADK Installation (Registry)"))
$adkReg = Safe-Execute {
    $adkPaths = @(
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows Kits\Installed Roots"
        "HKLM:\SOFTWARE\Microsoft\Windows Kits\Installed Roots"
    )
    foreach ($path in $adkPaths) {
        "Checking: $path"
        if (Test-Path $path) {
            $props = Get-ItemProperty -Path $path
            "  KitsRoot10: $($props.KitsRoot10)"
            "  KitsRoot81: $($props.KitsRoot81)"
            $props | Format-List
        } else {
            "  NOT FOUND"
        }
    }
} "ADK registry"
Add-DiagnosticLine -Builder $diagnosticData -Content $adkReg

$null = $diagnosticData.AppendLine((Write-SubSection "5.2 ADK Deployment Tools"))
$adkTools = Safe-Execute {
    $adkPaths = @(
        "${env:ProgramFiles(x86)}\Windows Kits\10\Assessment and Deployment Kit"
        "$env:ProgramFiles\Windows Kits\10\Assessment and Deployment Kit"
    )
    foreach ($basePath in $adkPaths) {
        "Checking: $basePath"
        if (Test-Path $basePath) {
            "  EXISTS"
            # Check for deployment tools
            $deployTools = Join-Path $basePath "Deployment Tools"
            if (Test-Path $deployTools) {
                "  Deployment Tools: EXISTS"
                # Check for DISM
                $dismPath = Join-Path $deployTools "amd64\DISM\dism.exe"
                if (Test-Path $dismPath) {
                    $dismFile = Get-Item $dismPath
                    "    DISM.exe: $dismPath"
                    "    Version: $($dismFile.VersionInfo.FileVersion)"
                }
            } else {
                "  Deployment Tools: NOT FOUND"
            }
            # Check for WinPE
            $winPE = Join-Path $basePath "Windows Preinstallation Environment"
            if (Test-Path $winPE) {
                "  Windows PE: EXISTS"
            } else {
                "  Windows PE: NOT FOUND"
            }
        } else {
            "  NOT FOUND"
        }
    }
} "ADK tools"
$null = $diagnosticData.AppendLine($adkTools)

$null = $diagnosticData.AppendLine((Write-SubSection "5.3 System DISM Version"))
$systemDism = Safe-Execute {
    $dismExe = "$env:SystemRoot\System32\Dism.exe"
    if (Test-Path $dismExe) {
        $file = Get-Item $dismExe
        "Path: $dismExe"
        "Version: $($file.VersionInfo.FileVersion)"
        "Product: $($file.VersionInfo.ProductName)"
        ""
        # Get DISM version output
        $dismVersion = & $dismExe /? 2>&1 | Select-Object -First 5
        $dismVersion
    } else {
        "System DISM.exe NOT FOUND"
    }
} "System DISM"
Add-DiagnosticLine -Builder $diagnosticData -Content $systemDism
#endregion

#region 6. DISM Component Status
$null = $diagnosticData.AppendLine((Write-Section "6. DISM COMPONENT STATUS"))

$null = $diagnosticData.AppendLine((Write-SubSection "6.1 DISM Log File Check"))
$dismLog = Safe-Execute {
    $logPath = "$env:SystemRoot\Logs\DISM\dism.log"
    if (Test-Path $logPath) {
        $logFile = Get-Item $logPath
        "Log file exists: $logPath"
        "Size: $($logFile.Length) bytes"
        "Modified: $($logFile.LastWriteTime)"
        ""
        "Last 50 lines of DISM log:"
        "---"
        Get-Content $logPath -Tail 50
    } else {
        "DISM log file not found at $logPath"
    }
} "DISM log"
Add-DiagnosticLine -Builder $diagnosticData -Content $dismLog

$null = $diagnosticData.AppendLine((Write-SubSection "6.2 Currently Mounted Images"))
$mountedImages = Safe-Execute {
    $result = dism /Get-MountedWimInfo 2>&1
    $result
} "Mounted images"
Add-DiagnosticLine -Builder $diagnosticData -Content $mountedImages

$null = $diagnosticData.AppendLine((Write-SubSection "6.3 Orphaned/Stale Mounts Check"))
$staleMounts = Safe-Execute {
    $output = @()
    # Check common mount point locations
    $mountPoints = @(
        "C:\Mount"
        "C:\FFUDevelopment\Mount"
        "$env:TEMP\Mount"
        "$env:SystemRoot\Temp\Mount"
    )

    foreach ($mp in $mountPoints) {
        if (Test-Path $mp) {
            $output += "Found mount point directory: $mp"
            $contents = Get-ChildItem $mp -ErrorAction SilentlyContinue
            if ($contents) {
                $output += "  Contents: $($contents.Count) items"
                $output += "  This may indicate a stale mount!"
            } else {
                $output += "  Empty (OK)"
            }
        }
    }

    # Check DISM mount registry
    $mountReg = "HKLM:\SOFTWARE\Microsoft\WIMMount\Mounted Images"
    if (Test-Path $mountReg) {
        $output += "Registry mounted images:"
        Get-ChildItem $mountReg | ForEach-Object {
            $output += "  $($_.PSChildName)"
        }
    }
    $output
} "Stale mounts"
Add-DiagnosticLine -Builder $diagnosticData -Content $staleMounts

$null = $diagnosticData.AppendLine((Write-SubSection "6.4 WIM Mount Functional Test"))
$wimTest = Safe-Execute {
    # Try to perform a simple DISM operation
    "Attempting DISM /Get-WimInfo on system recovery image..."
    $wimPath = "$env:SystemRoot\System32\Recovery\Winre.wim"
    if (Test-Path $wimPath) {
        $result = dism /Get-WimInfo /WimFile:$wimPath 2>&1
        $result
    } else {
        "No WinRE.wim found for testing. Trying install.wim if present..."
        $installWim = "D:\sources\install.wim"
        if (Test-Path $installWim) {
            $result = dism /Get-WimInfo /WimFile:$installWim 2>&1
            $result
        } else {
            "No WIM file available for functional test"
        }
    }
} "WIM test"
Add-DiagnosticLine -Builder $diagnosticData -Content $wimTest
#endregion

#region 7. System File Integrity
$null = $diagnosticData.AppendLine((Write-Section "7. SYSTEM FILE INTEGRITY"))

$null = $diagnosticData.AppendLine((Write-SubSection "7.1 Critical WIM-Related Files"))
$criticalFiles = @(
    "$env:SystemRoot\System32\dism.exe"
    "$env:SystemRoot\System32\Dism\DismCore.dll"
    "$env:SystemRoot\System32\Dism\DismHost.exe"
    "$env:SystemRoot\System32\Dism\DismProv.dll"
    "$env:SystemRoot\System32\Dism\WimProvider.dll"
    "$env:SystemRoot\System32\Dism\FolderProvider.dll"
    "$env:SystemRoot\System32\wimgapi.dll"
    "$env:SystemRoot\System32\drivers\wimmount.sys"
    "$env:SystemRoot\System32\wdscore.dll"
    "$env:SystemRoot\System32\imagesp1.dll"
)

foreach ($file in $criticalFiles) {
    $fileCheck = Safe-Execute {
        if (Test-Path $file) {
            $f = Get-Item $file
            "$file"
            "  Version: $($f.VersionInfo.FileVersion)"
            "  Size: $($f.Length)"
        } else {
            "$file - MISSING!"
        }
    } "Check $file"
    $null = $diagnosticData.AppendLine($fileCheck)
}

$null = $diagnosticData.AppendLine((Write-SubSection "7.2 SFC /SCANNOW Status (Last Run)"))
$sfcStatus = Safe-Execute {
    $cbsLog = "$env:SystemRoot\Logs\CBS\CBS.log"
    if (Test-Path $cbsLog) {
        "CBS Log exists. Checking for recent SFC results..."
        $sfcLines = Select-String -Path $cbsLog -Pattern "Verify complete|corruption|repair" -Context 0,2 |
                    Select-Object -Last 10
        if ($sfcLines) {
            $sfcLines | ForEach-Object { $_.Line }
        } else {
            "No recent SFC activity found in CBS log"
        }
    } else {
        "CBS log not found"
    }
} "SFC status"
$null = $diagnosticData.AppendLine($sfcStatus)
#endregion

#region 8. Security Software Check
$null = $diagnosticData.AppendLine((Write-Section "8. SECURITY SOFTWARE CHECK"))

$null = $diagnosticData.AppendLine((Write-SubSection "8.1 Antivirus Products"))
$avProducts = Safe-Execute {
    try {
        $av = Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntiVirusProduct -ErrorAction SilentlyContinue
        if ($av) {
            $av | ForEach-Object {
                "Product: $($_.displayName)"
                "Path: $($_.pathToSignedProductExe)"
                "State: $($_.productState)"
                ""
            }
        } else {
            "No AV products registered in SecurityCenter2"
        }
    }
    catch {
        "Unable to query SecurityCenter2 (may not be available on Server OS)"
    }
} "AV products"
Add-DiagnosticLine -Builder $diagnosticData -Content $avProducts

$null = $diagnosticData.AppendLine((Write-SubSection "8.2 Windows Defender Status"))
$defenderStatus = Safe-Execute {
    if (Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue) {
        $status = Get-MpComputerStatus
        "Real-Time Protection: $($status.RealTimeProtectionEnabled)"
        "Behavior Monitor: $($status.BehaviorMonitorEnabled)"
        "On-Access Protection: $($status.OnAccessProtectionEnabled)"
        "Anti-Spyware: $($status.AntispywareEnabled)"
        "Anti-Virus: $($status.AntivirusEnabled)"
    } else {
        "Get-MpComputerStatus not available (Defender may not be installed)"
    }
} "Defender status"
$null = $diagnosticData.AppendLine($defenderStatus)

$null = $diagnosticData.AppendLine((Write-SubSection "8.3 Third-Party Filter Drivers"))
$thirdPartyFilters = Safe-Execute {
    $filters = fltmc filters 2>&1
    $knownMS = @('bindflt','cldflt','FileCrypt','FileInfo','iorate','luafv','npsvctrig','storqosflt','wcifs','wcnfs','WdFilter','Wof','WimMount')

    $output = @("Non-Microsoft filter drivers that may interfere with WIM operations:")
    $filters | ForEach-Object {
        $line = $_.ToString()
        $isMS = $false
        foreach ($ms in $knownMS) {
            if ($line -match $ms) { $isMS = $true; break }
        }
        if (-not $isMS -and $line -match '^\w+') {
            $output += $line
        }
    }
    $output
} "Third-party filters"
Add-DiagnosticLine -Builder $diagnosticData -Content $thirdPartyFilters
#endregion

#region 9. PowerShell DISM Module
$null = $diagnosticData.AppendLine((Write-Section "9. POWERSHELL DISM MODULE"))

$null = $diagnosticData.AppendLine((Write-SubSection "9.1 DISM Module Info"))
$dismModule = Safe-Execute {
    $module = Get-Module -Name DISM -ListAvailable
    if ($module) {
        "Module found:"
        "  Name: $($module.Name)"
        "  Version: $($module.Version)"
        "  Path: $($module.Path)"
        "  ModuleBase: $($module.ModuleBase)"
    } else {
        "DISM module NOT FOUND in available modules"
    }
} "DISM module"
$null = $diagnosticData.AppendLine($dismModule)

$null = $diagnosticData.AppendLine((Write-SubSection "9.2 Mount-WindowsImage Command"))
$mountCmd = Safe-Execute {
    $cmd = Get-Command Mount-WindowsImage -ErrorAction SilentlyContinue
    if ($cmd) {
        $output = @()
        $output += "Command found: Mount-WindowsImage"
        $output += "  Module: $($cmd.ModuleName)"
        $output += "  Source: $($cmd.Source)"
        $output += "Parameters:"
        $cmd.Parameters.Keys | ForEach-Object { $output += "  - $_" }
        $output
    } else {
        "Mount-WindowsImage command NOT FOUND"
    }
} "Mount-WindowsImage"
Add-DiagnosticLine -Builder $diagnosticData -Content $mountCmd

$null = $diagnosticData.AppendLine((Write-SubSection "9.3 Test Mount-WindowsImage"))
$testMount = Safe-Execute {
    "Testing Mount-WindowsImage cmdlet availability..."
    try {
        Import-Module DISM -ErrorAction Stop
        "DISM module imported successfully"

        # Test with invalid path to check if cmdlet works
        $mountError = $null
        try {
            Mount-WindowsImage -ImagePath "C:\nonexistent.wim" -Path "C:\nonexistent" -Index 1 -ErrorAction Stop
        }
        catch {
            $mountError = $_.Exception.Message
        }

        if ($mountError) {
            if ($mountError -match "0x800704DB") {
                "ERROR: Mount-WindowsImage fails with 0x800704DB - WimMount filter issue confirmed!"
            } elseif ($mountError -match "not find|not exist|path|could not be found") {
                "Mount-WindowsImage cmdlet works (failed due to nonexistent test path - expected)"
            } else {
                "Mount-WindowsImage error: $mountError"
            }
        }
    }
    catch {
        "Error testing Mount-WindowsImage: $($_.Exception.Message)"
    }
} "Test mount"
$null = $diagnosticData.AppendLine($testMount)
#endregion

#region 10. Event Logs
$null = $diagnosticData.AppendLine((Write-Section "10. RELEVANT EVENT LOGS"))

$null = $diagnosticData.AppendLine((Write-SubSection "10.1 System Events - Filter Manager"))
$fltEvents = Safe-Execute {
    $events = Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-FilterManager'; StartTime=(Get-Date).AddDays(-7)} -MaxEvents 20 -ErrorAction SilentlyContinue
    if ($events) {
        $events | ForEach-Object {
            "[$($_.TimeCreated)] Level:$($_.LevelDisplayName) ID:$($_.Id)"
            "  $($_.Message)"
            ""
        }
    } else {
        "No FilterManager events in last 7 days"
    }
} "Filter manager events"
Add-DiagnosticLine -Builder $diagnosticData -Content $fltEvents

$null = $diagnosticData.AppendLine((Write-SubSection "10.2 Application Events - DISM"))
$dismEvents = Safe-Execute {
    $events = Get-WinEvent -FilterHashtable @{LogName='Application'; StartTime=(Get-Date).AddDays(-7)} -MaxEvents 100 -ErrorAction SilentlyContinue |
    Where-Object { $_.Message -match 'DISM|WIM|mount' } |
    Select-Object -First 20
    if ($events) {
        $events | ForEach-Object {
            "[$($_.TimeCreated)] Level:$($_.LevelDisplayName) ID:$($_.Id)"
            "  $($_.Message)"
            ""
        }
    } else {
        "No DISM-related Application events in last 7 days"
    }
} "DISM events"
Add-DiagnosticLine -Builder $diagnosticData -Content $dismEvents

$null = $diagnosticData.AppendLine((Write-SubSection "10.3 System Events - Service Control Manager"))
$scmEvents = Safe-Execute {
    $events = Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Service Control Manager'; StartTime=(Get-Date).AddDays(-7)} -MaxEvents 50 -ErrorAction SilentlyContinue |
    Where-Object { $_.Message -match 'WIM|wimmount|flt|filter' } |
    Select-Object -First 10
    if ($events) {
        $events | ForEach-Object {
            "[$($_.TimeCreated)] Level:$($_.LevelDisplayName) ID:$($_.Id)"
            "  $($_.Message)"
            ""
        }
    } else {
        "No WIM-related Service Control Manager events in last 7 days"
    }
} "SCM events"
Add-DiagnosticLine -Builder $diagnosticData -Content $scmEvents
#endregion

#region 11. Disk and Storage Status
$null = $diagnosticData.AppendLine((Write-Section "11. DISK AND STORAGE STATUS"))

$null = $diagnosticData.AppendLine((Write-SubSection "11.1 Volume Information"))
$volumes = Safe-Execute {
    Get-Volume | Where-Object { $_.DriveLetter } | ForEach-Object {
        "$($_.DriveLetter): $($_.FileSystemLabel)"
        "  FileSystem: $($_.FileSystem)"
        "  Size: $([math]::Round($_.Size/1GB, 2)) GB"
        "  Free: $([math]::Round($_.SizeRemaining/1GB, 2)) GB"
        "  Health: $($_.HealthStatus)"
        ""
    }
} "Volumes"
Add-DiagnosticLine -Builder $diagnosticData -Content $volumes

$null = $diagnosticData.AppendLine((Write-SubSection "11.2 File System Filter Status by Volume"))
$volumeFilters = Safe-Execute {
    $attachResult = fltmc attach 2>&1
    $attachResult
} "Volume filters"
Add-DiagnosticLine -Builder $diagnosticData -Content $volumeFilters
#endregion

#region 12. Environment and Path
$null = $diagnosticData.AppendLine((Write-Section "12. ENVIRONMENT INFORMATION"))

$null = $diagnosticData.AppendLine((Write-SubSection "12.1 System PATH"))
$pathInfo = Safe-Execute {
    $env:PATH -split ';' | ForEach-Object { $_ }
} "PATH"
Add-DiagnosticLine -Builder $diagnosticData -Content $pathInfo

$null = $diagnosticData.AppendLine((Write-SubSection "12.2 PSModulePath"))
$psModulePath = Safe-Execute {
    $env:PSModulePath -split ';' | ForEach-Object { $_ }
} "PSModulePath"
Add-DiagnosticLine -Builder $diagnosticData -Content $psModulePath

$null = $diagnosticData.AppendLine((Write-SubSection "12.3 Windows Feature Status"))
$features = Safe-Execute {
    Get-WindowsOptionalFeature -Online -ErrorAction SilentlyContinue | Where-Object { $_.FeatureName -match 'Hyper-V|Container|Sandbox|WSL' } |
    ForEach-Object {
        "$($_.FeatureName): $($_.State)"
    }
} "Features"
Add-DiagnosticLine -Builder $diagnosticData -Content $features
#endregion

#region 13. Remediation Suggestions
$null = $diagnosticData.AppendLine((Write-Section "13. REMEDIATION SUGGESTIONS"))

$null = $diagnosticData.AppendLine(@"
Based on the diagnostics above, try these remediation steps in order:

1. RESTART THE WIMMOUNT SERVICE:
   sc stop wimmount
   sc start wimmount
   -- OR --
   Stop-Service wimmount -Force; Start-Service wimmount

2. RE-REGISTER THE WIMMOUNT FILTER:
   fltmc unload WimMount
   fltmc load WimMount

3. CHECK FOR PENDING REBOOT:
   If reboot is pending, restart the system before attempting WIM operations.

4. CLEANUP STALE MOUNTS:
   dism /Cleanup-Mountdir
   dism /Cleanup-Wim

5. REPAIR SYSTEM FILES:
   sfc /scannow
   DISM /Online /Cleanup-Image /RestoreHealth

6. REINSTALL WIMMOUNT DRIVER:
   pnputil /delete-driver oem#.inf /uninstall  (find the WimMount inf)
   pnputil /add-driver %SystemRoot%\System32\DriverStore\FileRepository\wimmount.inf_*\wimmount.inf /install

7. RE-REGISTER DISM COMPONENTS:
   regsvr32 /s wimgapi.dll
   regsvr32 /s wdscore.dll

8. DISABLE CONFLICTING SOFTWARE:
   Temporarily disable antivirus/security software that may be intercepting file operations.

9. REPAIR WINDOWS ADK:
   Uninstall and reinstall Windows ADK with Deployment Tools and Windows PE add-on.

10. LAST RESORT - IN-PLACE UPGRADE:
    Run Windows Setup with /repair option to repair system components.

"@)
#endregion

#region 14. Raw Diagnostic Commands
$null = $diagnosticData.AppendLine((Write-Section "14. RAW DIAGNOSTIC COMMAND OUTPUT"))

$null = $diagnosticData.AppendLine((Write-SubSection "14.1 driverquery for WIM"))
$driverQuery = Safe-Execute {
    driverquery /v | Select-String -Pattern "wim"
} "driverquery"
Add-DiagnosticLine -Builder $diagnosticData -Content $driverQuery

$null = $diagnosticData.AppendLine((Write-SubSection "14.2 sc query type= filesys"))
$fsDrivers = Safe-Execute {
    sc.exe query type= filesys 2>&1
} "fs drivers"
Add-DiagnosticLine -Builder $diagnosticData -Content $fsDrivers

$null = $diagnosticData.AppendLine((Write-SubSection "14.3 WMI Win32_SystemDriver WimMount"))
$wmiDriver = Safe-Execute {
    Get-CimInstance Win32_SystemDriver | Where-Object { $_.Name -match 'wim' } | Format-List
} "WMI driver"
Add-DiagnosticLine -Builder $diagnosticData -Content $wmiDriver
#endregion

# Write output file
$outputDir = Split-Path $OutputPath -Parent
if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

$diagnosticData.ToString() | Out-File -FilePath $OutputPath -Encoding UTF8 -Force

Write-Host ""
Write-Host ("=" * 60) -ForegroundColor Cyan
Write-Host "WIM Mount Diagnostic Report Complete" -ForegroundColor Green
Write-Host ("=" * 60) -ForegroundColor Cyan
Write-Host ""
Write-Host "Report saved to: $OutputPath" -ForegroundColor Yellow
Write-Host ""
Write-Host "Key areas to review:" -ForegroundColor White
Write-Host "  1. Section 1-2: WimMount filter/service status" -ForegroundColor Gray
Write-Host "  2. Section 4.6: Pending reboot check" -ForegroundColor Gray
Write-Host "  3. Section 6.3: Stale/orphaned mounts" -ForegroundColor Gray
Write-Host "  4. Section 8: Security software interference" -ForegroundColor Gray
Write-Host "  5. Section 13: Remediation suggestions" -ForegroundColor Gray
Write-Host ""

# Return the output path
return $OutputPath
#endregion
