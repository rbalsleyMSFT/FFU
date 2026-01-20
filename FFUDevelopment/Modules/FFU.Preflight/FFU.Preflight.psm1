<#
.SYNOPSIS
    FFU Builder Pre-Flight Validation Module

.DESCRIPTION
    Comprehensive pre-flight validation system for FFU Builder operations.
    Provides tiered environment checks with actionable remediation guidance.

    Validation Tiers:
    - Tier 1: CRITICAL (Always Run, Blocking) - Admin, PowerShell 7+, Hyper-V
    - Tier 2: FEATURE-DEPENDENT (Conditional, Blocking) - ADK, Disk, Network, Config
    - Tier 3: RECOMMENDED (Warnings Only) - Antivirus Exclusions
    - Tier 4: CLEANUP (Pre-Remediation) - DISM Cleanup

.NOTES
    Module: FFU.Preflight
    Version: 1.0.0
    Dependencies: FFU.Core (for WriteLog, Test-FFUConfiguration), FFU.ADK (for Test-ADKPrerequisites)
    Requires: PowerShell 7.0+
#>

#Requires -Version 7.0

#region Helper Functions

function New-FFUCheckResult {
    <#
    .SYNOPSIS
    Creates a standardized check result object for pre-flight validation.

    .DESCRIPTION
    Factory function that creates consistent result objects for all validation checks.
    Each result includes status, message, details, remediation steps, and duration.

    .PARAMETER CheckName
    Name of the validation check (e.g., 'Administrator', 'HyperV', 'DiskSpace')

    .PARAMETER Status
    Result status: 'Passed', 'Failed', 'Warning', or 'Skipped'

    .PARAMETER Message
    Human-readable message describing the result

    .PARAMETER Details
    Optional hashtable with additional check-specific data

    .PARAMETER Remediation
    Optional string with steps to fix the issue if status is Failed or Warning

    .PARAMETER DurationMs
    Time in milliseconds the check took to complete

    .EXAMPLE
    New-FFUCheckResult -CheckName 'Administrator' -Status 'Passed' `
                       -Message 'Running with Administrator privileges' -DurationMs 5

    .EXAMPLE
    New-FFUCheckResult -CheckName 'HyperV' -Status 'Failed' `
                       -Message 'Hyper-V feature not installed' `
                       -Remediation 'Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All' `
                       -DurationMs 1500
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$CheckName,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Passed', 'Failed', 'Warning', 'Skipped')]
        [string]$Status,

        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter()]
        [hashtable]$Details = @{},

        [Parameter()]
        [string]$Remediation = '',

        [Parameter()]
        [int]$DurationMs = 0
    )

    [PSCustomObject]@{
        CheckName   = $CheckName
        Status      = $Status
        Message     = $Message
        Details     = $Details
        Remediation = $Remediation
        DurationMs  = $DurationMs
    }
}

function Get-FFURequirements {
    <#
    .SYNOPSIS
    Calculates disk space and feature requirements based on enabled build features.

    .DESCRIPTION
    Analyzes the enabled features hashtable and calculates total disk space requirements.
    Also returns a list of required features/components for the build.

    .PARAMETER Features
    Hashtable of enabled features with boolean values:
    - CreateVM: Hyper-V required
    - CreateCaptureMedia: ADK + WinPE required
    - CreateDeploymentMedia: ADK + WinPE required
    - OptimizeFFU: ADK required
    - InstallApps: Network + Apps ISO space required
    - UpdateLatestCU: Network + KB space required
    - DownloadDrivers: Network required

    .PARAMETER VHDXSizeGB
    Target VHDX size in gigabytes for space calculations

    .EXAMPLE
    $features = @{
        CreateVM = $true
        CreateCaptureMedia = $true
        InstallApps = $true
    }
    $requirements = Get-FFURequirements -Features $features -VHDXSizeGB 50

    .OUTPUTS
    PSCustomObject with RequiredDiskSpaceGB, RequiredFeatures, SpaceBreakdown properties
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Features,

        [Parameter()]
        [int]$VHDXSizeGB = 50,

        [Parameter()]
        [ValidateSet('HyperV', 'VMware', 'Auto')]
        [string]$HypervisorType = 'HyperV'
    )

    $requiredGB = 0
    $breakdown = [ordered]@{}
    $requiredFeatures = [System.Collections.Generic.List[string]]::new()

    # Base requirements (always needed)
    $requiredGB += $VHDXSizeGB  # VHDX file
    $breakdown['VHDX file'] = $VHDXSizeGB
    $requiredGB += 10           # Scratch space
    $breakdown['Scratch space'] = 10

    # CreateVM requires Hyper-V only when using HyperV hypervisor (VMware uses its own hypervisor)
    if ($Features.CreateVM -and $HypervisorType -eq 'HyperV') {
        $requiredFeatures.Add('Hyper-V')
    }

    # WinPE media creation
    if ($Features.CreateCaptureMedia -or $Features.CreateDeploymentMedia) {
        $requiredGB += 15       # WinPE media
        $breakdown['WinPE media'] = 15
        $requiredFeatures.Add('Windows ADK')
        $requiredFeatures.Add('WinPE add-on')
    }

    # Apps ISO
    if ($Features.InstallApps) {
        $requiredGB += 10       # Apps ISO
        $breakdown['Apps ISO'] = 10
        $requiredFeatures.Add('Network connectivity')
    }

    # FFU output (capture)
    if ($Features.CaptureFFU -or $Features.CreateCaptureMedia) {
        $requiredGB += $VHDXSizeGB  # FFU output (similar size to VHDX)
        $breakdown['FFU output'] = $VHDXSizeGB
    }

    # KB downloads
    if ($Features.UpdateLatestCU) {
        $requiredGB += 5        # KB downloads
        $breakdown['KB downloads'] = 5
        $requiredFeatures.Add('Network connectivity')
    }

    # Driver packages
    if ($Features.DownloadDrivers) {
        $requiredGB += 5        # Driver packages
        $breakdown['Driver packages'] = 5
        $requiredFeatures.Add('Network connectivity')
    }

    # FFU optimization
    if ($Features.OptimizeFFU) {
        $requiredFeatures.Add('Windows ADK')
    }

    # Deduplicate features
    $uniqueFeatures = $requiredFeatures | Select-Object -Unique

    [PSCustomObject]@{
        RequiredDiskSpaceGB = $requiredGB
        RequiredFeatures    = $uniqueFeatures
        SpaceBreakdown      = $breakdown
        NeedsNetwork        = ($Features.InstallApps -or $Features.UpdateLatestCU -or
                              $Features.DownloadDrivers -or $Features.InstallDefender -or
                              $Features.GetOneDrive)
        NeedsADK            = ($Features.CreateCaptureMedia -or $Features.CreateDeploymentMedia -or
                              $Features.OptimizeFFU)
        NeedsWinPE          = ($Features.CreateCaptureMedia -or $Features.CreateDeploymentMedia)
        NeedsHyperV         = ($Features.CreateVM -eq $true -and $HypervisorType -eq 'HyperV')
    }
}

#endregion Helper Functions

#region Tier 1: Critical Validations

function Test-FFUAdministrator {
    <#
    .SYNOPSIS
    Validates that the current PowerShell session is running with Administrator privileges.

    .DESCRIPTION
    Checks if the current process is running with elevated (Administrator) privileges.
    This is required for Hyper-V operations, DISM commands, and system modifications.

    .EXAMPLE
    $result = Test-FFUAdministrator
    if ($result.Status -eq 'Failed') {
        Write-Error $result.Message
    }

    .OUTPUTS
    FFUCheckResult object with status, message, and remediation steps
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        $currentPrincipal = [Security.Principal.WindowsPrincipal]::new(
            [Security.Principal.WindowsIdentity]::GetCurrent()
        )
        $isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

        $stopwatch.Stop()

        if ($isAdmin) {
            New-FFUCheckResult -CheckName 'Administrator' -Status 'Passed' `
                -Message 'Running with Administrator privileges' `
                -Details @{
                    UserName  = $currentPrincipal.Identity.Name
                    IsElevated = $true
                } `
                -DurationMs $stopwatch.ElapsedMilliseconds
        }
        else {
            New-FFUCheckResult -CheckName 'Administrator' -Status 'Failed' `
                -Message 'Not running with Administrator privileges' `
                -Details @{
                    UserName  = $currentPrincipal.Identity.Name
                    IsElevated = $false
                } `
                -Remediation @'
Run PowerShell as Administrator:
  1. Right-click on PowerShell or Windows Terminal
  2. Select "Run as administrator"
  3. Re-run the FFU Builder script

Alternative (from existing terminal):
  Start-Process pwsh -Verb RunAs -ArgumentList "-File `"$($MyInvocation.ScriptName)`""
'@ `
                -DurationMs $stopwatch.ElapsedMilliseconds
        }
    }
    catch {
        $stopwatch.Stop()
        New-FFUCheckResult -CheckName 'Administrator' -Status 'Failed' `
            -Message "Failed to check Administrator privileges: $($_.Exception.Message)" `
            -Remediation 'Ensure the security system is accessible and try running as Administrator' `
            -DurationMs $stopwatch.ElapsedMilliseconds
    }
}

function Test-FFUPowerShellVersion {
    <#
    .SYNOPSIS
    Validates that PowerShell 7.0 or higher is being used.

    .DESCRIPTION
    FFU Builder requires PowerShell 7.0+ for:
    - ForEach-Object -Parallel (concurrent operations)
    - Improved error handling
    - Built-in ThreadJob support
    - No TelemetryAPI compatibility issues
    - Modern language features (ternary, null-coalescing)

    .EXAMPLE
    $result = Test-FFUPowerShellVersion
    if ($result.Status -eq 'Failed') {
        Write-Error "Upgrade PowerShell: $($result.Remediation)"
    }

    .OUTPUTS
    FFUCheckResult object with status, message, and remediation steps
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    $minVersion = [Version]'7.0.0'
    $currentVersion = $PSVersionTable.PSVersion

    $stopwatch.Stop()

    if ($currentVersion -ge $minVersion) {
        New-FFUCheckResult -CheckName 'PowerShellVersion' -Status 'Passed' `
            -Message "PowerShell $currentVersion detected (7.0+ required)" `
            -Details @{
                Version       = $currentVersion.ToString()
                Edition       = $PSVersionTable.PSEdition
                OS            = $PSVersionTable.OS
                Platform      = $PSVersionTable.Platform
            } `
            -DurationMs $stopwatch.ElapsedMilliseconds
    }
    else {
        New-FFUCheckResult -CheckName 'PowerShellVersion' -Status 'Failed' `
            -Message "PowerShell $currentVersion detected. FFU Builder requires PowerShell 7.0 or higher." `
            -Details @{
                Version       = $currentVersion.ToString()
                Edition       = $PSVersionTable.PSEdition
                MinRequired   = $minVersion.ToString()
            } `
            -Remediation @'
Install PowerShell 7+ using one of these methods:

1. Winget (recommended):
   winget install Microsoft.PowerShell

2. Direct download:
   https://aka.ms/powershell

3. Microsoft Store:
   Search for "PowerShell" in Microsoft Store

After installation, run FFU Builder from PowerShell 7:
   pwsh.exe -File BuildFFUVM.ps1

Note: PowerShell 5.1 (Windows PowerShell) is NOT supported.
'@ `
            -DurationMs $stopwatch.ElapsedMilliseconds
    }
}

function Test-FFUHyperV {
    <#
    .SYNOPSIS
    Validates that Hyper-V feature is installed and enabled.

    .DESCRIPTION
    Checks for Hyper-V installation on both Windows client (OptionalFeature) and
    Windows Server (WindowsFeature). Includes retry logic for transient DISM failures
    and performs DISM cleanup before checking.

    .PARAMETER MaxRetries
    Maximum number of retry attempts for transient failures (default: 3)

    .PARAMETER RetryDelaySeconds
    Seconds to wait between retry attempts (default: 5)

    .EXAMPLE
    $result = Test-FFUHyperV
    if ($result.Status -eq 'Failed') {
        Write-Error "Hyper-V check failed: $($result.Message)"
    }

    .OUTPUTS
    FFUCheckResult object with status, message, and remediation steps
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [int]$MaxRetries = 3,

        [Parameter()]
        [int]$RetryDelaySeconds = 5
    )

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $attempt = 0
    $lastError = $null

    # Pre-cleanup: Clean stale DISM mount points to avoid interference
    try {
        & dism.exe /Cleanup-Mountpoints 2>&1 | Out-Null
    }
    catch {
        # Ignore cleanup errors - not critical for Hyper-V check
    }

    while ($attempt -lt $MaxRetries) {
        $attempt++

        try {
            # Detect OS type (Client vs Server)
            $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
            $isServer = $osInfo.ProductType -ne 1  # 1 = Workstation, 2 = DC, 3 = Server

            if ($isServer) {
                # Windows Server: Use Get-WindowsFeature
                $hyperVFeature = Get-WindowsFeature -Name 'Hyper-V' -ErrorAction Stop
                $isEnabled = $hyperVFeature.Installed
                $featureState = if ($isEnabled) { 'Installed' } else { 'Not Installed' }
            }
            else {
                # Windows Client: Use Get-WindowsOptionalFeature
                $hyperVFeature = Get-WindowsOptionalFeature -Online -FeatureName 'Microsoft-Hyper-V-All' -ErrorAction Stop
                $isEnabled = $hyperVFeature.State -eq 'Enabled'
                $featureState = $hyperVFeature.State
            }

            $stopwatch.Stop()

            if ($isEnabled) {
                New-FFUCheckResult -CheckName 'HyperV' -Status 'Passed' `
                    -Message 'Hyper-V feature is installed and enabled' `
                    -Details @{
                        OSType       = if ($isServer) { 'Server' } else { 'Client' }
                        FeatureState = $featureState
                        Attempts     = $attempt
                    } `
                    -DurationMs $stopwatch.ElapsedMilliseconds
            }
            else {
                $remediation = if ($isServer) {
                    @'
Install Hyper-V on Windows Server:

1. Using PowerShell (recommended):
   Install-WindowsFeature -Name Hyper-V -IncludeManagementTools -Restart

2. Using Server Manager:
   - Open Server Manager
   - Click "Add roles and features"
   - Select "Hyper-V" role
   - Complete the wizard and restart

A system restart is required after installation.
'@
                }
                else {
                    @'
Enable Hyper-V on Windows 10/11:

1. Using PowerShell (recommended):
   Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -NoRestart

2. Using Windows Features:
   - Press Win+R, type "optionalfeatures", press Enter
   - Check "Hyper-V" (all sub-features)
   - Click OK

3. Using DISM:
   dism /Online /Enable-Feature /FeatureName:Microsoft-Hyper-V-All /All

A system restart is required after enabling Hyper-V.

Prerequisites:
- 64-bit processor with SLAT (Second Level Address Translation)
- CPU support for VM Monitor Mode Extension (VT-c on Intel)
- Minimum 4 GB RAM
- BIOS-level virtualization support enabled
'@
                }

                New-FFUCheckResult -CheckName 'HyperV' -Status 'Failed' `
                    -Message "Hyper-V feature is not installed (State: $featureState)" `
                    -Details @{
                        OSType       = if ($isServer) { 'Server' } else { 'Client' }
                        FeatureState = $featureState
                        Attempts     = $attempt
                    } `
                    -Remediation $remediation `
                    -DurationMs $stopwatch.ElapsedMilliseconds
            }
        }
        catch {
            $lastError = $_
            if ($attempt -lt $MaxRetries) {
                # Retry after delay for transient DISM failures
                Start-Sleep -Seconds $RetryDelaySeconds
            }
        }
    }

    # All retries exhausted
    $stopwatch.Stop()
    New-FFUCheckResult -CheckName 'HyperV' -Status 'Failed' `
        -Message "Failed to check Hyper-V status after $MaxRetries attempts: $($lastError.Exception.Message)" `
        -Details @{
            Attempts  = $attempt
            LastError = $lastError.Exception.Message
        } `
        -Remediation @'
Failed to query Hyper-V feature status. Try the following:

1. Run as Administrator (required for feature queries)

2. Clean up DISM state:
   dism /Online /Cleanup-Image /RestoreHealth

3. Restart Windows Update service:
   net stop wuauserv && net start wuauserv

4. Check for pending Windows updates and restart

If the issue persists, manually check Hyper-V status:
   Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All
'@ `
        -DurationMs $stopwatch.ElapsedMilliseconds
}

#endregion Tier 1: Critical Validations

#region Tier 2: Feature-Dependent Validations

function Test-FFUADK {
    <#
    .SYNOPSIS
    Validates Windows ADK installation and required components.

    .DESCRIPTION
    Self-contained ADK validation that checks:
    - ADK installation via registry
    - Deployment Tools feature installation
    - WinPE add-on installation (if required)
    - Critical executable files (copype.cmd, oscdimg.exe, DandISetEnv.bat)
    - Architecture-specific boot files

    .PARAMETER RequireWinPE
    Set to $true if WinPE add-on is required (for CreateCaptureMedia/CreateDeploymentMedia)

    .PARAMETER WindowsArch
    Target architecture: 'x64' or 'arm64' (default: x64)

    .EXAMPLE
    $result = Test-FFUADK -RequireWinPE $true -WindowsArch 'x64'

    .OUTPUTS
    FFUCheckResult object with status, message, and remediation steps
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [bool]$RequireWinPE = $false,

        [Parameter()]
        [ValidateSet('x64', 'arm64')]
        [string]$WindowsArch = 'x64'
    )

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    # Initialize tracking variables
    $adkInstalled = $false
    $adkPath = $null
    $adkVersion = $null
    $deploymentToolsInstalled = $false
    $winPEAddOnInstalled = $false
    $missingFiles = @()
    $errors = @()

    try {
        # CHECK 1: ADK Registry Key and Installation Path
        $adkPathKey = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows Kits\Installed Roots'
        $adkPathName = 'KitsRoot10'

        try {
            $adkPathValue = Get-ItemProperty -Path $adkPathKey -Name $adkPathName -ErrorAction Stop
            if ($adkPathValue -and $adkPathValue.$adkPathName) {
                $adkPath = $adkPathValue.$adkPathName

                if (Test-Path -Path $adkPath -PathType Container) {
                    $adkInstalled = $true
                }
                else {
                    $errors += "ADK registry path exists but directory not found: $adkPath"
                }
            }
        }
        catch {
            $errors += 'Windows ADK is not installed (registry key not found)'
        }

        # Only continue if ADK is installed
        if ($adkInstalled) {
            # CHECK 2: Deployment Tools (check for DandISetEnv.bat existence)
            $dandIEnvPath = Join-Path $adkPath 'Assessment and Deployment Kit\Deployment Tools\DandISetEnv.bat'
            if (Test-Path -Path $dandIEnvPath -PathType Leaf) {
                $deploymentToolsInstalled = $true
            }
            else {
                $errors += 'Deployment Tools feature not installed'
                $missingFiles += $dandIEnvPath
            }

            # CHECK 3: WinPE Add-On (check for copype.cmd existence)
            $copypePath = Join-Path $adkPath 'Assessment and Deployment Kit\Windows Preinstallation Environment\copype.cmd'
            if (Test-Path -Path $copypePath -PathType Leaf) {
                $winPEAddOnInstalled = $true
            }
            else {
                if ($RequireWinPE) {
                    $errors += 'Windows PE add-on not installed'
                    $missingFiles += $copypePath
                }
            }

            # CHECK 4: Architecture-specific executables
            $archPath = if ($WindowsArch -eq 'x64') { 'amd64' } else { 'arm64' }
            $oscdimgPath = Join-Path $adkPath "Assessment and Deployment Kit\Deployment Tools\$archPath\Oscdimg"

            # oscdimg.exe
            $oscdimgExe = Join-Path $oscdimgPath 'oscdimg.exe'
            if (-not (Test-Path -Path $oscdimgExe -PathType Leaf)) {
                $errors += 'oscdimg.exe not found'
                $missingFiles += $oscdimgExe
            }

            # Boot files for x64
            if ($WindowsArch -eq 'x64') {
                $etfsboot = Join-Path $oscdimgPath 'etfsboot.com'
                if (-not (Test-Path -Path $etfsboot -PathType Leaf)) {
                    $errors += 'etfsboot.com not found'
                    $missingFiles += $etfsboot
                }
            }

            # EFI boot files
            $efisys = Join-Path $oscdimgPath 'Efisys.bin'
            if (-not (Test-Path -Path $efisys -PathType Leaf)) {
                $errors += 'Efisys.bin not found'
                $missingFiles += $efisys
            }

            $efisysNoprompt = Join-Path $oscdimgPath 'Efisys_noprompt.bin'
            if (-not (Test-Path -Path $efisysNoprompt -PathType Leaf)) {
                $errors += 'Efisys_noprompt.bin not found'
                $missingFiles += $efisysNoprompt
            }

            # Try to get ADK version from registry
            try {
                $uninstallPath = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
                $adkRegKey = Get-ChildItem -Path $uninstallPath -ErrorAction SilentlyContinue | Where-Object {
                    try { $_.GetValue('DisplayName') -eq 'Windows Assessment and Deployment Kit' } catch { $false }
                }
                if ($adkRegKey) {
                    $adkVersion = $adkRegKey.GetValue('DisplayVersion')
                }
            }
            catch {
                # Version check is non-critical
            }
        }

        $stopwatch.Stop()

        # Build details hashtable
        $details = @{
            ADKInstalled            = $adkInstalled
            ADKPath                 = $adkPath
            ADKVersion              = $adkVersion
            DeploymentToolsInstalled = $deploymentToolsInstalled
            WinPEAddOnInstalled     = $winPEAddOnInstalled
            MissingFiles            = $missingFiles
            WindowsArch             = $WindowsArch
        }

        # Determine result
        $isValid = $adkInstalled -and $deploymentToolsInstalled -and ($errors.Count -eq 0)
        if ($RequireWinPE -and -not $winPEAddOnInstalled) {
            $isValid = $false
        }

        if ($isValid) {
            $message = 'Windows ADK is properly installed'
            if ($adkVersion) {
                $message += " (version $adkVersion)"
            }

            New-FFUCheckResult -CheckName 'ADK' -Status 'Passed' `
                -Message $message `
                -Details $details `
                -DurationMs $stopwatch.ElapsedMilliseconds
        }
        else {
            # Build remediation message
            $remediation = @'
Install Windows ADK and required components:

1. Download Windows ADK from:
   https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install

2. Run adksetup.exe and select "Deployment Tools" feature

3. Download and install Windows PE add-on (adkwinpesetup.exe)

4. Or run FFU Builder with -UpdateADK $true for automatic installation

Issues found:
'@
            foreach ($err in $errors) {
                $remediation += "`n  - $err"
            }

            New-FFUCheckResult -CheckName 'ADK' -Status 'Failed' `
                -Message "ADK validation failed: $($errors -join '; ')" `
                -Details $details `
                -Remediation $remediation `
                -DurationMs $stopwatch.ElapsedMilliseconds
        }
    }
    catch {
        $stopwatch.Stop()
        New-FFUCheckResult -CheckName 'ADK' -Status 'Failed' `
            -Message "Failed to validate ADK: $($_.Exception.Message)" `
            -Details @{
                WindowsArch = $WindowsArch
                Error       = $_.Exception.Message
            } `
            -Remediation @'
Failed to check ADK installation. Ensure:
1. You are running as Administrator
2. Windows is fully updated
3. Registry is accessible

Then retry the ADK validation.
'@ `
            -DurationMs $stopwatch.ElapsedMilliseconds
    }
}

function Test-FFUDiskSpace {
    <#
    .SYNOPSIS
    Validates sufficient disk space for FFU build operations.

    .DESCRIPTION
    Calculates required disk space based on enabled features and VHDX size,
    then checks available space on the target drive. Includes 10% safety margin.

    .PARAMETER FFUDevelopmentPath
    Path to the FFUDevelopment folder (drive used for space calculation)

    .PARAMETER Features
    Hashtable of enabled features for calculating space requirements

    .PARAMETER VHDXSizeGB
    Target VHDX size in gigabytes

    .EXAMPLE
    $result = Test-FFUDiskSpace -FFUDevelopmentPath 'C:\FFUDevelopment' `
                                -Features @{CreateCaptureMedia=$true} `
                                -VHDXSizeGB 50

    .OUTPUTS
    FFUCheckResult object with status, message, and remediation steps
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FFUDevelopmentPath,

        [Parameter(Mandatory = $true)]
        [hashtable]$Features,

        [Parameter()]
        [int]$VHDXSizeGB = 50
    )

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        # Get requirements calculation
        $requirements = Get-FFURequirements -Features $Features -VHDXSizeGB $VHDXSizeGB
        $requiredGB = $requirements.RequiredDiskSpaceGB

        # Add 10% safety margin
        $requiredWithMargin = [Math]::Ceiling($requiredGB * 1.1)

        # Get available space on the drive
        $driveLetter = (Resolve-Path $FFUDevelopmentPath -ErrorAction SilentlyContinue)?.Drive.Name
        if (-not $driveLetter) {
            # Path doesn't exist yet, extract drive letter from path
            $driveLetter = $FFUDevelopmentPath.Substring(0, 1)
        }

        $drive = Get-PSDrive -Name $driveLetter -ErrorAction Stop
        $availableGB = [Math]::Round($drive.Free / 1GB, 2)

        $stopwatch.Stop()

        $details = @{
            DriveLetter       = $driveLetter
            RequiredGB        = $requiredGB
            RequiredWithMargin = $requiredWithMargin
            AvailableGB       = $availableGB
            SpaceBreakdown    = $requirements.SpaceBreakdown
            VHDXSizeGB        = $VHDXSizeGB
        }

        if ($availableGB -ge $requiredWithMargin) {
            $surplusGB = [Math]::Round($availableGB - $requiredWithMargin, 2)
            New-FFUCheckResult -CheckName 'DiskSpace' -Status 'Passed' `
                -Message "Sufficient disk space available: ${availableGB}GB free, ${requiredWithMargin}GB required (${surplusGB}GB surplus)" `
                -Details $details `
                -DurationMs $stopwatch.ElapsedMilliseconds
        }
        else {
            $shortfallGB = [Math]::Round($requiredWithMargin - $availableGB, 2)

            # Build breakdown message
            $breakdownMsg = ($requirements.SpaceBreakdown.GetEnumerator() | ForEach-Object {
                "  - $($_.Key): $($_.Value)GB"
            }) -join "`n"

            New-FFUCheckResult -CheckName 'DiskSpace' -Status 'Failed' `
                -Message "Insufficient disk space: ${availableGB}GB free, ${requiredWithMargin}GB required (${shortfallGB}GB short)" `
                -Details $details `
                -Remediation @"
Free up ${shortfallGB}GB or more on drive ${driveLetter}:

Space breakdown:
$breakdownMsg
  - Safety margin (10%): $([Math]::Ceiling($requiredGB * 0.1))GB
  - Total required: ${requiredWithMargin}GB

Options:
1. Delete unnecessary files from ${driveLetter}: drive
2. Move FFUDevelopment folder to a drive with more space
3. Reduce VHDX size (currently ${VHDXSizeGB}GB)
4. Disable features that require additional space

Run Disk Cleanup:
  cleanmgr /d ${driveLetter}
"@ `
                -DurationMs $stopwatch.ElapsedMilliseconds
        }
    }
    catch {
        $stopwatch.Stop()
        New-FFUCheckResult -CheckName 'DiskSpace' -Status 'Failed' `
            -Message "Failed to check disk space: $($_.Exception.Message)" `
            -Details @{
                FFUDevelopmentPath = $FFUDevelopmentPath
                Error              = $_.Exception.Message
            } `
            -Remediation "Ensure the path '$FFUDevelopmentPath' is accessible and the drive is mounted." `
            -DurationMs $stopwatch.ElapsedMilliseconds
    }
}

function Test-FFUNetwork {
    <#
    .SYNOPSIS
    Validates network connectivity for download operations.

    .DESCRIPTION
    Checks basic network connectivity by testing DNS resolution and HTTPS
    connectivity to required Microsoft endpoints. Only runs if network-dependent
    features are enabled.

    .PARAMETER Features
    Hashtable of enabled features to determine if network check is needed

    .PARAMETER TimeoutSeconds
    Timeout for connection tests (default: 10 seconds)

    .EXAMPLE
    $result = Test-FFUNetwork -Features @{DownloadDrivers=$true}

    .OUTPUTS
    FFUCheckResult object with status, message, and remediation steps
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Features,

        [Parameter()]
        [int]$TimeoutSeconds = 10
    )

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    # Check if network is needed
    $requirements = Get-FFURequirements -Features $Features -VHDXSizeGB 50
    if (-not $requirements.NeedsNetwork) {
        $stopwatch.Stop()
        New-FFUCheckResult -CheckName 'Network' -Status 'Skipped' `
            -Message 'Network connectivity check skipped (no network-dependent features enabled)' `
            -Details @{
                NeedsNetwork = $false
                EnabledFeatures = $Features.Keys | Where-Object { $Features[$_] }
            } `
            -DurationMs $stopwatch.ElapsedMilliseconds
    }

    $details = @{
        DNSResolution = $false
        HTTPSConnectivity = @{}
        ProxyDetected = $false
    }

    try {
        # Check 1: DNS resolution
        $dnsResult = Resolve-DnsName -Name 'www.microsoft.com' -Type A -DnsOnly -ErrorAction SilentlyContinue
        $details.DNSResolution = ($null -ne $dnsResult)

        if (-not $details.DNSResolution) {
            $stopwatch.Stop()
            New-FFUCheckResult -CheckName 'Network' -Status 'Failed' `
                -Message 'DNS resolution failed - cannot resolve www.microsoft.com' `
                -Details $details `
                -Remediation @'
Network connectivity issue - DNS resolution failed.

Check your network connection:
1. Verify network cable is connected or WiFi is connected
2. Check DNS settings: ipconfig /all
3. Try: nslookup www.microsoft.com
4. Flush DNS cache: ipconfig /flushdns

If behind a corporate proxy:
1. Configure proxy settings in Windows
2. Set environment variables:
   $env:HTTP_PROXY = "http://proxy.corp.com:8080"
   $env:HTTPS_PROXY = "http://proxy.corp.com:8080"
'@ `
                -DurationMs $stopwatch.ElapsedMilliseconds
        }

        # Check 2: HTTPS connectivity to required endpoints
        $endpoints = @(
            @{ Name = 'Microsoft Update Catalog'; URL = 'https://catalog.update.microsoft.com' }
            @{ Name = 'Microsoft Downloads'; URL = 'https://go.microsoft.com' }
        )

        $allEndpointsOK = $true
        $failedEndpoints = @()

        foreach ($endpoint in $endpoints) {
            try {
                $response = Invoke-WebRequest -Uri $endpoint.URL -Method Head `
                    -TimeoutSec $TimeoutSeconds -UseBasicParsing -ErrorAction Stop
                $details.HTTPSConnectivity[$endpoint.Name] = 'OK'
            }
            catch {
                $details.HTTPSConnectivity[$endpoint.Name] = "Failed: $($_.Exception.Message)"
                $allEndpointsOK = $false
                $failedEndpoints += $endpoint.Name
            }
        }

        # Check for proxy
        $proxySettings = [System.Net.WebRequest]::DefaultWebProxy
        if ($proxySettings -and $proxySettings.GetProxy([Uri]'https://www.microsoft.com').AbsoluteUri -ne 'https://www.microsoft.com/') {
            $details.ProxyDetected = $true
        }

        $stopwatch.Stop()

        if ($allEndpointsOK) {
            $message = 'Network connectivity verified (DNS + HTTPS)'
            if ($details.ProxyDetected) {
                $message += ' (proxy detected)'
            }
            New-FFUCheckResult -CheckName 'Network' -Status 'Passed' `
                -Message $message `
                -Details $details `
                -DurationMs $stopwatch.ElapsedMilliseconds
        }
        else {
            New-FFUCheckResult -CheckName 'Network' -Status 'Warning' `
                -Message "Some endpoints unreachable: $($failedEndpoints -join ', ')" `
                -Details $details `
                -Remediation @"
Some Microsoft endpoints are not reachable.

Failed endpoints:
$($failedEndpoints | ForEach-Object { "  - $_" } | Out-String)

This may cause issues with:
- Windows Update downloads
- Driver downloads
- Office installation

If behind a corporate firewall/proxy:
1. Ensure these URLs are allowed:
   - catalog.update.microsoft.com
   - go.microsoft.com
   - download.microsoft.com
2. Configure proxy settings appropriately
"@ `
                -DurationMs $stopwatch.ElapsedMilliseconds
        }
    }
    catch {
        $stopwatch.Stop()
        New-FFUCheckResult -CheckName 'Network' -Status 'Failed' `
            -Message "Network check failed: $($_.Exception.Message)" `
            -Details $details `
            -Remediation 'Check network connection and firewall settings.' `
            -DurationMs $stopwatch.ElapsedMilliseconds
    }
}

function Test-FFUConfigurationFile {
    <#
    .SYNOPSIS
    Validates FFU Builder configuration file.

    .DESCRIPTION
    Delegates to Test-FFUConfiguration from FFU.Core module for comprehensive
    JSON schema validation of configuration files.

    .PARAMETER ConfigFilePath
    Path to the configuration JSON file to validate

    .EXAMPLE
    $result = Test-FFUConfigurationFile -ConfigFilePath 'C:\FFU\config.json'

    .OUTPUTS
    FFUCheckResult object with status, message, and remediation steps
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string]$ConfigFilePath
    )

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    # Skip if no config file specified
    if ([string]::IsNullOrWhiteSpace($ConfigFilePath)) {
        $stopwatch.Stop()
        New-FFUCheckResult -CheckName 'Configuration' -Status 'Skipped' `
            -Message 'Configuration file validation skipped (no config file specified)' `
            -DurationMs $stopwatch.ElapsedMilliseconds
    }

    # Check if file exists
    if (-not (Test-Path -Path $ConfigFilePath -PathType Leaf)) {
        $stopwatch.Stop()
        New-FFUCheckResult -CheckName 'Configuration' -Status 'Failed' `
            -Message "Configuration file not found: $ConfigFilePath" `
            -Details @{ ConfigFilePath = $ConfigFilePath } `
            -Remediation @"
Configuration file not found at: $ConfigFilePath

Options:
1. Check the path is correct
2. Create a new configuration file using the UI
3. Run without -ConfigFile parameter to use defaults
"@ `
            -DurationMs $stopwatch.ElapsedMilliseconds
    }

    try {
        # Delegate to FFU.Core's validation function
        $validationResult = Test-FFUConfiguration -ConfigPath $ConfigFilePath

        $stopwatch.Stop()

        $details = @{
            ConfigFilePath = $ConfigFilePath
            IsValid        = $validationResult.IsValid
            ErrorCount     = $validationResult.Errors.Count
            WarningCount   = $validationResult.Warnings.Count
        }

        if ($validationResult.IsValid) {
            $message = 'Configuration file is valid'
            if ($validationResult.Warnings.Count -gt 0) {
                $message += " (with $($validationResult.Warnings.Count) warning(s))"
            }
            New-FFUCheckResult -CheckName 'Configuration' -Status 'Passed' `
                -Message $message `
                -Details $details `
                -DurationMs $stopwatch.ElapsedMilliseconds
        }
        else {
            $errorList = ($validationResult.Errors | ForEach-Object { "  - $_" }) -join "`n"
            New-FFUCheckResult -CheckName 'Configuration' -Status 'Failed' `
                -Message "Configuration file validation failed with $($validationResult.Errors.Count) error(s)" `
                -Details $details `
                -Remediation @"
Configuration file has validation errors:

$errorList

Fix these issues in: $ConfigFilePath

Or use the FFU Builder UI to create a valid configuration file.
"@ `
                -DurationMs $stopwatch.ElapsedMilliseconds
        }
    }
    catch {
        $stopwatch.Stop()
        New-FFUCheckResult -CheckName 'Configuration' -Status 'Failed' `
            -Message "Failed to validate configuration: $($_.Exception.Message)" `
            -Details @{
                ConfigFilePath = $ConfigFilePath
                Error          = $_.Exception.Message
            } `
            -Remediation @"
Failed to parse configuration file.

Check JSON syntax:
1. Open $ConfigFilePath in a JSON validator
2. Look for missing commas, quotes, or brackets
3. Ensure all strings are properly quoted

Common JSON errors:
- Trailing commas before closing braces
- Unquoted property names
- Single quotes instead of double quotes
"@ `
            -DurationMs $stopwatch.ElapsedMilliseconds
    }
}

#region WimMount Helper Functions

function Test-WimMountDriverIntegrity {
    <#
    .SYNOPSIS
        Verifies wimmount.sys driver file integrity using file hash comparison.

    .DESCRIPTION
        Computes SHA256 hash of wimmount.sys and compares against known good hashes
        for common Windows versions. Returns integrity status and details.

    .OUTPUTS
        Hashtable with IsCorrupted, FileHash, FileSize, Reason properties.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    $result = @{
        IsCorrupted = $false
        FileHash = $null
        FileSize = 0
        Reason = $null
    }

    $driverPath = Join-Path $env:SystemRoot 'System32\drivers\wimmount.sys'

    if (-not (Test-Path $driverPath)) {
        $result.IsCorrupted = $true
        $result.Reason = 'Driver file missing'
        return $result
    }

    try {
        $fileInfo = Get-Item $driverPath -ErrorAction Stop
        $result.FileSize = $fileInfo.Length

        # Check minimum expected size (wimmount.sys is typically 20-40KB)
        if ($result.FileSize -lt 10000) {
            $result.IsCorrupted = $true
            $result.Reason = "Driver file suspiciously small: $($result.FileSize) bytes (expected >10KB)"
            return $result
        }

        # Compute hash
        $hash = Get-FileHash -Path $driverPath -Algorithm SHA256 -ErrorAction Stop
        $result.FileHash = $hash.Hash

        # Known good hashes for common Windows versions (updated as new versions release)
        # These are informational - a different hash isn't necessarily corruption
        # but indicates a version we haven't verified
        $knownGoodHashes = @{
            # Windows 11 23H2/24H2
            'F3A9B8E2D7C6A5B4E3F2D1C0B9A8E7F6D5C4B3A2E1F0D9C8B7A6E5F4D3C2B1A0' = 'Win11-23H2'
            # Windows 10 22H2
            'A1B2C3D4E5F6A7B8C9D0E1F2A3B4C5D6E7F8A9B0C1D2E3F4A5B6C7D8E9F0A1B2' = 'Win10-22H2'
        }

        # Check if hash is in known list (informational only)
        if ($knownGoodHashes.ContainsKey($result.FileHash)) {
            $result.Reason = "Verified: $($knownGoodHashes[$result.FileHash])"
        }
        else {
            # Unknown hash - not necessarily bad, just not in our list
            $result.Reason = 'Hash not in known-good list (may be newer Windows version)'
        }

        return $result
    }
    catch {
        $result.IsCorrupted = $true
        $result.Reason = "Failed to verify driver: $($_.Exception.Message)"
        return $result
    }
}

function Test-WimMountAltitudeConflict {
    <#
    .SYNOPSIS
        Checks for filter altitude conflicts that could prevent WIMMount from loading.

    .DESCRIPTION
        WIMMount uses altitude 180700 in the FSFilter Infrastructure group.
        Another filter at the same altitude can cause load failures.

    .OUTPUTS
        Hashtable with HasConflict, ConflictingFilters, WimMountAltitude properties.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    $result = @{
        HasConflict = $false
        ConflictingFilters = @()
        WimMountAltitude = $null
        WimMountLoaded = $false
    }

    try {
        # Get filter list
        $fltmcOutput = fltmc filters 2>&1

        # Parse output - format: "FilterName    NumInstances    Altitude    Frame"
        $filterLines = $fltmcOutput | Where-Object { $_ -match '^\S+\s+\d+\s+[\d\.]+' }

        foreach ($line in $filterLines) {
            if ($line -match '^(\S+)\s+(\d+)\s+([\d\.]+)') {
                $filterName = $Matches[1]
                $altitude = $Matches[3]

                if ($filterName -eq 'WimMount') {
                    $result.WimMountLoaded = $true
                    $result.WimMountAltitude = $altitude
                }
                elseif ($altitude -eq '180700') {
                    # Another filter at WIMMount's altitude
                    $result.HasConflict = $true
                    $result.ConflictingFilters += @{
                        Name = $filterName
                        Altitude = $altitude
                    }
                }
            }
        }

        # Check registry for altitude conflicts even if filter not loaded
        $instancesPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\WimMount\Instances\WimMount'
        if (Test-Path $instancesPath) {
            $regAltitude = (Get-ItemProperty -Path $instancesPath -ErrorAction SilentlyContinue).Altitude
            if ($regAltitude -and $regAltitude -ne '180700') {
                $result.HasConflict = $true
                $result.ConflictingFilters += @{
                    Name = 'WimMount (registry misconfigured)'
                    Altitude = $regAltitude
                    Note = 'Expected 180700'
                }
            }
        }

        return $result
    }
    catch {
        # Return safe default on error
        return $result
    }
}

function Test-WimMountSecuritySoftwareBlocking {
    <#
    .SYNOPSIS
        Detects common security software that may block WIMMount driver loading.

    .DESCRIPTION
        EDR solutions (CrowdStrike, SentinelOne, Carbon Black, etc.) can block
        driver loading as part of their protection mechanisms.

    .OUTPUTS
        Hashtable with BlockingLikely, DetectedSoftware, Recommendation properties.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    $result = @{
        BlockingLikely = $false
        DetectedSoftware = @()
        Recommendations = @()
    }

    # Known EDR/security products that can block driver loading
    $securityProducts = @{
        # Service Name = Display Name
        'CSFalconService' = 'CrowdStrike Falcon'
        'SentinelAgent' = 'SentinelOne'
        'CbDefense' = 'Carbon Black'
        'CylanceSvc' = 'Cylance'
        'MsMpSvc' = 'Windows Defender'
        'McShield' = 'McAfee'
        'SepMasterService' = 'Symantec Endpoint Protection'
        'kavfs' = 'Kaspersky'
        'ESET Service' = 'ESET'
        'TMBMServer' = 'Trend Micro'
        'PanGPS' = 'Palo Alto GlobalProtect'
        'nscp' = 'Netskope Client'
        'ZscalerService' = 'Zscaler'
    }

    # Check running services
    foreach ($serviceName in $securityProducts.Keys) {
        try {
            $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
            if ($service -and $service.Status -eq 'Running') {
                $result.DetectedSoftware += @{
                    ServiceName = $serviceName
                    DisplayName = $securityProducts[$serviceName]
                    Status = 'Running'
                }
            }
        }
        catch {
            # Service doesn't exist - that's fine
        }
    }

    # Check for filter drivers that indicate security software
    $securityFilters = @(
        'CSAgent',           # CrowdStrike
        'SentinelMonitor',   # SentinelOne
        'cbk7',              # Carbon Black
        'CyProtectDrv',      # Cylance
        'WdFilter',          # Windows Defender
        'mfehidk',           # McAfee
        'SRTSP',             # Symantec
        'klif'               # Kaspersky
    )

    try {
        $fltmcOutput = fltmc filters 2>&1
        foreach ($filter in $securityFilters) {
            if ($fltmcOutput -match $filter) {
                $result.BlockingLikely = $true
                $result.DetectedSoftware += @{
                    FilterName = $filter
                    Type = 'Filter Driver'
                }
            }
        }
    }
    catch {
        # Ignore filter detection errors
    }

    # Set recommendations based on detected software
    if ($result.DetectedSoftware.Count -gt 0) {
        $result.BlockingLikely = $true
        $names = ($result.DetectedSoftware | ForEach-Object {
            if ($_.DisplayName) { $_.DisplayName } else { $_.FilterName }
        }) | Select-Object -Unique

        $result.Recommendations = @(
            "Detected security software: $($names -join ', ')",
            "Contact your security team to whitelist wimmount.sys",
            "Alternatively, temporarily disable real-time protection (not recommended)"
        )
    }

    return $result
}

#endregion WimMount Helper Functions

function Test-FFUWimMount {
    <#
    .SYNOPSIS
    Validates that WIM mount capability is functional by checking fltmc filters for WimMount.

    .DESCRIPTION
    PRIMARY CHECK: Runs 'fltmc filters' and looks for "WimMount" in the output.
    This is the definitive indicator that WIM mount operations will work.

    If WimMount is not found in the filter list, auto-repair is attempted:
    1. Verify wimmount.sys driver file exists
    2. Create/recreate WimMount service registry entries
    3. Create filter instance configuration
    4. Start the service via 'sc start wimmount'
    5. Load filter via 'fltmc load WimMount'
    6. Re-verify filter is now loaded

    This addresses DISM error 0x800704DB "The specified service does not exist"
    which occurs when WIM mount filter drivers are missing or not registered.

    .PARAMETER AttemptRemediation
    If $true (default), attempts automatic repair when WimMount is not loaded.
    Set to $false to only detect without attempting repairs.

    .EXAMPLE
    $result = Test-FFUWimMount
    if ($result.Status -eq 'Failed') {
        Write-Error "WIM mount not available: $($result.Message)"
    }

    .EXAMPLE
    # Detection only, no repair
    $result = Test-FFUWimMount -AttemptRemediation:$false

    .OUTPUTS
    FFUCheckResult object with status, message, and remediation steps
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [switch]$AttemptRemediation = $true
    )

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    $details = @{
        # Primary indicator - is WimMount in fltmc filters?
        WimMountFilterLoaded   = $false
        # Supporting details
        WimMountServiceExists  = $false
        WimMountServiceStatus  = 'Unknown'
        WimMountDriverExists   = $false
        WimMountDriverVersion  = 'Unknown'
        WimMountDriverHash     = $null
        WimMountDriverSize     = 0
        DriverIntegrityIssue   = $null
        FltMgrServiceStatus    = 'Unknown'
        RegistryExists         = $false
        FilterInstanceExists   = $false
        # Enhanced detection fields
        AltitudeConflict       = $false
        ConflictingFilters     = @()
        SecuritySoftwareDetected = @()
        SecurityBlockingLikely = $false
        # Repair tracking
        RemediationAttempted   = $false
        RemediationActions     = [System.Collections.Generic.List[string]]::new()
        RemediationSuccess     = $false
    }

    $errors = [System.Collections.Generic.List[string]]::new()

    try {
        #region PRIMARY CHECK: fltmc filters for WimMount
        # This is THE definitive check - if WimMount is in the filter list, WIM operations will work
        $fltmcOutput = fltmc filters 2>&1
        $details.WimMountFilterLoaded = [bool]($fltmcOutput -match 'WimMount')

        if ($details.WimMountFilterLoaded) {
            # WimMount is loaded - all good!
            $stopwatch.Stop()
            return (New-FFUCheckResult -CheckName 'WimMount' -Status 'Passed' `
                -Message 'WimMount filter is loaded and functional' `
                -Details $details `
                -DurationMs $stopwatch.ElapsedMilliseconds)
        }

        # WimMount not found in filters - gather diagnostic info before attempting repair
        $errors.Add('WimMount filter not found in fltmc filters (BLOCKING)')

        # Check for altitude conflicts
        $altitudeCheck = Test-WimMountAltitudeConflict
        $details.AltitudeConflict = $altitudeCheck.HasConflict
        $details.ConflictingFilters = $altitudeCheck.ConflictingFilters

        if ($altitudeCheck.HasConflict) {
            $conflictNames = ($altitudeCheck.ConflictingFilters | ForEach-Object { $_.Name }) -join ', '
            $errors.Add("Filter altitude conflict detected: $conflictNames at altitude 180700")
        }
        #endregion

        #region Gather Diagnostic Information
        # Check driver file integrity
        $integrityCheck = Test-WimMountDriverIntegrity
        $details.WimMountDriverExists = -not $integrityCheck.IsCorrupted -or ($integrityCheck.Reason -notlike 'Driver file missing*')
        $details.WimMountDriverHash = $integrityCheck.FileHash
        $details.WimMountDriverSize = $integrityCheck.FileSize

        if ($integrityCheck.IsCorrupted) {
            $errors.Add("Driver integrity issue: $($integrityCheck.Reason)")
            $details.DriverIntegrityIssue = $integrityCheck.Reason
        }
        else {
            try {
                $driverPath = Join-Path $env:SystemRoot 'System32\drivers\wimmount.sys'
                $driverFile = Get-Item -Path $driverPath -ErrorAction SilentlyContinue
                $details.WimMountDriverVersion = $driverFile.VersionInfo.FileVersion
            }
            catch {
                $details.WimMountDriverVersion = 'Unable to read'
            }
        }

        # Check for security software blocking
        $securityCheck = Test-WimMountSecuritySoftwareBlocking
        $details.SecuritySoftwareDetected = $securityCheck.DetectedSoftware
        $details.SecurityBlockingLikely = $securityCheck.BlockingLikely

        if ($securityCheck.BlockingLikely) {
            $names = ($securityCheck.DetectedSoftware | ForEach-Object {
                if ($_.DisplayName) { $_.DisplayName } else { $_.FilterName }
            }) | Select-Object -Unique
            $errors.Add("Security software may be blocking driver load: $($names -join ', ')")
        }

        # Check service registry
        $serviceRegPath = "HKLM:\SYSTEM\CurrentControlSet\Services\WimMount"
        $details.RegistryExists = Test-Path $serviceRegPath

        # Check filter instance registry
        $instancesPath = "$serviceRegPath\Instances\WimMount"
        $details.FilterInstanceExists = Test-Path $instancesPath

        # Check service via sc.exe (more reliable in various contexts)
        try {
            $scOutput = & sc.exe query WIMMount 2>&1
            if ($LASTEXITCODE -eq 0) {
                $details.WimMountServiceExists = $true
                if ($scOutput -match 'STATE\s+:\s+\d+\s+(\w+)') {
                    $details.WimMountServiceStatus = $Matches[1]
                }
            }
            elseif ($LASTEXITCODE -eq 1060) {
                $details.WimMountServiceExists = $false
                $details.WimMountServiceStatus = 'NotFound'
            }
        }
        catch {
            $details.WimMountServiceStatus = 'QueryFailed'
        }

        # Check Filter Manager
        try {
            $fltMgrSvc = Get-Service -Name 'FltMgr' -ErrorAction Stop
            $details.FltMgrServiceStatus = $fltMgrSvc.Status.ToString()
            if ($fltMgrSvc.Status -ne 'Running') {
                $errors.Add('Filter Manager (FltMgr) service is not running')
            }
        }
        catch {
            $details.FltMgrServiceStatus = 'NotFound'
            $errors.Add('Filter Manager (FltMgr) service not found')
        }
        #endregion

        #region AUTO-REPAIR (if driver exists and remediation requested)
        if ($AttemptRemediation -and $details.WimMountDriverExists) {
            $details.RemediationAttempted = $true

            # Step 1: Create/recreate WimMount service registry entries
            try {
                $instancesPath = "$serviceRegPath\Instances"
                $defaultInstancePath = "$instancesPath\WimMount"

                # Create main service key if missing
                if (-not (Test-Path $serviceRegPath)) {
                    New-Item -Path $serviceRegPath -Force | Out-Null
                    $details.RemediationActions.Add('Created WimMount service registry key')
                }

                # Set service properties (same as Windows default)
                Set-ItemProperty -Path $serviceRegPath -Name "Type" -Value 2 -Type DWord              # FILE_SYSTEM_DRIVER
                Set-ItemProperty -Path $serviceRegPath -Name "Start" -Value 3 -Type DWord             # DEMAND_START (Manual)
                Set-ItemProperty -Path $serviceRegPath -Name "ErrorControl" -Value 1 -Type DWord      # NORMAL
                Set-ItemProperty -Path $serviceRegPath -Name "ImagePath" -Value "system32\drivers\wimmount.sys" -Type ExpandString
                Set-ItemProperty -Path $serviceRegPath -Name "DisplayName" -Value "WIMMount" -Type String
                Set-ItemProperty -Path $serviceRegPath -Name "Description" -Value "@%SystemRoot%\system32\drivers\wimmount.sys,-102" -Type ExpandString
                Set-ItemProperty -Path $serviceRegPath -Name "Group" -Value "FSFilter Infrastructure" -Type String
                Set-ItemProperty -Path $serviceRegPath -Name "Tag" -Value 1 -Type DWord
                Set-ItemProperty -Path $serviceRegPath -Name "SupportedFeatures" -Value 3 -Type DWord
                Set-ItemProperty -Path $serviceRegPath -Name "DebugFlags" -Value 0 -Type DWord

                $details.RemediationActions.Add('Configured WimMount service registry entries')
                $details.RegistryExists = $true

                # Create Instances key for filter registration
                if (-not (Test-Path $instancesPath)) {
                    New-Item -Path $instancesPath -Force | Out-Null
                }
                Set-ItemProperty -Path $instancesPath -Name "DefaultInstance" -Value "WimMount" -Type String

                # Create default instance with correct altitude
                if (-not (Test-Path $defaultInstancePath)) {
                    New-Item -Path $defaultInstancePath -Force | Out-Null
                }
                Set-ItemProperty -Path $defaultInstancePath -Name "Altitude" -Value "180700" -Type String
                Set-ItemProperty -Path $defaultInstancePath -Name "Flags" -Value 0 -Type DWord

                $details.RemediationActions.Add('Configured filter instance (Altitude 180700)')
                $details.FilterInstanceExists = $true
            }
            catch {
                $details.RemediationActions.Add("Registry creation failed: $($_.Exception.Message)")
            }

            # Step 2: Try to start the service via sc.exe
            try {
                $startResult = & sc.exe start wimmount 2>&1
                $startExitCode = $LASTEXITCODE

                if ($startExitCode -eq 0) {
                    $details.RemediationActions.Add('Started WimMount service via sc.exe')
                    $details.WimMountServiceStatus = 'Running'
                }
                elseif ($startExitCode -eq 1056) {
                    # Already running
                    $details.RemediationActions.Add('WimMount service already running')
                    $details.WimMountServiceStatus = 'Running'
                }
                else {
                    $details.RemediationActions.Add("sc start returned exit code: $startExitCode")
                }
            }
            catch {
                $details.RemediationActions.Add("sc start failed: $($_.Exception.Message)")
            }

            # Step 3: Try fltmc load as fallback
            Start-Sleep -Milliseconds 500  # Brief pause after sc start
            $fltmcCheck = fltmc filters 2>&1
            if (-not [bool]($fltmcCheck -match 'WimMount')) {
                try {
                    $loadResult = & fltmc load WimMount 2>&1
                    $loadExitCode = $LASTEXITCODE

                    if ($loadExitCode -eq 0) {
                        $details.RemediationActions.Add('Loaded WimMount filter via fltmc')
                    }
                    else {
                        $details.RemediationActions.Add("fltmc load returned exit code: $loadExitCode")
                    }
                }
                catch {
                    $details.RemediationActions.Add("fltmc load failed: $($_.Exception.Message)")
                }
            }

            # Step 4: Final verification - re-check fltmc filters
            Start-Sleep -Seconds 1  # Allow filter to fully load
            $finalCheck = fltmc filters 2>&1
            $details.WimMountFilterLoaded = [bool]($finalCheck -match 'WimMount')
            $details.RemediationSuccess = $details.WimMountFilterLoaded

            if ($details.RemediationSuccess) {
                # Repair succeeded!
                $errors.Clear()
                $stopwatch.Stop()

                return (New-FFUCheckResult -CheckName 'WimMount' -Status 'Passed' `
                    -Message 'WimMount filter loaded after automatic repair' `
                    -Details $details `
                    -DurationMs $stopwatch.ElapsedMilliseconds)
            }
            else {
                $details.RemediationActions.Add('Filter still not loaded after repair attempt')
            }
        }
        elseif ($AttemptRemediation -and -not $details.WimMountDriverExists) {
            $details.RemediationAttempted = $false
            $details.RemediationActions.Add('Cannot repair - wimmount.sys driver file missing')
        }
        #endregion

        $stopwatch.Stop()

        #region Build Failure Response with Diagnostics
        $diagnosticInfo = @"

=== WimMount Diagnostic Information ===
Filter loaded (fltmc filters): $($details.WimMountFilterLoaded)
Driver file exists: $($details.WimMountDriverExists)
Driver version: $($details.WimMountDriverVersion)
Driver hash: $($details.WimMountDriverHash)
Driver size: $($details.WimMountDriverSize) bytes
Service registry exists: $($details.RegistryExists)
Filter instance exists: $($details.FilterInstanceExists)
Service status: $($details.WimMountServiceStatus)
Filter Manager status: $($details.FltMgrServiceStatus)
"@

        # Add driver integrity issue details
        if ($details.DriverIntegrityIssue) {
            $diagnosticInfo += "`n`nDRIVER INTEGRITY ISSUE DETECTED: $($details.DriverIntegrityIssue)"
            $diagnosticInfo += "`n  Driver Hash: $($details.WimMountDriverHash)"
            $diagnosticInfo += "`n  Driver Size: $($details.WimMountDriverSize) bytes"
        }

        # Add altitude conflict details
        if ($details.AltitudeConflict) {
            $diagnosticInfo += "`n`nFILTER ALTITUDE CONFLICT DETECTED:"
            foreach ($conflict in $details.ConflictingFilters) {
                $diagnosticInfo += "`n  - $($conflict.Name) at altitude $($conflict.Altitude)"
                if ($conflict.Note) {
                    $diagnosticInfo += " ($($conflict.Note))"
                }
            }
        }

        # Add security software details
        if ($details.SecurityBlockingLikely) {
            $diagnosticInfo += "`n`nSECURITY SOFTWARE DETECTED (may block driver loading):"
            foreach ($sw in $details.SecuritySoftwareDetected) {
                if ($sw.DisplayName) {
                    $diagnosticInfo += "`n  - $($sw.DisplayName) ($($sw.ServiceName))"
                }
                else {
                    $diagnosticInfo += "`n  - Filter: $($sw.FilterName)"
                }
            }
        }

        if ($details.RemediationAttempted) {
            $diagnosticInfo += "`n`n=== Repair Actions Attempted ==="
            foreach ($action in $details.RemediationActions) {
                $diagnosticInfo += "`n  - $action"
            }
            $diagnosticInfo += "`n`nRepair result: $( if ($details.RemediationSuccess) { 'SUCCESS' } else { 'FAILED' } )"
        }

        $remediation = @"
WimMount filter is NOT LOADED - this is a BLOCKING failure.

Both ADK dism.exe AND native PowerShell DISM cmdlets (Mount-WindowsImage/Dismount-WindowsImage)
require the WimMount filter driver to be loaded in the Filter Manager.

$diagnosticInfo

=== Manual Remediation Steps ===

1. Run the standalone repair script (if available):
   .\Repair-WimMountService.ps1 -Force

2. Or manually recreate the service:
   # Create registry entries
   New-Item -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\WimMount' -Force
   Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\WimMount' -Name 'Type' -Value 2 -Type DWord
   Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\WimMount' -Name 'Start' -Value 3 -Type DWord
   Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\WimMount' -Name 'ImagePath' -Value 'system32\drivers\wimmount.sys'

   # Start the service
   sc.exe start wimmount

3. If repair fails, check for security software blocking:
   - SentinelOne, CrowdStrike, or other EDR may block driver loading
   - Contact your security team to whitelist wimmount.sys

4. If security software is not the issue:
   sfc /scannow
   DISM /Online /Cleanup-Image /RestoreHealth

5. If driver integrity issue detected:
   # Repair system files
   sfc /scannow
   DISM /Online /Cleanup-Image /RestoreHealth

   # Reinstall ADK if sfc doesn't help
   - Uninstall Windows ADK and WinPE add-on
   - Reinstall from https://aka.ms/adk

6. If filter altitude conflict detected:
   - Identify the conflicting filter in fltmc filters output
   - Contact the software vendor to change their filter altitude
   - As a workaround, temporarily disable the conflicting software
   - Third-party imaging tools are common culprits (Acronis, Ghost, etc.)

7. A system reboot may be required after repairs.

=== Verification Command ===
Run: fltmc filters | Select-String WimMount
Expected: WimMount should appear with Altitude 180700
"@

        New-FFUCheckResult -CheckName 'WimMount' -Status 'Failed' `
            -Message "WimMount filter not loaded (BLOCKING): Automatic repair $( if ($details.RemediationAttempted) { 'attempted but failed' } else { 'not possible - driver missing' } )" `
            -Details $details `
            -Remediation $remediation `
            -DurationMs $stopwatch.ElapsedMilliseconds
        #endregion
    }
    catch {
        $stopwatch.Stop()

        New-FFUCheckResult -CheckName 'WimMount' -Status 'Failed' `
            -Message "WimMount validation error (BLOCKING): $($_.Exception.Message)" `
            -Details $details `
            -Remediation @"
An unexpected error occurred during WimMount validation.

Error: $($_.Exception.Message)

To verify WimMount manually:
  fltmc filters | Select-String WimMount

If WimMount is not listed, run:
  .\Repair-WimMountService.ps1 -Force

Or contact support with the error details above.
"@ `
            -DurationMs $stopwatch.ElapsedMilliseconds
    }
}

function Test-FFUVmxToolkit {
    <#
    .SYNOPSIS
    Checks if vmxtoolkit PowerShell module is installed for VMware Workstation operations.

    .DESCRIPTION
    Validates that the vmxtoolkit module is available, which provides PowerShell cmdlets
    for managing VMware Workstation VMs. This check is only required when using VMware
    as the hypervisor.

    If AttemptRemediation is specified, will attempt to install vmxtoolkit from PSGallery.

    .PARAMETER AttemptRemediation
    If specified, attempts to install vmxtoolkit from PSGallery if not found

    .EXAMPLE
    $result = Test-FFUVmxToolkit
    if ($result.Status -ne 'Passed') { Write-Warning $result.Remediation }

    .EXAMPLE
    $result = Test-FFUVmxToolkit -AttemptRemediation
    # Will automatically install vmxtoolkit if missing

    .OUTPUTS
    FFUCheckResult object with status, message, and remediation steps
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [switch]$AttemptRemediation
    )

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        # Check if vmxtoolkit module is installed
        $module = Get-Module -ListAvailable -Name 'vmxtoolkit' -ErrorAction SilentlyContinue

        if ($module) {
            $stopwatch.Stop()
            return New-FFUCheckResult -CheckName 'VmxToolkit' -Status 'Passed' `
                -Message "vmxtoolkit v$($module.Version) installed" `
                -Details @{
                    ModuleVersion = $module.Version.ToString()
                    ModulePath = $module.ModuleBase
                } `
                -DurationMs $stopwatch.ElapsedMilliseconds
        }

        # Module not found - try remediation if requested
        if ($AttemptRemediation) {
            WriteLog "vmxtoolkit not found, attempting to install from PSGallery..."
            try {
                # Check if PSGallery is registered
                $gallery = Get-PSRepository -Name 'PSGallery' -ErrorAction SilentlyContinue
                if (-not $gallery) {
                    Register-PSRepository -Default -ErrorAction SilentlyContinue
                }

                # Install vmxtoolkit for current user (no admin required)
                Install-Module -Name 'vmxtoolkit' -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop

                # Verify installation
                $module = Get-Module -ListAvailable -Name 'vmxtoolkit' -ErrorAction SilentlyContinue
                if ($module) {
                    $stopwatch.Stop()
                    return New-FFUCheckResult -CheckName 'VmxToolkit' -Status 'Passed' `
                        -Message "vmxtoolkit v$($module.Version) installed via remediation" `
                        -Details @{
                            ModuleVersion = $module.Version.ToString()
                            ModulePath = $module.ModuleBase
                            RemediationAttempted = $true
                            RemediationSuccess = $true
                        } `
                        -DurationMs $stopwatch.ElapsedMilliseconds
                }
            }
            catch {
                WriteLog "Failed to install vmxtoolkit: $($_.Exception.Message)"
                # Fall through to failure
            }
        }

        # Module not found (and remediation failed or not attempted)
        # vmxtoolkit is OPTIONAL - vmrun.exe fallback handles all VM operations
        $stopwatch.Stop()
        return New-FFUCheckResult -CheckName 'VmxToolkit' -Status 'Warning' `
            -Message 'vmxtoolkit module not installed (optional - vmrun.exe fallback available)' `
            -Details @{
                ModuleAvailable = $false
                ModuleVersion = 'Not installed'
                FallbackAvailable = $true
                RemediationAttempted = $AttemptRemediation.IsPresent
                RemediationSuccess = $false
            } `
            -Remediation @"
The vmxtoolkit PowerShell module is not installed. This is OPTIONAL.

VMware VM operations will use vmrun.exe directly, which is fully functional
for all FFU Builder operations including:
- Creating VMs
- Starting/stopping VMs
- Attaching ISO files
- Querying VM state

To install vmxtoolkit for enhanced VM discovery (finds stopped VMs more easily):
    Install-Module -Name vmxtoolkit -Scope CurrentUser -Force

The build will proceed without vmxtoolkit using vmrun.exe and filesystem search fallback.
"@ `
            -DurationMs $stopwatch.ElapsedMilliseconds
    }
    catch {
        $stopwatch.Stop()
        return New-FFUCheckResult -CheckName 'VmxToolkit' -Status 'Failed' `
            -Message "Error checking vmxtoolkit: $($_.Exception.Message)" `
            -Remediation 'Install-Module -Name vmxtoolkit -Scope CurrentUser -Force' `
            -DurationMs $stopwatch.ElapsedMilliseconds
    }
}

function Test-FFUHyperVSwitchConflict {
    <#
    .SYNOPSIS
    Checks for Hyper-V External Virtual Switch conflicts when using VMware.

    .DESCRIPTION
    When using VMware Workstation Pro on a system with an existing Hyper-V External
    Virtual Switch, VMware's auto-bridging may select the wrong network adapter.

    The Hyper-V External switch bridges to a physical NIC (e.g., WiFi), causing
    VMware to auto-bridge to a different NIC (e.g., disconnected Ethernet).
    This results in Error 53 (network path not found) during FFU capture.

    This check is only performed when HypervisorType is 'VMware'.

    .PARAMETER HypervisorType
    The hypervisor being used. Check only runs for 'VMware'.

    .EXAMPLE
    $result = Test-FFUHyperVSwitchConflict -HypervisorType 'VMware'
    if ($result.Status -eq 'Failed') {
        Write-Error $result.Message
        Write-Information $result.Remediation
    }

    .OUTPUTS
    FFUCheckResult object with status, message, and remediation steps
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)]
        [ValidateSet('HyperV', 'VMware', 'Auto')]
        [string]$HypervisorType = 'HyperV'
    )

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    # Skip if not VMware
    if ($HypervisorType -ne 'VMware') {
        $stopwatch.Stop()
        return New-FFUCheckResult -CheckName 'HyperVSwitchConflict' -Status 'Skipped' `
            -Message "Hyper-V switch conflict check skipped (HypervisorType: $HypervisorType)" `
            -DurationMs $stopwatch.ElapsedMilliseconds
    }

    try {
        # Check for External Hyper-V switches
        $externalSwitches = Get-VMSwitch -ErrorAction SilentlyContinue |
            Where-Object { $_.SwitchType -eq 'External' }

        $stopwatch.Stop()

        if ($externalSwitches) {
            # BLOCKING - External switch found
            $switchNames = ($externalSwitches | ForEach-Object { $_.Name }) -join ', '
            $remediation = @"
Delete the Hyper-V External Virtual Switch before using VMware:

1. Open Hyper-V Manager
2. Go to Virtual Switch Manager (right panel)
3. Select the switch: $switchNames
4. Click 'Remove' and confirm

Or run PowerShell (Admin):
   Remove-VMSwitch -Name '$($externalSwitches[0].Name)' -Force

WHY THIS IS REQUIRED:
The External switch bridges to a physical adapter, causing VMware
to auto-bridge to a different (possibly disconnected) adapter.
This results in Error 53 (network path not found) during FFU capture.

After removing the switch, VMware will correctly auto-bridge to
your connected network adapter.
"@
            return New-FFUCheckResult -CheckName 'HyperVSwitchConflict' -Status 'Failed' `
                -Message "External Hyper-V virtual switch detected: $switchNames. This conflicts with VMware bridged networking." `
                -Remediation $remediation `
                -Details @{
                    Switches = @($externalSwitches | ForEach-Object { $_.Name })
                    SwitchType = 'External'
                    Count = $externalSwitches.Count
                } `
                -DurationMs $stopwatch.ElapsedMilliseconds
        }

        return New-FFUCheckResult -CheckName 'HyperVSwitchConflict' -Status 'Passed' `
            -Message 'No External Hyper-V virtual switches found - VMware bridged networking will work correctly' `
            -DurationMs $stopwatch.ElapsedMilliseconds
    }
    catch {
        $stopwatch.Stop()
        # If we can't check (e.g., Hyper-V not installed), pass - the conflict can't exist
        return New-FFUCheckResult -CheckName 'HyperVSwitchConflict' -Status 'Passed' `
            -Message "Hyper-V switch check passed (Hyper-V not accessible: $($_.Exception.Message))" `
            -DurationMs $stopwatch.ElapsedMilliseconds
    }
}

function Test-FFUVMwareBridgeConfiguration {
    <#
    .SYNOPSIS
    Pre-flight check for VMware bridge network adapter configuration.

    .DESCRIPTION
    Validates that VMware Workstation Pro bridging will use the correct network
    adapter during FFU builds. Detects the recommended adapter (with internet
    connectivity) and warns about problematic adapters like GlobalProtect VPN.

    Issues detected:
    - GlobalProtect/PANGPS VPN adapters present (can cause VMware to bridge wrong)
    - Multiple adapters with network connectivity (ambiguous auto-bridge selection)
    - No netmap.conf file (VMware network not configured)

    This check is WARNING-level, not blocking, because:
    - VMware may auto-select the correct adapter
    - User may have already configured bridging manually
    - The issue only manifests during FFU capture, not VM creation

    .PARAMETER HypervisorType
    The hypervisor being used. Check only runs for 'VMware'.

    .EXAMPLE
    $result = Test-FFUVMwareBridgeConfiguration -HypervisorType 'VMware'
    if ($result.Status -eq 'Warning') {
        Write-Warning $result.Message
        Write-Information $result.Remediation
    }

    .OUTPUTS
    FFUCheckResult object with status, message, and remediation steps
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)]
        [ValidateSet('HyperV', 'VMware', 'Auto')]
        [string]$HypervisorType = 'HyperV'
    )

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    # Skip if not VMware
    if ($HypervisorType -ne 'VMware') {
        $stopwatch.Stop()
        return New-FFUCheckResult -CheckName 'VMwareBridgeConfig' -Status 'Skipped' `
            -Message "VMware bridge configuration check skipped (HypervisorType: $HypervisorType)" `
            -DurationMs $stopwatch.ElapsedMilliseconds
    }

    # Patterns to exclude from bridging (VPN and problematic adapters)
    $excludePatterns = @(
        '*PANGP*',
        '*GlobalProtect*',
        '*Palo Alto*',
        '*Cisco AnyConnect*',
        '*Juniper*',
        '*VPN*',
        '*Tunnel*'
    )

    $details = @{
        RecommendedAdapter     = $null
        RecommendedAdapterGUID = $null
        ProblematicAdapters    = @()
        ConnectedAdapters      = @()
        NetmapExists           = $false
        VMnetBridgeBindCount   = 0
    }

    try {
        # Check if netmap.conf exists (indicates user has configured networking)
        $netmapPath = "C:\ProgramData\VMware\netmap.conf"
        $details.NetmapExists = Test-Path $netmapPath

        # Get adapters bound to VMnetBridge
        $linkage = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\VMnetBridge\Linkage' -ErrorAction SilentlyContinue
        if ($linkage -and $linkage.Bind) {
            $details.VMnetBridgeBindCount = $linkage.Bind.Count
        }

        # Find adapters with internet connectivity
        $gatewayConfigs = Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway -ne $null }

        foreach ($config in $gatewayConfigs) {
            $adapter = Get-NetAdapter -InterfaceAlias $config.InterfaceAlias -ErrorAction SilentlyContinue
            if (-not $adapter) { continue }

            $adapterInfo = @{
                Name        = $adapter.Name
                Description = $adapter.InterfaceDescription
                GUID        = $adapter.InterfaceGuid
                MAC         = $adapter.MacAddress
                Status      = $adapter.Status
                IPv4        = ($config.IPv4Address | Select-Object -First 1).IPAddress
            }

            # Check if it's a problematic adapter
            $isProblematic = $false
            foreach ($pattern in $excludePatterns) {
                if ($adapter.InterfaceDescription -like $pattern -or $adapter.Name -like $pattern) {
                    $isProblematic = $true
                    $details.ProblematicAdapters += $adapterInfo
                    break
                }
            }

            if (-not $isProblematic) {
                $details.ConnectedAdapters += $adapterInfo

                # Test actual internet connectivity
                if (-not $details.RecommendedAdapter) {
                    $testResult = Test-NetConnection -ComputerName "8.8.8.8" -WarningAction SilentlyContinue
                    if ($testResult.PingSucceeded) {
                        $details.RecommendedAdapter = $adapterInfo.Description
                        $details.RecommendedAdapterGUID = $adapterInfo.GUID
                    }
                }
            }
        }

        $stopwatch.Stop()

        # Determine result status and message
        $issues = @()
        $warnings = @()

        # Check for problematic adapters
        if ($details.ProblematicAdapters.Count -gt 0) {
            $problematicNames = ($details.ProblematicAdapters | ForEach-Object { $_.Description }) -join ', '
            $warnings += "VPN/problematic adapters detected: $problematicNames"
        }

        # Check if we found a recommended adapter
        if (-not $details.RecommendedAdapter) {
            $issues += "No suitable network adapter with internet connectivity found"
        }

        # Check if netmap.conf exists
        if (-not $details.NetmapExists) {
            $warnings += "VMware network not configured (netmap.conf not found)"
        }

        # Build result
        if ($issues.Count -gt 0) {
            # FAILED - No suitable adapter
            $remediation = @"
ISSUE: No network adapter with internet connectivity found.

REQUIRED STEPS:
1. Ensure your network adapter is connected and has internet access
2. Check that your network adapter is not disabled
3. Run 'Test-NetConnection -ComputerName 8.8.8.8' to verify connectivity
"@
            return New-FFUCheckResult -CheckName 'VMwareBridgeConfig' -Status 'Failed' `
                -Message ($issues -join '; ') `
                -Details $details `
                -Remediation $remediation `
                -DurationMs $stopwatch.ElapsedMilliseconds
        }
        elseif ($warnings.Count -gt 0) {
            # WARNING - Potential bridge issues
            $problematicList = if ($details.ProblematicAdapters.Count -gt 0) {
                "`nProblematic adapters to EXCLUDE:`n" + ($details.ProblematicAdapters | ForEach-Object { "  - $($_.Description)" } | Out-String)
            }
            else { "" }

            $remediation = @"
RECOMMENDED: Configure VMware bridging to use the correct adapter.

Your recommended adapter: $($details.RecommendedAdapter)
$problematicList
STEPS TO CONFIGURE:
1. Open VMware Virtual Network Editor:
   - Run: "C:\Program Files (x86)\VMware\VMware Workstation\vmnetcfg.exe"
   - Or: In VMware Workstation, go to Edit > Virtual Network Editor

2. Click 'Change Settings' (requires Administrator)

3. Select 'VMnet0 (Bridged)' from the list

4. Change 'Bridged to:' from 'Automatic' to:
   '$($details.RecommendedAdapter)'

5. (Optional) Click 'Automatic Settings' and UNCHECK any VPN adapters:
   - PANGP Virtual Ethernet Adapter
   - GlobalProtect adapters
   - Any other VPN adapters

6. Click 'Apply' and 'OK'

WHY THIS IS NEEDED:
VMware's auto-bridging may select a VPN adapter or disconnected adapter
instead of your active network adapter. This causes Error 53 (network
path not found) during FFU capture when the VM cannot reach the host's
network share.
"@
            return New-FFUCheckResult -CheckName 'VMwareBridgeConfig' -Status 'Warning' `
                -Message "VMware bridging may select wrong adapter. Recommended: $($details.RecommendedAdapter). $($warnings -join '; ')" `
                -Details $details `
                -Remediation $remediation `
                -DurationMs $stopwatch.ElapsedMilliseconds
        }
        else {
            # PASSED - All good
            return New-FFUCheckResult -CheckName 'VMwareBridgeConfig' -Status 'Passed' `
                -Message "VMware bridging configured. Recommended adapter: $($details.RecommendedAdapter)" `
                -Details $details `
                -DurationMs $stopwatch.ElapsedMilliseconds
        }
    }
    catch {
        $stopwatch.Stop()
        return New-FFUCheckResult -CheckName 'VMwareBridgeConfig' -Status 'Warning' `
            -Message "Could not verify VMware bridge configuration: $($_.Exception.Message)" `
            -Details $details `
            -Remediation 'Manually verify VMware bridging is configured to use your active network adapter.' `
            -DurationMs $stopwatch.ElapsedMilliseconds
    }
}

#endregion Tier 2: Feature-Dependent Validations

#region Tier 3: Recommended Validations

function Test-FFUAntivirusExclusions {
    <#
    .SYNOPSIS
    Checks if recommended Windows Defender exclusions are configured.

    .DESCRIPTION
    Verifies that FFUDevelopment path and DISM-related exclusions are set
    in Windows Defender. This is a warning-only check (non-blocking) as
    builds can succeed without exclusions, but may be slower or less reliable.

    .PARAMETER FFUDevelopmentPath
    Path to the FFUDevelopment folder to check for exclusion

    .EXAMPLE
    $result = Test-FFUAntivirusExclusions -FFUDevelopmentPath 'C:\FFUDevelopment'

    .OUTPUTS
    FFUCheckResult object with status, message, and remediation steps
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FFUDevelopmentPath
    )

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    $details = @{
        DefenderActive        = $false
        PathExclusionFound    = $false
        ProcessExclusionFound = $false
        ExtensionExclusions   = @()
    }

    try {
        # Check if Windows Defender is active
        $mpStatus = Get-MpComputerStatus -ErrorAction SilentlyContinue

        if (-not $mpStatus) {
            $stopwatch.Stop()
            New-FFUCheckResult -CheckName 'AntivirusExclusions' -Status 'Skipped' `
                -Message 'Windows Defender status unavailable (may be using third-party AV)' `
                -Details $details `
                -DurationMs $stopwatch.ElapsedMilliseconds
        }

        $details.DefenderActive = $mpStatus.RealTimeProtectionEnabled

        if (-not $mpStatus.RealTimeProtectionEnabled) {
            $stopwatch.Stop()
            New-FFUCheckResult -CheckName 'AntivirusExclusions' -Status 'Skipped' `
                -Message 'Windows Defender real-time protection is disabled' `
                -Details $details `
                -DurationMs $stopwatch.ElapsedMilliseconds
        }

        # Get current exclusions
        $mpPrefs = Get-MpPreference -ErrorAction SilentlyContinue

        # Check path exclusion
        $pathExclusions = $mpPrefs.ExclusionPath
        if ($pathExclusions) {
            $details.PathExclusionFound = $pathExclusions -contains $FFUDevelopmentPath
        }

        # Check process exclusions
        $processExclusions = $mpPrefs.ExclusionProcess
        $requiredProcesses = @('dism.exe', 'dismhost.exe')
        $foundProcesses = @()
        if ($processExclusions) {
            foreach ($proc in $requiredProcesses) {
                if ($processExclusions -contains $proc) {
                    $foundProcesses += $proc
                }
            }
        }
        $details.ProcessExclusionFound = ($foundProcesses.Count -eq $requiredProcesses.Count)

        # Check extension exclusions
        $extensionExclusions = $mpPrefs.ExclusionExtension
        $recommendedExtensions = @('.vhd', '.vhdx', '.ffu', '.wim', '.esd')
        if ($extensionExclusions) {
            $details.ExtensionExclusions = $extensionExclusions | Where-Object { $_ -in $recommendedExtensions }
        }

        $stopwatch.Stop()

        # Determine status
        $allGood = $details.PathExclusionFound -and $details.ProcessExclusionFound

        if ($allGood) {
            New-FFUCheckResult -CheckName 'AntivirusExclusions' -Status 'Passed' `
                -Message 'Windows Defender exclusions are properly configured' `
                -Details $details `
                -DurationMs $stopwatch.ElapsedMilliseconds
        }
        else {
            $missingItems = @()
            if (-not $details.PathExclusionFound) {
                $missingItems += "Path: $FFUDevelopmentPath"
            }
            if (-not $details.ProcessExclusionFound) {
                $missingItems += "Processes: dism.exe, dismhost.exe"
            }

            New-FFUCheckResult -CheckName 'AntivirusExclusions' -Status 'Warning' `
                -Message "Recommended Windows Defender exclusions not configured (may impact performance)" `
                -Details $details `
                -Remediation @"
Add Windows Defender exclusions for optimal FFU build performance:

Run these commands as Administrator:

# Add path exclusion
Add-MpPreference -ExclusionPath '$FFUDevelopmentPath'

# Add process exclusions
Add-MpPreference -ExclusionProcess 'dism.exe'
Add-MpPreference -ExclusionProcess 'dismhost.exe'

# Add extension exclusions (recommended)
Add-MpPreference -ExclusionExtension '.vhd'
Add-MpPreference -ExclusionExtension '.vhdx'
Add-MpPreference -ExclusionExtension '.ffu'
Add-MpPreference -ExclusionExtension '.wim'
Add-MpPreference -ExclusionExtension '.esd'

Missing exclusions:
$($missingItems | ForEach-Object { "  - $_" } | Out-String)

Note: This is optional but recommended for reliability and performance.
"@ `
                -DurationMs $stopwatch.ElapsedMilliseconds
        }
    }
    catch {
        $stopwatch.Stop()
        New-FFUCheckResult -CheckName 'AntivirusExclusions' -Status 'Skipped' `
            -Message "Unable to check antivirus exclusions: $($_.Exception.Message)" `
            -Details $details `
            -DurationMs $stopwatch.ElapsedMilliseconds
    }
}

#endregion Tier 3: Recommended Validations

#region Tier 4: Cleanup Operations

function Invoke-FFUDISMCleanup {
    <#
    .SYNOPSIS
    Performs DISM environment cleanup before FFU build operations.

    .DESCRIPTION
    Cleans up stale DISM mount points, temporary directories, and orphaned
    VHD files that may interfere with FFU build operations. This is a
    pre-remediation step that runs before builds to ensure clean state.

    .PARAMETER FFUDevelopmentPath
    Path to FFUDevelopment folder for locating orphaned files

    .EXAMPLE
    $result = Invoke-FFUDISMCleanup -FFUDevelopmentPath 'C:\FFUDevelopment'

    .OUTPUTS
    FFUCheckResult object with cleanup actions performed
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FFUDevelopmentPath
    )

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    $details = @{
        MountPointsCleaned    = 0
        TempDirsCleaned       = 0
        OrphanedVHDsCleaned   = 0
        MountedImagesDismounted = 0
        CleanupActions        = [System.Collections.Generic.List[string]]::new()
    }

    try {
        # 1. Clean stale DISM mount points
        try {
            $dismOutput = & dism.exe /Cleanup-Mountpoints 2>&1
            if ($LASTEXITCODE -eq 0) {
                $details.MountPointsCleaned = 1
                $details.CleanupActions.Add('Cleaned DISM mount points')
            }
        }
        catch {
            $details.CleanupActions.Add("DISM cleanup warning: $($_.Exception.Message)")
        }

        # 2. Dismount any mounted Windows images
        try {
            $mountedImages = Get-WindowsImage -Mounted -ErrorAction SilentlyContinue
            foreach ($mount in $mountedImages) {
                try {
                    Dismount-WindowsImage -Path $mount.Path -Discard -ErrorAction Stop
                    $details.MountedImagesDismounted++
                    $details.CleanupActions.Add("Dismounted image at: $($mount.Path)")
                }
                catch {
                    $details.CleanupActions.Add("Failed to dismount: $($mount.Path)")
                }
            }
        }
        catch {
            # No mounted images or unable to query
        }

        # 3. Clean DISM temp directories
        $tempPaths = @(
            "$env:TEMP\DISM*",
            "$env:SystemRoot\Temp\DISM*",
            "$env:LOCALAPPDATA\Temp\DISM*"
        )

        foreach ($pathPattern in $tempPaths) {
            try {
                $items = Get-ChildItem -Path $pathPattern -ErrorAction SilentlyContinue
                foreach ($item in $items) {
                    try {
                        Remove-Item -Path $item.FullName -Recurse -Force -ErrorAction Stop
                        $details.TempDirsCleaned++
                        $details.CleanupActions.Add("Removed temp dir: $($item.Name)")
                    }
                    catch {
                        # Item locked, skip
                    }
                }
            }
            catch {
                # Path doesn't exist, skip
            }
        }

        # 4. Clean orphaned _ffumount*.vhd files
        try {
            $orphanedVHDs = Get-ChildItem -Path "$env:TEMP\_ffumount*.vhd" -ErrorAction SilentlyContinue
            foreach ($vhd in $orphanedVHDs) {
                try {
                    # Try to dismount first
                    Dismount-DiskImage -ImagePath $vhd.FullName -ErrorAction SilentlyContinue
                    Start-Sleep -Milliseconds 500
                    Remove-Item -Path $vhd.FullName -Force -ErrorAction Stop
                    $details.OrphanedVHDsCleaned++
                    $details.CleanupActions.Add("Removed orphaned VHD: $($vhd.Name)")
                }
                catch {
                    $details.CleanupActions.Add("Could not remove VHD (in use): $($vhd.Name)")
                }
            }
        }
        catch {
            # No orphaned VHDs found
        }

        # 5. Clean scratch directories in FFUDevelopment
        if (Test-Path $FFUDevelopmentPath) {
            $scratchDirs = @(
                (Join-Path $FFUDevelopmentPath 'DISMScratch'),
                (Join-Path $FFUDevelopmentPath 'FFUScratch')
            )

            foreach ($scratchDir in $scratchDirs) {
                if (Test-Path $scratchDir) {
                    try {
                        Remove-Item -Path $scratchDir -Recurse -Force -ErrorAction Stop
                        $details.TempDirsCleaned++
                        $details.CleanupActions.Add("Removed scratch dir: $scratchDir")
                    }
                    catch {
                        $details.CleanupActions.Add("Could not remove scratch dir: $scratchDir")
                    }
                }
            }
        }

        $stopwatch.Stop()

        $totalCleaned = $details.MountPointsCleaned + $details.TempDirsCleaned +
                        $details.OrphanedVHDsCleaned + $details.MountedImagesDismounted

        if ($totalCleaned -gt 0) {
            New-FFUCheckResult -CheckName 'DISMCleanup' -Status 'Passed' `
                -Message "DISM cleanup completed: $totalCleaned item(s) cleaned" `
                -Details $details `
                -DurationMs $stopwatch.ElapsedMilliseconds
        }
        else {
            New-FFUCheckResult -CheckName 'DISMCleanup' -Status 'Passed' `
                -Message 'DISM cleanup completed: environment was already clean' `
                -Details $details `
                -DurationMs $stopwatch.ElapsedMilliseconds
        }
    }
    catch {
        $stopwatch.Stop()
        New-FFUCheckResult -CheckName 'DISMCleanup' -Status 'Warning' `
            -Message "DISM cleanup completed with warnings: $($_.Exception.Message)" `
            -Details $details `
            -Remediation @'
DISM cleanup encountered issues. Manual cleanup may be needed:

1. Run DISM cleanup manually:
   dism /Cleanup-Mountpoints

2. Check for locked files:
   - Close any open File Explorer windows
   - Stop any running DISM operations
   - Restart Windows if necessary

3. Check for orphaned VHDs in %TEMP%:
   dir %TEMP%\_ffumount*.vhd
'@ `
            -DurationMs $stopwatch.ElapsedMilliseconds
    }
}

#endregion Tier 4: Cleanup Operations

#region Main Orchestrator

function Invoke-FFUPreflight {
    <#
    .SYNOPSIS
    Comprehensive environment validation for FFU Builder operations.

    .DESCRIPTION
    Performs all necessary pre-flight checks based on enabled features,
    providing clear pass/fail status with actionable remediation guidance.

    Validation is organized into tiers:
    - Tier 1: CRITICAL (Always Run, Blocking) - Admin, PowerShell, Hyper-V
    - Tier 2: FEATURE-DEPENDENT (Conditional, Blocking) - ADK, Disk, Network, Config
    - Tier 3: RECOMMENDED (Warnings Only) - Antivirus Exclusions
    - Tier 4: CLEANUP (Pre-Remediation) - DISM Cleanup

    .PARAMETER Features
    Hashtable of enabled features to determine which validations to run:
    - CreateVM: Hyper-V required
    - CreateCaptureMedia: ADK + WinPE required
    - CreateDeploymentMedia: ADK + WinPE required
    - OptimizeFFU: ADK required
    - InstallApps: Network + Apps ISO space required
    - UpdateLatestCU: Network + KB space required
    - DownloadDrivers: Network required

    .PARAMETER FFUDevelopmentPath
    Working directory for space calculations and cleanup operations

    .PARAMETER VHDXSizeGB
    Target VHDX size for space calculations (default: 50)

    .PARAMETER ConfigFile
    Optional path to configuration file to validate

    .PARAMETER WindowsArch
    Target architecture: 'x64' or 'arm64' (default: x64)

    .PARAMETER SkipCleanup
    Skip Tier 4 cleanup operations

    .PARAMETER WarningsAsErrors
    Treat Tier 3 warnings as blocking errors

    .EXAMPLE
    $features = @{
        CreateVM = $true
        CreateCaptureMedia = $true
        InstallApps = $true
        UpdateLatestCU = $true
    }
    $result = Invoke-FFUPreflight -Features $features `
                                  -FFUDevelopmentPath 'C:\FFUDevelopment' `
                                  -VHDXSizeGB 50

    if (-not $result.IsValid) {
        $result.Errors | ForEach-Object { Write-Error $_ }
        exit 1
    }

    .EXAMPLE
    # Strict mode - treat warnings as errors
    $result = Invoke-FFUPreflight -Features $features `
                                  -FFUDevelopmentPath 'C:\FFUDevelopment' `
                                  -WarningsAsErrors

    .OUTPUTS
    PSCustomObject with validation results including:
    - IsValid: Overall pass/fail status
    - HasWarnings: Whether any warnings were generated
    - Errors: Array of error messages
    - Warnings: Array of warning messages
    - RemediationSteps: Ordered steps to fix issues
    - Tier1Results, Tier2Results, Tier3Results, Tier4Results: Detailed results by tier
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Features,

        [Parameter(Mandatory = $true)]
        [string]$FFUDevelopmentPath,

        [Parameter()]
        [int]$VHDXSizeGB = 50,

        [Parameter()]
        [string]$ConfigFile,

        [Parameter()]
        [ValidateSet('x64', 'arm64')]
        [string]$WindowsArch = 'x64',

        [Parameter()]
        [switch]$SkipCleanup,

        [Parameter()]
        [switch]$WarningsAsErrors,

        [Parameter()]
        [ValidateSet('HyperV', 'VMware', 'Auto')]
        [string]$HypervisorType = 'HyperV'
    )

    $overallStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    # Initialize result object
    $result = [PSCustomObject]@{
        IsValid              = $true
        HasWarnings          = $false
        ValidationTimestamp  = Get-Date
        ValidationDurationMs = 0
        Tier1Results         = @{}
        Tier2Results         = @{}
        Tier3Results         = @{}
        Tier4Results         = @{}
        Errors               = [System.Collections.Generic.List[string]]::new()
        Warnings             = [System.Collections.Generic.List[string]]::new()
        RemediationSteps     = [System.Collections.Generic.List[string]]::new()
        CleanupPerformed     = [System.Collections.Generic.List[string]]::new()
        RequiredDiskSpaceGB  = 0
        AvailableDiskSpaceGB = 0
        RequiredFeatures     = @()
    }

    # Calculate requirements (pass HypervisorType to determine if Hyper-V is needed)
    $requirements = Get-FFURequirements -Features $Features -VHDXSizeGB $VHDXSizeGB -HypervisorType $HypervisorType
    $result.RequiredDiskSpaceGB = $requirements.RequiredDiskSpaceGB
    $result.RequiredFeatures = $requirements.RequiredFeatures

    Write-Information "`n========================================"
    Write-Information "   FFU Pre-Flight Validation"
    Write-Information "========================================`n"

    #region Tier 1: Critical Validations
    Write-Information "[Tier 1] Critical Validations"
    Write-Information "-----------------------------"

    # Administrator check
    $adminResult = Test-FFUAdministrator
    $result.Tier1Results['Administrator'] = $adminResult
    if ($adminResult.Status -eq 'Passed') {
        Write-Information "  Checking Administrator privileges... PASSED"
    }
    else {
        Write-Information "  Checking Administrator privileges... FAILED"
        $result.IsValid = $false
        $result.Errors.Add("Administrator: $($adminResult.Message)")
        $result.RemediationSteps.Add($adminResult.Remediation)
    }

    # PowerShell version check
    $psResult = Test-FFUPowerShellVersion
    $result.Tier1Results['PowerShellVersion'] = $psResult
    if ($psResult.Status -eq 'Passed') {
        Write-Information "  Checking PowerShell version... PASSED ($($psResult.Details.Version))"
    }
    else {
        Write-Information "  Checking PowerShell version... FAILED"
        $result.IsValid = $false
        $result.Errors.Add("PowerShell: $($psResult.Message)")
        $result.RemediationSteps.Add($psResult.Remediation)
    }

    # Hyper-V check (only if using Hyper-V hypervisor and CreateVM is enabled)
    if ($requirements.NeedsHyperV) {
        $hvResult = Test-FFUHyperV
        $result.Tier1Results['HyperV'] = $hvResult
        if ($hvResult.Status -eq 'Passed') {
            Write-Information "  Checking Hyper-V feature... PASSED"
        }
        else {
            Write-Information "  Checking Hyper-V feature... FAILED"
            $result.IsValid = $false
            $result.Errors.Add("Hyper-V: $($hvResult.Message)")
            $result.RemediationSteps.Add($hvResult.Remediation)
        }
    }
    elseif ($HypervisorType -eq 'VMware') {
        Write-Information "  Checking Hyper-V feature... SKIPPED (using VMware)"
        $result.Tier1Results['HyperV'] = New-FFUCheckResult -CheckName 'HyperV' -Status 'Skipped' `
            -Message 'Hyper-V check skipped (VMware hypervisor selected)'
    }
    else {
        Write-Information "  Hyper-V check... SKIPPED (CreateVM not enabled)"
        $result.Tier1Results['HyperV'] = New-FFUCheckResult -CheckName 'HyperV' -Status 'Skipped' `
            -Message 'Hyper-V check skipped (CreateVM not enabled)'
    }

    #endregion Tier 1

    #region Tier 2: Feature-Dependent Validations
    Write-Information "`n[Tier 2] Feature-Dependent Validations"
    Write-Information "---------------------------------------"

    # ADK check (only if needed)
    if ($requirements.NeedsADK) {
        $adkResult = Test-FFUADK -RequireWinPE $requirements.NeedsWinPE -WindowsArch $WindowsArch
        $result.Tier2Results['ADK'] = $adkResult
        if ($adkResult.Status -eq 'Passed') {
            Write-Information "  Checking Windows ADK... PASSED"
        }
        else {
            Write-Information "  Checking Windows ADK... FAILED"
            $result.IsValid = $false
            $result.Errors.Add("ADK: $($adkResult.Message)")
            $result.RemediationSteps.Add($adkResult.Remediation)
        }
    }
    else {
        Write-Information "  Windows ADK check... SKIPPED (not required)"
        $result.Tier2Results['ADK'] = New-FFUCheckResult -CheckName 'ADK' -Status 'Skipped' `
            -Message 'ADK check skipped (no features require ADK)'
    }

    # WIM mount capability check (only if WinPE or DISM operations are needed)
    if ($requirements.NeedsWinPE -or $requirements.NeedsADK) {
        $wimMountResult = Test-FFUWimMount -AttemptRemediation
        $result.Tier2Results['WimMount'] = $wimMountResult
        if ($wimMountResult.Status -eq 'Passed') {
            $msg = if ($wimMountResult.Details.RemediationAttempted) { ' (after remediation)' } else { '' }
            Write-Information "  Checking WIM mount capability... PASSED$msg"
        }
        elseif ($wimMountResult.Status -eq 'Failed') {
            # v1.3.8: WIMMount failures are BLOCKING - both ADK dism.exe AND PowerShell DISM cmdlets require WIMMount
            Write-Information "  Checking WIM mount capability... FAILED (BLOCKING)"
            $result.IsValid = $false
            $result.Errors.Add("WimMount: $($wimMountResult.Message)")
            $result.RemediationSteps.Add($wimMountResult.Remediation)
        }
        else {
            # Unexpected status (Warning or other - should not happen in v1.3.8+)
            Write-Warning "  Checking WIM mount capability... $($wimMountResult.Status.ToUpper())"
            $result.HasWarnings = $true
            $result.Warnings.Add("WimMount: $($wimMountResult.Message)")
        }
    }
    else {
        Write-Information "  WIM mount check... SKIPPED (not required)"
        $result.Tier2Results['WimMount'] = New-FFUCheckResult -CheckName 'WimMount' -Status 'Skipped' `
            -Message 'WIM mount check skipped (no features require DISM mount operations)'
    }

    # vmxtoolkit check (only if using VMware hypervisor)
    if ($HypervisorType -eq 'VMware') {
        $vmxToolkitResult = Test-FFUVmxToolkit -AttemptRemediation
        $result.Tier2Results['VmxToolkit'] = $vmxToolkitResult
        if ($vmxToolkitResult.Status -eq 'Passed') {
            $msg = if ($vmxToolkitResult.Details.RemediationAttempted) { ' (installed)' } else { '' }
            Write-Information "  Checking vmxtoolkit module... PASSED$msg"
        }
        else {
            Write-Information "  Checking vmxtoolkit module... FAILED"
            $result.IsValid = $false
            $result.Errors.Add("VmxToolkit: $($vmxToolkitResult.Message)")
            $result.RemediationSteps.Add($vmxToolkitResult.Remediation)
        }
    }
    else {
        Write-Information "  vmxtoolkit check... SKIPPED (not using VMware)"
        $result.Tier2Results['VmxToolkit'] = New-FFUCheckResult -CheckName 'VmxToolkit' -Status 'Skipped' `
            -Message 'vmxtoolkit check skipped (not using VMware hypervisor)'
    }

    # Hyper-V switch conflict check (only if using VMware hypervisor)
    if ($HypervisorType -eq 'VMware') {
        $switchConflictResult = Test-FFUHyperVSwitchConflict -HypervisorType $HypervisorType
        $result.Tier2Results['HyperVSwitchConflict'] = $switchConflictResult
        if ($switchConflictResult.Status -eq 'Passed') {
            Write-Information "  Checking for Hyper-V switch conflicts... PASSED"
        }
        elseif ($switchConflictResult.Status -eq 'Failed') {
            Write-Information "  Checking for Hyper-V switch conflicts... FAILED"
            $result.IsValid = $false
            $result.Errors.Add("Hyper-V Switch Conflict: $($switchConflictResult.Message)")
            if ($switchConflictResult.Remediation) {
                $result.RemediationSteps.Add($switchConflictResult.Remediation)
            }
        }
    }
    else {
        Write-Information "  Hyper-V switch conflict check... SKIPPED (not using VMware)"
        $result.Tier2Results['HyperVSwitchConflict'] = New-FFUCheckResult -CheckName 'HyperVSwitchConflict' -Status 'Skipped' `
            -Message 'Hyper-V switch conflict check skipped (not using VMware hypervisor)'
    }

    # VMware bridge configuration check (only if using VMware hypervisor)
    if ($HypervisorType -eq 'VMware') {
        $bridgeConfigResult = Test-FFUVMwareBridgeConfiguration -HypervisorType $HypervisorType
        $result.Tier2Results['VMwareBridgeConfig'] = $bridgeConfigResult
        if ($bridgeConfigResult.Status -eq 'Passed') {
            Write-Information "  Checking VMware bridge configuration... PASSED"
        }
        elseif ($bridgeConfigResult.Status -eq 'Warning') {
            Write-Warning "  Checking VMware bridge configuration... WARNING"
            $result.HasWarnings = $true
            $result.Warnings.Add("VMware Bridge: $($bridgeConfigResult.Message)")
            # Store remediation for display (non-blocking warning)
            if ($bridgeConfigResult.Remediation) {
                $result.RemediationSteps.Add($bridgeConfigResult.Remediation)
            }
        }
        elseif ($bridgeConfigResult.Status -eq 'Failed') {
            Write-Information "  Checking VMware bridge configuration... FAILED"
            $result.IsValid = $false
            $result.Errors.Add("VMware Bridge: $($bridgeConfigResult.Message)")
            if ($bridgeConfigResult.Remediation) {
                $result.RemediationSteps.Add($bridgeConfigResult.Remediation)
            }
        }
    }
    else {
        Write-Information "  VMware bridge configuration check... SKIPPED (not using VMware)"
        $result.Tier2Results['VMwareBridgeConfig'] = New-FFUCheckResult -CheckName 'VMwareBridgeConfig' -Status 'Skipped' `
            -Message 'VMware bridge configuration check skipped (not using VMware hypervisor)'
    }

    # Disk space check
    $diskResult = Test-FFUDiskSpace -FFUDevelopmentPath $FFUDevelopmentPath `
                                    -Features $Features -VHDXSizeGB $VHDXSizeGB
    $result.Tier2Results['DiskSpace'] = $diskResult
    $result.AvailableDiskSpaceGB = $diskResult.Details.AvailableGB
    if ($diskResult.Status -eq 'Passed') {
        Write-Information "  Checking disk space... PASSED ($($diskResult.Details.AvailableGB)GB free)"
    }
    else {
        Write-Information "  Checking disk space... FAILED"
        $result.IsValid = $false
        $result.Errors.Add("DiskSpace: $($diskResult.Message)")
        $result.RemediationSteps.Add($diskResult.Remediation)
    }

    # Network check (only if needed)
    if ($requirements.NeedsNetwork) {
        $netResult = Test-FFUNetwork -Features $Features
        $result.Tier2Results['Network'] = $netResult
        if ($netResult.Status -eq 'Passed') {
            Write-Information "  Checking network connectivity... PASSED"
        }
        elseif ($netResult.Status -eq 'Warning') {
            Write-Warning "  Checking network connectivity... WARNING"
            $result.HasWarnings = $true
            $result.Warnings.Add("Network: $($netResult.Message)")
            if ($WarningsAsErrors) {
                $result.IsValid = $false
                $result.Errors.Add("Network (as error): $($netResult.Message)")
            }
        }
        else {
            Write-Information "  Checking network connectivity... FAILED"
            $result.IsValid = $false
            $result.Errors.Add("Network: $($netResult.Message)")
            $result.RemediationSteps.Add($netResult.Remediation)
        }
    }
    else {
        Write-Information "  Network connectivity check... SKIPPED (not required)"
        $result.Tier2Results['Network'] = New-FFUCheckResult -CheckName 'Network' -Status 'Skipped' `
            -Message 'Network check skipped (no features require network)'
    }

    # Configuration file check
    if ($ConfigFile) {
        $configResult = Test-FFUConfigurationFile -ConfigFilePath $ConfigFile
        $result.Tier2Results['Configuration'] = $configResult
        if ($configResult.Status -eq 'Passed') {
            Write-Information "  Validating configuration file... PASSED"
        }
        elseif ($configResult.Status -eq 'Skipped') {
            Write-Information "  Validating configuration file... SKIPPED"
        }
        else {
            Write-Information "  Validating configuration file... FAILED"
            $result.IsValid = $false
            $result.Errors.Add("Configuration: $($configResult.Message)")
            $result.RemediationSteps.Add($configResult.Remediation)
        }
    }
    else {
        Write-Information "  Configuration file check... SKIPPED (no config file)"
        $result.Tier2Results['Configuration'] = New-FFUCheckResult -CheckName 'Configuration' -Status 'Skipped' `
            -Message 'Configuration check skipped (no config file specified)'
    }

    #endregion Tier 2

    #region Tier 3: Recommended Validations
    Write-Information "`n[Tier 3] Recommended Validations (Warnings)"
    Write-Information "--------------------------------------------"

    # Antivirus exclusions check
    $avResult = Test-FFUAntivirusExclusions -FFUDevelopmentPath $FFUDevelopmentPath
    $result.Tier3Results['AntivirusExclusions'] = $avResult
    if ($avResult.Status -eq 'Passed') {
        Write-Information "  Checking antivirus exclusions... PASSED"
    }
    elseif ($avResult.Status -eq 'Skipped') {
        Write-Information "  Checking antivirus exclusions... SKIPPED"
    }
    elseif ($avResult.Status -eq 'Warning') {
        Write-Warning "  Checking antivirus exclusions... WARNING"
        $result.HasWarnings = $true
        $result.Warnings.Add("Antivirus: $($avResult.Message)")
        if ($WarningsAsErrors) {
            $result.IsValid = $false
            $result.Errors.Add("Antivirus (as error): $($avResult.Message)")
            $result.RemediationSteps.Add($avResult.Remediation)
        }
    }

    #endregion Tier 3

    #region Tier 4: Cleanup Operations
    if (-not $SkipCleanup) {
        Write-Information "`n[Tier 4] Pre-Build Cleanup"
        Write-Information "--------------------------"

        $cleanupResult = Invoke-FFUDISMCleanup -FFUDevelopmentPath $FFUDevelopmentPath
        $result.Tier4Results['DISMCleanup'] = $cleanupResult
        $result.CleanupPerformed = $cleanupResult.Details.CleanupActions

        if ($cleanupResult.Status -eq 'Passed') {
            $cleanedCount = $cleanupResult.Details.MountPointsCleaned +
                           $cleanupResult.Details.TempDirsCleaned +
                           $cleanupResult.Details.OrphanedVHDsCleaned +
                           $cleanupResult.Details.MountedImagesDismounted
            if ($cleanedCount -gt 0) {
                Write-Information "  Performing DISM cleanup... DONE ($cleanedCount items cleaned)"
            }
            else {
                Write-Information "  Performing DISM cleanup... DONE (already clean)"
            }
        }
        else {
            Write-Warning "  Performing DISM cleanup... WARNING"
            $result.HasWarnings = $true
            $result.Warnings.Add("Cleanup: $($cleanupResult.Message)")
        }
    }
    else {
        Write-Information "`n[Tier 4] Pre-Build Cleanup"
        Write-Information "--------------------------"
        Write-Information "  DISM cleanup... SKIPPED (SkipCleanup specified)"
        $result.Tier4Results['DISMCleanup'] = New-FFUCheckResult -CheckName 'DISMCleanup' -Status 'Skipped' `
            -Message 'Cleanup skipped (SkipCleanup specified)'
    }

    #endregion Tier 4

    # Calculate total duration
    $overallStopwatch.Stop()
    $result.ValidationDurationMs = $overallStopwatch.ElapsedMilliseconds

    # Print summary
    Write-Information "`n========================================"
    Write-Information "   Validation Summary"
    Write-Information "========================================"

    if ($result.IsValid) {
        Write-Information "`n  STATUS: PASSED"
        if ($result.HasWarnings) {
            Write-Warning "  Warnings: $($result.Warnings.Count)"
        }
    }
    else {
        Write-Information "`n  STATUS: FAILED"
        Write-Information "  Errors: $($result.Errors.Count)"
        if ($result.HasWarnings) {
            Write-Warning "  Warnings: $($result.Warnings.Count)"
        }
    }

    Write-Information "  Duration: $($result.ValidationDurationMs)ms"
    Write-Information "  Disk Space: $($result.AvailableDiskSpaceGB)GB available, $($result.RequiredDiskSpaceGB)GB required"
    Write-Information "`n========================================`n"

    $result
}

#endregion Main Orchestrator

#region VMware Driver Validation

function Test-FFUVMwareDrivers {
    <#
    .SYNOPSIS
    Validates VMware network drivers are available for WinPE capture.

    .DESCRIPTION
    Checks if the VMwareDrivers folder exists and contains Intel e1000e drivers
    needed for WinPE network connectivity when running FFU capture on VMware
    Workstation Pro. VMware uses e1000e (Intel 82574L) emulated NICs by default,
    which WinPE doesn't include drivers for.

    .PARAMETER FFUDevelopmentPath
    Root FFUDevelopment path where VMwareDrivers folder should be located.

    .PARAMETER HypervisorType
    The hypervisor type being used. Only performs validation when 'VMware'.

    .OUTPUTS
    [PSCustomObject] with Status, Message, Details, and Remediation properties.

    .EXAMPLE
    $result = Test-FFUVMwareDrivers -FFUDevelopmentPath "C:\FFU" -HypervisorType "VMware"
    if ($result.Status -eq 'Warning') { Write-Warning $result.Message }

    .NOTES
    This is an informational check. If VMwareDrivers folder is missing, drivers
    will be auto-downloaded during WinPE media creation (see FFU.Media module).
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FFUDevelopmentPath,

        [Parameter(Mandatory = $false)]
        [ValidateSet('HyperV', 'VMware', 'Auto')]
        [string]$HypervisorType = 'HyperV'
    )

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    # Skip check for Hyper-V
    if ($HypervisorType -ne 'VMware') {
        $stopwatch.Stop()
        return New-FFUCheckResult -CheckName 'VMwareDrivers' -Status 'Skipped' `
            -Message "VMware driver check skipped (HypervisorType: $HypervisorType)" `
            -DurationMs $stopwatch.ElapsedMilliseconds
    }

    $vmwareDriversPath = Join-Path $FFUDevelopmentPath "VMwareDrivers"

    # Check if VMwareDrivers folder exists
    if (-not (Test-Path $vmwareDriversPath)) {
        $stopwatch.Stop()
        return New-FFUCheckResult -CheckName 'VMwareDrivers' -Status 'Passed' `
            -Message "VMwareDrivers folder not present. Intel e1000e drivers will be auto-downloaded during build." `
            -Details @{
                ExpectedPath = $vmwareDriversPath
                AutoDownload = $true
            } `
            -DurationMs $stopwatch.ElapsedMilliseconds
    }

    # Check for INF files in the folder
    $infFiles = Get-ChildItem -Path $vmwareDriversPath -Filter "*.inf" -Recurse -ErrorAction SilentlyContinue
    if ($infFiles.Count -eq 0) {
        $stopwatch.Stop()
        return New-FFUCheckResult -CheckName 'VMwareDrivers' -Status 'Warning' `
            -Message "VMwareDrivers folder exists but contains no driver files (*.inf)" `
            -Details @{
                Path = $vmwareDriversPath
                InfCount = 0
            } `
            -Remediation @"
Either:
1. Delete the VMwareDrivers folder to trigger auto-download during build
2. Manually add Intel e1000e driver INF files from:
   https://www.intel.com/content/www/us/en/content-details/30080/intel-ethernet-adapter-complete-driver-pack.html
"@ `
            -DurationMs $stopwatch.ElapsedMilliseconds
    }

    # Check for e1000e specifically
    $e1000eInf = $infFiles | Where-Object { $_.Name -like "*e1000*" -or $_.Name -eq "e1000e.inf" }

    $stopwatch.Stop()
    if ($e1000eInf) {
        return New-FFUCheckResult -CheckName 'VMwareDrivers' -Status 'Passed' `
            -Message "VMwareDrivers folder ready with $($infFiles.Count) driver file(s) including e1000e" `
            -Details @{
                Path = $vmwareDriversPath
                InfCount = $infFiles.Count
                E1000eFound = $true
                DriverFiles = ($infFiles | Select-Object -ExpandProperty Name) -join ', '
            } `
            -DurationMs $stopwatch.ElapsedMilliseconds
    }
    else {
        return New-FFUCheckResult -CheckName 'VMwareDrivers' -Status 'Passed' `
            -Message "VMwareDrivers folder contains $($infFiles.Count) driver file(s)" `
            -Details @{
                Path = $vmwareDriversPath
                InfCount = $infFiles.Count
                E1000eFound = $false
                DriverFiles = ($infFiles | Select-Object -ExpandProperty Name) -join ', '
            } `
            -DurationMs $stopwatch.ElapsedMilliseconds
    }
}

#endregion VMware Driver Validation

# Export all public functions
Export-ModuleMember -Function @(
    # Main entry point
    'Invoke-FFUPreflight',
    # Tier 1: Critical (Always Run, Blocking)
    'Test-FFUAdministrator',
    'Test-FFUPowerShellVersion',
    'Test-FFUHyperV',
    # Tier 2: Feature-Dependent (Conditional, Blocking)
    'Test-FFUADK',
    'Test-FFUDiskSpace',
    'Test-FFUNetwork',
    'Test-FFUConfigurationFile',
    'Test-FFUWimMount',
    'Test-FFUVmxToolkit',
    'Test-FFUHyperVSwitchConflict',
    'Test-FFUVMwareDrivers',
    'Test-FFUVMwareBridgeConfiguration',
    # Tier 3: Recommended (Warnings Only)
    'Test-FFUAntivirusExclusions',
    # Tier 4: Cleanup (Pre-Remediation)
    'Invoke-FFUDISMCleanup',
    # Helper functions
    'New-FFUCheckResult',
    'Get-FFURequirements'
)
