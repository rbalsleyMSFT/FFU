#Requires -Version 5.1
<#
.SYNOPSIS
    FFU.Checkpoint - Build checkpoint and resume functionality for FFU Builder.

.DESCRIPTION
    Provides checkpoint persistence for FFU builds, enabling save/resume capability
    at phase boundaries. Checkpoints are stored as JSON files with atomic writes
    to prevent corruption.

    Key Features:
    - Atomic checkpoint writes (temp file + rename pattern)
    - Cross-version compatible (PS5.1 and PS7+)
    - Phase-aware progress tracking
    - Artifact path validation
    - No external module dependencies (must work early in build)

.NOTES
    Module: FFU.Checkpoint
    Version: 1.0.0
    Author: FFUBuilder Team
    Requires: PowerShell 5.1 or later
#>

#region Type Definitions

# Build phase enumeration - defines the order of build phases
enum FFUBuildPhase {
    NotStarted = 0
    PreflightValidation = 1
    DriverDownload = 2
    UpdatesDownload = 3
    AppsPreparation = 4
    VHDXCreation = 5
    WindowsUpdates = 6
    VMSetup = 7
    VMStart = 8
    AppInstallation = 9
    VMShutdown = 10
    FFUCapture = 11
    DeploymentMedia = 12
    USBCreation = 13
    Cleanup = 14
    Completed = 15
}

#endregion Type Definitions

#region Helper Functions

function Get-FFUBuildPhasePercent {
    <#
    .SYNOPSIS
    Returns the approximate completion percentage for a build phase.

    .DESCRIPTION
    Maps each build phase to an estimated percentage of total build completion.
    This provides progress feedback to users during long-running builds.

    .PARAMETER Phase
    The build phase to get the percentage for.

    .OUTPUTS
    System.Int32 - Percentage (0-100)

    .EXAMPLE
    Get-FFUBuildPhasePercent -Phase VHDXCreation
    # Returns: 35
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]
        [FFUBuildPhase]$Phase
    )

    # Phase percentages based on typical build timing
    $phasePercents = @{
        [FFUBuildPhase]::NotStarted         = 0
        [FFUBuildPhase]::PreflightValidation = 5
        [FFUBuildPhase]::DriverDownload     = 15
        [FFUBuildPhase]::UpdatesDownload    = 25
        [FFUBuildPhase]::AppsPreparation    = 30
        [FFUBuildPhase]::VHDXCreation       = 35
        [FFUBuildPhase]::WindowsUpdates     = 50
        [FFUBuildPhase]::VMSetup            = 55
        [FFUBuildPhase]::VMStart            = 60
        [FFUBuildPhase]::AppInstallation    = 75
        [FFUBuildPhase]::VMShutdown         = 80
        [FFUBuildPhase]::FFUCapture         = 90
        [FFUBuildPhase]::DeploymentMedia    = 95
        [FFUBuildPhase]::USBCreation        = 98
        [FFUBuildPhase]::Cleanup            = 99
        [FFUBuildPhase]::Completed          = 100
    }

    if ($phasePercents.ContainsKey($Phase)) {
        return $phasePercents[$Phase]
    }

    return 0
}

function ConvertTo-HashtableRecursive {
    <#
    .SYNOPSIS
    Recursively converts PSCustomObject to hashtable (for PS5.1 compatibility).

    .DESCRIPTION
    PowerShell 5.1's ConvertFrom-Json doesn't support -AsHashtable, so this
    function manually converts the resulting PSCustomObject to hashtables.

    .PARAMETER InputObject
    The object to convert.

    .OUTPUTS
    System.Collections.Hashtable or the original value for primitives.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        $InputObject
    )

    if ($null -eq $InputObject) {
        return $null
    }

    if ($InputObject -is [System.Collections.IDictionary]) {
        # Already a hashtable, but convert nested objects
        $result = @{}
        foreach ($key in $InputObject.Keys) {
            $result[$key] = ConvertTo-HashtableRecursive -InputObject $InputObject[$key]
        }
        return $result
    }

    if ($InputObject -is [PSCustomObject]) {
        $result = @{}
        foreach ($property in $InputObject.PSObject.Properties) {
            $result[$property.Name] = ConvertTo-HashtableRecursive -InputObject $property.Value
        }
        return $result
    }

    if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
        $result = @()
        foreach ($item in $InputObject) {
            $result += ConvertTo-HashtableRecursive -InputObject $item
        }
        return $result
    }

    # Primitive type - return as-is
    return $InputObject
}

#endregion Helper Functions

#region Core Functions

function Save-FFUBuildCheckpoint {
    <#
    .SYNOPSIS
    Saves the current build state to a checkpoint file.

    .DESCRIPTION
    Creates a JSON checkpoint file at the specified FFUDevelopmentPath that
    captures the current build state. Uses atomic write pattern (temp file +
    rename) to prevent corruption.

    IMPORTANT: Do NOT include sensitive data (passwords, credentials) in the
    Configuration, Artifacts, or Paths parameters.

    .PARAMETER CompletedPhase
    The build phase that has just completed.

    .PARAMETER Configuration
    Hashtable containing build configuration (VMName, WindowsRelease, etc.).
    Do NOT include passwords or credentials.

    .PARAMETER Artifacts
    Hashtable tracking which artifacts have been created (vhdxCreated, etc.).

    .PARAMETER Paths
    Hashtable containing paths to build artifacts (VHDXPath, VMPath, etc.).

    .PARAMETER FFUDevelopmentPath
    The root FFU development path where checkpoint will be stored.

    .EXAMPLE
    Save-FFUBuildCheckpoint -CompletedPhase VHDXCreation `
        -Configuration @{ VMName = "FFU_Build"; WindowsRelease = "24H2" } `
        -Artifacts @{ vhdxCreated = $true; driversDownloaded = $true } `
        -Paths @{ VHDXPath = "C:\FFU\VM\FFU_Build.vhdx" } `
        -FFUDevelopmentPath "C:\FFUDevelopment"

    .OUTPUTS
    None
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [FFUBuildPhase]$CompletedPhase,

        [Parameter(Mandatory)]
        [hashtable]$Configuration,

        [Parameter(Mandatory)]
        [hashtable]$Artifacts,

        [Parameter(Mandatory)]
        [hashtable]$Paths,

        [Parameter(Mandatory)]
        [string]$FFUDevelopmentPath
    )

    $checkpointDir = Join-Path -Path $FFUDevelopmentPath -ChildPath ".ffubuilder"
    $checkpointPath = Join-Path -Path $checkpointDir -ChildPath "checkpoint.json"
    $tempPath = "$checkpointPath.tmp"

    # Create directory if needed
    if (-not (Test-Path -Path $checkpointDir)) {
        New-Item -Path $checkpointDir -ItemType Directory -Force | Out-Null
    }

    # Build checkpoint object
    $checkpoint = [PSCustomObject]@{
        version            = "1.0"
        buildId            = $Configuration.VMName
        timestamp          = (Get-Date).ToUniversalTime().ToString("o")
        lastCompletedPhase = $CompletedPhase.ToString()
        percentComplete    = Get-FFUBuildPhasePercent -Phase $CompletedPhase
        configuration      = $Configuration
        artifacts          = $Artifacts
        paths              = $Paths
    }

    # Atomic write: temp file then rename
    $checkpoint | ConvertTo-Json -Depth 10 | Set-Content -Path $tempPath -Encoding UTF8 -Force
    Move-Item -Path $tempPath -Destination $checkpointPath -Force

    # Log if WriteLog is available
    if (Get-Command -Name WriteLog -ErrorAction SilentlyContinue) {
        WriteLog "Checkpoint saved: Phase $CompletedPhase ($($checkpoint.percentComplete)%)"
    }
    else {
        Write-Verbose "Checkpoint saved: Phase $CompletedPhase ($($checkpoint.percentComplete)%)"
    }
}

function Get-FFUBuildCheckpoint {
    <#
    .SYNOPSIS
    Loads a build checkpoint from disk.

    .DESCRIPTION
    Reads the checkpoint JSON file and returns it as a hashtable.
    Returns $null if no checkpoint exists or if the checkpoint version
    doesn't match "1.0".

    .PARAMETER FFUDevelopmentPath
    The root FFU development path where checkpoint is stored.

    .OUTPUTS
    System.Collections.Hashtable or $null

    .EXAMPLE
    $checkpoint = Get-FFUBuildCheckpoint -FFUDevelopmentPath "C:\FFUDevelopment"
    if ($checkpoint) {
        Write-Host "Found checkpoint at phase: $($checkpoint.lastCompletedPhase)"
    }
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$FFUDevelopmentPath
    )

    $checkpointPath = Join-Path -Path $FFUDevelopmentPath -ChildPath ".ffubuilder\checkpoint.json"

    if (-not (Test-Path -Path $checkpointPath)) {
        Write-Verbose "No checkpoint file found at: $checkpointPath"
        return $null
    }

    try {
        $json = Get-Content -Path $checkpointPath -Raw -ErrorAction Stop

        # Handle PS5.1 vs PS7+ difference for -AsHashtable
        if ($PSVersionTable.PSVersion.Major -ge 7) {
            $checkpoint = $json | ConvertFrom-Json -AsHashtable -ErrorAction Stop
        }
        else {
            # PS5.1: ConvertFrom-Json returns PSCustomObject, convert manually
            $psObject = $json | ConvertFrom-Json -ErrorAction Stop
            $checkpoint = ConvertTo-HashtableRecursive -InputObject $psObject
        }

        # Validate version
        if ($checkpoint.version -ne "1.0") {
            Write-Verbose "Checkpoint version mismatch: expected '1.0', got '$($checkpoint.version)'"
            return $null
        }

        return $checkpoint
    }
    catch {
        Write-Verbose "Failed to load checkpoint: $($_.Exception.Message)"
        return $null
    }
}

function Remove-FFUBuildCheckpoint {
    <#
    .SYNOPSIS
    Removes the checkpoint file.

    .DESCRIPTION
    Deletes the checkpoint JSON file if it exists. Safe to call even if
    no checkpoint file exists.

    .PARAMETER FFUDevelopmentPath
    The root FFU development path where checkpoint is stored.

    .OUTPUTS
    None

    .EXAMPLE
    # Clean up after successful build
    Remove-FFUBuildCheckpoint -FFUDevelopmentPath "C:\FFUDevelopment"
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [string]$FFUDevelopmentPath
    )

    $checkpointPath = Join-Path -Path $FFUDevelopmentPath -ChildPath ".ffubuilder\checkpoint.json"

    if (Test-Path -Path $checkpointPath) {
        Remove-Item -Path $checkpointPath -Force -ErrorAction SilentlyContinue
        Write-Verbose "Checkpoint file removed: $checkpointPath"
    }
    else {
        Write-Verbose "No checkpoint file to remove"
    }
}

function Test-FFUBuildCheckpoint {
    <#
    .SYNOPSIS
    Validates a checkpoint's integrity and artifact existence.

    .DESCRIPTION
    Checks that a checkpoint:
    1. Has the correct version ("1.0")
    2. Contains all required fields
    3. Has valid artifact paths (for artifacts marked as created)

    .PARAMETER FFUDevelopmentPath
    The root FFU development path where checkpoint is stored.

    .PARAMETER Checkpoint
    Optional - an already-loaded checkpoint hashtable. If not provided,
    the checkpoint will be loaded from disk.

    .OUTPUTS
    System.Boolean - True if checkpoint is valid, False otherwise.

    .EXAMPLE
    if (Test-FFUBuildCheckpoint -FFUDevelopmentPath "C:\FFUDevelopment") {
        Write-Host "Checkpoint is valid and resumable"
    }

    .EXAMPLE
    $checkpoint = Get-FFUBuildCheckpoint -FFUDevelopmentPath "C:\FFUDevelopment"
    if (Test-FFUBuildCheckpoint -Checkpoint $checkpoint) {
        # Resume from checkpoint
    }
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter()]
        [string]$FFUDevelopmentPath,

        [Parameter()]
        [hashtable]$Checkpoint
    )

    # Load checkpoint if not provided
    if ($null -eq $Checkpoint) {
        if ([string]::IsNullOrWhiteSpace($FFUDevelopmentPath)) {
            Write-Verbose "Test-FFUBuildCheckpoint: Either FFUDevelopmentPath or Checkpoint must be provided"
            return $false
        }
        $Checkpoint = Get-FFUBuildCheckpoint -FFUDevelopmentPath $FFUDevelopmentPath
    }

    if ($null -eq $Checkpoint) {
        Write-Verbose "Test-FFUBuildCheckpoint: No checkpoint found"
        return $false
    }

    # Check version
    if ($Checkpoint.version -ne "1.0") {
        Write-Verbose "Test-FFUBuildCheckpoint: Version mismatch - expected '1.0', got '$($Checkpoint.version)'"
        return $false
    }

    # Check required fields
    $requiredFields = @('buildId', 'timestamp', 'lastCompletedPhase', 'configuration', 'artifacts', 'paths')
    foreach ($field in $requiredFields) {
        if (-not $Checkpoint.ContainsKey($field)) {
            Write-Verbose "Test-FFUBuildCheckpoint: Missing required field '$field'"
            return $false
        }
    }

    # Validate artifact paths - for artifacts marked as $true, check if corresponding path exists
    $artifacts = $Checkpoint.artifacts
    $paths = $Checkpoint.paths

    # Map of artifact flags to path keys
    $artifactPathMapping = @{
        'vhdxCreated'        = 'VHDXPath'
        'driversDownloaded'  = 'DriversFolder'
        'appsIsoCreated'     = 'AppsISO'
        'captureIsoCreated'  = 'CaptureISO'
        'ffuCaptured'        = 'FFUPath'
    }

    foreach ($artifactKey in $artifactPathMapping.Keys) {
        if ($artifacts.ContainsKey($artifactKey) -and $artifacts[$artifactKey] -eq $true) {
            $pathKey = $artifactPathMapping[$artifactKey]
            if ($paths.ContainsKey($pathKey)) {
                $artifactPath = $paths[$pathKey]
                if (-not [string]::IsNullOrWhiteSpace($artifactPath) -and -not (Test-Path -Path $artifactPath)) {
                    Write-Verbose "Test-FFUBuildCheckpoint: Artifact '$artifactKey' marked complete but path not found: $artifactPath"
                    return $false
                }
            }
        }
    }

    Write-Verbose "Test-FFUBuildCheckpoint: Checkpoint is valid"
    return $true
}

#endregion Core Functions

#region Module Exports

Export-ModuleMember -Function @(
    'Save-FFUBuildCheckpoint'
    'Get-FFUBuildCheckpoint'
    'Remove-FFUBuildCheckpoint'
    'Test-FFUBuildCheckpoint'
    'Get-FFUBuildPhasePercent'
)

#endregion Module Exports
