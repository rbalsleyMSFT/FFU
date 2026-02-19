function Invoke-Process {
    [CmdletBinding(SupportsShouldProcess)]
    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$FilePath,

        [Parameter()]
        [string[]]$ArgumentList,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [bool]$Wait = $true,

        [Parameter()]
        [string[]]$AdditionalSuccessCodes,

        [Parameter()]
        [bool]$IgnoreNonZeroExitCodes = $false
    )

    $ErrorActionPreference = 'Stop'

    try {
        if ($PSCmdlet.ShouldProcess("Process [$($FilePath)]", "Run with args: [$($ArgumentList)]")) {
            # Use .NET Process class for proper stream handling
            $pinfo = New-Object System.Diagnostics.ProcessStartInfo
            $pinfo.FileName = $FilePath
            if ($ArgumentList) {
                $pinfo.Arguments = $ArgumentList -join ' '
            }
            $pinfo.RedirectStandardOutput = $true
            $pinfo.RedirectStandardError = $true
            $pinfo.UseShellExecute = $false
            $pinfo.CreateNoWindow = $true
            
            $p = New-Object System.Diagnostics.Process
            $p.StartInfo = $pinfo
            
            # Start the process
            $p.Start() | Out-Null
            
            # Read output and error streams
            $cmdOutput = $p.StandardOutput.ReadToEnd()
            $cmdError = $p.StandardError.ReadToEnd()
            
            if ($Wait) {
                $p.WaitForExit()
            }
            
            $exitCode = $p.ExitCode
            # An exit code of 0 is always a success
            if ($exitCode -ne 0) {
                # If IgnoreNonZeroExitCodes is true, treat any non-zero exit code as a success
                if ($IgnoreNonZeroExitCodes) {
                    Write-Host "Ignoring non-zero exit code $exitCode because IgnoreNonZeroExitCodes is set to true."
                }
                # Check if the non-zero exit code is in the list of additional success codes
                elseif ($null -eq $AdditionalSuccessCodes -or $exitCode -notin $AdditionalSuccessCodes) {
                    if ($cmdError) {
                        throw $cmdError.Trim()
                    }
                    if ($cmdOutput) {
                        throw $cmdOutput.Trim()
                    }
                    # If there's no output, throw a generic error with the exit code
                    if (-not $cmdError -and -not $cmdOutput) {
                        throw "Process exited with non-zero code: $exitCode"
                    }
                }
            }
            else {
                if ([string]::IsNullOrEmpty($cmdOutput) -eq $false) {
                    # WriteLog $cmdOutput
                }
            }
            
            # Create a simple object with exit code for compatibility
            $result = [PSCustomObject]@{
                ExitCode = $exitCode
            }
            
            return $result
        }
    }
    catch {
        #$PSCmdlet.ThrowTerminatingError($_)
        # WriteLog $_
        # Write-Host "Script failed - $Logfile for more info"
        throw $_
    }
}

function Format-MsiArguments {
    <#
    .SYNOPSIS
        Ensures MSI file paths in msiexec arguments are properly quoted.
    .DESCRIPTION
        Detects /i arguments followed by an unquoted path ending in .msi
        and wraps the path in double quotes to handle paths with spaces.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$CommandLine,

        [Parameter(Mandatory)]
        [string]$Arguments
    )

    # Only process if the command is msiexec
    if ($CommandLine -notmatch '^msiexec(\.exe)?$') {
        return $Arguments
    }

    # Regex pattern explanation:
    # (?i)            - Case-insensitive matching
    # (/i)\s+         - Match /i followed by whitespace
    # (?!")           - Negative lookahead: not already quoted
    # (.+?\.msi)      - Capture path ending in .msi (lazy match to stop at first .msi)
    # (?=\s+/|\s*$)   - Followed by another switch or end of string
    
    # Pattern to match /i followed by an unquoted MSI path
    $pattern = '(?i)(/i)\s+(?!")(.+?\.msi)(?=\s+/|\s*$)'
    
    if ($Arguments -match $pattern) {
        $originalArgs = $Arguments
        # Replace with quoted path
        $Arguments = $Arguments -replace $pattern, '$1 "$2"'
        Write-Host "Detected unquoted MSI path in msiexec arguments. Adjusted arguments:"
        Write-Host "Original: $originalArgs"
        Write-Host "Modified: $Arguments"
    }

    return $Arguments
}

function Install-Applications {
    param(
        [Parameter(Mandatory)]
        [array]$apps
    )

    if ($apps.Count -eq 0) {
        Write-Host "No applications to install from this source."
        return
    }

    Write-Host "Total apps to install from this source: $($apps.Count)"

    # Sort all apps by priority
    $sortedApps = $apps | Sort-Object -Property Priority

    # Install each app
    foreach ($app in $sortedApps) {
        # Check if required properties exist
        if (-not $app.PSObject.Properties['Name'] -or -not $app.PSObject.Properties['CommandLine'] -or -not $app.PSObject.Properties['Arguments']) {
            Write-Warning "Skipping app due to missing required properties (Name, CommandLine, Arguments): $($app | ConvertTo-Json -Depth 1 -Compress)"
            continue
        }

        Write-Host "Installing $($app.Name)..."
        
        # Wait until no MSIExec installation is running
        while ($true) {
            try {
                # Try to open the MSIExec global mutex
                $Mutex = [System.Threading.Mutex]::OpenExisting("Global\_MSIExecute")
                # Dispose releases the handle from our script only.
                $Mutex.Dispose()
                Write-Host "Another MSIExec installer is running. Waiting for 5 seconds before rechecking..."
                Start-Sleep -Seconds 5
            }
            catch [System.Threading.WaitHandleCannotBeOpenedException] {
                # If we can't open the mutex, it means no MSIExec installation is running
                break
            }
            catch {
                # Handle other potential errors when checking the mutex
                Write-Warning "Error checking MSIExec mutex: $_. Proceeding with caution."
                break 
            }
        }

        # Check for 'PAUSE' command
        if ($app.CommandLine -eq 'PAUSE') {
            Write-Host "Pausing script as requested by '$($app.Name)'. Press Enter to continue..."
            $null = Read-Host
            continue
        }
        
        try {
            # Normalize arguments: treat null/empty/whitespace as no arguments
            $argumentsToPass = $null
            if ($null -ne $app.Arguments) {
                if ($app.Arguments -is [array]) {
                    $trimmed = $app.Arguments | ForEach-Object { ($_ | ForEach-Object { if ($_ -ne $null) { $_.ToString().Trim() } else { $_ } }) } | Where-Object { $_ -and (-not [string]::IsNullOrWhiteSpace($_)) }
                    if ($trimmed.Count -gt 0) {
                        $argumentsToPass = $trimmed
                    }
                }
                else {
                    $single = $app.Arguments.ToString().Trim()
                    if (-not [string]::IsNullOrWhiteSpace($single)) {
                        $argumentsToPass = @($single)
                    }
                }
            }

            # Check for and parse AdditionalExitCodes
            $additionalSuccessCodes = @()
            if ($app.PSObject.Properties['AdditionalExitCodes'] -and -not [string]::IsNullOrWhiteSpace($app.AdditionalExitCodes)) {
                $additionalSuccessCodes = $app.AdditionalExitCodes -split ',' | ForEach-Object { $_.Trim() }
                Write-Host "Additional success exit codes for $($app.Name): $($additionalSuccessCodes -join ', ')"
            }

            # Check for IgnoreNonZeroExitCodes
            $ignoreNonZeroExitCodes = $false
            if ($app.PSObject.Properties['IgnoreNonZeroExitCodes'] -and $app.IgnoreNonZeroExitCodes -is [bool]) {
                $ignoreNonZeroExitCodes = $app.IgnoreNonZeroExitCodes
            }

            # Auto-quote MSI paths if using msiexec and path contains spaces but no quotes
            if ($null -ne $argumentsToPass -and $argumentsToPass.Count -gt 0) {
                $joinedArgs = $argumentsToPass -join ' '
                $formattedArgs = Format-MsiArguments -CommandLine $app.CommandLine -Arguments $joinedArgs
                if ($formattedArgs -ne $joinedArgs) {
                    $argumentsToPass = @($formattedArgs)
                }
            }

            if ($null -eq $argumentsToPass -or $argumentsToPass.Count -eq 0) {
                Write-Host "Running command: $($app.CommandLine) (no arguments)"
                $result = Invoke-Process -FilePath $app.CommandLine -AdditionalSuccessCodes $additionalSuccessCodes -IgnoreNonZeroExitCodes $ignoreNonZeroExitCodes
            }
            else {
                Write-Host "Running command: $($app.CommandLine) $($argumentsToPass -join ' ')"
                $result = Invoke-Process -FilePath $app.CommandLine -ArgumentList $argumentsToPass -AdditionalSuccessCodes $additionalSuccessCodes -IgnoreNonZeroExitCodes $ignoreNonZeroExitCodes
            }
            Write-Host "$($app.Name) exited with exit code: $($result.ExitCode)`r`n"
        }
        catch {
            Write-Error "Error occurred while installing $($app.Name): $_"
            Read-Host "An error occurred, and the script cannot continue. Press Enter to exit."
            throw $_
        }
    }
}

# Define paths for the JSON files
$wingetAppsJsonFile = "$PSScriptRoot\WinGetWin32Apps.json"
# Look for UserAppList.json one directory level up from the script's location. This keeps the user specific json files (AppList.json and UserAppList.json in the Apps dir)
$userAppsJsonFile = Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath "UserAppList.json"

# Initialize empty arrays for apps from each source
$wingetApps = @()
$userApps = @()

# Read the WinGetWin32Apps.json file if it exists
if (Test-Path -Path $wingetAppsJsonFile) {
    Write-Host "Processing WinGetWin32Apps.json..."
    try {
        $wingetContent = Get-Content -Path $wingetAppsJsonFile -Raw -ErrorAction Stop | ConvertFrom-Json
        if ($wingetContent -is [array]) {
            $wingetApps = $wingetContent
            Write-Host "Found $(($wingetApps | Measure-Object).Count) WinGet Win32 apps."
        }
        elseif ($wingetContent) {
            $wingetApps = @($wingetContent) # Ensure it's an array
            Write-Host "Found 1 WinGet Win32 app."
        }
        else {
            Write-Host "WinGetWin32Apps.json is empty or invalid."
        }
    }
    catch {
        Write-Error "Failed to read or parse WinGetWin32Apps.json file: $_"
    }
}
else {
    Write-Host "WinGetWin32Apps.json file not found. Skipping."
}

# Install WinGet apps if any were found
if ($wingetApps.Count -gt 0) {
    Install-Applications -apps $wingetApps
}

# Read the UserAppList.json file if it exists
if (Test-Path -Path $userAppsJsonFile) {
    Write-Host "Processing UserAppList.json..."
    try {
        $userContent = Get-Content -Path $userAppsJsonFile -Raw -ErrorAction Stop | ConvertFrom-Json
        if ($userContent -is [array]) {
            $userApps = $userContent
            Write-Host "Found $(($userApps | Measure-Object).Count) user-defined apps."
        }
        elseif ($userContent) {
            $userApps = @($userContent) # Ensure it's an array
            Write-Host "Found 1 user-defined app."
        }
        else {
            Write-Host "UserAppList.json is empty or invalid."
        }
    }
    catch {
        Write-Error "Failed to read or parse UserAppList.json file: $_"
    }
}
else {
    Write-Host "UserAppList.json file not found. Skipping."
}

# Install User apps if any were found
if ($userApps.Count -gt 0) {
    Install-Applications -apps $userApps
}

# Check if any apps were installed at all
if ($wingetApps.Count -eq 0 -and $userApps.Count -eq 0) {
    Write-Host "No Win32 apps found in either WinGetWin32Apps.json or UserAppList.json. Exiting."
    exit 0
}

Write-Host "All Win32 app installations attempted."