<#
.SYNOPSIS
    FFU Builder Core Utilities Module

.DESCRIPTION
    Common utility functions for configuration management, logging, session tracking,
    and helper operations used across all FFU Builder modules.

.NOTES
    Module: FFU.Core
    Version: 1.0.0
    Dependencies: None (foundation module)
#>

#Requires -Version 7.0

# Import constants module
using module ..\FFU.Constants\FFU.Constants.psm1

function Get-Parameters {
    [CmdletBinding()]
    param (
        [Parameter()]
        $ParamNames
    )
    # Define unwanted parameters
    $excludedParams = 'Debug', 'ErrorAction', 'ErrorVariable', 'InformationAction', 'InformationVariable', 'OutBuffer', 'OutVariable', 'PipelineVariable', 'Verbose', 'WarningAction', 'WarningVariable', 'ProgressAction'

    # Filter out the unwanted parameters
    $filteredParamNames = $paramNames | Where-Object { $excludedParams -notcontains $_ }
    $filteredParamNames
}

function Write-VariableValues {
    <#
    .SYNOPSIS
    Logs all script-scope variable values for diagnostic purposes

    .DESCRIPTION
    Enumerates all script-scope variables (excluding system variables) and writes
    their names and values to the log. Used for troubleshooting build issues by
    capturing complete configuration state.

    .PARAMETER version
    Script version string to log

    .EXAMPLE
    Write-VariableValues -version "2.0.1"

    .OUTPUTS
    None - Writes variable information to log via WriteLog

    .NOTES
    Renamed from LogVariableValues to Write-VariableValues in v1.0.11 for
    PowerShell approved verb compliance. Alias 'LogVariableValues' is available
    for backward compatibility but is deprecated.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$version
    )
    $excludedVariables = @(
        'PSBoundParameters',
        'PSScriptRoot',
        'PSCommandPath',
        'MyInvocation',
        '?',
        'ConsoleFileName',
        'ExecutionContext',
        'false',
        'HOME',
        'Host',
        'hyperVFeature',
        'input',
        'MaximumAliasCount',
        'MaximumDriveCount',
        'MaximumErrorCount',
        'MaximumFunctionCount',
        'MaximumVariableCount',
        'null',
        'PID',
        'PSCmdlet',
        'PSCulture',
        'PSUICulture',
        'PSVersionTable',
        'ShellId',
        'true'
    )

    $allVariables = Get-Variable -Scope Script | Where-Object { $_.Name -notin $excludedVariables }
    Writelog "Script version: $version"
    WriteLog 'Logging variables'
    foreach ($variable in $allVariables) {
        $variableName = $variable.Name
        $variableValue = $variable.Value
        if ($null -ne $variableValue) {
            WriteLog "[VAR]$variableName`: $variableValue"
        }
        else {
            WriteLog "[VAR]Variable $variableName not found or not set"
        }
    }
    WriteLog 'End logging variables'
}

function Get-ChildProcesses {
    [CmdletBinding()]
    [OutputType([CimInstance[]])]
    param(
        [Parameter(Mandatory = $true)]
        [int]$ParentId
    )
    $result = @()
    $children = Get-CimInstance -ClassName Win32_Process -Filter "ParentProcessId = $ParentId"
    foreach ($child in $children) {
        $result += $child
        $result += Get-ChildProcesses -ParentId $child.ProcessId
    }
    $result
}

function Test-Url {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Url
    )
    try {
        # Create a web request and check the response
        $request = [System.Net.WebRequest]::Create($Url)
        $request.Method = 'HEAD'
        $response = $request.GetResponse()
        $true
    }
    catch {
        $false
    }
}

function Get-PrivateProfileString {
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter()]
        [string]$FileName,
        [Parameter()]
        [string]$SectionName,
        [Parameter()]
        [string]$KeyName
    )
    $sbuilder = [System.Text.StringBuilder]::new(1024)
    [void][Win32.Kernel32]::GetPrivateProfileString($SectionName, $KeyName, "", $sbuilder, $sbuilder.Capacity, $FileName)

    $sbuilder.ToString()
}

function Get-PrivateProfileSection {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param (
        [Parameter()]
        [string]$FileName,
        [Parameter()]
        [string]$SectionName
    )
    $buffer = [byte[]]::new(16384)
    [void][Win32.Kernel32]::GetPrivateProfileSection($SectionName, $buffer, $buffer.Length, $FileName)
    $keyValues = [System.Text.Encoding]::Unicode.GetString($buffer).TrimEnd("`0").Split("`0")
    $hashTable = @{}

    foreach ($keyValue in $keyValues) {
        if (![string]::IsNullOrEmpty($keyValue)) {
            $parts = $keyValue -split "="
            $hashTable[$parts[0]] = $parts[1]
        }
    }

    $hashTable
}

function Get-ShortenedWindowsSKU {
    <#
    .SYNOPSIS
    Converts Windows SKU names to shortened versions for FFU file names

    .DESCRIPTION
    Maps full Windows edition names to shortened abbreviations for use in FFU file naming.
    Handles 30+ known Windows SKU variations. For unknown SKUs, returns the original name
    with a warning rather than failing the build.

    .PARAMETER WindowsSKU
    Full Windows SKU/edition name (e.g., "Pro", "Enterprise", "Education")

    .EXAMPLE
    Get-ShortenedWindowsSKU -WindowsSKU "Professional"
    Returns: "Pro"

    .EXAMPLE
    Get-ShortenedWindowsSKU -WindowsSKU "Enterprise LTSC"
    Returns: "Ent_LTSC"

    .EXAMPLE
    Get-ShortenedWindowsSKU -WindowsSKU "CustomEdition"
    Returns: "CustomEdition" (with warning)

    .NOTES
    Enhanced with parameter validation and default case to prevent empty return values.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$WindowsSKU
    )

    # Trim whitespace for robust matching
    $WindowsSKU = $WindowsSKU.Trim()

    $shortenedWindowsSKU = switch ($WindowsSKU) {
        'Core' { 'Home' }
        'Home' { 'Home' }
        'CoreN' { 'Home_N' }
        'Home N' { 'Home_N' }
        'CoreSingleLanguage' { 'Home_SL' }
        'Home Single Language' { 'Home_SL' }
        'Education' { 'Edu' }
        'EducationN' { 'Edu_N' }
        'Education N' { 'Edu_N' }
        'Professional' { 'Pro' }
        'Pro' { 'Pro' }
        'ProfessionalN' { 'Pro_N' }
        'Pro N' { 'Pro_N' }
        'ProfessionalEducation' { 'Pro_Edu' }
        'Pro Education' { 'Pro_Edu' }
        'ProfessionalEducationN' { 'Pro_Edu_N' }
        'Pro Education N' { 'Pro_Edu_N' }
        'ProfessionalWorkstation' { 'Pro_WKS' }
        'Pro for Workstations' { 'Pro_WKS' }
        'ProfessionalWorkstationN' { 'Pro_WKS_N' }
        'Pro N for Workstations' { 'Pro_WKS_N' }
        'Enterprise' { 'Ent' }
        'EnterpriseN' { 'Ent_N' }
        'Enterprise N' { 'Ent_N' }
        'Enterprise N LTSC' { 'Ent_N_LTSC' }
        'EnterpriseS' { 'Ent_LTSC' }
        'EnterpriseSN' { 'Ent_N_LTSC' }
        'Enterprise LTSC' { 'Ent_LTSC' }
        'Enterprise 2016 LTSB' { 'Ent_LTSC' }
        'Enterprise N 2016 LTSB' { 'Ent_N_LTSC' }
        'IoT Enterprise LTSC' { 'IoT_Ent_LTSC' }
        'IoTEnterpriseS' { 'IoT_Ent_LTSC' }
        'IoT Enterprise N LTSC' { 'IoT_Ent_N_LTSC' }
        'ServerStandard' { 'Srv_Std' }
        'Standard' { 'Srv_Std' }
        'ServerDatacenter' { 'Srv_Dtc' }
        'Datacenter' { 'Srv_Dtc' }
        'Standard (Desktop Experience)' { 'Srv_Std_DE' }
        'Datacenter (Desktop Experience)' { 'Srv_Dtc_DE' }

        # DEFAULT CASE - Return original SKU if no match found
        # This prevents empty string returns and allows builds to continue with unknown SKUs
        default {
            Write-Warning "Unknown Windows SKU '$WindowsSKU' - using original name in FFU filename"
            Write-Verbose "If this SKU should have a shorter name, please add it to Get-ShortenedWindowsSKU function"
            $WindowsSKU
        }
    }

    $shortenedWindowsSKU
}

function New-FFUFileName {
    <#
    .SYNOPSIS
    Generates FFU filename from template with variable substitution

    .DESCRIPTION
    Creates FFU filename by replacing template placeholders with actual values
    for Windows release, version, SKU, and build date/time. Supports custom
    naming patterns with various date/time format specifiers.

    .PARAMETER installationType
    Installation type (Client or Server) - affects Windows release naming

    .PARAMETER winverinfo
    Windows version information object containing OS name (Win10/Win11)

    .PARAMETER WindowsRelease
    Windows release version (10, 11, 2016, 2019, 2022, 2025)

    .PARAMETER CustomFFUNameTemplate
    Template string with placeholders: {WindowsRelease}, {WindowsVersion}, {SKU},
    {BuildDate}, {yyyy}, {MM}, {dd}, {HH}, {hh}, {mm}, {tt}

    .PARAMETER WindowsVersion
    Specific Windows version/build (e.g., "21H2", "22H2", "23H2", "24H2")

    .PARAMETER shortenedWindowsSKU
    Shortened Windows SKU name (e.g., "Pro", "Enterprise", "Education")

    .EXAMPLE
    New-FFUFileName -installationType "Client" -winverinfo $info -WindowsRelease 11 `
                    -CustomFFUNameTemplate "Win{WindowsRelease}_{SKU}_{BuildDate}" `
                    -WindowsVersion "23H2" -shortenedWindowsSKU "Pro"
    Returns: "Win11_Pro_Jan2025.ffu"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Client', 'Server')]
        [string]$installationType,

        [Parameter(Mandatory = $false)]
        $winverinfo,

        [Parameter(Mandatory = $true)]
        [int]$WindowsRelease,

        [Parameter(Mandatory = $true)]
        [string]$CustomFFUNameTemplate,

        [Parameter(Mandatory = $true)]
        [string]$WindowsVersion,

        [Parameter(Mandatory = $true)]
        [string]$shortenedWindowsSKU
    )

    # $Winverinfo.name will be either Win10 or Win11 for client OSes
    # Since WindowsRelease now includes dates, it breaks default name template in the config file
    # This should keep in line with the naming that's done via VM Captures
    if ($installationType -eq 'Client' -and $winverinfo) {
        $WindowsRelease = $winverinfo.name
    }

    $BuildDate = Get-Date -uformat %b%Y
    # Replace '{WindowsRelease}' with the Windows release (e.g., 10, 11, 2016, 2019, 2022, 2025)
    $CustomFFUNameTemplate = $CustomFFUNameTemplate -replace '{WindowsRelease}', $WindowsRelease
    # Replace '{WindowsVersion}' with the Windows version (e.g., 1607, 1809, 21h2, 22h2, 23h2, 24h2, etc)
    $CustomFFUNameTemplate = $CustomFFUNameTemplate -replace '{WindowsVersion}', $WindowsVersion
    # Replace '{SKU}' with the SKU of the Windows image (e.g., Pro, Enterprise, etc.)
    $CustomFFUNameTemplate = $CustomFFUNameTemplate -replace '{SKU}', $shortenedWindowsSKU
    # Replace '{BuildDate}' with the current month and year (e.g., Jan2023)
    $CustomFFUNameTemplate = $CustomFFUNameTemplate -replace '{BuildDate}', $BuildDate
    # Replace '{yyyy}' with the current year in 4-digit format (e.g., 2023)
    $CustomFFUNameTemplate = $CustomFFUNameTemplate -replace '{yyyy}', (Get-Date -UFormat '%Y')
    # Replace '{MM}' with the current month in 2-digit format (e.g., 01 for January)
    $CustomFFUNameTemplate = $CustomFFUNameTemplate -creplace '{MM}', (Get-Date -UFormat '%m')
    # Replace '{dd}' with the current day of the month in 2-digit format (e.g., 05)
    $CustomFFUNameTemplate = $CustomFFUNameTemplate -replace '{dd}', (Get-Date -UFormat '%d')
    # Replace '{HH}' with the current hour in 24-hour format (e.g., 14 for 2 PM)
    $CustomFFUNameTemplate = $CustomFFUNameTemplate -creplace '{HH}', (Get-Date -UFormat '%H')
    # Replace '{hh}' with the current hour in 12-hour format (e.g., 02 for 2 PM)
    $CustomFFUNameTemplate = $CustomFFUNameTemplate -creplace '{hh}', (Get-Date -UFormat '%I')
    # Replace '{mm}' with the current minute in 2-digit format (e.g., 09)
    $CustomFFUNameTemplate = $CustomFFUNameTemplate -creplace '{mm}', (Get-Date -UFormat '%M')
    # Replace '{tt}' with the current AM/PM designator (e.g., AM or PM)
    $CustomFFUNameTemplate = $CustomFFUNameTemplate -replace '{tt}', (Get-Date -UFormat '%p')
    if ($CustomFFUNameTemplate -notlike '*.ffu') {
        $CustomFFUNameTemplate += '.ffu'
    }
    $CustomFFUNameTemplate
}

function Export-ConfigFile {
    <#
    .SYNOPSIS
    Exports FFU build configuration parameters to JSON file

    .DESCRIPTION
    Filters and exports specified build parameters to a JSON configuration file
    for reuse in future builds. Automatically sorts parameters alphabetically
    and saves with UTF8 encoding.

    .PARAMETER paramNames
    Array of parameter names to export to the configuration file

    .PARAMETER ExportConfigFile
    Full path to the JSON configuration file where parameters will be exported

    .EXAMPLE
    Export-ConfigFile -paramNames $PSBoundParameters.Keys -ExportConfigFile "C:\FFU\config.json"

    .OUTPUTS
    None - Writes configuration to file specified by ExportConfigFile parameter
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        $paramNames,

        [Parameter(Mandatory = $true)]
        [string]$ExportConfigFile
    )
    $filteredParamNames = Get-Parameters -ParamNames $paramNames

    # Retrieve their values
    $paramsToExport = @{}
    foreach ($paramName in $filteredParamNames) {
        $paramsToExport[$paramName] = Get-Variable -Name $paramName -ValueOnly
    }

    # Sort the keys alphabetically
    $orderedParams = [ordered]@{}
    foreach ($key in ($paramsToExport.Keys | Sort-Object)) {
        $orderedParams[$key] = $paramsToExport[$key]
    }

    # Convert to JSON and save
    $orderedParams | ConvertTo-Json -Depth 10 | Set-Content -Path $ExportConfigFile -Encoding UTF8
}

function New-RunSession {
    <#
    .SYNOPSIS
    Creates a new FFU build session with backup manifests

    .DESCRIPTION
    Initializes per-run session directory structure and backs up JSON/XML configuration
    files that may be modified during the build. Creates manifest tracking all backups
    for restoration during cleanup.

    .PARAMETER FFUDevelopmentPath
    Root FFUDevelopment directory path

    .PARAMETER DriversFolder
    Path to drivers folder (optional, for DriverMapping.json backup)

    .PARAMETER OrchestrationPath
    Path to orchestration folder (optional, for WinGetWin32Apps.json backup)

    .PARAMETER OfficePath
    Path to Office folder (optional, for Office XML configuration backup)

    .EXAMPLE
    New-RunSession -FFUDevelopmentPath "C:\FFU" -DriversFolder "C:\FFU\Drivers" `
                   -OrchestrationPath "C:\FFU\Orchestration" -OfficePath "C:\FFU\Office"

    .OUTPUTS
    None - Creates .session directory structure and backup files
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FFUDevelopmentPath,

        [Parameter(Mandatory = $false)]
        [string]$DriversFolder,

        [Parameter(Mandatory = $false)]
        [string]$OrchestrationPath,

        [Parameter(Mandatory = $false)]
        [string]$OfficePath
    )
    try {
        $sessionDir = Join-Path $FFUDevelopmentPath '.session'
        $backupDir = Join-Path $sessionDir 'backups'
        $inprogDir = Join-Path $sessionDir 'inprogress'
        if (-not (Test-Path $sessionDir)) { New-Item -ItemType Directory -Path $sessionDir -Force | Out-Null }
        if (-not (Test-Path $backupDir)) { New-Item -ItemType Directory -Path $backupDir -Force | Out-Null }
        if (-not (Test-Path $inprogDir)) { New-Item -ItemType Directory -Path $inprogDir -Force | Out-Null }

        $manifest = [ordered]@{
            RunStartUtc      = (Get-Date).ToUniversalTime().ToString('o')
            JsonBackups      = @()
            OfficeXmlBackups = @()
        }

        if ($DriversFolder) {
            $driverMapPath = Join-Path $DriversFolder 'DriverMapping.json'
            if (Test-Path $driverMapPath) {
                $backup = Join-Path $backupDir 'DriverMapping.json'
                Copy-Item -Path $driverMapPath -Destination $backup -Force
                $manifest.JsonBackups += @{ Path = $driverMapPath; Backup = $backup }
                WriteLog "Backed up DriverMapping.json to $backup"
            }
        }
        if ($OrchestrationPath) {
            $wgPath = Join-Path $OrchestrationPath 'WinGetWin32Apps.json'
            if (Test-Path $wgPath) {
                $backup2 = Join-Path $backupDir 'WinGetWin32Apps.json'
                Copy-Item -Path $wgPath -Destination $backup2 -Force
                $manifest.JsonBackups += @{ Path = $wgPath; Backup = $backup2 }
                WriteLog "Backed up WinGetWin32Apps.json to $backup2"
            }
        }
        # Backup Office XMLs (DeployFFU.xml, DownloadFFU.xml) if present so we can restore them after cleanup
        if ($OfficePath) {
            foreach ($n in @('DeployFFU.xml', 'DownloadFFU.xml')) {
                $src = Join-Path $OfficePath $n
                if (Test-Path $src) {
                    $dst = Join-Path $backupDir $n
                    try {
                        Copy-Item -Path $src -Destination $dst -Force
                        $manifest.OfficeXmlBackups += @{ Path = $src; Backup = $dst }
                        WriteLog "Backed up $n to $dst"
                    }
                    catch { WriteLog "Failed backing up $($n): $($_.Exception.Message)" }
                }
            }
        }

        $manifestPath = Join-Path $sessionDir 'currentRun.json'
        $manifest | ConvertTo-Json -Depth 5 | Set-Content -Path $manifestPath -Encoding UTF8
        WriteLog "Run session initialized at $sessionDir"
    }
    catch {
        WriteLog "New-RunSession failed: $($_.Exception.Message)"
    }
}

function Get-CurrentRunManifest {
    param([string]$FFUDevelopmentPath)
    $manifestPath = Join-Path $FFUDevelopmentPath '.session\currentRun.json'
    if (Test-Path -Path $manifestPath) { Get-Content -Path $manifestPath -Raw | ConvertFrom-Json; return }
    $null
}

function Save-RunManifest {
    param([string]$FFUDevelopmentPath, [object]$Manifest)
    if ($null -eq $Manifest) { return }
    $manifestPath = Join-Path $FFUDevelopmentPath '.session\currentRun.json'
    $Manifest | ConvertTo-Json -Depth 5 | Set-Content -Path $manifestPath -Encoding UTF8
}

function Set-DownloadInProgress {
    <#
    .SYNOPSIS
    Marks a download target as in-progress for cleanup tracking

    .DESCRIPTION
    Creates a marker file in the session inprogress folder to track downloads
    that are currently in progress. This enables cleanup of partially completed
    downloads if the build fails.

    .PARAMETER FFUDevelopmentPath
    Root FFUDevelopment path

    .PARAMETER TargetPath
    Path to the download target being marked as in-progress

    .EXAMPLE
    Set-DownloadInProgress -FFUDevelopmentPath "C:\FFU" -TargetPath "C:\FFU\Drivers\Dell\driver.cab"

    .OUTPUTS
    None

    .NOTES
    Renamed from Mark-DownloadInProgress to Set-DownloadInProgress in v1.0.11 for
    PowerShell approved verb compliance. Alias 'Mark-DownloadInProgress' is available
    for backward compatibility but is deprecated.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$FFUDevelopmentPath,

        [Parameter(Mandatory = $false)]
        [string]$TargetPath
    )
    if ([string]::IsNullOrWhiteSpace($FFUDevelopmentPath) -or [string]::IsNullOrWhiteSpace($TargetPath)) { return }
    $sessionInprog = Join-Path (Join-Path $FFUDevelopmentPath '.session') 'inprogress'
    if (-not (Test-Path $sessionInprog)) { New-Item -ItemType Directory -Path $sessionInprog -Force | Out-Null }
    $marker = Join-Path $sessionInprog ("{0}.marker" -f ([guid]::NewGuid()))
    $payload = @{ TargetPath = $TargetPath; CreatedUtc = (Get-Date).ToUniversalTime().ToString('o') }
    $payload | ConvertTo-Json -Depth 3 | Set-Content -Path $marker -Encoding UTF8
    WriteLog "Marked in-progress: $TargetPath"
}

function Clear-DownloadInProgress {
    param([string]$FFUDevelopmentPath, [string]$TargetPath)
    $sessionInprog = Join-Path (Join-Path $FFUDevelopmentPath '.session') 'inprogress'
    if (-not (Test-Path $sessionInprog)) { return }
    Get-ChildItem -Path $sessionInprog -Filter *.marker -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $data = Get-Content $_.FullName -Raw | ConvertFrom-Json
            if ($data.TargetPath -eq $TargetPath) { Remove-Item -Path $_.FullName -Force -ErrorAction SilentlyContinue }
        }
        catch {}
    }
    WriteLog "Cleared in-progress: $TargetPath"
}

function Remove-InProgressItems {
    <#
    .SYNOPSIS
    Removes items marked as in-progress from previous incomplete FFU build runs

    .DESCRIPTION
    Scans the .session/inprogress folder for download markers and removes
    corresponding files/folders that were being downloaded when the build failed.
    Implements special handling for Drivers folder (promotes to model folder level)
    and Office folder (preserves XML configuration files).

    .PARAMETER FFUDevelopmentPath
    Root FFUDevelopment path

    .PARAMETER DriversFolder
    Root path to OEM drivers folder (for smart cleanup of partial driver downloads)

    .PARAMETER OfficePath
    Path to Office installer/configs folder (preserves XML configuration files)

    .EXAMPLE
    Remove-InProgressItems -FFUDevelopmentPath "C:\FFU" -DriversFolder "C:\FFU\Drivers" `
                          -OfficePath "C:\FFU\Office"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FFUDevelopmentPath,

        [Parameter(Mandatory = $false)]
        [string]$DriversFolder,

        [Parameter(Mandatory = $false)]
        [string]$OfficePath
    )
    $sessionInprog = Join-Path (Join-Path $FFUDevelopmentPath '.session') 'inprogress'
    if (-not (Test-Path $sessionInprog)) { return }

    function Remove-PathWithRetry {
        param(
            [string]$path,
            [bool]$isDirectory
        )
        for ($i = 0; $i -lt 3; $i++) {
            try {
                if ($isDirectory) {
                    Remove-Item -Path $path -Recurse -Force -ErrorAction Stop
                }
                else {
                    # clear readonly if set
                    try { (Get-Item -LiteralPath $path -ErrorAction SilentlyContinue).Attributes = 'Normal' } catch {}
                    Remove-Item -Path $path -Force -ErrorAction Stop
                }
                $true
                return
            }
            catch {
                Start-Sleep -Milliseconds ([FFUConstants]::PROCESS_POLL_INTERVAL_MS)
            }
        }
        -not (Test-Path -LiteralPath $path)
    }

    Get-ChildItem -Path $sessionInprog -Filter *.marker -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $data = Get-Content $_.FullName -Raw | ConvertFrom-Json
            $target = $data.TargetPath
            try {
                if ($DriversFolder -and $target) {
                    $fullTarget = [System.IO.Path]::GetFullPath($target).TrimEnd('\')
                    $driversRoot = [System.IO.Path]::GetFullPath($DriversFolder).TrimEnd('\')
                    if ($fullTarget.StartsWith($driversRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
                        $remainder = $fullTarget.Substring($driversRoot.Length).TrimStart('\')
                        $parts = $remainder -split '\\'
                        if ($parts.Length -ge 1) {
                            $knownMakes = @('Dell', 'HP', 'Lenovo', 'Microsoft')
                            if ($parts.Length -ge 2 -and $knownMakes -contains $parts[0]) {
                                # Drivers\<Make>\<Model>\...
                                $modelFolder = Join-Path (Join-Path $driversRoot $parts[0]) $parts[1]
                            }
                            else {
                                # Drivers\<Model>\... (when DriversFolder already includes Make)
                                $modelFolder = Join-Path $driversRoot $parts[0]
                            }
                            if ($modelFolder) {
                                WriteLog "Promoting in-progress driver target to model folder: $modelFolder (from $target)"
                                $target = $modelFolder
                            }
                        }
                    }
                }
            }
            catch {}

            if (Test-Path $target) {
                # Special-case Office: preserve DeployFFU.xml and DownloadFFU.xml; remove everything else with retries.
                $targetFull = [System.IO.Path]::GetFullPath($target).TrimEnd('\')
                $officeFull = $null
                if ($OfficePath) { $officeFull = [System.IO.Path]::GetFullPath($OfficePath).TrimEnd('\') }

                if ($officeFull -and ($targetFull -ieq $officeFull) -and (Test-Path $OfficePath -PathType Container)) {
                    $preserve = @('DeployFFU.xml', 'DownloadFFU.xml')
                    WriteLog "Cleaning in-progress Office folder: preserving $($preserve -join ', ') and removing other content."
                    Get-ChildItem -Path $OfficePath -Force | ForEach-Object {
                        if ($preserve -notcontains $_.Name) {
                            $itemPath = $_.FullName
                            $isDir = $_.PSIsContainer
                            WriteLog "Removing Office item: $itemPath"
                            $removed = $false
                            try { $removed = Remove-PathWithRetry -path $itemPath -isDirectory:$isDir } catch {}
                            if (-not $removed) {
                                # If setup.exe (or ODT stub) is locked, try to stop the exact owning process by path and retry.
                                try {
                                    $basename = [System.IO.Path]::GetFileName($itemPath)
                                    if (-not $isDir -and $basename -in @('setup.exe', 'odtsetup.exe')) {
                                        Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $itemPath } | Stop-Process -Force -ErrorAction SilentlyContinue
                                        Start-Sleep -Milliseconds ([FFUConstants]::SERVICE_CHECK_INTERVAL_MS)
                                        $removed = Remove-PathWithRetry -path $itemPath -isDirectory:$false
                                    }
                                }
                                catch {
                                    WriteLog "Process stop attempt for $itemPath failed: $($_.Exception.Message)"
                                }
                            }
                            if (-not $removed) {
                                WriteLog "Failed removing Office item $itemPath after retries."
                            }
                        }
                    }
                }
                else {
                    WriteLog "Removing in-progress target: $target"
                    $isDir = Test-Path $target -PathType Container
                    [void](Remove-PathWithRetry -path $target -isDirectory:$isDir)
                }
            }

            Remove-Item -Path $_.FullName -Force -ErrorAction SilentlyContinue
        }
        catch {
            WriteLog "Failed Remove-InProgressItems marker '$($_.FullName)': $($_.Exception.Message)"
        }
    }
    # Also clean up any driver content created this run (model folders and temp folders),
    # even when broader current-run cleanup is not requested.
    try {
        if ($DriversFolder -and (Test-Path $DriversFolder)) {
            $manifest = Get-CurrentRunManifest -FFUDevelopmentPath $FFUDevelopmentPath
            if ($manifest -and $manifest.RunStartUtc) {
                $runStart = [datetime]::Parse($manifest.RunStartUtc)

                # Remove OEM temp folders like _TEMP_* (safe to always remove)
                Get-ChildItem -Path $DriversFolder -Directory -Recurse -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -like '_TEMP_*' } |
                ForEach-Object {
                    WriteLog "Removing driver temp folder: $($_.FullName)"
                    Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
                }

                # Remove model folders created/modified this run; never remove top-level make roots
                Get-ChildItem -Path $DriversFolder -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                    $makeRoot = $_.FullName
                    # Model-level folders are immediate children under a make root (e.g. Drivers\Lenovo\<Model>)
                    Get-ChildItem -Path $makeRoot -Directory -ErrorAction SilentlyContinue |
                    Where-Object { $_.CreationTimeUtc -ge $runStart -or $_.LastWriteTimeUtc -ge $runStart } |
                    ForEach-Object {
                        WriteLog "Removing driver model folder from current run: $($_.FullName)"
                        Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
                    }
                }

                # Remove make root folders created this run (if empty)
                Get-ChildItem -Path $DriversFolder -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.CreationTimeUtc -ge $runStart -and $_.LastWriteTimeUtc -ge $runStart } |
                ForEach-Object {
                    $any = Get-ChildItem -Path $_.FullName -Force -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
                    if ($null -eq $any) {
                        WriteLog "Removing empty make root folder created this run: $($_.FullName)"
                        Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
                    }
                    else {
                        WriteLog "Skipping non-empty make root folder: $($_.FullName)"
                    }
                }
            }
        }
    }
    catch {
        WriteLog "Driver in-progress cleanup step failed: $($_.Exception.Message)"
    }
}

function Clear-CurrentRunDownloads {
    <#
    .SYNOPSIS
    Removes downloaded files and folders created during the current FFU build run

    .DESCRIPTION
    Scans configured download paths (Apps, Defender, MSRT, OneDrive, Edge, KB, Drivers,
    Orchestration, Office) and removes items created/modified during the current build
    session based on timestamps. Uses per-run manifest to determine session boundaries.
    Implements special logic for Drivers folder to preserve existing OEM trees and only
    remove current-run additions.

    .PARAMETER FFUDevelopmentPath
    Root FFUDevelopment path

    .PARAMETER AppsPath
    Path to Apps download folder (Win32 and MSStore subfolders)

    .PARAMETER DefenderPath
    Path to Windows Defender updates download folder

    .PARAMETER MSRTPath
    Path to Microsoft Safety Scanner / MSRT download folder

    .PARAMETER OneDrivePath
    Path to OneDrive installer download folder

    .PARAMETER EdgePath
    Path to Microsoft Edge download folder

    .PARAMETER KBPath
    Path to Windows KB/update packages download folder

    .PARAMETER DriversFolder
    Root path to OEM drivers folder (Dell, HP, Lenovo, Microsoft subfolders)

    .PARAMETER orchestrationPath
    Path to orchestration scripts/configs folder

    .PARAMETER OfficePath
    Path to Office installer/configs folder (preserves XML configuration files)

    .EXAMPLE
    Clear-CurrentRunDownloads -FFUDevelopmentPath "C:\FFU" -AppsPath "C:\FFU\Apps" `
                              -DefenderPath "C:\FFU\Defender" -MSRTPath "C:\FFU\MSRT" `
                              -OneDrivePath "C:\FFU\OneDrive" -EdgePath "C:\FFU\Edge" `
                              -KBPath "C:\FFU\KB" -DriversFolder "C:\FFU\Drivers" `
                              -orchestrationPath "C:\FFU\Orchestration" -OfficePath "C:\FFU\Office"

    .OUTPUTS
    None

    .NOTES
    Renamed from Cleanup-CurrentRunDownloads to Clear-CurrentRunDownloads in v1.0.11 for
    PowerShell approved verb compliance. Alias 'Cleanup-CurrentRunDownloads' is available
    for backward compatibility but is deprecated.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FFUDevelopmentPath,

        [Parameter(Mandatory = $false)]
        [string]$AppsPath,

        [Parameter(Mandatory = $false)]
        [string]$DefenderPath,

        [Parameter(Mandatory = $false)]
        [string]$MSRTPath,

        [Parameter(Mandatory = $false)]
        [string]$OneDrivePath,

        [Parameter(Mandatory = $false)]
        [string]$EdgePath,

        [Parameter(Mandatory = $false)]
        [string]$KBPath,

        [Parameter(Mandatory = $false)]
        [string]$DriversFolder,

        [Parameter(Mandatory = $false)]
        [string]$orchestrationPath,

        [Parameter(Mandatory = $false)]
        [string]$OfficePath
    )
    $manifest = Get-CurrentRunManifest -FFUDevelopmentPath $FFUDevelopmentPath
    if ($null -eq $manifest) { WriteLog "No current run manifest; skipping current-run cleanup."; return }
    $runStart = [datetime]::Parse($manifest.RunStartUtc)

    # 1) Generic current-run scrub across known roots (includes Orchestration now)
    $roots = @()
    if ($AppsPath) { $roots += (Join-Path $AppsPath 'Win32'); $roots += (Join-Path $AppsPath 'MSStore') }
    if ($DefenderPath) { $roots += $DefenderPath }
    if ($MSRTPath) { $roots += $MSRTPath }
    if ($OneDrivePath) { $roots += $OneDrivePath }
    if ($EdgePath) { $roots += $EdgePath }
    if ($KBPath) { $roots += $KBPath }
    if ($DriversFolder) { $roots += $DriversFolder }
    if ($orchestrationPath) { $roots += $orchestrationPath }

    foreach ($root in $roots | Where-Object { $_ -and (Test-Path $_) }) {
        $isDriversRoot = $false
        try {
            if ($DriversFolder) {
                $isDriversRoot = ([System.IO.Path]::GetFullPath($root).TrimEnd('\') -ieq [System.IO.Path]::GetFullPath($DriversFolder).TrimEnd('\'))
            }
        }
        catch {}

        if ($isDriversRoot) {
            WriteLog "Scanning Drivers folder (creation-time filter) in $root"

            # Remove driver folders created this run (skip non-empty make roots)
            Get-ChildItem -Path $root -Directory -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.CreationTimeUtc -ge $runStart } |
            Sort-Object FullName -Descending | ForEach-Object {
                try {
                    $parent = Split-Path -Path $_.FullName -Parent
                    $parentIsDriversRoot = ([System.IO.Path]::GetFullPath($parent).TrimEnd('\') -ieq [System.IO.Path]::GetFullPath($root).TrimEnd('\'))
                    if ($parentIsDriversRoot) {
                        # Only remove top-level make folders if created this run AND empty (avoid deleting existing Lenovo/HP/Dell/Microsoft trees)
                        $any = Get-ChildItem -Path $_.FullName -Force -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
                        if ($null -eq $any) {
                            WriteLog "Removing empty make folder created this run: $($_.FullName)"
                            Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
                        }
                    }
                    else {
                        WriteLog "Removing current-run driver folder: $($_.FullName)"
                        Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
                    }
                }
                catch { WriteLog "Failed removing driver folder $($_.FullName): $($_.Exception.Message)" }
            }

            # Remove driver files created this run
            Get-ChildItem -Path $root -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.CreationTimeUtc -ge $runStart } |
            ForEach-Object {
                try {
                    WriteLog "Removing current-run driver file: $($_.FullName)"
                    Remove-Item -Path $_.FullName -Force -ErrorAction SilentlyContinue
                }
                catch { WriteLog "Failed removing driver file $($_.FullName): $($_.Exception.Message)" }
            }

            # Prune empty driver folders (skip existing make roots)
            Get-ChildItem -Path $root -Directory -Recurse -ErrorAction SilentlyContinue |
            Sort-Object FullName -Descending | ForEach-Object {
                try {
                    $any = Get-ChildItem -Path $_.FullName -Force -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
                    if ($null -eq $any) {
                        $parent = Split-Path -Path $_.FullName -Parent
                        $parentIsDriversRoot = ([System.IO.Path]::GetFullPath($parent).TrimEnd('\') -ieq [System.IO.Path]::GetFullPath($root).TrimEnd('\'))
                        if ($parentIsDriversRoot) {
                            # Only remove empty make roots if they were created this run
                            if ($_.CreationTimeUtc -ge $runStart) {
                                WriteLog "Removing empty make folder created this run: $($_.FullName)"
                                Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
                            }
                        }
                        else {
                            WriteLog "Removing empty driver subfolder: $($_.FullName)"
                            Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
                        }
                    }
                }
                catch { WriteLog "Failed pruning empty driver folder $($_.FullName): $($_.Exception.Message)" }
            }
        }
        else {
            WriteLog "Scanning for current-run items in $root"
            # Remove folders created/modified this run (legacy behavior for non-Drivers roots)
            Get-ChildItem -Path $root -Directory -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTimeUtc -ge $runStart } |
            Sort-Object FullName -Descending | ForEach-Object {
                try {
                    WriteLog "Removing current-run folder: $($_.FullName)"
                    Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
                }
                catch { WriteLog "Failed removing folder $($_.FullName): $($_.Exception.Message)" }
            }
            # Remove files created/modified this run (preserve Office XMLs)
            Get-ChildItem -Path $root -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTimeUtc -ge $runStart -and $_.Name -notin @('DeployFFU.xml', 'DownloadFFU.xml') } |
            ForEach-Object {
                try {
                    WriteLog "Removing current-run file: $($_.FullName)"
                    Remove-Item -Path $_.FullName -Force -ErrorAction SilentlyContinue
                }
                catch { WriteLog "Failed removing file $($_.FullName): $($_.Exception.Message)" }
            }
        }
    }

    # 2) Office folder policy: keep XML configs, remove everything else
    if ($OfficePath -and (Test-Path $OfficePath)) {
        $preserve = @('DeployFFU.xml', 'DownloadFFU.xml')
        WriteLog "Cleaning Office folder: preserving $($preserve -join ', ') and removing other content."
        Get-ChildItem -Path $OfficePath -Force | ForEach-Object {
            if ($preserve -notcontains $_.Name) {
                try {
                    WriteLog "Removing Office item: $($_.FullName)"
                    if ($_.PSIsContainer) {
                        Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
                    }
                    else {
                        Remove-Item -Path $_.FullName -Force -ErrorAction SilentlyContinue
                    }
                }
                catch { WriteLog "Failed removing Office item $($_.FullName): $($_.Exception.Message)" }
            }
        }
    }

    # 3) Remove generated update artifacts under Orchestration (Update-*.ps1) created this run
    if ($orchestrationPath -and (Test-Path $orchestrationPath)) {
        try {
            Get-ChildItem -Path $orchestrationPath -Filter 'Update-*.ps1' -File -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTimeUtc -ge $runStart } | ForEach-Object {
                WriteLog "Removing current-run artifact: $($_.FullName)"
                Remove-Item -Path $_.FullName -Force -ErrorAction SilentlyContinue
            }
        }
        catch { WriteLog "Failed removing Update-*.ps1 artifacts: $($_.Exception.Message)" }
        # Also remove Install-Office.ps1 if created this run
        $installOffice = Join-Path $orchestrationPath 'Install-Office.ps1'
        if (Test-Path $installOffice) {
            $fi = Get-Item $installOffice
            if ($fi.LastWriteTimeUtc -ge $runStart) {
                WriteLog "Removing current-run artifact: $installOffice"
                Remove-Item -Path $installOffice -Force -ErrorAction SilentlyContinue
            }
        }
    }

    # 4) If Defender/OneDrive/Edge/MSRT folders exist, remove them entirely (they're session downloads)
    foreach ($p in @($DefenderPath, $OneDrivePath, $EdgePath, $MSRTPath)) {
        if ($p -and (Test-Path $p)) {
            try {
                WriteLog "Removing current-run folder (entire): $p"
                Remove-Item -Path $p -Recurse -Force -ErrorAction SilentlyContinue
            }
            catch { WriteLog "Failed removing folder $($p): $($_.Exception.Message)" }
        }
    }

    # 5) Remove any ESDs downloaded this run
    Get-ChildItem -Path $PSScriptRoot -Filter *.esd -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTimeUtc -ge $runStart } | ForEach-Object {
        try {
            WriteLog "Removing current-run ESD: $($_.FullName)"
            Remove-Item -Path $_.FullName -Force -ErrorAction SilentlyContinue
        }
        catch { WriteLog "Failed removing ESD $($_.FullName): $($_.Exception.Message)" }
    }

    # 6) Remove empty top-level subfolders under Apps (cosmetic)
    if ($AppsPath -and (Test-Path $AppsPath)) {
        Get-ChildItem -Path $AppsPath -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                $any = Get-ChildItem -Path $_.FullName -Force -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($null -eq $any) {
                    WriteLog "Removing empty folder: $($_.FullName)"
                    Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
            catch { WriteLog "Failed removing empty folder $($_.FullName): $($_.Exception.Message)" }
        }
    }
}

function Restore-RunJsonBackups {
    <#
    .SYNOPSIS
    Restores JSON backup files from previous build run

    .DESCRIPTION
    Restores JSON configuration files (DriverMapping.json, WinGetWin32Apps.json) from
    backup copies made at the start of the build run. Removes current-run JSON files
    that don't have backups and were created after the run started.

    .PARAMETER FFUDevelopmentPath
    Root FFUDevelopment directory path

    .PARAMETER DriversFolder
    Path to drivers folder containing DriverMapping.json (optional)

    .PARAMETER orchestrationPath
    Path to orchestration folder containing WinGetWin32Apps.json (optional)

    .EXAMPLE
    Restore-RunJsonBackups -FFUDevelopmentPath "C:\FFU" -DriversFolder "C:\FFU\Drivers" `
                           -orchestrationPath "C:\FFU\Orchestration"

    .OUTPUTS
    None - Restores files in-place from backup locations
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FFUDevelopmentPath,

        [Parameter(Mandatory = $false)]
        [string]$DriversFolder,

        [Parameter(Mandatory = $false)]
        [string]$orchestrationPath
    )
    $manifest = Get-CurrentRunManifest -FFUDevelopmentPath $FFUDevelopmentPath
    if ($null -eq $manifest) { return }
    $runStart = [datetime]::Parse($manifest.RunStartUtc)

    foreach ($entry in $manifest.JsonBackups) {
        $path = $entry.Path
        $backup = $entry.Backup
        try {
            if (Test-Path $backup) {
                WriteLog "Restoring JSON from backup: $path"
                Copy-Item -Path $backup -Destination $path -Force
            }
        }
        catch { WriteLog "Failed restoring backup for $($path): $($_.Exception.Message)" }
    }

    $candidateJsons = @()
    if ($DriversFolder) { $candidateJsons += (Join-Path $DriversFolder 'DriverMapping.json') }
    if ($orchestrationPath) { $candidateJsons += (Join-Path $orchestrationPath 'WinGetWin32Apps.json') }

    foreach ($jp in $candidateJsons) {
        if (Test-Path $jp) {
            $hasBackup = $manifest.JsonBackups | Where-Object { $_.Path -eq $jp }
            if ($null -eq $hasBackup) {
                $fi = Get-Item $jp
                if ($fi.LastWriteTimeUtc -ge $runStart) {
                    WriteLog "Removing current-run JSON: $jp"
                    Remove-Item -Path $jp -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }
}

# ============================================================================
# ERROR HANDLING HELPERS
# ============================================================================

function Invoke-WithErrorHandling {
    <#
    .SYNOPSIS
    Executes a script block with standardized error handling, retry logic, and cleanup.

    .DESCRIPTION
    Wraps operations in try/catch with optional retry logic and cleanup actions.
    Provides consistent error handling pattern across all FFU modules.

    .PARAMETER Operation
    The script block to execute.

    .PARAMETER OperationName
    Human-readable name for logging purposes.

    .PARAMETER MaxRetries
    Maximum number of retry attempts (default: 1 = no retry).

    .PARAMETER RetryDelaySeconds
    Delay between retry attempts in seconds (default: 5).

    .PARAMETER CleanupAction
    Optional script block to run on failure for resource cleanup.

    .PARAMETER CriticalOperation
    If $true, throws on final failure. If $false, returns $null (default: $true).

    .PARAMETER SuppressErrorLog
    If $true, doesn't log errors (useful for expected failures).

    .EXAMPLE
    Invoke-WithErrorHandling -OperationName "Mount VHD" -Operation {
        Mount-VHD -Path $VHDXPath -ErrorAction Stop
    } -CleanupAction {
        Dismount-VHD -Path $VHDXPath -ErrorAction SilentlyContinue
    }

    .EXAMPLE
    $result = Invoke-WithErrorHandling -OperationName "Download catalog" -MaxRetries 3 -Operation {
        Invoke-WebRequest -Uri $catalogUrl -UseBasicParsing -ErrorAction Stop
    }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$Operation,

        [Parameter(Mandatory = $true)]
        [string]$OperationName,

        [Parameter(Mandatory = $false)]
        [int]$MaxRetries = 1,

        [Parameter(Mandatory = $false)]
        [int]$RetryDelaySeconds = 5,

        [Parameter(Mandatory = $false)]
        [scriptblock]$CleanupAction,

        [Parameter(Mandatory = $false)]
        [bool]$CriticalOperation = $true,

        [Parameter(Mandatory = $false)]
        [switch]$SuppressErrorLog
    )

    # Safe logging helper - uses WriteLog if available, otherwise Write-Verbose
    $log = {
        param([string]$Message)
        if (Get-Command WriteLog -ErrorAction SilentlyContinue) {
            WriteLog $Message
        } else {
            Write-Verbose $Message
        }
    }

    $attempt = 0
    $lastError = $null

    while ($attempt -lt $MaxRetries) {
        $attempt++

        try {
            if ($attempt -gt 1) {
                & $log "Retrying '$OperationName' (attempt $attempt of $MaxRetries)..."
            }

            $result = & $Operation

            if ($attempt -gt 1) {
                & $log "Operation '$OperationName' succeeded on attempt $attempt"
            }

            $result
            return
        }
        catch {
            $lastError = $_
            $errorMessage = if ($_.Exception.Message) { $_.Exception.Message } else { $_.ToString() }

            if (-not $SuppressErrorLog) {
                & $log "ERROR in '$OperationName' (attempt $attempt): $errorMessage"
            }

            # Run cleanup action if provided
            if ($CleanupAction) {
                try {
                    & $log "Running cleanup for '$OperationName'..."
                    & $CleanupAction
                }
                catch {
                    & $log "WARNING: Cleanup for '$OperationName' failed: $($_.Exception.Message)"
                }
            }

            # If not last attempt, wait and retry
            if ($attempt -lt $MaxRetries) {
                & $log "Waiting $RetryDelaySeconds seconds before retry..."
                Start-Sleep -Seconds $RetryDelaySeconds
            }
        }
    }

    # All retries exhausted
    $finalMessage = "Operation '$OperationName' failed after $MaxRetries attempt(s): $($lastError.Exception.Message)"

    if ($CriticalOperation) {
        throw $finalMessage
    }
    else {
        & $log "WARNING: $finalMessage"
        $null
    }
}

function Test-ExternalCommandSuccess {
    <#
    .SYNOPSIS
    Validates that an external command (robocopy, oscdimg, etc.) succeeded.

    .DESCRIPTION
    Checks $LASTEXITCODE after running external commands and returns true/false.
    Handles special cases like robocopy which uses non-zero codes for success.
    Robocopy exit codes 0-7 are considered success; 8+ indicate errors.

    .PARAMETER CommandName
    Name of the command for error messages and robocopy detection.

    .PARAMETER SuccessCodes
    Array of exit codes that indicate success (default: 0).
    Ignored for robocopy (auto-detected based on CommandName).

    .PARAMETER Output
    Optional output from the command to include in error message.

    .OUTPUTS
    [bool] True if command succeeded, False otherwise.

    .EXAMPLE
    robocopy $source $dest /E /R:3
    if (-not (Test-ExternalCommandSuccess -CommandName "Robocopy copy")) {
        throw "Robocopy failed"
    }

    .EXAMPLE
    & oscdimg.exe $args
    Test-ExternalCommandSuccess -CommandName "oscdimg"
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$CommandName,

        [Parameter(Mandatory = $false)]
        [int[]]$SuccessCodes = @(0),

        [Parameter(Mandatory = $false)]
        [string]$Output
    )

    # Safe logging helper - uses WriteLog if available, otherwise Write-Verbose
    $logError = {
        param([string]$Message)
        if (Get-Command WriteLog -ErrorAction SilentlyContinue) {
            WriteLog "ERROR: $Message"
        } else {
            Write-Verbose "ERROR: $Message"
        }
    }

    # Special handling for robocopy - exit codes 0-7 are success
    if ($CommandName -match 'robocopy') {
        $robocopySuccessCodes = @(0, 1, 2, 3, 4, 5, 6, 7)
        if ($robocopySuccessCodes -contains $LASTEXITCODE) {
            $true
            return
        } else {
            $errorMsg = "$CommandName failed with exit code $LASTEXITCODE (robocopy: 8+ indicates error)"
            if ($Output) { $errorMsg += "`nOutput: $Output" }
            & $logError $errorMsg
            $false
            return
        }
    }

    # Standard command handling
    if ($SuccessCodes -contains $LASTEXITCODE) {
        $true
    } else {
        $errorMsg = "$CommandName failed with exit code $LASTEXITCODE"
        if ($Output) { $errorMsg += "`nOutput: $Output" }
        & $logError $errorMsg
        $false
    }
}

function Invoke-WithCleanup {
    <#
    .SYNOPSIS
    Executes an operation with guaranteed cleanup in finally block.

    .DESCRIPTION
    Ensures cleanup actions run regardless of success or failure.
    Useful for resource cleanup like dismounting images, removing temp files.

    .PARAMETER Operation
    The main script block to execute.

    .PARAMETER Cleanup
    Script block to run in finally (always executes).

    .PARAMETER OperationName
    Human-readable name for logging.

    .EXAMPLE
    Invoke-WithCleanup -OperationName "Apply drivers" -Operation {
        Mount-WindowsImage -Path $mountPath -ImagePath $wimPath -Index 1
        Add-WindowsDriver -Path $mountPath -Driver $driverPath -Recurse
    } -Cleanup {
        Dismount-WindowsImage -Path $mountPath -Save
    }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$Operation,

        [Parameter(Mandatory = $true)]
        [scriptblock]$Cleanup,

        [Parameter(Mandatory = $false)]
        [string]$OperationName = "Operation"
    )

    # Safe logging helper - uses WriteLog if available, otherwise Write-Verbose
    $logMessage = {
        param([string]$Level, [string]$Message)
        if (Get-Command WriteLog -ErrorAction SilentlyContinue) {
            WriteLog "$Level $Message"
        } else {
            Write-Verbose "$Level $Message"
        }
    }

    try {
        $result = & $Operation
        $result
    }
    catch {
        & $logMessage "ERROR:" "in '$OperationName': $($_.Exception.Message)"
        throw
    }
    finally {
        try {
            & $Cleanup
        }
        catch {
            & $logMessage "WARNING:" "Cleanup for '$OperationName' failed: $($_.Exception.Message)"
        }
    }
}

# =============================================================================
# WIM Mount Error Handling
# Enhanced error handling for Mount-WindowsImage operations
# =============================================================================

function Invoke-WimMountWithErrorHandling {
    <#
    .SYNOPSIS
    Mounts a Windows image with enhanced error handling for WIMMount issues.

    .DESCRIPTION
    Wraps Mount-WindowsImage with detection and user-friendly messaging for
    error 0x800704db (WIMMount filter driver missing/corrupted).

    When the WIMMount filter driver is missing or corrupted, Mount-WindowsImage
    fails with a cryptic "specified service does not exist" error. This function
    detects that specific error and provides clear remediation guidance.

    .PARAMETER ImagePath
    Path to the WIM or FFU file to mount.

    .PARAMETER Path
    Directory to mount the image to.

    .PARAMETER Index
    Index of the image to mount (default: 1).

    .PARAMETER ReadOnly
    Mount the image as read-only.

    .PARAMETER Optimize
    Optimize the mount for faster access (read-only mounts only).

    .EXAMPLE
    Invoke-WimMountWithErrorHandling -ImagePath "C:\boot.wim" -Path "C:\mount" -Index 1 -ReadOnly

    .EXAMPLE
    Invoke-WimMountWithErrorHandling -ImagePath "D:\images\install.wim" -Path "C:\mount\offline" -Index 3

    .OUTPUTS
    None. The function outputs nothing on success (like Mount-WindowsImage with Out-Null).

    .NOTES
    Version: 1.0.0
    Added in FFU.Core v1.0.13

    ROOT CAUSE: The WIMMount filter driver (wimmount.sys) is required for all WIM
    mount operations. ADK versions 10.1.26100.1 and later can corrupt this driver
    during installation, causing error 0x800704DB.

    .LINK
    https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ImagePath,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter()]
        [ValidateRange(1, 999)]
        [int]$Index = 1,

        [Parameter()]
        [switch]$ReadOnly,

        [Parameter()]
        [switch]$Optimize
    )

    # Safe logging helper - uses WriteLog if available, otherwise Write-Verbose
    $logMessage = {
        param([string]$Message)
        if (Get-Command WriteLog -ErrorAction SilentlyContinue) {
            WriteLog $Message
        } else {
            Write-Verbose $Message
        }
    }

    try {
        & $logMessage "Mounting image '$ImagePath' (Index: $Index) to '$Path'..."

        $mountParams = @{
            ImagePath = $ImagePath
            Path = $Path
            Index = $Index
            ErrorAction = 'Stop'
        }

        if ($ReadOnly) { $mountParams.ReadOnly = $true }
        if ($Optimize) { $mountParams.Optimize = $true }

        Mount-WindowsImage @mountParams | Out-Null

        & $logMessage "Successfully mounted image to '$Path'"
    }
    catch {
        $errorMessage = $_.Exception.Message
        $errorCode = if ($_.Exception.HResult) { '0x{0:X8}' -f $_.Exception.HResult } else { 'Unknown' }

        # Check for WIMMount filter driver error (0x800704DB = -2147023653 signed, 2147943643 unsigned)
        $isWimMountError = $false
        if ($errorMessage -match 'specified service does not exist' -or
            $errorMessage -match '0x800704[dD][bB]' -or
            $_.Exception.HResult -eq -2147023653 -or  # 0x800704DB as signed int32
            $_.Exception.HResult -eq 2147943643) {    # 0x800704DB as unsigned int32
            $isWimMountError = $true
        }

        if ($isWimMountError) {
            $dismLogPath = Join-Path $env:WINDIR 'Logs\DISM\dism.log'

            $enhancedMessage = @"
MOUNT FAILED: WIMMount filter driver service is missing or corrupted

Error: $errorMessage
Error Code: $errorCode
Image: $ImagePath
Mount Path: $Path
DISM Log: $dismLogPath

ROOT CAUSE: The WIMMount filter driver (wimmount.sys) is required for all WIM mount
operations, including native PowerShell cmdlets (Mount-WindowsImage). ADK versions
10.1.26100.1 and later can corrupt this driver during installation.

REMEDIATION STEPS:
1. Run FFU Builder pre-flight validation to diagnose the issue:
   Invoke-FFUPreflight -CheckWimMount

2. Try reinstalling the Windows ADK Deployment Tools:
   - Open "Add or remove programs"
   - Find "Windows Assessment and Deployment Kit"
   - Select Modify, then reinstall "Deployment Tools"

3. If reinstallation doesn't work, manually re-register the WIMMount service:
   - Open Administrator PowerShell
   - Run: RUNDLL32.EXE WIMGAPI.DLL,WIMRegisterFilterDriver
   - Reboot and retry

4. As a last resort, completely uninstall and reinstall the Windows ADK

For full diagnostics, check the DISM log at: $dismLogPath
"@
            & $logMessage "ERROR: WIMMount filter driver issue detected - $errorMessage"
            throw $enhancedMessage
        }
        else {
            # Re-throw with enhanced context for non-WIMMount errors
            & $logMessage "ERROR: Mount-WindowsImage failed - $errorMessage (Code: $errorCode)"
            throw "Mount-WindowsImage failed for '$ImagePath': $errorMessage (Error code: $errorCode)"
        }
    }
}

# =============================================================================
# Secure Credential Management
# Provides secure password generation and credential handling
# =============================================================================

function New-SecureRandomPassword {
    <#
    .SYNOPSIS
    Generates a cryptographically secure random password as a SecureString.

    .DESCRIPTION
    Creates a random password directly as a SecureString without ever storing
    the complete password in a plain text string variable. This prevents the
    password from appearing in memory dumps or being accessible through
    debugging tools.

    Uses RNGCryptoServiceProvider for cryptographically secure random number
    generation instead of Get-Random which uses a predictable PRNG.

    .PARAMETER Length
    Length of the password to generate. Default is 32 characters.
    Minimum is 16, maximum is 128.

    .PARAMETER IncludeSpecialChars
    If specified, includes special characters (!@#$%^&*-_) in the password.
    Default is $true.

    .EXAMPLE
    $securePassword = New-SecureRandomPassword -Length 32
    # Creates a 32-character SecureString password

    .EXAMPLE
    $securePassword = New-SecureRandomPassword -Length 20 -IncludeSpecialChars $false
    # Creates a 20-character alphanumeric-only SecureString password

    .OUTPUTS
    System.Security.SecureString - The generated secure password

    .NOTES
    SECURITY: This function never creates a plain text string containing the
    complete password. Each character is added directly to the SecureString.

    The password character set includes:
    - Lowercase letters (a-z)
    - Uppercase letters (A-Z)
    - Digits (0-9)
    - Special characters (!@#$%^&*-_) if IncludeSpecialChars is true
    #>
    [CmdletBinding()]
    [OutputType([SecureString])]
    param(
        [Parameter(Mandatory = $false)]
        [ValidateRange(16, 128)]
        [int]$Length = 32,

        [Parameter(Mandatory = $false)]
        [bool]$IncludeSpecialChars = $true
    )

    # Build character set
    $lowercase = 'abcdefghijklmnopqrstuvwxyz'
    $uppercase = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
    $digits = '0123456789'
    $special = '!@#$%^&*-_'

    $charSet = $lowercase + $uppercase + $digits
    if ($IncludeSpecialChars) {
        $charSet += $special
    }
    $charArray = $charSet.ToCharArray()
    $charCount = $charArray.Length

    # Create SecureString
    $securePassword = New-Object System.Security.SecureString

    # Use cryptographically secure random number generator
    $rng = [System.Security.Cryptography.RNGCryptoServiceProvider]::new()
    try {
        $bytes = New-Object byte[] 4

        for ($i = 0; $i -lt $Length; $i++) {
            # Generate cryptographically random index
            $rng.GetBytes($bytes)
            $randomIndex = [Math]::Abs([BitConverter]::ToInt32($bytes, 0)) % $charCount

            # Add character directly to SecureString (never in plain text variable)
            $securePassword.AppendChar($charArray[$randomIndex])
        }

        # Make SecureString read-only for security
        $securePassword.MakeReadOnly()

        $securePassword
    }
    finally {
        # Dispose of RNG
        $rng.Dispose()
    }
}

function ConvertFrom-SecureStringToPlainText {
    <#
    .SYNOPSIS
    Converts a SecureString to plain text with proper cleanup.

    .DESCRIPTION
    Safely converts a SecureString to plain text for scenarios where plain
    text is unavoidable (e.g., writing credentials to a configuration file
    for use in WinPE which cannot use SecureString).

    IMPORTANT: Use this function sparingly. The plain text password will
    exist in memory and should be cleared as soon as possible.

    .PARAMETER SecureString
    The SecureString to convert.

    .EXAMPLE
    $plainText = ConvertFrom-SecureStringToPlainText -SecureString $securePassword
    try {
        # Use $plainText...
    }
    finally {
        Clear-PlainTextPassword -PasswordVariable ([ref]$plainText)
    }

    .OUTPUTS
    System.String - The plain text password

    .NOTES
    SECURITY WARNING: The returned plain text password should be:
    1. Used immediately
    2. Cleared from memory using Clear-PlainTextPassword as soon as possible
    3. Never logged or displayed
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [SecureString]$SecureString
    )

    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString)
    try {
        [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    }
    finally {
        # Zero out and free the BSTR
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

function Clear-PlainTextPassword {
    <#
    .SYNOPSIS
    Clears a plain text password variable from memory.

    .DESCRIPTION
    Attempts to clear a plain text password from memory by overwriting the
    string variable with null. While .NET string immutability means the
    original string may still exist in memory until garbage collected, this
    removes the direct reference and signals intent.

    For best security, call [GC]::Collect() after clearing sensitive data
    in security-critical scenarios.

    .PARAMETER PasswordVariable
    A reference to the string variable to clear.

    .EXAMPLE
    $plainPassword = "sensitive"
    # ... use password ...
    Clear-PlainTextPassword -PasswordVariable ([ref]$plainPassword)

    .NOTES
    Due to .NET string immutability, the actual string data may persist in
    memory until garbage collection. This function provides defense in depth
    by removing the variable reference immediately.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ref]$PasswordVariable
    )

    if ($null -ne $PasswordVariable.Value) {
        $PasswordVariable.Value = $null
    }
}

function Remove-SecureStringFromMemory {
    <#
    .SYNOPSIS
    Properly disposes of a SecureString and clears the variable.

    .DESCRIPTION
    Disposes of a SecureString to release its protected memory and sets
    the variable to null.

    .PARAMETER SecureStringVariable
    A reference to the SecureString variable to dispose.

    .EXAMPLE
    $securePassword = New-SecureRandomPassword
    # ... use password ...
    Remove-SecureStringFromMemory -SecureStringVariable ([ref]$securePassword)

    .NOTES
    Always call this function in a finally block to ensure cleanup even
    if an exception occurs.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ref]$SecureStringVariable
    )

    if ($null -ne $SecureStringVariable.Value -and $SecureStringVariable.Value -is [SecureString]) {
        try {
            $SecureStringVariable.Value.Dispose()
        }
        catch {
            # Ignore disposal errors
        }
        $SecureStringVariable.Value = $null
    }
}

# =============================================================================
# Configuration Schema Validation
# Provides JSON Schema validation for FFU Builder configuration files
# =============================================================================

function Test-FFUConfiguration {
    <#
    .SYNOPSIS
    Validates an FFU Builder configuration file against the JSON schema.

    .DESCRIPTION
    Performs comprehensive validation of FFU Builder configuration files, checking:
    - JSON syntax validity
    - Property types (string, boolean, integer, object)
    - Enum values (WindowsSKU, WindowsArch, Make, etc.)
    - Numeric ranges (Memory, Disksize, Processors, etc.)
    - String patterns (ShareName, Username, IP addresses, etc.)
    - Unknown properties detection
    - Required vs optional property handling

    Returns a validation result object containing IsValid status, errors, warnings,
    and the parsed configuration.

    .PARAMETER ConfigPath
    Path to the JSON configuration file to validate. File must exist.

    .PARAMETER ConfigObject
    Hashtable containing configuration properties to validate directly.

    .PARAMETER SchemaPath
    Optional path to a custom JSON schema file. If not specified, uses the default
    schema at config/ffubuilder-config.schema.json relative to the module.

    .PARAMETER ThrowOnError
    If specified, throws an exception on validation failure instead of returning
    the validation result object.

    .EXAMPLE
    $result = Test-FFUConfiguration -ConfigPath "C:\FFU\config\my-config.json"
    if ($result.IsValid) {
        Write-Output "Configuration is valid"
    } else {
        $result.Errors | ForEach-Object { Write-Error $_ }
    }

    .EXAMPLE
    $config = @{
        WindowsSKU = "Pro"
        WindowsRelease = 11
        Memory = 8GB
    }
    $result = Test-FFUConfiguration -ConfigObject $config

    .EXAMPLE
    # Throws exception on validation failure
    Test-FFUConfiguration -ConfigPath "config.json" -ThrowOnError

    .OUTPUTS
    PSCustomObject with properties:
    - IsValid: [bool] True if configuration passes all validation rules
    - Errors: [string[]] Array of validation error messages
    - Warnings: [string[]] Array of validation warning messages (deprecated properties, etc.)
    - Config: [hashtable] Parsed configuration object (null if JSON parsing failed)

    .NOTES
    Version: 1.0.0
    Introduced in FFU.Core v1.0.10

    The validation is performed in PowerShell without external dependencies.
    JSON Schema is parsed and validation rules are applied programmatically.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [ValidateScript({ Test-Path $_ -PathType Leaf })]
        [string]$ConfigPath,

        [Parameter(Mandatory = $true, ParameterSetName = 'Object')]
        [hashtable]$ConfigObject,

        [Parameter(Mandatory = $false)]
        [string]$SchemaPath,

        [Parameter(Mandatory = $false)]
        [switch]$ThrowOnError
    )

    # Initialize result object
    $result = [PSCustomObject]@{
        IsValid  = $false
        Errors   = [System.Collections.Generic.List[string]]::new()
        Warnings = [System.Collections.Generic.List[string]]::new()
        Config   = $null
    }

    # Helper function to add error
    function Add-ValidationError {
        param([string]$Message)
        $result.Errors.Add($Message)
    }

    # Helper function to add warning
    function Add-ValidationWarning {
        param([string]$Message)
        $result.Warnings.Add($Message)
    }

    # Load schema
    $schema = $null
    try {
        if ([string]::IsNullOrWhiteSpace($SchemaPath)) {
            # Default schema location relative to module
            $moduleRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
            $SchemaPath = Join-Path $moduleRoot "config\ffubuilder-config.schema.json"
        }

        if (-not (Test-Path -Path $SchemaPath -PathType Leaf)) {
            Add-ValidationError "Schema file not found: $SchemaPath"
            if ($ThrowOnError) {
                throw "Configuration validation failed: Schema file not found at $SchemaPath"
            }
            $result
            return
        }

        $schemaContent = Get-Content -Path $SchemaPath -Raw -ErrorAction Stop
        $schema = $schemaContent | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Add-ValidationError "Failed to load schema: $($_.Exception.Message)"
        if ($ThrowOnError) {
            throw "Configuration validation failed: $($_.Exception.Message)"
        }
        $result
        return
    }

    # Load configuration
    $config = $null
    try {
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            $configContent = Get-Content -Path $ConfigPath -Raw -ErrorAction Stop
            $configPSObject = $configContent | ConvertFrom-Json -ErrorAction Stop

            # Convert PSCustomObject to hashtable for easier processing
            $config = @{}
            foreach ($prop in $configPSObject.PSObject.Properties) {
                if ($prop.Value -is [System.Management.Automation.PSCustomObject]) {
                    # Convert nested objects to hashtable
                    $nested = @{}
                    foreach ($nestedProp in $prop.Value.PSObject.Properties) {
                        $nested[$nestedProp.Name] = $nestedProp.Value
                    }
                    $config[$prop.Name] = $nested
                }
                else {
                    $config[$prop.Name] = $prop.Value
                }
            }
        }
        else {
            $config = $ConfigObject
        }
        $result.Config = $config
    }
    catch {
        Add-ValidationError "Failed to parse configuration JSON: $($_.Exception.Message)"
        if ($ThrowOnError) {
            throw "Configuration validation failed: Invalid JSON - $($_.Exception.Message)"
        }
        $result
        return
    }

    # Get schema properties
    $schemaProperties = @{}
    if ($schema.properties) {
        foreach ($prop in $schema.properties.PSObject.Properties) {
            $schemaProperties[$prop.Name] = $prop.Value
        }
    }

    # Validate each property in config
    foreach ($key in $config.Keys) {
        # Skip metadata properties
        if ($key -eq '$schema' -or $key -eq '_comment') {
            continue
        }

        $value = $config[$key]
        $schemaProp = $schemaProperties[$key]

        # Check for unknown properties
        if ($null -eq $schemaProp) {
            if ($schema.additionalProperties -eq $false) {
                Add-ValidationError "Unknown property '$key' is not allowed in configuration"
            }
            else {
                Add-ValidationWarning "Unknown property '$key' - not defined in schema"
            }
            continue
        }

        # Check for deprecated properties (warn but allow)
        if ($schemaProp.deprecated -eq $true) {
            $deprecationMsg = "Property '$key' is deprecated"
            if ($schemaProp.description -and $schemaProp.description -match '\[DEPRECATED\](.+?)(?:This property is ignored|$)') {
                $deprecationMsg = "Property '$key' is deprecated: $($Matches[1].Trim())"
            }
            Add-ValidationWarning $deprecationMsg
            # Continue validation - deprecated properties still need valid values
        }

        # Skip null values (optional properties)
        if ($null -eq $value) {
            continue
        }

        # Validate type
        $expectedType = $schemaProp.type
        $actualType = $null

        # Handle oneOf for nullable types
        if ($null -eq $expectedType -and $schemaProp.oneOf) {
            $oneOfTypes = @()
            foreach ($oneOf in $schemaProp.oneOf) {
                if ($oneOf.type) {
                    $oneOfTypes += $oneOf.type
                }
            }
            # Check if value matches any of the allowed types
            $typeMatched = $false
            foreach ($oneOfType in $oneOfTypes) {
                if ($oneOfType -eq 'null' -and $null -eq $value) {
                    $typeMatched = $true
                    break
                }
                elseif ($oneOfType -eq 'object' -and ($value -is [hashtable] -or $value -is [System.Management.Automation.PSCustomObject])) {
                    $typeMatched = $true
                    break
                }
            }
            if (-not $typeMatched -and $null -ne $value) {
                # If not null, treat as object type for hashtable validation
                if ($value -is [hashtable] -or $value -is [System.Management.Automation.PSCustomObject]) {
                    $expectedType = 'object'
                }
            }
            else {
                continue  # Value matches oneOf, skip further validation
            }
        }

        # Determine actual type
        if ($value -is [bool]) {
            $actualType = 'boolean'
        }
        elseif ($value -is [int] -or $value -is [int64] -or $value -is [uint32] -or $value -is [uint64] -or $value -is [double]) {
            $actualType = 'integer'
        }
        elseif ($value -is [string]) {
            $actualType = 'string'
        }
        elseif ($value -is [hashtable] -or $value -is [System.Management.Automation.PSCustomObject]) {
            $actualType = 'object'
        }
        elseif ($value -is [array]) {
            $actualType = 'array'
        }

        # Type validation
        if ($expectedType -and $actualType -ne $expectedType) {
            # Allow integer for numeric strings
            if ($expectedType -eq 'integer' -and $actualType -eq 'string') {
                $intValue = 0
                if (-not [int64]::TryParse($value, [ref]$intValue)) {
                    Add-ValidationError "Property '$key' has type '$actualType' but expected '$expectedType'"
                }
                else {
                    # Update value to parsed integer for range validation
                    $value = $intValue
                }
            }
            # Allow string for numbers (for flexibility)
            elseif ($expectedType -eq 'string' -and $actualType -eq 'integer') {
                # Convert to string for pattern validation
                $value = $value.ToString()
            }
            else {
                Add-ValidationError "Property '$key' has type '$actualType' but expected '$expectedType'"
                continue
            }
        }

        # Enum validation
        if ($schemaProp.enum) {
            $enumValues = @($schemaProp.enum)
            if ($enumValues -notcontains $value) {
                $validValues = $enumValues -join ', '
                Add-ValidationError "Property '$key' has invalid value '$value'. Valid values are: $validValues"
            }
        }

        # Range validation for integers
        if ($expectedType -eq 'integer') {
            if ($null -ne $schemaProp.minimum -and $value -lt $schemaProp.minimum) {
                Add-ValidationError "Property '$key' value $value is less than minimum $($schemaProp.minimum)"
            }
            if ($null -ne $schemaProp.maximum -and $value -gt $schemaProp.maximum) {
                Add-ValidationError "Property '$key' value $value is greater than maximum $($schemaProp.maximum)"
            }
        }

        # Pattern validation for strings
        if ($expectedType -eq 'string' -and $schemaProp.pattern) {
            $pattern = $schemaProp.pattern
            if ($value -notmatch $pattern) {
                Add-ValidationError "Property '$key' value '$value' does not match required pattern: $pattern"
            }
        }
    }

    # Set final validity
    $result.IsValid = ($result.Errors.Count -eq 0)

    # Throw if requested and validation failed
    if ($ThrowOnError -and -not $result.IsValid) {
        $errorSummary = $result.Errors -join "`n  - "
        throw "Configuration validation failed with $($result.Errors.Count) error(s):`n  - $errorSummary"
    }

    $result
}

function Get-FFUConfigurationSchema {
    <#
    .SYNOPSIS
    Returns the path to the FFU Builder configuration schema file.

    .DESCRIPTION
    Returns the full path to the default FFU Builder JSON schema file.
    Useful for referencing the schema in configuration files or for
    programmatic schema access.

    .EXAMPLE
    $schemaPath = Get-FFUConfigurationSchema
    Write-Output "Schema located at: $schemaPath"

    .OUTPUTS
    System.String - Full path to the schema file
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $moduleRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Join-Path -Path $moduleRoot -ChildPath "config\ffubuilder-config.schema.json"
}

# =============================================================================
# Cleanup Registration System
# Provides automatic resource cleanup on script failure or termination
# =============================================================================

# Script-scoped cleanup registry - stores cleanup actions in LIFO order
$script:CleanupRegistry = [System.Collections.Generic.List[PSCustomObject]]::new()

function Register-CleanupAction {
    <#
    .SYNOPSIS
    Registers a cleanup action to be executed on failure or script termination.

    .DESCRIPTION
    Adds a cleanup action to the registry. Actions are executed in reverse order
    (LIFO - Last In First Out) when Invoke-FailureCleanup is called.

    .PARAMETER Name
    A descriptive name for the cleanup action (for logging).

    .PARAMETER Action
    ScriptBlock containing the cleanup code.

    .PARAMETER ResourceType
    Type of resource being tracked (VM, VHDX, DISM, ISO, TempFile, BITS, Share, User).

    .PARAMETER ResourceId
    Identifier for the resource (e.g., VM name, file path).

    .EXAMPLE
    Register-CleanupAction -Name "Remove Build VM" -ResourceType "VM" -ResourceId "FFU_Build" -Action {
        Stop-VM -Name "FFU_Build" -Force -TurnOff -ErrorAction SilentlyContinue
        Remove-VM -Name "FFU_Build" -Force -ErrorAction SilentlyContinue
    }

    .OUTPUTS
    [string] Returns a unique ID for the cleanup action (can be used to unregister).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [scriptblock]$Action,

        [Parameter(Mandatory = $false)]
        [ValidateSet('VM', 'VHDX', 'DISM', 'ISO', 'TempFile', 'BITS', 'Share', 'User', 'Other')]
        [string]$ResourceType = 'Other',

        [Parameter(Mandatory = $false)]
        [string]$ResourceId = ''
    )

    $cleanupId = [Guid]::NewGuid().ToString()

    $entry = [PSCustomObject]@{
        Id           = $cleanupId
        Name         = $Name
        ResourceType = $ResourceType
        ResourceId   = $ResourceId
        Action       = $Action
        RegisteredAt = Get-Date
    }

    $script:CleanupRegistry.Add($entry)

    # Safe logging
    if (Get-Command WriteLog -ErrorAction SilentlyContinue) {
        WriteLog "Registered cleanup action: $Name (Type: $ResourceType, Id: $ResourceId)"
    }

    $cleanupId
}

function Unregister-CleanupAction {
    <#
    .SYNOPSIS
    Removes a cleanup action from the registry.

    .DESCRIPTION
    Call this after a resource has been successfully cleaned up normally,
    to prevent duplicate cleanup attempts.

    .PARAMETER CleanupId
    The ID returned by Register-CleanupAction.

    .OUTPUTS
    System.Boolean - True if the entry was found and removed, False otherwise.

    .EXAMPLE
    $cleanupId = Register-CleanupAction -Name "Mount Point" -Action { ... }
    # ... do work ...
    Dismount-WindowsImage -Path $mountPath -Save
    Unregister-CleanupAction -CleanupId $cleanupId
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$CleanupId
    )

    $entry = $script:CleanupRegistry | Where-Object { $_.Id -eq $CleanupId }
    if ($entry) {
        $script:CleanupRegistry.Remove($entry) | Out-Null
        if (Get-Command WriteLog -ErrorAction SilentlyContinue) {
            WriteLog "Unregistered cleanup action: $($entry.Name)"
        }
        $true
        return
    }
    $false
}

function Invoke-FailureCleanup {
    <#
    .SYNOPSIS
    Executes all registered cleanup actions in reverse order (LIFO).

    .DESCRIPTION
    Should be called from catch blocks or trap handlers when a failure occurs.
    Runs all cleanup actions and logs results. Does not throw on cleanup errors.

    .PARAMETER Reason
    Description of why cleanup is being invoked.

    .PARAMETER ResourceType
    Optional - only cleanup resources of this type.

    .EXAMPLE
    catch {
        Invoke-FailureCleanup -Reason "Build failed: $($_.Exception.Message)"
        throw
    }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Reason = "Unspecified failure",

        [Parameter(Mandatory = $false)]
        [ValidateSet('VM', 'VHDX', 'DISM', 'ISO', 'TempFile', 'BITS', 'Share', 'User', 'Other', 'All')]
        [string]$ResourceType = 'All'
    )

    # Safe logging helper (Write-Verbose fallback for background job compatibility)
    $log = {
        param([string]$Message)
        if (Get-Command WriteLog -ErrorAction SilentlyContinue) {
            WriteLog $Message
        } else {
            Write-Verbose $Message
        }
    }

    & $log "=========================================="
    & $log "FAILURE CLEANUP INITIATED"
    & $log "Reason: $Reason"
    & $log "Registered actions: $($script:CleanupRegistry.Count)"
    & $log "=========================================="

    if ($script:CleanupRegistry.Count -eq 0) {
        & $log "No cleanup actions registered."
        return
    }

    # Filter by resource type if specified
    $actionsToRun = if ($ResourceType -eq 'All') {
        $script:CleanupRegistry
    } else {
        $script:CleanupRegistry | Where-Object { $_.ResourceType -eq $ResourceType }
    }

    # Run in reverse order (LIFO)
    $reversedActions = @($actionsToRun)
    [Array]::Reverse($reversedActions)

    $successCount = 0
    $failCount = 0

    foreach ($entry in $reversedActions) {
        & $log "Cleanup: $($entry.Name) (Type: $($entry.ResourceType))"
        try {
            & $entry.Action
            $successCount++
            & $log "  [SUCCESS] $($entry.Name)"

            # Remove from registry after successful cleanup
            $script:CleanupRegistry.Remove($entry) | Out-Null
        }
        catch {
            $failCount++
            & $log "  [FAILED] $($entry.Name): $($_.Exception.Message)"
            # Don't remove failed cleanups - might need manual intervention
        }
    }

    & $log "=========================================="
    & $log "CLEANUP COMPLETE: $successCount succeeded, $failCount failed"
    & $log "=========================================="
}

function Test-BuildCancellation {
    <#
    .SYNOPSIS
    Checks if cancellation was requested and handles cleanup if so.

    .DESCRIPTION
    Should be called at major phase boundaries in BuildFFUVM.ps1 to check
    if the user has requested build cancellation. Returns $true if cancelled
    (caller should return early).

    This function provides a consistent pattern for cancellation checking
    that includes logging, UI notification, and optional cleanup invocation.

    .PARAMETER MessagingContext
    The synchronized messaging context from FFU.Messaging. If $null (CLI mode),
    the function returns $false immediately since cancellation is not supported.

    .PARAMETER PhaseName
    Name of the current build phase (for logging and cleanup reason).

    .PARAMETER InvokeCleanup
    If specified, calls Invoke-FailureCleanup and sets build state to Cancelled
    when cancellation is detected.

    .EXAMPLE
    # Check cancellation without cleanup (just returns status)
    if (Test-BuildCancellation -MessagingContext $MessagingContext -PhaseName "Driver Download") {
        return
    }

    .EXAMPLE
    # Check cancellation with automatic cleanup
    if (Test-BuildCancellation -MessagingContext $MessagingContext -PhaseName "VHDX Creation" -InvokeCleanup) {
        return
    }

    .EXAMPLE
    # CLI mode (no messaging context) - always returns false
    $result = Test-BuildCancellation -MessagingContext $null -PhaseName "Test"
    # $result is $false

    .OUTPUTS
    System.Boolean
    Returns $true if cancellation was requested, $false otherwise.

    .NOTES
    Requires FFU.Messaging module for Test-FFUCancellationRequested, Write-FFUWarning,
    and Set-FFUBuildState functions. These are called only when MessagingContext is provided.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter()]
        [hashtable]$MessagingContext,

        [Parameter(Mandatory)]
        [string]$PhaseName,

        [Parameter()]
        [switch]$InvokeCleanup
    )

    # No messaging context = no cancellation support (CLI mode)
    if ($null -eq $MessagingContext) {
        return $false
    }

    # Check if cancellation was requested via FFU.Messaging
    $cancellationRequested = $false
    if (Get-Command Test-FFUCancellationRequested -ErrorAction SilentlyContinue) {
        $cancellationRequested = Test-FFUCancellationRequested -Context $MessagingContext
    }

    if (-not $cancellationRequested) {
        return $false
    }

    # Cancellation was requested - log and notify
    # Safe logging helper (Write-Verbose fallback for background job compatibility)
    if (Get-Command WriteLog -ErrorAction SilentlyContinue) {
        WriteLog "Cancellation detected at phase: $PhaseName"
    } else {
        Write-Verbose "Cancellation detected at phase: $PhaseName"
    }

    # Send warning to UI if FFU.Messaging functions available
    if (Get-Command Write-FFUWarning -ErrorAction SilentlyContinue) {
        Write-FFUWarning -Context $MessagingContext `
            -Message "Build cancellation requested at: $PhaseName" `
            -Source 'BuildFFUVM'
    }

    # Invoke cleanup if requested
    if ($InvokeCleanup) {
        Invoke-FailureCleanup -Reason "User cancelled build at: $PhaseName"

        if (Get-Command Set-FFUBuildState -ErrorAction SilentlyContinue) {
            Set-FFUBuildState -Context $MessagingContext -State Cancelled -SendMessage
        }
    }

    return $true
}

function Clear-CleanupRegistry {
    <#
    .SYNOPSIS
    Clears all registered cleanup actions.

    .DESCRIPTION
    Call this at the end of a successful script run to clear the registry.
    #>
    [CmdletBinding()]
    param()

    $count = $script:CleanupRegistry.Count
    $script:CleanupRegistry.Clear()

    if (Get-Command WriteLog -ErrorAction SilentlyContinue) {
        WriteLog "Cleared cleanup registry ($count actions removed)"
    }
}

function Get-CleanupRegistry {
    <#
    .SYNOPSIS
    Returns the current cleanup registry for inspection.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param()

    @($script:CleanupRegistry)
}

# =============================================================================
# Specialized Cleanup Registration Functions
# Convenience functions for common resource types
# =============================================================================

function Register-VMCleanup {
    <#
    .SYNOPSIS
    Registers cleanup for a Hyper-V VM.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$VMName
    )

    Register-CleanupAction -Name "Stop and remove VM: $VMName" -ResourceType 'VM' -ResourceId $VMName -Action {
        $vm = Get-VM -Name $using:VMName -ErrorAction SilentlyContinue
        if ($vm) {
            if ($vm.State -ne 'Off') {
                Stop-VM -Name $using:VMName -Force -TurnOff -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 2
            }
            Remove-VM -Name $using:VMName -Force -ErrorAction SilentlyContinue
        }
        # Also try to remove HGS Guardian if it exists
        Remove-HgsGuardian -Name $using:VMName -ErrorAction SilentlyContinue
    }.GetNewClosure()
}

function Register-VHDXCleanup {
    <#
    .SYNOPSIS
    Registers cleanup for a mounted VHDX file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$VHDXPath
    )

    Register-CleanupAction -Name "Dismount VHDX: $VHDXPath" -ResourceType 'VHDX' -ResourceId $VHDXPath -Action {
        $vhd = Get-VHD -Path $using:VHDXPath -ErrorAction SilentlyContinue
        if ($vhd -and $vhd.Attached) {
            Dismount-VHD -Path $using:VHDXPath -ErrorAction SilentlyContinue
        }
    }.GetNewClosure()
}

function Register-DISMMountCleanup {
    <#
    .SYNOPSIS
    Registers cleanup for a DISM mount point.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$MountPath
    )

    Register-CleanupAction -Name "Dismount DISM image: $MountPath" -ResourceType 'DISM' -ResourceId $MountPath -Action {
        # Try to dismount gracefully first
        try {
            Dismount-WindowsImage -Path $using:MountPath -Discard -ErrorAction Stop | Out-Null
        }
        catch {
            # If that fails, run DISM cleanup
            & dism.exe /Cleanup-Mountpoints 2>&1 | Out-Null
        }
    }.GetNewClosure()
}

function Register-ISOCleanup {
    <#
    .SYNOPSIS
    Registers cleanup for a mounted ISO image.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ISOPath
    )

    Register-CleanupAction -Name "Dismount ISO: $ISOPath" -ResourceType 'ISO' -ResourceId $ISOPath -Action {
        Dismount-DiskImage -ImagePath $using:ISOPath -ErrorAction SilentlyContinue | Out-Null
    }.GetNewClosure()
}

function Register-TempFileCleanup {
    <#
    .SYNOPSIS
    Registers cleanup for temporary files or directories.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [switch]$Recurse
    )

    $desc = if ($Recurse) { "Remove temp directory: $Path" } else { "Remove temp file: $Path" }

    Register-CleanupAction -Name $desc -ResourceType 'TempFile' -ResourceId $Path -Action {
        if (Test-Path $using:Path) {
            Remove-Item -Path $using:Path -Force -Recurse:$using:Recurse -ErrorAction SilentlyContinue
        }
    }.GetNewClosure()
}

function Register-NetworkShareCleanup {
    <#
    .SYNOPSIS
    Registers cleanup for a network share.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ShareName
    )

    Register-CleanupAction -Name "Remove share: $ShareName" -ResourceType 'Share' -ResourceId $ShareName -Action {
        Remove-SmbShare -Name $using:ShareName -Force -ErrorAction SilentlyContinue
    }.GetNewClosure()
}

function Register-UserAccountCleanup {
    <#
    .SYNOPSIS
    Registers cleanup for a local user account.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Username
    )

    Register-CleanupAction -Name "Remove user: $Username" -ResourceType 'User' -ResourceId $Username -Action {
        # Use DirectoryServices API for cross-version compatibility
        try {
            $context = New-Object System.DirectoryServices.AccountManagement.PrincipalContext([System.DirectoryServices.AccountManagement.ContextType]::Machine)
            $user = [System.DirectoryServices.AccountManagement.UserPrincipal]::FindByIdentity($context, $using:Username)
            if ($user) {
                $user.Delete()
                $user.Dispose()
            }
            $context.Dispose()
        }
        catch {
            # Ignore errors - user may not exist
        }
    }.GetNewClosure()
}

function Register-SensitiveMediaCleanup {
    <#
    .SYNOPSIS
    Registers cleanup for sensitive capture media files containing credentials.

    .DESCRIPTION
    When credentials are written to CaptureFFU.ps1, backup files may be created
    that contain plain-text passwords. If the build fails before Remove-SensitiveCaptureMedia
    runs, these files could persist. This cleanup action ensures they are removed.

    .PARAMETER FFUDevelopmentPath
    Path to the FFU development folder containing WinPECaptureFFUFiles.

    .EXAMPLE
    Register-SensitiveMediaCleanup -FFUDevelopmentPath "C:\FFUDevelopment"

    .NOTES
    SECURITY: Critical for preventing credential leakage on build failures.
    Should be registered immediately after Update-CaptureFFUScript is called.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FFUDevelopmentPath
    )

    Register-CleanupAction -Name "Remove sensitive capture media backups" -ResourceType 'TempFile' -ResourceId "CaptureFFU-Backups" -Action {
        $captureFilesPath = Join-Path $using:FFUDevelopmentPath "WinPECaptureFFUFiles"

        # Remove backup files that may contain credentials
        $backupPattern = Join-Path $captureFilesPath "CaptureFFU.ps1.backup-*"
        $backupFiles = Get-ChildItem -Path $backupPattern -ErrorAction SilentlyContinue

        foreach ($backup in $backupFiles) {
            try {
                Remove-Item -Path $backup.FullName -Force -ErrorAction Stop
            }
            catch {
                # Log but don't fail - best effort cleanup
            }
        }

        # Also sanitize the main CaptureFFU.ps1 if it exists
        $captureScript = Join-Path $captureFilesPath "CaptureFFU.ps1"
        if (Test-Path $captureScript) {
            try {
                $content = Get-Content -Path $captureScript -Raw -ErrorAction SilentlyContinue
                if ($content -and $content -match '\$Password\s*=\s*[''"](?!YOURPASSWORDHERE)[^''"]+[''"]') {
                    # Password found - sanitize it
                    $sanitized = $content -replace '(\$Password\s*=\s*[''"])[^''"]+([''"])', '$1YOURPASSWORDHERE$2'
                    Set-Content -Path $captureScript -Value $sanitized -Force -ErrorAction SilentlyContinue
                }
            }
            catch {
                # Log but don't fail - best effort cleanup
            }
        }
    }.GetNewClosure()
}

# ============================================================================
# Script Integrity Verification Functions (v1.0.15 - SEC-03)
# ============================================================================

function Test-ScriptIntegrity {
    <#
    .SYNOPSIS
    Verifies script integrity against expected SHA-256 hash

    .DESCRIPTION
    Calculates SHA-256 hash of a script file and compares against expected hash
    from manifest or parameter. Returns $true if match, $false if mismatch.
    Used to detect tampering of orchestration scripts before execution.

    .PARAMETER ScriptPath
    Full path to the script file to verify

    .PARAMETER ExpectedHash
    Optional - direct hash to compare against (overrides manifest lookup)

    .PARAMETER ManifestPath
    Optional - path to JSON manifest file containing expected hashes

    .PARAMETER FailOnMismatch
    If $true (default), logs ERROR on mismatch. If $false, logs WARNING.

    .EXAMPLE
    Test-ScriptIntegrity -ScriptPath "C:\Apps\Orchestrator.ps1" -ManifestPath "C:\FFU\.security\orchestration-hashes.json"

    .OUTPUTS
    [bool] $true if hash matches or no hash available, $false if mismatch

    .NOTES
    Added in v1.0.15 for SEC-03 (Script Integrity Verification)
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path $_ -PathType Leaf })]
        [string]$ScriptPath,

        [Parameter(Mandatory = $false)]
        [string]$ExpectedHash,

        [Parameter(Mandatory = $false)]
        [string]$ManifestPath,

        [Parameter(Mandatory = $false)]
        [bool]$FailOnMismatch = $true
    )

    # Calculate actual hash
    $actualHash = (Get-FileHash -Path $ScriptPath -Algorithm SHA256).Hash

    # Get expected hash from manifest if not provided directly
    if ([string]::IsNullOrEmpty($ExpectedHash) -and -not [string]::IsNullOrEmpty($ManifestPath)) {
        if (Test-Path $ManifestPath) {
            try {
                $manifest = Get-Content $ManifestPath -Raw | ConvertFrom-Json
                $scriptName = [System.IO.Path]::GetFileName($ScriptPath)
                $ExpectedHash = $manifest.scripts.$scriptName
            }
            catch {
                # Safe logging - use WriteLog if available, otherwise Write-Verbose
                if (Get-Command -Name 'WriteLog' -ErrorAction SilentlyContinue) {
                    WriteLog "WARNING: Failed to read hash manifest: $($_.Exception.Message)"
                }
                else {
                    Write-Verbose "WARNING: Failed to read hash manifest: $($_.Exception.Message)"
                }
            }
        }
        else {
            if (Get-Command -Name 'WriteLog' -ErrorAction SilentlyContinue) {
                WriteLog "WARNING: Hash manifest not found at $ManifestPath"
            }
            else {
                Write-Verbose "WARNING: Hash manifest not found at $ManifestPath"
            }
        }
    }

    # If no expected hash available, log and return based on strict mode
    if ([string]::IsNullOrEmpty($ExpectedHash)) {
        if (Get-Command -Name 'WriteLog' -ErrorAction SilentlyContinue) {
            WriteLog "WARNING: No expected hash for $(Split-Path $ScriptPath -Leaf) - skipping verification"
        }
        else {
            Write-Verbose "WARNING: No expected hash for $(Split-Path $ScriptPath -Leaf) - skipping verification"
        }
        return $true  # Permissive mode - allow execution when no hash available
    }

    # Compare hashes
    if ($actualHash -eq $ExpectedHash) {
        if (Get-Command -Name 'WriteLog' -ErrorAction SilentlyContinue) {
            WriteLog "SECURITY: Verified integrity of $(Split-Path $ScriptPath -Leaf)"
        }
        else {
            Write-Verbose "SECURITY: Verified integrity of $(Split-Path $ScriptPath -Leaf)"
        }
        return $true
    }
    else {
        $logLevel = if ($FailOnMismatch) { "ERROR" } else { "WARNING" }
        $message = "$logLevel`: Hash mismatch for $(Split-Path $ScriptPath -Leaf)"
        if (Get-Command -Name 'WriteLog' -ErrorAction SilentlyContinue) {
            WriteLog $message
            WriteLog "  Expected: $ExpectedHash"
            WriteLog "  Actual:   $actualHash"
        }
        else {
            Write-Verbose $message
            Write-Verbose "  Expected: $ExpectedHash"
            Write-Verbose "  Actual:   $actualHash"
        }
        return $false
    }
}

function New-OrchestrationHashManifest {
    <#
    .SYNOPSIS
    Generates hash manifest for all orchestration scripts

    .DESCRIPTION
    Calculates SHA-256 hashes for all .ps1 files in the orchestration folder
    and writes them to a JSON manifest file. Used to establish baseline
    integrity hashes for script verification.

    .PARAMETER OrchestrationPath
    Path to the Apps/Orchestration folder

    .PARAMETER ManifestPath
    Output path for the manifest JSON file

    .EXAMPLE
    New-OrchestrationHashManifest -OrchestrationPath "C:\FFU\Apps\Orchestration" -ManifestPath "C:\FFU\.security\orchestration-hashes.json"

    .OUTPUTS
    [hashtable] The generated manifest object

    .NOTES
    Added in v1.0.15 for SEC-03 (Script Integrity Verification)
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path $_ -PathType Container })]
        [string]$OrchestrationPath,

        [Parameter(Mandatory = $true)]
        [string]$ManifestPath
    )

    $scripts = Get-ChildItem -Path $OrchestrationPath -Filter "*.ps1" -File
    $manifest = @{
        generated = (Get-Date).ToString('o')
        algorithm = 'SHA256'
        version   = '1.0.0'
        scripts   = @{}
    }

    foreach ($script in $scripts) {
        $hash = (Get-FileHash -Path $script.FullName -Algorithm SHA256).Hash
        $manifest.scripts[$script.Name] = $hash
        if (Get-Command -Name 'WriteLog' -ErrorAction SilentlyContinue) {
            WriteLog "Hashed $($script.Name): $hash"
        }
        else {
            Write-Verbose "Hashed $($script.Name): $hash"
        }
    }

    # Ensure directory exists
    $manifestDir = Split-Path $ManifestPath -Parent
    if (-not (Test-Path $manifestDir)) {
        New-Item -Path $manifestDir -ItemType Directory -Force | Out-Null
    }

    $manifest | ConvertTo-Json -Depth 3 | Set-Content -Path $ManifestPath -Encoding UTF8
    if (Get-Command -Name 'WriteLog' -ErrorAction SilentlyContinue) {
        WriteLog "Generated manifest at $ManifestPath with $($scripts.Count) scripts"
    }
    else {
        Write-Verbose "Generated manifest at $ManifestPath with $($scripts.Count) scripts"
    }

    return $manifest
}

function Update-OrchestrationHashManifest {
    <#
    .SYNOPSIS
    Updates hash manifest for specific scripts (leaves others unchanged)

    .DESCRIPTION
    Recalculates hashes only for specified scripts, preserving existing hashes.
    Used when individual scripts are modified and need their hashes updated.

    .PARAMETER OrchestrationPath
    Path to the Apps/Orchestration folder

    .PARAMETER ManifestPath
    Path to the manifest JSON file

    .PARAMETER ScriptNames
    Array of script names to update (e.g., "Orchestrator.ps1")

    .EXAMPLE
    Update-OrchestrationHashManifest -OrchestrationPath "C:\FFU\Apps\Orchestration" -ManifestPath "C:\FFU\.security\orchestration-hashes.json" -ScriptNames @("Orchestrator.ps1")

    .OUTPUTS
    None

    .NOTES
    Added in v1.0.15 for SEC-03 (Script Integrity Verification)
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$OrchestrationPath,

        [Parameter(Mandatory = $true)]
        [string]$ManifestPath,

        [Parameter(Mandatory = $true)]
        [string[]]$ScriptNames
    )

    # Load existing manifest or create new
    if (Test-Path $ManifestPath) {
        $manifest = Get-Content $ManifestPath -Raw | ConvertFrom-Json -AsHashtable
    }
    else {
        $manifest = @{
            generated = (Get-Date).ToString('o')
            algorithm = 'SHA256'
            version   = '1.0.0'
            scripts   = @{}
        }
    }

    foreach ($scriptName in $ScriptNames) {
        $scriptPath = Join-Path $OrchestrationPath $scriptName
        if (Test-Path $scriptPath) {
            $hash = (Get-FileHash -Path $scriptPath -Algorithm SHA256).Hash
            $manifest.scripts[$scriptName] = $hash
            if (Get-Command -Name 'WriteLog' -ErrorAction SilentlyContinue) {
                WriteLog "Updated hash for $scriptName`: $hash"
            }
            else {
                Write-Verbose "Updated hash for $scriptName`: $hash"
            }
        }
        else {
            if (Get-Command -Name 'WriteLog' -ErrorAction SilentlyContinue) {
                WriteLog "WARNING: Script not found: $scriptPath"
            }
            else {
                Write-Verbose "WARNING: Script not found: $scriptPath"
            }
        }
    }

    $manifest.generated = (Get-Date).ToString('o')

    # Ensure directory exists
    $manifestDir = Split-Path $ManifestPath -Parent
    if (-not (Test-Path $manifestDir)) {
        New-Item -Path $manifestDir -ItemType Directory -Force | Out-Null
    }

    $manifest | ConvertTo-Json -Depth 3 | Set-Content -Path $ManifestPath -Encoding UTF8
    if (Get-Command -Name 'WriteLog' -ErrorAction SilentlyContinue) {
        WriteLog "Updated manifest at $ManifestPath"
    }
    else {
        Write-Verbose "Updated manifest at $ManifestPath"
    }
}

# Create backward compatibility aliases for renamed functions (v1.0.11)
# These aliases allow existing code to continue working while encouraging migration to approved verbs
Set-Alias -Name 'LogVariableValues' -Value 'Write-VariableValues' -Scope Script
Set-Alias -Name 'Mark-DownloadInProgress' -Value 'Set-DownloadInProgress' -Scope Script
Set-Alias -Name 'Cleanup-CurrentRunDownloads' -Value 'Clear-CurrentRunDownloads' -Scope Script

# Export all module functions
Export-ModuleMember -Function @(
    # Configuration and utilities
    'Get-Parameters'
    'Write-VariableValues'              # v1.0.11: Renamed from LogVariableValues (approved verb)
    'Get-ChildProcesses'
    'Test-Url'
    'Get-PrivateProfileString'
    'Get-PrivateProfileSection'
    'Get-ShortenedWindowsSKU'
    'New-FFUFileName'
    'Export-ConfigFile'
    # Session management
    'New-RunSession'
    'Get-CurrentRunManifest'
    'Save-RunManifest'
    'Set-DownloadInProgress'            # v1.0.11: Renamed from Mark-DownloadInProgress (approved verb)
    'Clear-DownloadInProgress'
    'Remove-InProgressItems'
    'Clear-CurrentRunDownloads'         # v1.0.11: Renamed from Cleanup-CurrentRunDownloads (approved verb)
    'Restore-RunJsonBackups'
    # Error handling (v1.0.5)
    'Invoke-WithErrorHandling'
    'Test-ExternalCommandSuccess'
    'Invoke-WithCleanup'
    # Cleanup registration system (v1.0.6)
    'Register-CleanupAction'
    'Unregister-CleanupAction'
    'Invoke-FailureCleanup'
    'Clear-CleanupRegistry'
    'Get-CleanupRegistry'
    # Specialized cleanup helpers
    'Register-VMCleanup'
    'Register-VHDXCleanup'
    'Register-DISMMountCleanup'
    'Register-ISOCleanup'
    'Register-TempFileCleanup'
    'Register-NetworkShareCleanup'
    'Register-UserAccountCleanup'
    'Register-SensitiveMediaCleanup'
    # Secure credential management (v1.0.7)
    'New-SecureRandomPassword'
    'ConvertFrom-SecureStringToPlainText'
    'Clear-PlainTextPassword'
    'Remove-SecureStringFromMemory'
    # Configuration schema validation (v1.0.10)
    'Test-FFUConfiguration'
    'Get-FFUConfigurationSchema'
    # WIM mount error handling (v1.0.13)
    'Invoke-WimMountWithErrorHandling'
    # Script integrity verification (v1.0.15 - SEC-03)
    'Test-ScriptIntegrity'
    'New-OrchestrationHashManifest'
    'Update-OrchestrationHashManifest'
)

# Export backward compatibility aliases (deprecated - use new function names)
Export-ModuleMember -Alias @(
    'LogVariableValues'                 # Deprecated: Use Write-VariableValues
    'Mark-DownloadInProgress'           # Deprecated: Use Set-DownloadInProgress
    'Cleanup-CurrentRunDownloads'       # Deprecated: Use Clear-CurrentRunDownloads
)