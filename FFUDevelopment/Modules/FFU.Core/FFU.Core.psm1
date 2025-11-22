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
    param (
        [string]$WindowsSKU
    )
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
            if ($data.TargetPath -eq $TargetPath) { Remove-Item -Path $_.FullName -Force }
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
                Start-Sleep -Milliseconds 350
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
                                        Start-Sleep -Milliseconds 500
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

            Remove-Item -Path $_.FullName -Force
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

# Export all module functions
Export-ModuleMember -Function @(
    'Get-Parameters'
    'LogVariableValues'
    'Get-ChildProcesses'
    'Test-Url'
    'Get-PrivateProfileString'
    'Get-PrivateProfileSection'
    'Get-ShortenedWindowsSKU'
    'New-FFUFileName'
    'Export-ConfigFile'
    'New-RunSession'
    'Get-CurrentRunManifest'
    'Save-RunManifest'
    'Mark-DownloadInProgress'
    'Clear-DownloadInProgress'
    'Remove-InProgressItems'
    'Cleanup-CurrentRunDownloads'
    'Restore-RunJsonBackups'
)