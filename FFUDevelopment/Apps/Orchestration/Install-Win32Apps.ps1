function Invoke-Process {
    [CmdletBinding(SupportsShouldProcess)]
    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$FilePath,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string[]]$ArgumentList,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [bool]$Wait = $true
    )

    $ErrorActionPreference = 'Stop'

    try {
        $stdOutTempFile = "$env:TEMP\$((New-Guid).Guid)"
        $stdErrTempFile = "$env:TEMP\$((New-Guid).Guid)"

        $startProcessParams = @{
            FilePath               = $FilePath
            ArgumentList           = $ArgumentList
            RedirectStandardError  = $stdErrTempFile
            RedirectStandardOutput = $stdOutTempFile
            Wait                   = $($Wait);
            PassThru               = $true;
            NoNewWindow            = $true;
        }
        if ($PSCmdlet.ShouldProcess("Process [$($FilePath)]", "Run with args: [$($ArgumentList)]")) {
            $cmd = Start-Process @startProcessParams
            $cmdOutput = Get-Content -Path $stdOutTempFile -Raw
            $cmdError = Get-Content -Path $stdErrTempFile -Raw
            if ($cmd.ExitCode -ne 0 -and $wait -eq $true) {
                if ($cmdError) {
                    throw $cmdError.Trim()
                }
                if ($cmdOutput) {
                    throw $cmdOutput.Trim()
                }
            }
            else {
                if ([string]::IsNullOrEmpty($cmdOutput) -eq $false) {
                    # WriteLog $cmdOutput
                    Write-Host $cmdOutput
                }
            }
        }
    }
    catch {
        #$PSCmdlet.ThrowTerminatingError($_)
        # WriteLog $_
        # Write-Host "Script failed - $Logfile for more info"
        throw $_

    }
    finally {
        Remove-Item -Path $stdOutTempFile, $stdErrTempFile -Force -ErrorAction Ignore
    }
    return $cmd
}

# Define paths for the JSON files
$wingetAppsJsonFile = "$PSScriptRoot\WinGetWin32Apps.json"
# Look for UserAppList.json one directory level up from the script's location. This keeps the user specific json files (AppList.json and UserAppList.json in the Apps dir)
$userAppsJsonFile = Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath "UserAppList.json"

# Initialize an empty array to hold all apps
$allApps = @()

# Read the WinGetWin32Apps.json file if it exists
if (Test-Path -Path $wingetAppsJsonFile) {
    Write-Host "Processing WinGetWin32Apps.json..."
    try {
        $wingetApps = Get-Content -Path $wingetAppsJsonFile -Raw -ErrorAction Stop | ConvertFrom-Json
        if ($wingetApps -is [array]) {
            $allApps += $wingetApps
            Write-Host "Found $(($wingetApps | Measure-Object).Count) WinGet Win32 apps."
        } elseif ($wingetApps) {
            $allApps += @($wingetApps) # Ensure it's added as an array element
            Write-Host "Found 1 WinGet Win32 app."
        } else {
             Write-Host "WinGetWin32Apps.json is empty or invalid."
        }
    } catch {
        Write-Error "Failed to read or parse WinGetWin32Apps.json file: $_"
        # Decide if execution should stop or continue
        # exit 1 
    }
} else {
    Write-Host "WinGetWin32Apps.json file not found. Skipping."
}

# Read the UserAppList.json file if it exists
if (Test-Path -Path $userAppsJsonFile) {
    Write-Host "Processing UserAppList.json..."
    try {
        $userApps = Get-Content -Path $userAppsJsonFile -Raw -ErrorAction Stop | ConvertFrom-Json
        if ($userApps -is [array]) {
            $allApps += $userApps
            Write-Host "Found $(($userApps | Measure-Object).Count) user-defined apps."
        } elseif ($userApps) {
            $allApps += @($userApps) # Ensure it's added as an array element
            Write-Host "Found 1 user-defined app."
        } else {
             Write-Host "UserAppList.json is empty or invalid."
        }
    } catch {
        Write-Error "Failed to read or parse UserAppList.json file: $_"
        # Decide if execution should stop or continue
        # exit 1
    }
} else {
    Write-Host "UserAppList.json file not found. Skipping."
}

# Check if there are any apps to install
if ($allApps.Count -eq 0) {
    Write-Host "No Win32 apps found in either WinGetWin32Apps.json or UserAppList.json. Exiting."
    exit 0
}

Write-Host "Total apps to install: $($allApps.Count)"

# Sort all apps by priority
$sortedApps = $allApps | Sort-Object -Property Priority

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
    
    try {
        # Construct the argument list properly, handling potential array vs string
        $argumentsToPass = if ($app.Arguments -is [array]) { $app.Arguments } else { @($app.Arguments) }
        
        Write-Host "Running command: $($app.CommandLine) $($argumentsToPass -join ' ')"
        $result = Invoke-Process -FilePath $($app.CommandLine) -ArgumentList $argumentsToPass
        Write-Host "$($app.Name) exited with exit code: $($result.ExitCode)`r`n"
    } catch {
        Write-Error "Error occurred while installing $($app.Name): $_"
        # Decide if execution should stop or continue after an error
        # exit 1 
    }
}

Write-Host "All Win32 app installations attempted."