param(
	[Parameter(Mandatory)]
	[string]$Stage,
	[Parameter(Mandatory)]
	[string]$LogPath,
	[Parameter(Mandatory)]
	[scriptblock]$Action
)

$ErrorActionPreference = 'Stop'
$failure = $null
$transcriptStarted = $false
$markerWritten = $false
$markerPath = Join-Path $env:SystemRoot 'Temp\FFUBuildVmFailure.json'
try {
	Start-Transcript -LiteralPath $LogPath -Append -Force | Out-Null
	$transcriptStarted = $true
	& $Action
}
catch {
	$failure = $_
	$details = $failure.Exception.Data
	$failureStage = if ($Stage -eq 'Orchestration' -and $details['FFUSysprepFailure']) { 'Sysprep' } else { $Stage }
	Write-Warning "FFU build VM failed during ${failureStage}: $($failure.Exception.Message)"

	$retryCount = $details['FFUSysprepRetryCount']
	if (-not $details.Contains('FFUSysprepRetryCount')) {
		try {
			$retryStatePath = Join-Path $env:SystemRoot 'Setup\Scripts\Logs\SysprepRetry.state'
			$retryCount = if (Test-Path -LiteralPath $retryStatePath) {
				[int](Get-Content -LiteralPath $retryStatePath -Raw).Trim()
			}
			else { 0 }
		}
		catch {
			Write-Warning "Unable to read the Sysprep retry count: $($_.Exception.Message)"
		}
	}

	try {
		[ordered]@{
			Stage                = $failureStage
			TimestampUtc         = [DateTime]::UtcNow.ToString('o')
			Message              = $failure.Exception.Message
			RetryCount           = $retryCount
			PendingRebootReasons = @($details['FFUPendingRebootReasons'] | Where-Object { $null -ne $_ })
			SysprepExitCode      = $details['FFUSysprepExitCode']
		} | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $markerPath -Encoding UTF8 -Force
		$markerWritten = $true
		Write-Host "Recorded build VM failure at '$markerPath'. Shutting down the build VM."
	}
	catch {
		Write-Warning "Unable to write the build VM failure marker '$markerPath'. No shutdown was requested: $($_.Exception.Message)"
	}
}
finally {
	if ($transcriptStarted) {
		try {
			Stop-Transcript | Out-Null
			$transcriptStarted = $false
		}
		catch {
			if ($null -eq $failure) { throw }
			Write-Warning "Unable to close the build VM transcript. No shutdown was requested: $($_.Exception.Message)"
		}
	}
}

if ($null -ne $failure) {
	if ($markerWritten -and -not $transcriptStarted) {
		try {
			Stop-Computer
		}
		catch {
			$shutdownWarning = "Unable to shut down the build VM after recording its failure: $($_.Exception.Message)"
			Write-Warning $shutdownWarning
			try {
				Add-Content -LiteralPath $LogPath -Value $shutdownWarning -Encoding UTF8
			}
			catch {
				Write-Warning "Unable to append the shutdown error to '$LogPath': $($_.Exception.Message)"
			}
		}
	}
	throw $failure
}
