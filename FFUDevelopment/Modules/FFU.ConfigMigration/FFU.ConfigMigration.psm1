#Requires -Version 5.1
<#
.SYNOPSIS
    FFU.ConfigMigration - Configuration schema versioning and migration for FFU Builder.

.DESCRIPTION
    Provides automatic detection of older configuration files and migration to the
    current schema format. Key features:

    - Schema version tracking (configSchemaVersion field)
    - Pre-versioning config detection (no version = 0.0)
    - Deprecated property transformation (7 properties)
    - Backup creation before migration
    - Forward compatibility (unknown properties preserved)
    - Cross-version compatible (PS5.1 and PS7+)

.NOTES
    Module: FFU.ConfigMigration
    Version: 1.0.0
    Author: FFUBuilder Team
    Requires: PowerShell 5.1 or later
#>

#region Version Constant

# Single source of truth for current schema version
$script:CurrentConfigSchemaVersion = "1.1"

#endregion Version Constant

#region Helper Functions

function ConvertTo-HashtableRecursive {
    <#
    .SYNOPSIS
    Recursively converts PSCustomObject to hashtable (for PS5.1 compatibility).

    .DESCRIPTION
    PowerShell 5.1's ConvertFrom-Json doesn't support -AsHashtable, so this
    function manually converts the resulting PSCustomObject to hashtables.
    This is re-exported from FFU.Checkpoint for convenience.

    .PARAMETER InputObject
    The object to convert.

    .OUTPUTS
    System.Collections.Hashtable or the original value for primitives.

    .EXAMPLE
    $json = Get-Content config.json -Raw | ConvertFrom-Json
    $hashtable = ConvertTo-HashtableRecursive -InputObject $json
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

function Get-FFUConfigSchemaVersion {
    <#
    .SYNOPSIS
    Returns the current configuration schema version.

    .DESCRIPTION
    Returns the current schema version as a string. This is the single source
    of truth for the schema version used by Test-FFUConfigVersion and
    Invoke-FFUConfigMigration.

    .OUTPUTS
    System.String - The current schema version (e.g., "1.0")

    .EXAMPLE
    $version = Get-FFUConfigSchemaVersion
    Write-Host "Current schema version: $version"
    # Output: Current schema version: 1.0
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    return $script:CurrentConfigSchemaVersion
}

function Test-FFUConfigVersion {
    <#
    .SYNOPSIS
    Checks if a configuration file needs migration.

    .DESCRIPTION
    Compares the configuration's schema version against the current schema version
    to determine if migration is needed. Configs without a configSchemaVersion
    field are treated as version "0.0" (pre-versioning).

    .PARAMETER ConfigPath
    Path to a JSON configuration file to check.

    .PARAMETER Config
    Hashtable containing configuration data to check.

    .PARAMETER CurrentSchemaVersion
    Optional - the target schema version to compare against. Defaults to
    Get-FFUConfigSchemaVersion.

    .OUTPUTS
    PSCustomObject with properties:
    - ConfigVersion: The version found in the config (or "0.0" if missing)
    - CurrentSchemaVersion: The target schema version
    - NeedsMigration: Boolean indicating if migration is required
    - VersionDifference: Integer comparison result (-1, 0, 1)

    .EXAMPLE
    $result = Test-FFUConfigVersion -ConfigPath "C:\FFU\config.json"
    if ($result.NeedsMigration) {
        Write-Host "Config needs migration from $($result.ConfigVersion)"
    }

    .EXAMPLE
    $config = @{ FFUDevelopmentPath = "C:\FFU"; Verbose = $true }
    $result = Test-FFUConfigVersion -Config $config
    # Returns NeedsMigration=$true because no configSchemaVersion
    #>
    [CmdletBinding(DefaultParameterSetName = 'Object')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Path')]
        [ValidateScript({ Test-Path $_ -PathType Leaf })]
        [string]$ConfigPath,

        [Parameter(Mandatory, ParameterSetName = 'Object')]
        [hashtable]$Config,

        [Parameter()]
        [string]$CurrentSchemaVersion
    )

    # Use module version if not specified
    if ([string]::IsNullOrEmpty($CurrentSchemaVersion)) {
        $CurrentSchemaVersion = Get-FFUConfigSchemaVersion
    }

    # Load config from path if needed
    if ($PSCmdlet.ParameterSetName -eq 'Path') {
        $content = Get-Content -Path $ConfigPath -Raw -ErrorAction Stop
        $configData = $content | ConvertFrom-Json -ErrorAction Stop

        # Convert to hashtable for consistent handling
        if ($PSVersionTable.PSVersion.Major -ge 7) {
            $Config = $content | ConvertFrom-Json -AsHashtable -ErrorAction Stop
        }
        else {
            $Config = ConvertTo-HashtableRecursive -InputObject $configData
        }
    }

    # Get config version (0.0 if missing = pre-versioning)
    $configVersion = $Config['configSchemaVersion']
    if ([string]::IsNullOrEmpty($configVersion)) {
        $configVersion = "0.0"
    }

    # Parse versions for proper comparison
    try {
        $currentVer = [System.Version]::Parse($CurrentSchemaVersion)
        $configVer = [System.Version]::Parse($configVersion)
    }
    catch {
        Write-Error "Invalid version format: CurrentSchemaVersion='$CurrentSchemaVersion', ConfigVersion='$configVersion'"
        return $null
    }

    # Compare versions
    $versionDiff = $currentVer.CompareTo($configVer)
    $needsMigration = $configVer -lt $currentVer

    [PSCustomObject]@{
        ConfigVersion        = $configVersion
        CurrentSchemaVersion = $CurrentSchemaVersion
        NeedsMigration       = $needsMigration
        VersionDifference    = $versionDiff
    }
}

function Invoke-FFUConfigMigration {
    <#
    .SYNOPSIS
    Migrates a configuration to the current schema version.

    .DESCRIPTION
    Transforms deprecated properties in a configuration hashtable to their
    modern equivalents. The function:

    1. Removes properties that are now computed dynamically (AppsPath, OfficePath)
    2. Removes properties replaced by CLI switches (Verbose)
    3. Removes properties that are automatic (Threads)
    4. Transforms renamed properties (InstallWingetApps -> InstallApps)
    5. Removes properties requiring manual setup with warnings (DownloadDrivers, CopyOfficeConfigXML)
    6. Sets configSchemaVersion to the target version
    7. Preserves all unknown properties for forward compatibility

    .PARAMETER Config
    Hashtable containing configuration data to migrate.

    .PARAMETER TargetVersion
    Optional - the target schema version. Defaults to Get-FFUConfigSchemaVersion.

    .PARAMETER CreateBackup
    Switch to create a backup of the original config file before migration.

    .PARAMETER ConfigPath
    Path to the configuration file. Required if -CreateBackup is specified.

    .OUTPUTS
    Hashtable with properties:
    - Config: The migrated configuration hashtable
    - Changes: Array of change descriptions
    - FromVersion: Original version
    - ToVersion: Target version
    - BackupPath: Path to backup file (if created)

    .EXAMPLE
    $config = @{
        FFUDevelopmentPath = "C:\FFU"
        AppsPath = "C:\FFU\Apps"
        Verbose = $true
        InstallWingetApps = $true
    }
    $result = Invoke-FFUConfigMigration -Config $config
    Write-Host "Migrated from $($result.FromVersion) to $($result.ToVersion)"
    $result.Changes | ForEach-Object { Write-Host "  - $_" }

    .EXAMPLE
    # With backup creation
    $result = Invoke-FFUConfigMigration -Config $config -CreateBackup -ConfigPath "C:\FFU\config.json"
    Write-Host "Backup created at: $($result.BackupPath)"
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config,

        [Parameter()]
        [string]$TargetVersion,

        [Parameter()]
        [switch]$CreateBackup,

        [Parameter()]
        [string]$ConfigPath
    )

    # Use module version if not specified
    if ([string]::IsNullOrEmpty($TargetVersion)) {
        $TargetVersion = Get-FFUConfigSchemaVersion
    }

    # Determine current version
    $currentVersion = $Config['configSchemaVersion']
    if ([string]::IsNullOrEmpty($currentVersion)) {
        $currentVersion = "0.0"  # Pre-versioning configs
    }

    # Initialize result
    $result = @{
        Config      = $null
        Changes     = @()
        FromVersion = $currentVersion
        ToVersion   = $TargetVersion
        BackupPath  = $null
    }

    # Compare versions
    try {
        $current = [System.Version]::Parse($currentVersion)
        $target = [System.Version]::Parse($TargetVersion)
    }
    catch {
        Write-Error "Invalid version format: CurrentVersion='$currentVersion', TargetVersion='$TargetVersion'"
        return $result
    }

    # If already at or beyond target version, return unchanged
    if ($current -ge $target) {
        Write-Verbose "Config already at version $currentVersion (target: $TargetVersion) - no migration needed"
        $result.Config = $Config
        return $result
    }

    # Log migration start
    if (Get-Command -Name WriteLog -ErrorAction SilentlyContinue) {
        WriteLog "Migrating config from version $currentVersion to $TargetVersion"
    }
    else {
        Write-Verbose "Migrating config from version $currentVersion to $TargetVersion"
    }

    # Create backup if requested
    if ($CreateBackup -and $ConfigPath) {
        if (Test-Path -Path $ConfigPath) {
            $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
            $backupPath = "$ConfigPath.backup-$timestamp"
            Copy-Item -Path $ConfigPath -Destination $backupPath -Force
            $result.BackupPath = $backupPath

            if (Get-Command -Name WriteLog -ErrorAction SilentlyContinue) {
                WriteLog "Created backup at $backupPath"
            }
            else {
                Write-Verbose "Created backup at $backupPath"
            }
        }
    }

    # Clone config to preserve unknown properties (forward compatibility)
    $migrated = @{}
    foreach ($key in $Config.Keys) {
        $migrated[$key] = $Config[$key]
    }

    $changes = @()

    #region Migration: Remove deprecated path properties (computed dynamically)
    foreach ($prop in @('AppsPath', 'OfficePath')) {
        if ($migrated.ContainsKey($prop)) {
            $migrated.Remove($prop)
            $changes += "Removed deprecated property '$prop' (now computed from FFUDevelopmentPath)"
        }
    }
    #endregion

    #region Migration: Verbose -> removed (use CLI switch)
    if ($migrated.ContainsKey('Verbose')) {
        $migrated.Remove('Verbose')
        $changes += "Removed deprecated property 'Verbose' (use -Verbose CLI switch instead)"
    }
    #endregion

    #region Migration: Threads -> removed (automatic)
    if ($migrated.ContainsKey('Threads')) {
        $migrated.Remove('Threads')
        $changes += "Removed deprecated property 'Threads' (parallel processing now automatic)"
    }
    #endregion

    #region Migration: InstallWingetApps -> InstallApps
    if ($migrated.ContainsKey('InstallWingetApps')) {
        if ($migrated['InstallWingetApps'] -eq $true) {
            # Set InstallApps if not already set
            if (-not $migrated.ContainsKey('InstallApps') -or $migrated['InstallApps'] -ne $true) {
                $migrated['InstallApps'] = $true
                $changes += "Migrated 'InstallWingetApps=true' to 'InstallApps=true'"
            }
            else {
                $changes += "Removed 'InstallWingetApps' (InstallApps already set)"
            }
        }
        else {
            $changes += "Removed deprecated property 'InstallWingetApps' (was false)"
        }
        $migrated.Remove('InstallWingetApps')
    }
    #endregion

    #region Migration: DownloadDrivers -> warning (requires Make/Model)
    if ($migrated.ContainsKey('DownloadDrivers')) {
        if ($migrated['DownloadDrivers'] -eq $true) {
            # Check if Make is set
            if (-not $migrated.ContainsKey('Make') -or [string]::IsNullOrEmpty($migrated['Make'])) {
                $changes += "WARNING: 'DownloadDrivers' was true but 'Make' not specified - set Make and Model manually to enable driver downloads"
            }
            else {
                $changes += "Removed deprecated property 'DownloadDrivers' (Make/Model already configured)"
            }
        }
        else {
            $changes += "Removed deprecated property 'DownloadDrivers' (was false)"
        }
        $migrated.Remove('DownloadDrivers')
    }
    #endregion

    #region Migration: CopyOfficeConfigXML -> warning (requires OfficeConfigXMLFile)
    if ($migrated.ContainsKey('CopyOfficeConfigXML')) {
        if ($migrated['CopyOfficeConfigXML'] -eq $true) {
            # Check if OfficeConfigXMLFile is set
            if (-not $migrated.ContainsKey('OfficeConfigXMLFile') -or [string]::IsNullOrEmpty($migrated['OfficeConfigXMLFile'])) {
                $changes += "WARNING: 'CopyOfficeConfigXML' was true but 'OfficeConfigXMLFile' not specified - set OfficeConfigXMLFile path manually"
            }
            else {
                $changes += "Removed deprecated property 'CopyOfficeConfigXML' (OfficeConfigXMLFile already configured)"
            }
        }
        else {
            $changes += "Removed deprecated property 'CopyOfficeConfigXML' (was false)"
        }
        $migrated.Remove('CopyOfficeConfigXML')
    }
    #endregion

    #region Migration: Add IncludePreviewUpdates default (v1.1)
    if (-not $migrated.ContainsKey('IncludePreviewUpdates')) {
        $migrated['IncludePreviewUpdates'] = $false
        $changes += "Added default 'IncludePreviewUpdates=false' (preview updates excluded by default)"
    }
    #endregion

    # Set new version
    $migrated['configSchemaVersion'] = $TargetVersion

    # Log changes
    foreach ($change in $changes) {
        if (Get-Command -Name WriteLog -ErrorAction SilentlyContinue) {
            WriteLog "Migration: $change"
        }
        else {
            Write-Verbose "Migration: $change"
        }
    }

    $result.Config = $migrated
    $result.Changes = $changes

    return $result
}

#endregion Core Functions

#region Module Exports

Export-ModuleMember -Function @(
    'Get-FFUConfigSchemaVersion'
    'Test-FFUConfigVersion'
    'Invoke-FFUConfigMigration'
    'ConvertTo-HashtableRecursive'
)

#endregion Module Exports
