$ErrorActionPreference = 'Stop'

& (Join-Path $PSScriptRoot 'Invoke-FFUBuildVmStage.ps1') -Stage 'Orchestration' -LogPath 'C:\Windows\Temp\FFUOrchestrationBootstrap.log' -Action {
    Write-Host "---------------------------------------------------" -ForegroundColor Yellow
    Write-Host "             FFU Builder Orchestrator              " -ForegroundColor Yellow
    Write-Host "---------------------------------------------------" -ForegroundColor Yellow
    Write-Host 'Starting FFU orchestration bootstrap.'
    $driveLetterRuntimeDirectory = 'C:\Windows\Setup\Scripts\FFUDL'
    $driveLetterScriptPath = Join-Path -Path $driveLetterRuntimeDirectory -ChildPath 'Apply.ps1'
    $driveLetterManifestPath = Join-Path -Path $driveLetterRuntimeDirectory -ChildPath 'Manifest.json'
    if (Test-Path -LiteralPath $driveLetterScriptPath -PathType Leaf) {
        Write-Host 'Applying configured data partition drive letters before locating Apps media.'
        & 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -NoProfile -ExecutionPolicy Bypass -File $driveLetterScriptPath -ManifestPath $driveLetterManifestPath -Phase Audit
        $driveLetterExitCode = $LASTEXITCODE
        if ($driveLetterExitCode -ne 0) {
            throw "Data partition drive-letter enforcement failed with exit code $driveLetterExitCode."
        }
        Write-Host 'Configured data partition drive letters are ready.'
    }

    $deadline = (Get-Date).AddMinutes(10)
    $orchestratorPath = $null

    do {
        $fileSystemDrives = @(Get-PSDrive -PSProvider FileSystem | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.Root) })
        foreach ($driveInfo in $fileSystemDrives) {
            $candidatePath = Join-Path -Path $driveInfo.Root -ChildPath 'Orchestration\Orchestrator.ps1'
            Write-Host "Checking for orchestrator at $candidatePath"
            if (Test-Path -Path $candidatePath -PathType Leaf) {
                $orchestratorPath = $candidatePath
                break
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($orchestratorPath)) {
            break
        }

        Write-Host 'Apps ISO orchestrator was not found yet. Waiting before retry.'
        Start-Sleep -Seconds 5
    } while ((Get-Date) -lt $deadline)

    if ([string]::IsNullOrWhiteSpace($orchestratorPath)) {
        throw 'Unable to locate Apps ISO orchestrator after waiting for Apps media.'
    }

    $env:FFUAppsRoot = Split-Path -Parent (Split-Path -Parent $orchestratorPath)
    Write-Host "Using Apps media root: $env:FFUAppsRoot"
    Write-Host "Launching orchestrator: $orchestratorPath"
    & $orchestratorPath
    Write-Host 'FFU orchestrator completed.'
}