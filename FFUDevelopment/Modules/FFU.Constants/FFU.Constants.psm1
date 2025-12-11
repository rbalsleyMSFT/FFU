#Requires -Version 7.0

<#
.SYNOPSIS
Central constants module for FFUBuilder

.DESCRIPTION
Defines all hardcoded values, magic numbers, timeouts, retry counts,
and default paths used throughout the FFUBuilder project.

All values are documented with their purpose and rationale.

Path constants are now dynamically resolved based on the installation location,
allowing FFUBuilder to be installed anywhere (not just C:\FFUDevelopment).

.NOTES
Module Name: FFU.Constants
Author: FFUBuilder Contributors
Version: 1.1.0
#>

class FFUConstants {
    #region Dynamic Path Resolution

    # Private cached base path - resolved once on first access
    static hidden [string] $_resolvedBasePath = $null

    <#
    .SYNOPSIS
    Get the base FFUDevelopment path dynamically

    .DESCRIPTION
    Resolves the installation path from the module location.
    Path resolution: Modules/FFU.Constants -> Modules -> FFUDevelopment

    Supports environment variable override via FFU_BASE_PATH.

    .EXAMPLE
    $basePath = [FFUConstants]::GetBasePath()
    #>
    static [string] GetBasePath() {
        if ([string]::IsNullOrEmpty([FFUConstants]::_resolvedBasePath)) {
            # Check for environment variable override first
            $envOverride = $env:FFU_BASE_PATH
            if ($envOverride -and (Test-Path $envOverride -PathType Container)) {
                [FFUConstants]::_resolvedBasePath = $envOverride
                return [FFUConstants]::_resolvedBasePath
            }

            # Resolve from module location: Modules/FFU.Constants/FFU.Constants.psm1
            # Go up: FFU.Constants.psm1 -> FFU.Constants -> Modules -> FFUDevelopment
            $scriptPath = $PSScriptRoot
            if ($scriptPath) {
                # $PSScriptRoot is the directory containing this psm1 file
                # Go up two levels: FFU.Constants folder -> Modules folder -> FFUDevelopment
                $modulesDir = Split-Path $scriptPath -Parent
                $ffuDevPath = Split-Path $modulesDir -Parent

                if (Test-Path $ffuDevPath -PathType Container) {
                    [FFUConstants]::_resolvedBasePath = $ffuDevPath
                } else {
                    # Fallback if path doesn't exist (shouldn't happen in normal use)
                    [FFUConstants]::_resolvedBasePath = "C:\FFUDevelopment"
                }
            } else {
                # Fallback if $PSScriptRoot not available (e.g., in certain test scenarios)
                [FFUConstants]::_resolvedBasePath = "C:\FFUDevelopment"
            }
        }
        return [FFUConstants]::_resolvedBasePath
    }

    <#
    .SYNOPSIS
    Override the base path (useful for tests and non-standard installations)

    .DESCRIPTION
    Allows manual setting of the base path. This is primarily intended for:
    - Unit testing with isolated paths
    - Programmatic override when running from non-standard locations
    - Multi-instance scenarios

    .PARAMETER Path
    The path to use as the base FFUDevelopment directory

    .EXAMPLE
    [FFUConstants]::SetBasePath("D:\MyFFUDevelopment")
    #>
    static [void] SetBasePath([string]$Path) {
        [FFUConstants]::_resolvedBasePath = $Path
    }

    <#
    .SYNOPSIS
    Reset the cached base path to force re-resolution

    .DESCRIPTION
    Clears the cached path so the next call to GetBasePath() will
    re-resolve from $PSScriptRoot or environment variable.
    Useful for testing or after changing FFU_BASE_PATH.

    .EXAMPLE
    [FFUConstants]::ResetBasePath()
    #>
    static [void] ResetBasePath() {
        [FFUConstants]::_resolvedBasePath = $null
    }

    #endregion

    #region Dynamic Path Methods

    <#
    .SYNOPSIS
    Get the default working directory path

    .DESCRIPTION
    Returns the base FFUDevelopment path. This is the root directory
    for all FFU operations.

    Supports environment variable override via FFU_WORKING_DIR.

    .EXAMPLE
    $workDir = [FFUConstants]::GetDefaultWorkingDir()
    #>
    static [string] GetDefaultWorkingDir() {
        $envOverride = $env:FFU_WORKING_DIR
        if ($envOverride -and (Test-Path $envOverride -PathType Container)) {
            return $envOverride
        }
        return [FFUConstants]::GetBasePath()
    }

    <#
    .SYNOPSIS
    Get the default VM directory path

    .DESCRIPTION
    Returns the path where Hyper-V VMs are stored during builds.
    Defaults to <BasePath>\VM.

    Supports environment variable override via FFU_VM_DIR.

    .EXAMPLE
    $vmDir = [FFUConstants]::GetDefaultVMDir()
    #>
    static [string] GetDefaultVMDir() {
        $envOverride = $env:FFU_VM_DIR
        if ($envOverride -and (Test-Path (Split-Path $envOverride -Parent) -PathType Container)) {
            return $envOverride
        }
        return Join-Path ([FFUConstants]::GetBasePath()) "VM"
    }

    <#
    .SYNOPSIS
    Get the default FFU capture output directory

    .DESCRIPTION
    Returns the path where captured FFU images are saved.
    Defaults to <BasePath>\FFU.

    Supports environment variable override via FFU_CAPTURE_DIR.

    .EXAMPLE
    $captureDir = [FFUConstants]::GetDefaultCaptureDir()
    #>
    static [string] GetDefaultCaptureDir() {
        $envOverride = $env:FFU_CAPTURE_DIR
        if ($envOverride -and (Test-Path (Split-Path $envOverride -Parent) -PathType Container)) {
            return $envOverride
        }
        return Join-Path ([FFUConstants]::GetBasePath()) "FFU"
    }

    <#
    .SYNOPSIS
    Get the default drivers directory path

    .DESCRIPTION
    Returns the path where downloaded OEM drivers are cached.
    Defaults to <BasePath>\Drivers.

    Supports environment variable override via FFU_DRIVERS_DIR.

    .EXAMPLE
    $driversDir = [FFUConstants]::GetDefaultDriversDir()
    #>
    static [string] GetDefaultDriversDir() {
        $envOverride = $env:FFU_DRIVERS_DIR
        if ($envOverride) {
            # Allow creating new directories, just check parent exists
            $parent = Split-Path $envOverride -Parent
            if (-not $parent -or (Test-Path $parent -PathType Container)) {
                return $envOverride
            }
        }
        return Join-Path ([FFUConstants]::GetBasePath()) "Drivers"
    }

    <#
    .SYNOPSIS
    Get the default applications directory path

    .DESCRIPTION
    Returns the path where application installers are stored.
    Defaults to <BasePath>\Apps.

    Supports environment variable override via FFU_APPS_DIR.

    .EXAMPLE
    $appsDir = [FFUConstants]::GetDefaultAppsDir()
    #>
    static [string] GetDefaultAppsDir() {
        $envOverride = $env:FFU_APPS_DIR
        if ($envOverride) {
            $parent = Split-Path $envOverride -Parent
            if (-not $parent -or (Test-Path $parent -PathType Container)) {
                return $envOverride
            }
        }
        return Join-Path ([FFUConstants]::GetBasePath()) "Apps"
    }

    <#
    .SYNOPSIS
    Get the default Windows updates directory path

    .DESCRIPTION
    Returns the path where downloaded MSU updates are cached.
    Defaults to <BasePath>\Updates.

    Supports environment variable override via FFU_UPDATES_DIR.

    .EXAMPLE
    $updatesDir = [FFUConstants]::GetDefaultUpdatesDir()
    #>
    static [string] GetDefaultUpdatesDir() {
        $envOverride = $env:FFU_UPDATES_DIR
        if ($envOverride) {
            $parent = Split-Path $envOverride -Parent
            if (-not $parent -or (Test-Path $parent -PathType Container)) {
                return $envOverride
            }
        }
        return Join-Path ([FFUConstants]::GetBasePath()) "Updates"
    }

    #endregion

    #region Static Path Properties (for backward compatibility)
    # These are initialized by the static constructor and reference hardcoded values
    # Code should prefer the Get* methods for dynamic resolution

    # Base working directory for all FFU operations
    # DEPRECATED: Use [FFUConstants]::GetDefaultWorkingDir() instead
    static [string] $DEFAULT_WORKING_DIR = "C:\FFUDevelopment"

    # VM storage location
    # DEPRECATED: Use [FFUConstants]::GetDefaultVMDir() instead
    static [string] $DEFAULT_VM_DIR = "C:\FFUDevelopment\VM"

    # FFU capture output location
    # DEPRECATED: Use [FFUConstants]::GetDefaultCaptureDir() instead
    static [string] $DEFAULT_CAPTURE_DIR = "C:\FFUDevelopment\FFU"

    # Driver storage location
    # DEPRECATED: Use [FFUConstants]::GetDefaultDriversDir() instead
    static [string] $DEFAULT_DRIVERS_DIR = "C:\FFUDevelopment\Drivers"

    # Application installers location
    # DEPRECATED: Use [FFUConstants]::GetDefaultAppsDir() instead
    static [string] $DEFAULT_APPS_DIR = "C:\FFUDevelopment\Apps"

    # Windows Update cache location
    # DEPRECATED: Use [FFUConstants]::GetDefaultUpdatesDir() instead
    static [string] $DEFAULT_UPDATES_DIR = "C:\FFUDevelopment\Updates"

    #endregion

    #region ADK Paths (system-dependent, not project-relative)

    # Windows ADK Deployment Tools path
    # Required for DISM and image manipulation
    static [string] $ADK_DEPLOYMENT_TOOLS = "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools"

    # Windows ADK Windows PE add-on path
    # Required for WinPE boot media creation
    static [string] $ADK_WINPE_PATH = "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Windows Preinstallation Environment"

    #endregion

    #region VM Configuration Defaults

    # Default VM memory allocation (4GB)
    # Minimum required for Windows 10/11 installation and updates
    # Balance between performance and host resource availability
    static [uint64] $DEFAULT_VM_MEMORY = 4GB

    # Default VM processor count (4)
    # Balances build performance with host system availability
    # Most modern systems have 4+ logical processors
    static [int] $DEFAULT_VM_PROCESSORS = 4

    # Default VHDX disk size (50GB)
    # Sufficient for base Windows + drivers + Office + updates
    # Typical FFU size: 15-25GB after optimization
    static [uint64] $DEFAULT_VHDX_SIZE = 50GB

    # VM Generation (2 for UEFI)
    # Generation 2 required for modern Windows 10/11 UEFI boot
    # Supports Secure Boot and TPM 2.0
    static [int] $DEFAULT_VM_GENERATION = 2

    #endregion

    #region Validation Limits

    # Minimum memory for Windows installation (2GB)
    # Windows 10/11 absolute minimum per Microsoft requirements
    static [uint64] $MIN_VM_MEMORY = 2GB

    # Maximum memory allocation (128GB)
    # Prevents misconfiguration from exhausting host resources
    # Hyper-V Gen2 supports up to 12TB but 128GB is practical limit
    static [uint64] $MAX_VM_MEMORY = 128GB

    # Minimum disk size for Windows (25GB)
    # Based on Windows 11 minimum requirement (20GB) + safety margin
    # Accounts for updates and temporary files during installation
    static [uint64] $MIN_VHDX_SIZE = 25GB

    # Maximum disk size (2TB)
    # Reasonable upper limit for deployment images
    # Prevents accidental over-allocation
    static [uint64] $MAX_VHDX_SIZE = 2TB

    # Minimum processor count (1)
    # Single CPU sufficient but slow for builds
    static [int] $MIN_VM_PROCESSORS = 1

    # Maximum processor count (64)
    # Hyper-V Gen2 maximum logical processor count
    static [int] $MAX_VM_PROCESSORS = 64

    #endregion

    #region Timeouts (in seconds)

    # VM startup timeout (5 minutes)
    # Allows for UEFI initialization, PXE timeout, and Windows boot
    # Slower systems may take 3-4 minutes
    static [int] $VM_STARTUP_TIMEOUT = 300

    # VM shutdown timeout (10 minutes)
    # Allows for Windows update installation during shutdown
    # Cumulative updates can take 5-8 minutes to install on shutdown
    static [int] $VM_SHUTDOWN_TIMEOUT = 600

    # DISM mount operation timeout (5 minutes)
    # Time to mount large VHDX/WIM files (10-20GB)
    # Depends on disk I/O performance
    static [int] $DISM_MOUNT_TIMEOUT = 300

    # DISM package application timeout (30 minutes)
    # Large cumulative updates (500MB-1GB) can take 15-25 minutes
    # Includes extraction, application, and cleanup
    static [int] $DISM_PACKAGE_TIMEOUT = 1800

    # DISM image capture timeout (60 minutes)
    # FFU capture of large images (20-30GB) with compression
    # Depends on CPU and disk I/O performance
    static [int] $DISM_CAPTURE_TIMEOUT = 3600

    # Network download timeout (20 minutes)
    # Large driver packages (1-2GB) and cumulative updates (1GB+)
    # Accounts for slow corporate networks and throttling
    static [int] $NETWORK_DOWNLOAD_TIMEOUT = 1200

    #endregion

    #region Wait/Sleep Times (in seconds)

    # DISM service stabilization wait (10 seconds)
    # Ensures TrustedInstaller service is fully started
    # Service may report "Running" but not yet accept connections
    static [int] $DISM_SERVICE_WAIT = 10

    # VM state change polling interval (5 seconds)
    # Check VM status during boot/shutdown operations
    # Balances responsiveness with host CPU usage
    static [int] $VM_STATE_POLL_INTERVAL = 5

    # DISM operation pre-flight cleanup wait (3 seconds)
    # Allow system to stabilize after cleanup operations
    # Ensures mount points fully released before next operation
    static [int] $DISM_CLEANUP_WAIT = 3

    # Mount point validation wait (2 seconds)
    # Ensure mount points are fully registered in Windows
    # Required after DISM mount operations
    static [int] $MOUNT_VALIDATION_WAIT = 2

    # Driver extraction wait (5 seconds)
    # Allow driver installer to complete extraction
    # Dell/HP/Lenovo extractors may background their operations
    static [int] $DRIVER_EXTRACTION_WAIT = 5

    # Service startup wait (1 second)
    # Wait for Windows services to initialize
    # Minimal delay for service state propagation
    static [int] $SERVICE_STARTUP_WAIT = 1

    # Update catalog search wait (5 seconds)
    # Rate limiting for Microsoft Update Catalog requests
    # Prevents HTTP 429 throttling errors
    static [int] $UPDATE_CATALOG_WAIT = 5

    # Process poll interval (350 milliseconds)
    # Background job status checking in UI
    # Balances UI responsiveness with CPU usage
    static [int] $PROCESS_POLL_INTERVAL_MS = 350

    # Service status check interval (500 milliseconds)
    # Windows service state validation during initialization
    # Used for TrustedInstaller and BITS service checks
    static [int] $SERVICE_CHECK_INTERVAL_MS = 500

    #endregion

    #region Retry Configuration

    # Maximum retries for DISM service initialization (3)
    # DISM/TrustedInstaller service can be slow to start
    # Especially after Windows updates or system boot
    static [int] $MAX_DISM_SERVICE_RETRIES = 3

    # Maximum retries for copype command (1)
    # WIM mount failures require cleanup and retry
    # More than 1 retry indicates deeper system issues
    static [int] $MAX_COPYPE_RETRIES = 1

    # Maximum retries for Windows Update package application (2)
    # Transient BITS/DISM failures during package extraction
    # Retry helps with temporary file locks or disk I/O issues
    static [int] $MAX_PACKAGE_RETRIES = 2

    # Maximum retries for network downloads (3)
    # Network instability, throttling, and transient failures
    # Standard retry count for network operations
    static [int] $MAX_DOWNLOAD_RETRIES = 3

    # Retry delay (30 seconds)
    # Wait between retry attempts to allow system recovery
    # Allows services to stabilize, locks to release, I/O to complete
    static [int] $RETRY_DELAY = 30

    #endregion

    #region Disk Space Requirements

    # Minimum free disk space for copype (10GB)
    # WinPE creation requires significant temporary space
    # Includes: boot.wim (300MB), temp files (2GB), safety margin
    static [uint64] $MIN_FREE_SPACE_COPYPE = 10GB

    # MSU package extraction multiplier (3x)
    # expand.exe requires 3x package size for extraction
    # 1GB MSU requires 3GB free space during extraction
    static [int] $MSU_EXTRACTION_MULTIPLIER = 3

    # MSU extraction safety margin (5GB)
    # Additional space for temporary files during DISM operations
    # Accounts for DISM scratch space and log files
    static [uint64] $MSU_SAFETY_MARGIN = 5GB

    #endregion

    #region String Formatting

    # Maximum username length (20 characters)
    # Windows local account username limit per Microsoft
    # Domain accounts support longer names but local accounts limited
    static [int] $MAX_USERNAME_LENGTH = 20

    # Maximum share name length (80 characters)
    # Windows SMB share name limit per SMB protocol
    # Practical limit is lower for compatibility
    static [int] $MAX_SHARENAME_LENGTH = 80

    # Product key format pattern
    # Standard Windows product key format: XXXXX-XXXXX-XXXXX-XXXXX-XXXXX
    # 5 groups of 5 alphanumeric characters separated by hyphens
    static [string] $PRODUCT_KEY_PATTERN = '^[A-Z0-9]{5}-[A-Z0-9]{5}-[A-Z0-9]{5}-[A-Z0-9]{5}-[A-Z0-9]{5}$'

    # IPv4 address format pattern
    # Standard dotted-decimal notation (0.0.0.0 to 255.255.255.255)
    # Used for VMHostIPAddress validation
    static [string] $IPV4_PATTERN = '^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$'

    # Invalid Windows share name characters
    # Characters not allowed in SMB share names
    static [string] $INVALID_SHARENAME_CHARS = '[\\/:*?"<>|]'

    # Invalid Windows username characters
    # Characters not allowed in local account usernames
    static [string] $INVALID_USERNAME_CHARS = '[\\/:*?"<>|@]'

    #endregion

    #region Feature Flags

    # Enable verbose DISM logging
    # Detailed DISM operation logs in Windows\Logs\DISM\dism.log
    # Useful for troubleshooting but increases log file size
    static [bool] $ENABLE_DISM_VERBOSE = $true

    # Enable automatic DISM cleanup
    # Run Dism.exe /Cleanup-Mountpoints before operations
    # Prevents stale mount point failures
    static [bool] $ENABLE_AUTO_CLEANUP = $true

    # Enable pre-flight validation
    # Comprehensive validation before starting builds
    # Catches 90%+ of configuration issues early
    static [bool] $ENABLE_PREFLIGHT_CHECKS = $true

    #endregion

    #region Legacy Helper Methods (backward compatibility)

    <#
    .SYNOPSIS
    Get working directory with environment variable override support

    .DESCRIPTION
    Returns the working directory, checking environment variable first
    Allows users to override default path without code changes

    DEPRECATED: Use GetDefaultWorkingDir() instead

    .EXAMPLE
    $workDir = [FFUConstants]::GetWorkingDirectory()
    #>
    static [string] GetWorkingDirectory() {
        return [FFUConstants]::GetDefaultWorkingDir()
    }

    <#
    .SYNOPSIS
    Get VM directory with environment variable override support

    DEPRECATED: Use GetDefaultVMDir() instead

    .EXAMPLE
    $vmDir = [FFUConstants]::GetVMDirectory()
    #>
    static [string] GetVMDirectory() {
        return [FFUConstants]::GetDefaultVMDir()
    }

    <#
    .SYNOPSIS
    Get capture directory with environment variable override support

    DEPRECATED: Use GetDefaultCaptureDir() instead

    .EXAMPLE
    $captureDir = [FFUConstants]::GetCaptureDirectory()
    #>
    static [string] GetCaptureDirectory() {
        return [FFUConstants]::GetDefaultCaptureDir()
    }

    #endregion
}

# Classes are automatically exported in PowerShell 5.1+
# No explicit export needed for classes defined in module scope
