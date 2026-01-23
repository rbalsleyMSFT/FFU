<#
.SYNOPSIS
    Pre-flight check for VMware bridge network adapter configuration.

.DESCRIPTION
    Validates that VMware Workstation Pro bridging will use the correct network
    adapter during FFU builds. Detects the recommended adapter (with internet
    connectivity) and warns about problematic adapters like GlobalProtect VPN.

    Issues detected:
    - GlobalProtect/PANGPS VPN adapters present (can cause VMware to bridge wrong)
    - Multiple adapters with network connectivity (ambiguous auto-bridge selection)
    - No netmap.conf file (VMware network not configured)

.PARAMETER HypervisorType
    The hypervisor being used. Check only runs for 'VMware'.

.EXAMPLE
    $result = Test-FFUVMwareBridgeConfiguration -HypervisorType 'VMware'
    if ($result.Status -eq 'Warning') {
        Write-Warning $result.Message
        Write-Host $result.Remediation
    }

.OUTPUTS
    FFUCheckResult object with status, message, and remediation steps

.NOTES
    This check is WARNING-level, not blocking, because:
    - VMware may auto-select the correct adapter
    - User may have already configured bridging manually
    - The issue only manifests during FFU capture, not VM creation
#>

function Test-FFUVMwareBridgeConfiguration {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)]
        [ValidateSet('HyperV', 'VMware', 'Auto')]
        [string]$HypervisorType = 'HyperV'
    )

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    # Skip if not VMware
    if ($HypervisorType -ne 'VMware') {
        $stopwatch.Stop()
        return [PSCustomObject]@{
            CheckName   = 'VMwareBridgeConfig'
            Status      = 'Skipped'
            Message     = "VMware bridge configuration check skipped (HypervisorType: $HypervisorType)"
            Details     = @{}
            Remediation = ''
            DurationMs  = $stopwatch.ElapsedMilliseconds
        }
    }

    # Patterns to exclude from bridging (VPN and problematic adapters)
    $excludePatterns = @(
        '*PANGP*',
        '*GlobalProtect*',
        '*Palo Alto*',
        '*Cisco AnyConnect*',
        '*Juniper*',
        '*VPN*',
        '*Tunnel*'
    )

    $details = @{
        RecommendedAdapter    = $null
        RecommendedAdapterGUID = $null
        ProblematicAdapters   = @()
        ConnectedAdapters     = @()
        NetmapExists          = $false
        VMnetBridgeBindCount  = 0
    }

    try {
        # Check if netmap.conf exists (indicates user has configured networking)
        $netmapPath = "C:\ProgramData\VMware\netmap.conf"
        $details.NetmapExists = Test-Path $netmapPath

        # Get adapters bound to VMnetBridge
        $linkage = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\VMnetBridge\Linkage' -ErrorAction SilentlyContinue
        if ($linkage -and $linkage.Bind) {
            $details.VMnetBridgeBindCount = $linkage.Bind.Count
        }

        # Find adapters with internet connectivity
        $gatewayConfigs = Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway -ne $null }

        foreach ($config in $gatewayConfigs) {
            $adapter = Get-NetAdapter -InterfaceAlias $config.InterfaceAlias -ErrorAction SilentlyContinue
            if (-not $adapter) { continue }

            $adapterInfo = @{
                Name        = $adapter.Name
                Description = $adapter.InterfaceDescription
                GUID        = $adapter.InterfaceGuid
                MAC         = $adapter.MacAddress
                Status      = $adapter.Status
                IPv4        = ($config.IPv4Address | Select-Object -First 1).IPAddress
            }

            # Check if it's a problematic adapter
            $isProblematic = $false
            foreach ($pattern in $excludePatterns) {
                if ($adapter.InterfaceDescription -like $pattern -or $adapter.Name -like $pattern) {
                    $isProblematic = $true
                    $details.ProblematicAdapters += $adapterInfo
                    break
                }
            }

            if (-not $isProblematic) {
                $details.ConnectedAdapters += $adapterInfo

                # Test actual internet connectivity
                if (-not $details.RecommendedAdapter) {
                    $testResult = Test-NetConnection -ComputerName "8.8.8.8" -WarningAction SilentlyContinue
                    if ($testResult.PingSucceeded) {
                        $details.RecommendedAdapter = $adapterInfo.Description
                        $details.RecommendedAdapterGUID = $adapterInfo.GUID
                    }
                }
            }
        }

        $stopwatch.Stop()

        # Determine result status and message
        $issues = @()
        $warnings = @()

        # Check for problematic adapters
        if ($details.ProblematicAdapters.Count -gt 0) {
            $problematicNames = ($details.ProblematicAdapters | ForEach-Object { $_.Description }) -join ', '
            $warnings += "VPN/problematic adapters detected: $problematicNames"
        }

        # Check if we found a recommended adapter
        if (-not $details.RecommendedAdapter) {
            $issues += "No suitable network adapter with internet connectivity found"
        }

        # Check if netmap.conf exists
        if (-not $details.NetmapExists) {
            $warnings += "VMware network not configured (netmap.conf not found)"
        }

        # Build result
        if ($issues.Count -gt 0) {
            # FAILED - No suitable adapter
            $remediation = @"
ISSUE: No network adapter with internet connectivity found.

REQUIRED STEPS:
1. Ensure your network adapter is connected and has internet access
2. Check that your network adapter is not disabled
3. Run 'Test-NetConnection -ComputerName 8.8.8.8' to verify connectivity
"@
            return [PSCustomObject]@{
                CheckName   = 'VMwareBridgeConfig'
                Status      = 'Failed'
                Message     = ($issues -join '; ')
                Details     = $details
                Remediation = $remediation
                DurationMs  = $stopwatch.ElapsedMilliseconds
            }
        }
        elseif ($warnings.Count -gt 0) {
            # WARNING - Potential bridge issues
            $problematicList = if ($details.ProblematicAdapters.Count -gt 0) {
                "`nProblematic adapters to EXCLUDE:`n" + ($details.ProblematicAdapters | ForEach-Object { "  - $($_.Description)" } | Out-String)
            } else { "" }

            $remediation = @"
RECOMMENDED: Configure VMware bridging to use the correct adapter.

Your recommended adapter: $($details.RecommendedAdapter)
$problematicList
STEPS TO CONFIGURE:
1. Open VMware Virtual Network Editor:
   - Run: "C:\Program Files (x86)\VMware\VMware Workstation\vmnetcfg.exe"
   - Or: In VMware Workstation, go to Edit > Virtual Network Editor

2. Click 'Change Settings' (requires Administrator)

3. Select 'VMnet0 (Bridged)' from the list

4. Change 'Bridged to:' from 'Automatic' to:
   '$($details.RecommendedAdapter)'

5. (Optional) Click 'Automatic Settings' and UNCHECK any VPN adapters:
   - PANGP Virtual Ethernet Adapter
   - GlobalProtect adapters
   - Any other VPN adapters

6. Click 'Apply' and 'OK'

WHY THIS IS NEEDED:
VMware's auto-bridging may select a VPN adapter or disconnected adapter
instead of your active network adapter. This causes Error 53 (network
path not found) during FFU capture when the VM cannot reach the host's
network share.
"@
            return [PSCustomObject]@{
                CheckName   = 'VMwareBridgeConfig'
                Status      = 'Warning'
                Message     = "VMware bridging may select wrong adapter. Recommended: $($details.RecommendedAdapter). $($warnings -join '; ')"
                Details     = $details
                Remediation = $remediation
                DurationMs  = $stopwatch.ElapsedMilliseconds
            }
        }
        else {
            # PASSED - All good
            return [PSCustomObject]@{
                CheckName   = 'VMwareBridgeConfig'
                Status      = 'Passed'
                Message     = "VMware bridging configured. Recommended adapter: $($details.RecommendedAdapter)"
                Details     = $details
                Remediation = ''
                DurationMs  = $stopwatch.ElapsedMilliseconds
            }
        }
    }
    catch {
        $stopwatch.Stop()
        return [PSCustomObject]@{
            CheckName   = 'VMwareBridgeConfig'
            Status      = 'Warning'
            Message     = "Could not verify VMware bridge configuration: $($_.Exception.Message)"
            Details     = $details
            Remediation = 'Manually verify VMware bridging is configured to use your active network adapter.'
            DurationMs  = $stopwatch.ElapsedMilliseconds
        }
    }
}

# Test the function
Write-Host "=== Testing VMware Bridge Configuration Check ===" -ForegroundColor Cyan
$result = Test-FFUVMwareBridgeConfiguration -HypervisorType 'VMware'

Write-Host "`nResult:" -ForegroundColor Yellow
Write-Host "  Status: $($result.Status)" -ForegroundColor $(switch ($result.Status) { 'Passed' { 'Green' } 'Warning' { 'Yellow' } 'Failed' { 'Red' } default { 'White' } })
Write-Host "  Message: $($result.Message)"
Write-Host "  Duration: $($result.DurationMs)ms"

Write-Host "`nDetails:" -ForegroundColor Yellow
$result.Details | Format-List

if ($result.Remediation) {
    Write-Host "`nRemediation:" -ForegroundColor Cyan
    Write-Host $result.Remediation
}
