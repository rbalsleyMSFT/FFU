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

#Requires -Version 5.1

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
    return $filteredParamNames
}

function LogVariableValues {
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
    LogVariableValues -version "2.0.1"

    .OUTPUTS
    None - Writes variable information to log via WriteLog
    #>
    [CmdletBinding()]
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

function Get-ChildProcesses($parentId) {
    $result = @()
    $children = Get-CimInstance Win32_Process -Filter "ParentProcessId = $parentId"
    foreach ($child in $children) {
        $result += $child
        $result += Get-ChildProcesses $child.ProcessId
    }
    return $result
}

function Test-Url {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Url
    )
    try {
        # Create a web request and check the response
        $request = [System.Net.WebRequest]::Create($Url)
        $request.Method = 'HEAD'
        $response = $request.GetResponse()
        return $true
    }
    catch {
        return $false
    }
}

function Get-PrivateProfileString {
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

    return $sbuilder.ToString()
}

function Get-PrivateProfileSection {
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

    return $hashTable
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

    return $shortenedWindowsSKU
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
    return $CustomFFUNameTemplate
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
    if (Test-Path $manifestPath) { return (Get-Content $manifestPath -Raw | ConvertFrom-Json) }
    return $null
}

function Save-RunManifest {
    param([string]$FFUDevelopmentPath, [object]$Manifest)
    if ($null -eq $Manifest) { return }
    $manifestPath = Join-Path $FFUDevelopmentPath '.session\currentRun.json'
    $Manifest | ConvertTo-Json -Depth 5 | Set-Content -Path $manifestPath -Encoding UTF8
}

function Mark-DownloadInProgress {
    param([string]$FFUDevelopmentPath, [string]$TargetPath)
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
                return $true
            }
            catch {
                Start-Sleep -Milliseconds ([FFUConstants]::PROCESS_POLL_INTERVAL_MS)
            }
        }
        return -not (Test-Path -LiteralPath $path)
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

function Cleanup-CurrentRunDownloads {
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
    Cleanup-CurrentRunDownloads -FFUDevelopmentPath "C:\FFU" -AppsPath "C:\FFU\Apps" `
                                -DefenderPath "C:\FFU\Defender" -MSRTPath "C:\FFU\MSRT" `
                                -OneDrivePath "C:\FFU\OneDrive" -EdgePath "C:\FFU\Edge" `
                                -KBPath "C:\FFU\KB" -DriversFolder "C:\FFU\Drivers" `
                                -orchestrationPath "C:\FFU\Orchestration" -OfficePath "C:\FFU\Office"
    #>
    [CmdletBinding()]
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

            return $result
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
        return $null
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
            return $true
        } else {
            $errorMsg = "$CommandName failed with exit code $LASTEXITCODE (robocopy: 8+ indicates error)"
            if ($Output) { $errorMsg += "`nOutput: $Output" }
            & $logError $errorMsg
            return $false
        }
    }

    # Standard command handling
    if ($SuccessCodes -contains $LASTEXITCODE) {
        return $true
    } else {
        $errorMsg = "$CommandName failed with exit code $LASTEXITCODE"
        if ($Output) { $errorMsg += "`nOutput: $Output" }
        & $logError $errorMsg
        return $false
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
        return $result
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

        return $securePassword
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
        return [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
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

    return $cleanupId
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
        return $true
    }
    return $false
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

    # Safe logging helper
    $log = {
        param([string]$Message)
        if (Get-Command WriteLog -ErrorAction SilentlyContinue) {
            WriteLog $Message
        } else {
            Write-Host $Message
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

    return @($script:CleanupRegistry)
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

# Export all module functions
Export-ModuleMember -Function @(
    # Configuration and utilities
    'Get-Parameters'
    'LogVariableValues'
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
    'Mark-DownloadInProgress'
    'Clear-DownloadInProgress'
    'Remove-InProgressItems'
    'Cleanup-CurrentRunDownloads'
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
    # Secure credential management (v1.0.7)
    'New-SecureRandomPassword'
    'ConvertFrom-SecureStringToPlainText'
    'Clear-PlainTextPassword'
    'Remove-SecureStringFromMemory'
)