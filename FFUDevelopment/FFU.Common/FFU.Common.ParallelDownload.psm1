<#
.SYNOPSIS
    Parallel download orchestration for FFUBuilder with multi-method fallback support

.DESCRIPTION
    Provides parallel downloading using runspaces (PowerShell 5.1) or ForEach-Object -Parallel (PowerShell 7+)
    with full preservation of existing fallback mechanisms (BITS -> WebRequest -> WebClient -> curl).

    This module is designed to work in both UI and non-UI (CLI build) contexts.

.NOTES
    - Preserves all existing download fallback methods from FFU.Common.Download.psm1
    - Supports proxy configuration for corporate environments
    - Works with PowerShell 5.1 (runspace pool) and PowerShell 7+ (ForEach-Object -Parallel)
    - Thread-safe progress reporting for UI integration
#>

#Requires -Version 7.0

# Configuration class for parallel downloads
class ParallelDownloadConfig {
    [int]$MaxConcurrentDownloads = 5
    [int]$RetryCount = 3
    [int]$RetryDelaySeconds = 2
    [bool]$UseExponentialBackoff = $true
    [string]$LogPath = $null
    [object]$ProxyConfig = $null
    [scriptblock]$ProgressCallback = $null
    [bool]$ContinueOnError = $true  # Continue downloading other files if one fails
}

# Download item class
class DownloadItem {
    [string]$Id           # Unique identifier for tracking
    [string]$Source       # URL to download
    [string]$Destination  # Local file path
    [string]$Category     # Grouping (KB, Defender, Apps, etc.)
    [string]$DisplayName  # Human-readable name
    [hashtable]$Metadata  # Additional context (KB article, version, etc.)

    DownloadItem() {
        $this.Metadata = @{}
    }
}

# Result class
class DownloadResult {
    [string]$Id
    [string]$Source
    [string]$Destination
    [bool]$Success
    [string]$Method        # Which method succeeded (BITS, WebRequest, WebClient, Curl)
    [string]$ErrorMessage
    [long]$BytesDownloaded
    [double]$DurationSeconds
}

function Start-ParallelDownloads {
    <#
    .SYNOPSIS
        Downloads multiple files in parallel with multi-method fallback support

    .DESCRIPTION
        Uses parallel processing to download multiple files simultaneously.
        Each download uses the full fallback chain: BITS -> WebRequest -> WebClient -> Curl.
        Works in both PowerShell 5.1 (using runspace pools) and PowerShell 7+ (using ForEach-Object -Parallel).

    .PARAMETER Downloads
        Array of DownloadItem objects to process

    .PARAMETER Config
        ParallelDownloadConfig object with settings (optional, uses defaults if not provided)

    .PARAMETER WaitForCompletion
        If $true (default), blocks until all downloads complete. If $false, returns job object for async monitoring.

    .OUTPUTS
        Array of DownloadResult objects (when WaitForCompletion = $true)

    .EXAMPLE
        $items = @(
            [DownloadItem]@{ Id = "KB1"; Source = "https://..."; Destination = "C:\KB\file1.msu"; DisplayName = "SSU Update" }
            [DownloadItem]@{ Id = "KB2"; Source = "https://..."; Destination = "C:\KB\file2.msu"; DisplayName = "CU Update" }
        )
        $results = Start-ParallelDownloads -Downloads $items

    .EXAMPLE
        # With custom configuration
        $config = [ParallelDownloadConfig]::new()
        $config.MaxConcurrentDownloads = 3
        $config.ProgressCallback = { param($Update) Write-Host "$($Update.Id): $($Update.Status)" }
        $results = Start-ParallelDownloads -Downloads $items -Config $config
    #>
    [CmdletBinding()]
    [OutputType([DownloadResult[]])]
    param(
        [Parameter(Mandatory = $true)]
        [DownloadItem[]]$Downloads,

        [Parameter()]
        [ParallelDownloadConfig]$Config = $null,

        [Parameter()]
        [switch]$WaitForCompletion = $true
    )

    # Use default config if not provided
    if ($null -eq $Config) {
        $Config = [ParallelDownloadConfig]::new()
    }

    # Validate inputs
    if ($Downloads.Count -eq 0) {
        WriteLog "No downloads specified"
        return @()
    }

    WriteLog "Starting parallel download of $($Downloads.Count) items (MaxConcurrent: $($Config.MaxConcurrentDownloads))"

    # Determine which parallel implementation to use
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        WriteLog "Using PowerShell 7+ ForEach-Object -Parallel"
        return Start-ParallelDownloadsPS7 -Downloads $Downloads -Config $Config -WaitForCompletion:$WaitForCompletion
    }
    else {
        WriteLog "Using PowerShell 5.1 RunspacePool"
        return Start-ParallelDownloadsRunspacePool -Downloads $Downloads -Config $Config -WaitForCompletion:$WaitForCompletion
    }
}

function Start-ParallelDownloadsPS7 {
    <#
    .SYNOPSIS
        PowerShell 7+ implementation using ForEach-Object -Parallel
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [DownloadItem[]]$Downloads,

        [Parameter(Mandatory = $true)]
        [ParallelDownloadConfig]$Config,

        [Parameter()]
        [switch]$WaitForCompletion
    )

    # Prepare paths for parallel scope
    $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
    $downloadModulePath = Join-Path $PSScriptRoot "FFU.Common.Download.psm1"
    $coreModulePath = Join-Path $PSScriptRoot "FFU.Common.Core.psm1"

    # Thread-safe progress queue
    $progressQueue = [System.Collections.Concurrent.ConcurrentQueue[hashtable]]::new()

    # Serialize config for parallel scope
    $configRetries = $Config.RetryCount
    $configLogPath = $Config.LogPath
    $configProxyConfig = $Config.ProxyConfig

    $job = $Downloads | ForEach-Object -Parallel {
        $download = $_
        $localRetries = $using:configRetries
        $localLogPath = $using:configLogPath
        $localProgressQueue = $using:progressQueue
        $localDownloadModulePath = $using:downloadModulePath
        $localCoreModulePath = $using:coreModulePath

        # Import modules in parallel runspace
        try {
            Import-Module $localCoreModulePath -Force -ErrorAction Stop
            Import-Module $localDownloadModulePath -Force -ErrorAction Stop
        }
        catch {
            # Return error result if module import fails
            return [PSCustomObject]@{
                Id             = $download.Id
                Source         = $download.Source
                Destination    = $download.Destination
                Success        = $false
                Method         = $null
                ErrorMessage   = "Failed to import modules: $($_.Exception.Message)"
                BytesDownloaded = 0
                DurationSeconds = 0
            }
        }

        # Set log path if provided
        if (-not [string]::IsNullOrEmpty($localLogPath)) {
            try { Set-CommonCoreLogPath -Path $localLogPath } catch { }
        }

        $result = [PSCustomObject]@{
            Id             = $download.Id
            Source         = $download.Source
            Destination    = $download.Destination
            Success        = $false
            Method         = $null
            ErrorMessage   = $null
            BytesDownloaded = 0
            DurationSeconds = 0
        }

        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        # Report progress - starting
        $localProgressQueue.Enqueue(@{
            Id          = $download.Id
            DisplayName = $download.DisplayName
            Status      = "Downloading"
            Category    = $download.Category
        })

        try {
            # Ensure destination directory exists
            $destDir = Split-Path -Path $download.Destination -Parent
            if (-not [string]::IsNullOrEmpty($destDir) -and -not (Test-Path -Path $destDir)) {
                New-Item -Path $destDir -ItemType Directory -Force | Out-Null
            }

            # Use resilient download with all fallback methods
            $downloadResult = Start-ResilientDownload -Source $download.Source `
                                                      -Destination $download.Destination `
                                                      -Retries $localRetries

            if ($downloadResult -and (Test-Path $download.Destination)) {
                $result.Success = $true
                $result.Method = "ResilientDownload"
                $result.BytesDownloaded = (Get-Item $download.Destination).Length

                $localProgressQueue.Enqueue(@{
                    Id          = $download.Id
                    DisplayName = $download.DisplayName
                    Status      = "Completed"
                    Category    = $download.Category
                })
            }
            else {
                $result.Success = $false
                $result.ErrorMessage = "Download completed but file not found"

                $localProgressQueue.Enqueue(@{
                    Id          = $download.Id
                    DisplayName = $download.DisplayName
                    Status      = "Failed: File not created"
                    Category    = $download.Category
                })
            }
        }
        catch {
            $result.Success = $false
            $result.ErrorMessage = $_.Exception.Message

            $localProgressQueue.Enqueue(@{
                Id          = $download.Id
                DisplayName = $download.DisplayName
                Status      = "Failed: $($_.Exception.Message)"
                Category    = $download.Category
            })
        }
        finally {
            $stopwatch.Stop()
            $result.DurationSeconds = $stopwatch.Elapsed.TotalSeconds
        }

        return $result

    } -ThrottleLimit $Config.MaxConcurrentDownloads -AsJob

    if ($WaitForCompletion) {
        # Monitor progress while waiting
        while ($job.State -eq 'Running') {
            # Process progress updates
            $update = $null
            while ($progressQueue.TryDequeue([ref]$update)) {
                if ($Config.ProgressCallback) {
                    try { & $Config.ProgressCallback $update } catch { }
                }
                WriteLog "Download $($update.Id) ($($update.DisplayName)): $($update.Status)"
            }
            Start-Sleep -Milliseconds 100
        }

        # Process any remaining progress updates
        $update = $null
        while ($progressQueue.TryDequeue([ref]$update)) {
            if ($Config.ProgressCallback) {
                try { & $Config.ProgressCallback $update } catch { }
            }
            WriteLog "Download $($update.Id) ($($update.DisplayName)): $($update.Status)"
        }

        # Get final results
        $jobResults = $job | Receive-Job -Wait
        Remove-Job $job -Force

        return $jobResults
    }
    else {
        return @{
            Job           = $job
            ProgressQueue = $progressQueue
        }
    }
}

function Start-ParallelDownloadsRunspacePool {
    <#
    .SYNOPSIS
        PowerShell 5.1 compatible parallel downloads using runspace pool
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [DownloadItem[]]$Downloads,

        [Parameter(Mandatory = $true)]
        [ParallelDownloadConfig]$Config,

        [Parameter()]
        [switch]$WaitForCompletion
    )

    # Prepare paths
    $downloadModulePath = Join-Path $PSScriptRoot "FFU.Common.Download.psm1"
    $coreModulePath = Join-Path $PSScriptRoot "FFU.Common.Core.psm1"

    # Create runspace pool
    $runspacePool = [runspacefactory]::CreateRunspacePool(1, $Config.MaxConcurrentDownloads)
    $runspacePool.Open()

    $jobs = [System.Collections.Generic.List[hashtable]]::new()
    $progressQueue = [System.Collections.Concurrent.ConcurrentQueue[hashtable]]::new()

    # Script block for each download
    $downloadScriptBlock = {
        param(
            $Download,
            $Retries,
            $LogPath,
            $CoreModulePath,
            $DownloadModulePath,
            $ProgressQueue
        )

        # Import modules
        try {
            Import-Module $CoreModulePath -Force -ErrorAction Stop
            Import-Module $DownloadModulePath -Force -ErrorAction Stop
        }
        catch {
            return [PSCustomObject]@{
                Id             = $Download.Id
                Source         = $Download.Source
                Destination    = $Download.Destination
                Success        = $false
                Method         = $null
                ErrorMessage   = "Failed to import modules: $($_.Exception.Message)"
                BytesDownloaded = 0
                DurationSeconds = 0
            }
        }

        # Set log path
        if (-not [string]::IsNullOrEmpty($LogPath)) {
            try { Set-CommonCoreLogPath -Path $LogPath } catch { }
        }

        $result = [PSCustomObject]@{
            Id             = $Download.Id
            Source         = $Download.Source
            Destination    = $Download.Destination
            Success        = $false
            Method         = $null
            ErrorMessage   = $null
            BytesDownloaded = 0
            DurationSeconds = 0
        }

        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        # Report progress - starting
        $ProgressQueue.Enqueue(@{
            Id          = $Download.Id
            DisplayName = $Download.DisplayName
            Status      = "Downloading"
            Category    = $Download.Category
        })

        try {
            # Ensure destination directory exists
            $destDir = Split-Path -Path $Download.Destination -Parent
            if (-not [string]::IsNullOrEmpty($destDir) -and -not (Test-Path -Path $destDir)) {
                New-Item -Path $destDir -ItemType Directory -Force | Out-Null
            }

            # Use resilient download with all fallback methods
            $downloadSuccess = Start-ResilientDownload -Source $Download.Source `
                                                       -Destination $Download.Destination `
                                                       -Retries $Retries

            if ($downloadSuccess -and (Test-Path $Download.Destination)) {
                $result.Success = $true
                $result.Method = "ResilientDownload"
                $result.BytesDownloaded = (Get-Item $Download.Destination).Length

                $ProgressQueue.Enqueue(@{
                    Id          = $Download.Id
                    DisplayName = $Download.DisplayName
                    Status      = "Completed"
                    Category    = $Download.Category
                })
            }
            else {
                $result.Success = $false
                $result.ErrorMessage = "Download completed but file not found"

                $ProgressQueue.Enqueue(@{
                    Id          = $Download.Id
                    DisplayName = $Download.DisplayName
                    Status      = "Failed: File not created"
                    Category    = $Download.Category
                })
            }
        }
        catch {
            $result.Success = $false
            $result.ErrorMessage = $_.Exception.Message

            $ProgressQueue.Enqueue(@{
                Id          = $Download.Id
                DisplayName = $Download.DisplayName
                Status      = "Failed: $($_.Exception.Message)"
                Category    = $Download.Category
            })
        }
        finally {
            $stopwatch.Stop()
            $result.DurationSeconds = $stopwatch.Elapsed.TotalSeconds
        }

        return $result
    }

    # Start a runspace job for each download
    foreach ($download in $Downloads) {
        $powershell = [powershell]::Create()
        $powershell.RunspacePool = $runspacePool

        $null = $powershell.AddScript($downloadScriptBlock)
        $null = $powershell.AddArgument($download)
        $null = $powershell.AddArgument($Config.RetryCount)
        $null = $powershell.AddArgument($Config.LogPath)
        $null = $powershell.AddArgument($coreModulePath)
        $null = $powershell.AddArgument($downloadModulePath)
        $null = $powershell.AddArgument($progressQueue)

        $jobs.Add(@{
            PowerShell = $powershell
            Handle     = $powershell.BeginInvoke()
            Download   = $download
        })

        WriteLog "Started runspace job for $($download.DisplayName)"
    }

    if ($WaitForCompletion) {
        # Wait for all jobs to complete while processing progress updates
        $allResults = [System.Collections.Generic.List[object]]::new()
        $completedJobs = [System.Collections.Generic.HashSet[int]]::new()

        while ($completedJobs.Count -lt $jobs.Count) {
            # Process progress updates
            $update = $null
            while ($progressQueue.TryDequeue([ref]$update)) {
                if ($Config.ProgressCallback) {
                    try { & $Config.ProgressCallback $update } catch { }
                }
                WriteLog "Download $($update.Id) ($($update.DisplayName)): $($update.Status)"
            }

            # Check for completed jobs
            for ($i = 0; $i -lt $jobs.Count; $i++) {
                if (-not $completedJobs.Contains($i) -and $jobs[$i].Handle.IsCompleted) {
                    $completedJobs.Add($i) | Out-Null
                    try {
                        $result = $jobs[$i].PowerShell.EndInvoke($jobs[$i].Handle)
                        if ($result) {
                            $allResults.Add($result)
                        }
                        WriteLog "Completed download: $($jobs[$i].Download.DisplayName)"
                    }
                    catch {
                        WriteLog "Failed download: $($jobs[$i].Download.DisplayName) - $($_.Exception.Message)"
                        $allResults.Add([PSCustomObject]@{
                            Id             = $jobs[$i].Download.Id
                            Source         = $jobs[$i].Download.Source
                            Destination    = $jobs[$i].Download.Destination
                            Success        = $false
                            Method         = $null
                            ErrorMessage   = $_.Exception.Message
                            BytesDownloaded = 0
                            DurationSeconds = 0
                        })
                    }
                }
            }

            Start-Sleep -Milliseconds 100
        }

        # Process any remaining progress updates
        $update = $null
        while ($progressQueue.TryDequeue([ref]$update)) {
            if ($Config.ProgressCallback) {
                try { & $Config.ProgressCallback $update } catch { }
            }
        }

        # Cleanup
        foreach ($job in $jobs) {
            $job.PowerShell.Dispose()
        }
        $runspacePool.Close()
        $runspacePool.Dispose()

        return $allResults.ToArray()
    }
    else {
        return @{
            Jobs          = $jobs
            RunspacePool  = $runspacePool
            ProgressQueue = $progressQueue
        }
    }
}

function New-KBDownloadItems {
    <#
    .SYNOPSIS
        Creates an array of DownloadItem objects from a collection of KB update information

    .DESCRIPTION
        Helper function to convert KB update objects (as returned by Get-UpdateFileInfo) into
        DownloadItem objects suitable for Start-ParallelDownloads.

    .PARAMETER Updates
        Array of KB update objects with Name and Url properties

    .PARAMETER KBPath
        Base path where KB files should be downloaded

    .PARAMETER NetUpdatesPath
        Optional separate path for .NET updates (defaults to KBPath\NET if not specified)

    .PARAMETER NetUpdateNames
        Optional list of update names that should be considered .NET updates

    .OUTPUTS
        Array of DownloadItem objects

    .EXAMPLE
        $items = New-KBDownloadItems -Updates $requiredUpdates -KBPath "C:\FFUDevelopment\KB"
        $results = Start-ParallelDownloads -Downloads $items
    #>
    [CmdletBinding()]
    [OutputType([DownloadItem[]])]
    param(
        [Parameter(Mandatory = $true)]
        [array]$Updates,

        [Parameter(Mandatory = $true)]
        [string]$KBPath,

        [Parameter()]
        [string]$NetUpdatesPath = $null,

        [Parameter()]
        [string[]]$NetUpdateNames = @()
    )

    $items = [System.Collections.Generic.List[DownloadItem]]::new()

    # Default .NET path
    if ([string]::IsNullOrEmpty($NetUpdatesPath)) {
        $NetUpdatesPath = Join-Path -Path $KBPath -ChildPath "NET"
    }

    foreach ($update in $Updates) {
        if ([string]::IsNullOrEmpty($update.Url)) {
            WriteLog "Warning: Update '$($update.Name)' has no URL, skipping"
            continue
        }

        $fileName = ($update.Url -split '/')[-1]

        # Determine destination based on whether this is a .NET update
        $isNetUpdate = $NetUpdateNames -contains $update.Name
        $destination = if ($isNetUpdate) {
            Join-Path -Path $NetUpdatesPath -ChildPath $fileName
        }
        else {
            Join-Path -Path $KBPath -ChildPath $fileName
        }

        $item = [DownloadItem]::new()
        $item.Id = $update.Name
        $item.Source = $update.Url
        $item.Destination = $destination
        $item.Category = if ($isNetUpdate) { "DotNetUpdate" } else { "WindowsUpdate" }
        $item.DisplayName = $update.Name
        $item.Metadata = @{
            UpdateType = if ($isNetUpdate) { "DotNet" } else { "WindowsUpdate" }
        }

        $items.Add($item)
    }

    WriteLog "Created $($items.Count) download items from $($Updates.Count) updates"
    return $items.ToArray()
}

function New-DownloadItem {
    <#
    .SYNOPSIS
        Creates a new DownloadItem object for parallel downloading

    .DESCRIPTION
        Factory function to create a DownloadItem object. This function is required because
        PowerShell classes defined in modules are not directly accessible from calling scripts.

    .PARAMETER Id
        Unique identifier for tracking

    .PARAMETER Source
        URL to download from

    .PARAMETER Destination
        Local file path to save to

    .PARAMETER DisplayName
        Human-readable name for progress display (defaults to Id if not specified)

    .PARAMETER Category
        Category for grouping (e.g., "WindowsUpdate", "Defender", "Apps")

    .PARAMETER Metadata
        Optional hashtable with additional context

    .OUTPUTS
        DownloadItem object

    .EXAMPLE
        $item = New-DownloadItem -Id "KB5001" -Source "https://..." -Destination "C:\KB\file.msu" -DisplayName "SSU Update" -Category "WindowsUpdate"
    #>
    [CmdletBinding()]
    [OutputType([DownloadItem])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Id,

        [Parameter(Mandatory = $true)]
        [string]$Source,

        [Parameter(Mandatory = $true)]
        [string]$Destination,

        [Parameter()]
        [string]$DisplayName = $null,

        [Parameter()]
        [string]$Category = "General",

        [Parameter()]
        [hashtable]$Metadata = @{}
    )

    $item = [DownloadItem]::new()
    $item.Id = $Id
    $item.Source = $Source
    $item.Destination = $Destination
    $item.Category = $Category
    $item.DisplayName = if ([string]::IsNullOrEmpty($DisplayName)) { $Id } else { $DisplayName }
    $item.Metadata = $Metadata

    return $item
}

function New-ParallelDownloadConfig {
    <#
    .SYNOPSIS
        Creates a new ParallelDownloadConfig object

    .DESCRIPTION
        Factory function to create a ParallelDownloadConfig object for configuring parallel downloads.

    .PARAMETER MaxConcurrentDownloads
        Maximum number of concurrent downloads (default: 5)

    .PARAMETER RetryCount
        Number of retries per download method (default: 3)

    .PARAMETER LogPath
        Path to log file for download logging

    .PARAMETER ContinueOnError
        Whether to continue downloading other files if one fails (default: true)

    .PARAMETER ProgressCallback
        Optional scriptblock to call with progress updates

    .OUTPUTS
        ParallelDownloadConfig object

    .EXAMPLE
        $config = New-ParallelDownloadConfig -MaxConcurrentDownloads 3 -RetryCount 5
    #>
    [CmdletBinding()]
    [OutputType([ParallelDownloadConfig])]
    param(
        [Parameter()]
        [int]$MaxConcurrentDownloads = 5,

        [Parameter()]
        [int]$RetryCount = 3,

        [Parameter()]
        [string]$LogPath = $null,

        [Parameter()]
        [bool]$ContinueOnError = $true,

        [Parameter()]
        [scriptblock]$ProgressCallback = $null
    )

    $config = [ParallelDownloadConfig]::new()
    $config.MaxConcurrentDownloads = $MaxConcurrentDownloads
    $config.RetryCount = $RetryCount
    $config.LogPath = $LogPath
    $config.ContinueOnError = $ContinueOnError
    $config.ProgressCallback = $ProgressCallback

    return $config
}

function New-GenericDownloadItem {
    <#
    .SYNOPSIS
        Creates a single DownloadItem object for a file download (alias for New-DownloadItem)

    .DESCRIPTION
        Helper function to create a DownloadItem for non-KB downloads like Defender updates,
        OneDrive, Edge, etc. This is an alias for New-DownloadItem for backward compatibility.

    .PARAMETER Id
        Unique identifier for tracking

    .PARAMETER Source
        URL to download from

    .PARAMETER Destination
        Local file path to save to

    .PARAMETER DisplayName
        Human-readable name for progress display

    .PARAMETER Category
        Category for grouping (e.g., "Defender", "Apps", "Tools")

    .OUTPUTS
        DownloadItem object

    .EXAMPLE
        $item = New-GenericDownloadItem -Id "OneDrive" -Source "https://..." -Destination "C:\Apps\OneDrive.exe" -DisplayName "OneDrive Setup" -Category "Apps"
    #>
    [CmdletBinding()]
    [OutputType([DownloadItem])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Id,

        [Parameter(Mandatory = $true)]
        [string]$Source,

        [Parameter(Mandatory = $true)]
        [string]$Destination,

        [Parameter()]
        [string]$DisplayName = $null,

        [Parameter()]
        [string]$Category = "General"
    )

    return New-DownloadItem -Id $Id -Source $Source -Destination $Destination -DisplayName $DisplayName -Category $Category
}

function Get-ParallelDownloadSummary {
    <#
    .SYNOPSIS
        Generates a summary of parallel download results

    .DESCRIPTION
        Takes an array of DownloadResult objects and produces a summary including
        success/failure counts, total bytes downloaded, and error details.

    .PARAMETER Results
        Array of DownloadResult objects from Start-ParallelDownloads

    .OUTPUTS
        PSCustomObject with summary statistics

    .EXAMPLE
        $results = Start-ParallelDownloads -Downloads $items
        $summary = Get-ParallelDownloadSummary -Results $results
        Write-Host "Downloaded $($summary.SuccessCount) of $($summary.TotalCount) files"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [array]$Results
    )

    $successful = @($Results | Where-Object { $_.Success -eq $true })
    $failed = @($Results | Where-Object { $_.Success -ne $true })
    $totalBytes = ($successful | Measure-Object -Property BytesDownloaded -Sum).Sum
    $totalDuration = ($Results | Measure-Object -Property DurationSeconds -Sum).Sum

    return [PSCustomObject]@{
        TotalCount       = $Results.Count
        SuccessCount     = $successful.Count
        FailedCount      = $failed.Count
        TotalBytesDownloaded = $totalBytes
        TotalDurationSeconds = $totalDuration
        AverageBytesPerSecond = if ($totalDuration -gt 0) { [math]::Round($totalBytes / $totalDuration, 2) } else { 0 }
        FailedDownloads  = $failed | ForEach-Object {
            [PSCustomObject]@{
                Id           = $_.Id
                Source       = $_.Source
                ErrorMessage = $_.ErrorMessage
            }
        }
        SuccessRate      = if ($Results.Count -gt 0) { [math]::Round(($successful.Count / $Results.Count) * 100, 1) } else { 0 }
    }
}

# Export functions
Export-ModuleMember -Function Start-ParallelDownloads, New-KBDownloadItems, New-DownloadItem, New-ParallelDownloadConfig, New-GenericDownloadItem, Get-ParallelDownloadSummary
