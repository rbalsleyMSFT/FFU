<#
.SYNOPSIS
    FFU Capture Script for WinPE Environment

.DESCRIPTION
    This script runs in Windows PE to capture a Full Flash Update (FFU) image
    from a target disk and upload it to a network share.

.SECURITY WARNING
    ============================================================================
    THIS FILE CONTAINS AUTHENTICATION CREDENTIALS IN PLAIN TEXT
    ============================================================================

    The credentials below are required for WinPE to connect to the FFU capture
    network share. WinPE is a minimal environment that cannot use:
    - Windows Credential Manager
    - DPAPI-protected secrets
    - Secure credential stores

    SECURITY MEASURES IN PLACE:
    1. Password is randomly generated (32 characters) for each build
    2. Password is unique per build session - never reused
    3. The ffu_user account is automatically removed after capture
    4. Account has a 4-hour expiry failsafe (auto-disabled if cleanup fails)
    5. Credentials are sanitized from source files after capture completes
    6. Password is NOT logged during the build process

    RECOMMENDATIONS:
    - Do not leave capture media (USB/ISO) unattended
    - Destroy or securely store capture media after use
    - Do not share this file or capture media
    - The credentials become invalid after the ffu_user account is removed

    For more information, see: docs/designs/CREDENTIAL-SECURITY.md
    ============================================================================
#>

# Runtime configuration - values replaced by Update-CaptureFFUScript
$VMHostIPAddress = '192.168.1.158'
$ShareName = 'FFUCaptureShare'
$UserName = 'ffu_user'
$Password = '23202eb4-10c3-47e9-b389-f0c462663a23'
$CustomFFUNameTemplate = '{WindowsRelease}_{WindowsVersion}_{SKU}_{yyyy}-{MM}-{dd}_{HH}{mm}'

# Solution C: Automatic Network Wait + Retry + Diagnostics

function Get-WmiNetworkAdapter {
    <#
    .SYNOPSIS
    WMI-based alternative to Get-NetAdapter for WinPE compatibility

    .DESCRIPTION
    Uses Win32_NetworkAdapter WMI class to query network adapters.
    This works in WinPE where the NetAdapter PowerShell module is not available.

    .PARAMETER ConnectedOnly
    If specified, returns only connected adapters (NetConnectionStatus = 2)

    .EXAMPLE
    Get-WmiNetworkAdapter -ConnectedOnly

    .NOTES
    NetConnectionStatus values:
    0 = Disconnected
    2 = Connected
    7 = Media Disconnected
    9 = Connecting
    #>
    param(
        [Parameter(Mandatory = $false)]
        [switch]$ConnectedOnly
    )

    try {
        $adapters = Get-CimInstance -ClassName Win32_NetworkAdapter -ErrorAction Stop | Where-Object {
            # Filter out virtual/software adapters (PhysicalAdapter property may not exist in all WinPE versions)
            $_.AdapterType -notlike "*software*" -and
            $_.Name -notlike "*Virtual*" -and
            $_.Name -notlike "*Loopback*" -and
            $_.Name -notlike "*Bluetooth*" -and
            $_.NetConnectionID -ne $null
        }

        if ($ConnectedOnly) {
            $adapters = $adapters | Where-Object { $_.NetConnectionStatus -eq 2 }
        }

        # Return adapters with normalized property names for compatibility
        $adapters | ForEach-Object {
            [PSCustomObject]@{
                Name = $_.NetConnectionID
                InterfaceDescription = $_.Name
                Status = switch ($_.NetConnectionStatus) {
                    0 { 'Disconnected' }
                    2 { 'Up' }
                    7 { 'Disconnected' }
                    9 { 'Connecting' }
                    default { 'Unknown' }
                }
                LinkSpeed = if ($_.Speed) { "$([math]::Round($_.Speed / 1MB)) Mbps" } else { "Unknown" }
                MacAddress = $_.MACAddress
                NetConnectionStatus = $_.NetConnectionStatus
                NetEnabled = $_.NetEnabled
                DeviceID = $_.DeviceID
            }
        }
    }
    catch {
        Write-Host "Error querying network adapters via WMI: $_" -ForegroundColor Red
        return $null
    }
}

function Get-WmiIPAddress {
    <#
    .SYNOPSIS
    WMI-based alternative to Get-NetIPAddress for WinPE compatibility

    .DESCRIPTION
    Uses Win32_NetworkAdapterConfiguration WMI class to query IP addresses.
    This works in WinPE where the NetTCPIP PowerShell module is not available.

    .PARAMETER AddressFamily
    Filter by address family. Only 'IPv4' is supported (IPv6 filtering done automatically)

    .EXAMPLE
    Get-WmiIPAddress -AddressFamily IPv4

    .NOTES
    Returns objects with IPAddress, InterfaceAlias, and SubnetMask properties
    to match Get-NetIPAddress output format.
    #>
    param(
        [Parameter(Mandatory = $false)]
        [ValidateSet('IPv4', 'IPv6')]
        [string]$AddressFamily = 'IPv4'
    )

    try {
        $configs = Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -ErrorAction Stop |
            Where-Object { $_.IPEnabled -eq $true -and $_.IPAddress }

        $results = @()
        foreach ($config in $configs) {
            for ($i = 0; $i -lt $config.IPAddress.Count; $i++) {
                $ip = $config.IPAddress[$i]
                $subnet = if ($config.IPSubnet -and $config.IPSubnet[$i]) { $config.IPSubnet[$i] } else { "255.255.255.0" }

                # Filter by address family
                if ($AddressFamily -eq 'IPv4' -and $ip -match '^\d+\.\d+\.\d+\.\d+$') {
                    $results += [PSCustomObject]@{
                        IPAddress = $ip
                        InterfaceAlias = $config.Description
                        SubnetMask = $subnet
                        PrefixLength = (Convert-SubnetMaskToPrefix -SubnetMask $subnet)
                        DHCPEnabled = $config.DHCPEnabled
                    }
                }
                elseif ($AddressFamily -eq 'IPv6' -and $ip -match ':') {
                    $results += [PSCustomObject]@{
                        IPAddress = $ip
                        InterfaceAlias = $config.Description
                        SubnetMask = $subnet
                        PrefixLength = $subnet
                        DHCPEnabled = $config.DHCPEnabled
                    }
                }
            }
        }
        return $results
    }
    catch {
        Write-Host "Error querying IP addresses via WMI: $_" -ForegroundColor Red
        return $null
    }
}

function Convert-SubnetMaskToPrefix {
    <#
    .SYNOPSIS
    Converts a subnet mask to CIDR prefix length

    .EXAMPLE
    Convert-SubnetMaskToPrefix -SubnetMask "255.255.255.0"  # Returns 24
    #>
    param([string]$SubnetMask)

    try {
        $binaryBits = ([IPAddress]$SubnetMask).GetAddressBytes() | ForEach-Object { [Convert]::ToString($_, 2).PadLeft(8, '0') }
        return ($binaryBits -join '').TrimEnd('0').Length
    }
    catch {
        return 24  # Default to /24 if conversion fails
    }
}

function Get-WmiDefaultGateway {
    <#
    .SYNOPSIS
    WMI-based alternative to Get-NetRoute for default gateway in WinPE

    .DESCRIPTION
    Uses Win32_NetworkAdapterConfiguration WMI class to query default gateway.
    This works in WinPE where the NetTCPIP PowerShell module is not available.

    .EXAMPLE
    Get-WmiDefaultGateway

    .NOTES
    Returns objects with NextHop, DestinationPrefix, and InterfaceAlias properties
    to match Get-NetRoute output format.
    #>
    try {
        $configs = Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -ErrorAction Stop |
            Where-Object { $_.IPEnabled -eq $true -and $_.DefaultIPGateway }

        $results = @()
        foreach ($config in $configs) {
            foreach ($gateway in $config.DefaultIPGateway) {
                $results += [PSCustomObject]@{
                    NextHop = $gateway
                    DestinationPrefix = "0.0.0.0/0"
                    InterfaceAlias = $config.Description
                }
            }
        }
        return $results
    }
    catch {
        Write-Host "Error querying default gateway via WMI: $_" -ForegroundColor Red
        return $null
    }
}

function Test-HostConnection {
    <#
    .SYNOPSIS
    Tests connectivity to a host using ping.exe (WinPE compatible)

    .DESCRIPTION
    Uses ping.exe instead of Test-Connection cmdlet for WinPE compatibility.
    Test-Connection may not work reliably in WinPE environments.

    .PARAMETER ComputerName
    IP address or hostname to test connectivity to

    .PARAMETER Count
    Number of ping attempts (default: 1)

    .PARAMETER Quiet
    If specified, returns only $true/$false instead of detailed output

    .EXAMPLE
    Test-HostConnection -ComputerName "192.168.1.100" -Count 1 -Quiet

    .NOTES
    Returns $true if host is reachable, $false otherwise
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ComputerName,

        [Parameter(Mandatory = $false)]
        [int]$Count = 1,

        [Parameter(Mandatory = $false)]
        [switch]$Quiet
    )

    try {
        $pingOutput = & ping.exe -n $Count -w 2000 $ComputerName 2>&1
        $success = $LASTEXITCODE -eq 0

        if ($Quiet) {
            return $success
        }
        else {
            # Return ping output for diagnostic purposes
            return [PSCustomObject]@{
                Success = $success
                ComputerName = $ComputerName
                Output = ($pingOutput | Out-String)
            }
        }
    }
    catch {
        if ($Quiet) {
            return $false
        }
        else {
            return [PSCustomObject]@{
                Success = $false
                ComputerName = $ComputerName
                Output = "Ping failed with error: $_"
            }
        }
    }
}

function Resolve-HostNameDotNet {
    <#
    .SYNOPSIS
    .NET-based alternative to Resolve-DnsName for WinPE compatibility

    .DESCRIPTION
    Uses System.Net.Dns .NET class for DNS resolution.
    This works in WinPE where the DnsClient PowerShell module is not available.

    .PARAMETER Name
    Hostname or IP address to resolve

    .EXAMPLE
    Resolve-HostNameDotNet -Name "192.168.1.100"

    .NOTES
    Returns resolved IP addresses or $null if resolution fails
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    try {
        $resolved = [System.Net.Dns]::GetHostAddresses($Name)
        return $resolved | ForEach-Object {
            [PSCustomObject]@{
                IPAddress = $_.IPAddressToString
                AddressFamily = $_.AddressFamily
            }
        }
    }
    catch {
        # DNS resolution failed - not critical when using IP addresses directly
        return $null
    }
}

function Wait-For-NetworkReady {
    <#
    .SYNOPSIS
    Waits for network to be fully initialized and ready for SMB connections

    .DESCRIPTION
    Validates network adapter, IP address, and host connectivity before proceeding.
    Implements intelligent waiting with timeout to handle WinPE boot timing issues.

    .PARAMETER HostIP
    IP address of the host to validate connectivity to

    .PARAMETER TimeoutSeconds
    Maximum time to wait for network readiness (default: 60 seconds)

    .EXAMPLE
    Wait-For-NetworkReady -HostIP "192.168.1.100" -TimeoutSeconds 60
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$HostIP,

        [Parameter(Mandatory = $false)]
        [int]$TimeoutSeconds = 60
    )

    Write-Host "`n========== Network Initialization =========="
    Write-Host "Waiting for network to be ready (timeout: ${TimeoutSeconds}s)..."
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $script:pingWarningShown = $false  # Track if we've shown the ICMP warning

    while ($stopwatch.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        $elapsed = [math]::Round($stopwatch.Elapsed.TotalSeconds)

        # Check 1: Network adapter exists and is up
        $adapter = Get-WmiNetworkAdapter -ConnectedOnly
        if (-not $adapter) {
            Write-Host "  [$elapsed`s] Waiting for network adapter..." -ForegroundColor Yellow
            Start-Sleep -Seconds 2
            continue
        }

        # Check 2: IP address assigned (not APIPA 169.254.x.x)
        # Using WMI alternative for WinPE compatibility (Get-NetIPAddress not available)
        $ip = Get-WmiIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike "169.254.*" -and $_.IPAddress -ne "127.0.0.1" }
        if (-not $ip) {
            Write-Host "  [$elapsed`s] Waiting for IP address (DHCP)..." -ForegroundColor Yellow
            Start-Sleep -Seconds 2
            continue
        }

        # Check 3: Default gateway exists (optional but recommended)
        # Using WMI alternative for WinPE compatibility (Get-NetRoute not available)
        $gateway = Get-WmiDefaultGateway
        $gatewayIP = if ($gateway) { $gateway[0].NextHop } else { "None" }

        # Check 4: Host is reachable via ping (NON-BLOCKING - ICMP may be blocked by firewall)
        # Using ping.exe for WinPE compatibility (Test-Connection may not work)
        # Note: Many corporate environments block ICMP but allow SMB. If ping fails,
        # we proceed anyway and let the SMB connection attempt provide the real error.
        $ping = Test-HostConnection -ComputerName $HostIP -Count 1 -Quiet
        $hostStatus = if ($ping) { "reachable" } else { "ping blocked/failed" }

        if (-not $ping) {
            # Only show warning once, don't block progress
            if (-not $script:pingWarningShown) {
                Write-Host "  [$elapsed`s] Note: Ping to host ($HostIP) failed - ICMP may be blocked by firewall" -ForegroundColor Yellow
                Write-Host "  [$elapsed`s] Proceeding anyway - SMB connection will provide definitive status" -ForegroundColor Yellow
                $script:pingWarningShown = $true
            }
            # Don't 'continue' - proceed to success checks below
        }

        # All checks passed (or ping skipped due to ICMP blocking)
        Write-Host "[SUCCESS] Network ready!" -ForegroundColor Green
        Write-Host "  Adapter: $($adapter[0].Name)" -ForegroundColor Cyan
        Write-Host "  IP Address: $($ip[0].IPAddress)" -ForegroundColor Cyan
        Write-Host "  Gateway: $gatewayIP" -ForegroundColor Cyan
        Write-Host "  Host: $HostIP ($hostStatus)" -ForegroundColor Cyan
        Write-Host "  Time elapsed: $elapsed seconds" -ForegroundColor Cyan
        Write-Host "==========================================`n"

        return $true
    }

    # Timeout reached
    Write-Host "`n[TIMEOUT] Network failed to become ready within ${TimeoutSeconds} seconds" -ForegroundColor Red
    Write-Host "Current network state:" -ForegroundColor Yellow

    $adapters = Get-WmiNetworkAdapter
    if ($adapters) {
        Write-Host "  Adapters found: $($adapters.Count)" -ForegroundColor Yellow
        $adapters | ForEach-Object { Write-Host "    - $($_.Name): $($_.Status)" -ForegroundColor Yellow }
    } else {
        Write-Host "  No network adapters found!" -ForegroundColor Red
    }

    # Using WMI alternative for WinPE compatibility (Get-NetIPAddress not available)
    $ips = Get-WmiIPAddress -AddressFamily IPv4
    if ($ips) {
        Write-Host "  IP Addresses:" -ForegroundColor Yellow
        $ips | ForEach-Object { Write-Host "    - $($_.IPAddress) on $($_.InterfaceAlias)" -ForegroundColor Yellow }
    } else {
        Write-Host "  No IP addresses assigned!" -ForegroundColor Red
    }

    return $false
}

function Connect-NetworkShareWithRetry {
    <#
    .SYNOPSIS
    Connects to network share with automatic retry and diagnostics

    .DESCRIPTION
    Attempts to connect to SMB network share with intelligent retry logic.
    Provides detailed error messages and diagnostics on failure.

    .PARAMETER SharePath
    UNC path to the network share (e.g., \\192.168.1.100\ShareName)

    .PARAMETER Username
    Username for authentication

    .PARAMETER Password
    Password for authentication

    .PARAMETER DriveLetter
    Drive letter to map (e.g., W:)

    .PARAMETER MaxRetries
    Maximum number of connection attempts (default: 3)

    .EXAMPLE
    Connect-NetworkShareWithRetry -SharePath "\\192.168.1.100\FFUCaptureShare" -Username "ffu_user" -Password "pass123" -DriveLetter "W:" -MaxRetries 3
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$SharePath,

        [Parameter(Mandatory = $true)]
        [string]$Username,

        [Parameter(Mandatory = $true)]
        [string]$Password,

        [Parameter(Mandatory = $true)]
        [string]$DriveLetter,

        [Parameter(Mandatory = $false)]
        [int]$MaxRetries = 3
    )

    Write-Host "`n========== Connecting to Network Share =========="

    for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
        Write-Host "`nAttempt $attempt of $MaxRetries" -ForegroundColor Cyan
        Write-Host "Connecting to: $SharePath"
        Write-Host "Drive letter: $DriveLetter"
        Write-Host "Username: $Username"

        try {
            $netUseResult = net use $DriveLetter $SharePath "/user:$Username" "$Password" 2>&1

            if ($LASTEXITCODE -eq 0) {
                Write-Host "[SUCCESS] Connected to network share on drive $DriveLetter" -ForegroundColor Green
                Write-Host "=============================================`n"
                return $true
            }

            # Parse error code from net use output
            $message = $netUseResult | Out-String
            $regex = [regex]'System error (\d+)'
            $match = $regex.Match($message)

            if ($match.Success) {
                $errorCode = [int]$match.Groups[1].Value

                $errorDetails = switch ($errorCode) {
                    53 {
                        @"
Network path not found (Error 53)

This usually means:
  - Host IP address is incorrect or unreachable
  - VM network switch is Internal/Private (should be External)
  - Windows Firewall is blocking SMB traffic (port 445/TCP)
  - Network cable disconnected (if using External switch)
"@
                    }
                    67 { "Share name not found. Verify share '$ShareName' exists on host." }
                    86 { "Password is incorrect for user '$Username'." }
                    1219 { "Multiple connections to share exist. Disconnect existing connections." }
                    1326 { "Logon failure: Unknown username or bad password." }
                    1385 {
                        @"
Logon failure: User not granted network logon rights.

This is due to User Rights Assignment policy.
See: https://github.com/rbalsleyMSFT/FFU/issues/122
"@
                    }
                    1792 { "Unable to connect. Verify SMB server service is running on host." }
                    2250 { "Network connection attempt timed out." }
                    default { "Network connection failed with error code: $errorCode" }
                }

                Write-Host "[FAIL] $errorDetails" -ForegroundColor Red
                Write-Host "`nRaw error output:" -ForegroundColor Yellow
                Write-Host $message -ForegroundColor Yellow

                if ($attempt -lt $MaxRetries) {
                    Write-Host "`nRetrying in 5 seconds..." -ForegroundColor Yellow
                    Start-Sleep -Seconds 5
                }
            }
            else {
                Write-Host "[FAIL] Could not parse error code from net use output" -ForegroundColor Red
                Write-Host "Raw output: $message" -ForegroundColor Yellow

                if ($attempt -lt $MaxRetries) {
                    Start-Sleep -Seconds 5
                }
            }
        }
        catch {
            Write-Host "[FAIL] Exception during connection attempt: $_" -ForegroundColor Red

            if ($attempt -lt $MaxRetries) {
                Write-Host "Retrying in 5 seconds..." -ForegroundColor Yellow
                Start-Sleep -Seconds 5
            }
        }
    }

    # All retries failed - run comprehensive diagnostics
    Write-Host "`n[CRITICAL] All $MaxRetries connection attempts failed" -ForegroundColor Red
    Write-Host "`n========== NETWORK DIAGNOSTICS ==========" -ForegroundColor Yellow

    Write-Host "`n1. Network Adapters:" -ForegroundColor Cyan
    try {
        Get-WmiNetworkAdapter | Format-Table Name, Status, LinkSpeed, MacAddress -AutoSize | Out-Host
    } catch {
        Write-Host "  Failed to retrieve network adapters: $_" -ForegroundColor Red
    }

    Write-Host "`n2. IP Configuration:" -ForegroundColor Cyan
    try {
        # Using WMI alternative for WinPE compatibility (Get-NetIPAddress not available)
        Get-WmiIPAddress -AddressFamily IPv4 | Format-Table IPAddress, InterfaceAlias, PrefixLength -AutoSize | Out-Host
    } catch {
        Write-Host "  Failed to retrieve IP configuration: $_" -ForegroundColor Red
    }

    Write-Host "`n3. Default Gateway:" -ForegroundColor Cyan
    try {
        # Using WMI alternative for WinPE compatibility (Get-NetRoute not available)
        Get-WmiDefaultGateway | Format-Table DestinationPrefix, NextHop, InterfaceAlias -AutoSize | Out-Host
    } catch {
        Write-Host "  No default gateway configured" -ForegroundColor Yellow
    }

    Write-Host "`n4. Ping Test to Host ($($SharePath.Split('\')[2])):" -ForegroundColor Cyan
    try {
        $hostIP = $SharePath.Split('\')[2]
        # Using ping.exe for WinPE compatibility (Test-Connection may not work)
        $pingResult = Test-HostConnection -ComputerName $hostIP -Count 4
        Write-Host $pingResult.Output
    } catch {
        Write-Host "  Ping failed: $_" -ForegroundColor Red
    }

    Write-Host "`n5. SMB Port 445 Connectivity Test:" -ForegroundColor Cyan
    try {
        $hostIP = $SharePath.Split('\')[2]
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $tcpClient.ReceiveTimeout = 3000
        $tcpClient.SendTimeout = 3000

        $connectTask = $tcpClient.ConnectAsync($hostIP, 445)
        $connectTask.Wait(3000) | Out-Null

        if ($tcpClient.Connected) {
            Write-Host "  [OK] Port 445 is OPEN and accessible" -ForegroundColor Green
            $tcpClient.Close()
        } else {
            Write-Host "  [FAIL] Port 445 connection timed out" -ForegroundColor Red
        }
    } catch {
        Write-Host "  [FAIL] Port 445 is BLOCKED or unreachable" -ForegroundColor Red
        Write-Host "  Error: $_" -ForegroundColor Red
    }

    Write-Host "`n6. DNS Resolution Test:" -ForegroundColor Cyan
    try {
        $hostIP = $SharePath.Split('\')[2]
        # Using .NET alternative for WinPE compatibility (Resolve-DnsName not available)
        $resolved = Resolve-HostNameDotNet -Name $hostIP
        if ($resolved) {
            Write-Host "  Resolved: $($resolved[0].IPAddress)" -ForegroundColor Green
        } else {
            Write-Host "  IP address used (no DNS resolution needed): $hostIP" -ForegroundColor Cyan
        }
    } catch {
        Write-Host "  DNS resolution failed (not critical when using IP): $_" -ForegroundColor Yellow
    }

    Write-Host "`n========== TROUBLESHOOTING GUIDE ==========" -ForegroundColor Yellow
    Write-Host "`nMost Common Solutions (try in order):" -ForegroundColor White
    Write-Host ""
    Write-Host "1. VERIFY HOST IP ADDRESS" -ForegroundColor Cyan
    Write-Host "   Check that VMHostIPAddress parameter matches your actual host IP"
    Write-Host "   Run 'ipconfig' on host and verify IP matches: $($SharePath.Split('\')[2])"
    Write-Host ""
    Write-Host "2. CHECK HYPER-V VM SWITCH TYPE" -ForegroundColor Cyan
    Write-Host "   VM switch MUST be 'External' (not Internal or Private)"
    Write-Host "   Open Hyper-V Manager > Virtual Switch Manager"
    Write-Host "   Verify switch is External and connected to physical adapter"
    Write-Host ""
    Write-Host "3. DISABLE WINDOWS FIREWALL (TEMPORARY TEST)" -ForegroundColor Cyan
    Write-Host "   On HOST machine, temporarily disable Windows Firewall"
    Write-Host "   If this fixes it, SMB port 445/TCP is being blocked"
    Write-Host "   Re-enable firewall and add exception for SMB"
    Write-Host ""
    Write-Host "4. VERIFY NETWORK DRIVERS IN WINPE" -ForegroundColor Cyan
    Write-Host "   Ensure network drivers are in PEDrivers folder"
    Write-Host "   Rebuild WinPE capture media with network drivers"
    Write-Host ""
    Write-Host "5. CHECK SMB SHARE EXISTS ON HOST" -ForegroundColor Cyan
    Write-Host "   On host, verify share exists: Get-SmbShare -Name '$ShareName'"
    Write-Host "   Check FFUDevelopment.log for Set-CaptureFFU errors"
    Write-Host ""
    Write-Host "6. VERIFY SMB SERVER SERVICE" -ForegroundColor Cyan
    Write-Host "   On host: Get-Service -Name LanmanServer"
    Write-Host "   Should be Running. If not: Start-Service LanmanServer"
    Write-Host ""
    Write-Host "For more help, see: https://github.com/rbalsleyMSFT/FFU/issues" -ForegroundColor White
    Write-Host "============================================`n"

    return $false
}

# Main execution with Solution C
try {
    Write-Host "`n"
    Write-Host "=====================================================" -ForegroundColor Green
    Write-Host "       FFU Capture Network Connection (WinPE)        " -ForegroundColor Green
    Write-Host "=====================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Configuration:" -ForegroundColor White
    Write-Host "  Host IP: $VMHostIPAddress"
    Write-Host "  Share: \\$VMHostIPAddress\$ShareName"
    Write-Host "  User: $UserName"
    Write-Host ""

    # Step 1: Wait for network to be ready (max 60 seconds)
    if (-not (Wait-For-NetworkReady -HostIP $VMHostIPAddress -TimeoutSeconds 60)) {
        throw "Network initialization failed - network is not ready after 60 seconds"
    }

    # Step 2: Connect to share with retry (max 3 attempts)
    $shareConnected = Connect-NetworkShareWithRetry `
        -SharePath "\\$VMHostIPAddress\$ShareName" `
        -Username $UserName `
        -Password $Password `
        -DriveLetter "W:" `
        -MaxRetries 3

    if (-not $shareConnected) {
        throw "Failed to connect to network share \\$VMHostIPAddress\$ShareName after multiple attempts. See diagnostics above."
    }

    Write-Host "Network share connection successful! Proceeding with FFU capture..." -ForegroundColor Green
    Write-Host ""

} catch {
    Write-Host "`n=====================================================" -ForegroundColor Red
    Write-Host "          NETWORK CONNECTION FAILED                   " -ForegroundColor Red
    Write-Host "=====================================================" -ForegroundColor Red
    Write-Error "CaptureFFU.ps1 network connection error: $_"
    Write-Host ""
    Write-Host "Please review the troubleshooting guide above and try again." -ForegroundColor Yellow
    Write-Host "Press any key to continue (script will exit)..." -ForegroundColor Yellow
    pause
    throw
}

$AssignDriveLetter = 'x:\AssignDriveLetter.txt'
try {
    Write-Host 'Assigning M: as Windows drive letter'
    Start-Process -FilePath diskpart.exe -ArgumentList "/S $AssignDriveLetter" -Wait -ErrorAction Stop | Out-Null
}
catch {
    Write-Error "Failed to assign drive letter using diskpart: $_"
    
}

#Load Registry Hive
$Software = 'M:\Windows\System32\config\software'
try {
    Write-Host "Loading software registry hive to $Software"
    if (-not (Test-Path -Path $Software)) {
        throw "Software registry hive not found at $Software"
    }
    $regResult = reg load "HKLM\FFU" $Software 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Registry load failed with exit code $($LASTEXITCODE): $regResult"
    }
    Write-Host "Successfully loaded software registry hive."
}
catch {
    Write-Error "Failed to load registry hive: $_"
    
}

try {
    #Find Windows version values
    Write-Host "Retrieving Windows information from the registry..."
    $SKU = Get-ItemPropertyValue -Path 'HKLM:\FFU\Microsoft\Windows NT\CurrentVersion\' -Name 'EditionID'
    Write-Host "SKU: $SKU"
    [int]$CurrentBuild = Get-ItemPropertyValue -Path 'HKLM:\FFU\Microsoft\Windows NT\CurrentVersion\' -Name 'CurrentBuild'
    Write-Host "CurrentBuild: $CurrentBuild"
    if ($CurrentBuild -notin 14393, 17763) {
        Write-Host "CurrentBuild is not 14393 or 17763, retrieving WindowsVersion..."
        $WindowsVersion = Get-ItemPropertyValue -Path 'HKLM:\FFU\Microsoft\Windows NT\CurrentVersion\' -Name 'DisplayVersion'
        Write-Host "WindowsVersion: $WindowsVersion"
    }
    $InstallationType = Get-ItemPropertyValue -Path 'HKLM:\FFU\Microsoft\Windows NT\CurrentVersion\' -Name 'InstallationType'
    Write-Host "InstallationType: $InstallationType"
    $BuildDate = Get-Date -uformat %b%Y
    Write-Host "BuildDate: $BuildDate"

$SKU = switch ($SKU) {
    Core { 'Home' }
    CoreN { 'Home_N' }
    CoreSingleLanguage { 'Home_SL' }
    Professional { 'Pro' }
    ProfessionalN { 'Pro_N' }
    ProfessionalEducation { 'Pro_Edu' }
    ProfessionalEducationN { 'Pro_Edu_N' }
    Enterprise { 'Ent' }
    EnterpriseN { 'Ent_N' }
    EnterpriseS { 'Ent_LTSC' }
    EnterpriseSN { 'Ent_N_LTSC' }
    IoTEnterpriseS { 'IoT_Ent_LTSC' }
    Education { 'Edu' }
    EducationN { 'Edu_N' }
    ProfessionalWorkstation { 'Pro_Wks' }
    ProfessionalWorkstationN { 'Pro_Wks_N' }
    ServerStandard { 'Srv_Std' }
    ServerDatacenter { 'Srv_Dtc' }
}

    if ($InstallationType -eq "Client") {
        if ($CurrentBuild -ge 22000) {
            $WindowsRelease = 'Win11'
            Write-Host "WindowsRelease: $WindowsRelease"
        }
        else {
            $WindowsRelease = 'Win10'
            Write-Host "WindowsRelease: $WindowsRelease"
        }
    }
    else {
        $WindowsRelease = switch ($CurrentBuild) {
            26100 { '2025' }
            20348 { '2022' }
            17763 { '2019' }
            14393 { '2016' }
            Default { $WindowsVersion }
        }
        Write-Host "WindowsRelease: $WindowsRelease"
        if ($InstallationType -eq "Server Core") {
            $SKU += "_Core"
            Write-Host "InstallType is Server Core, changing SKU to: $SKU"
        }
    }

    if ($CustomFFUNameTemplate) {
        Write-Host 'Using custom FFU name template...'
        $FFUFileName = $CustomFFUNameTemplate
        $FFUFileName = $FFUFileName -replace '{WindowsRelease}', $WindowsRelease
        $FFUFileName = $FFUFileName -replace '{WindowsVersion}', $WindowsVersion
        $FFUFileName = $FFUFileName -replace '{SKU}', $SKU
        $FFUFileName = $FFUFileName -replace '{BuildDate}', $BuildDate
        $FFUFileName = $FFUFileName -replace '{yyyy}', (Get-Date -UFormat '%Y')
        $FFUFileName = $FFUFileName -creplace '{MM}', (Get-Date -UFormat '%m')
        $FFUFileName = $FFUFileName -replace '{dd}', (Get-Date -UFormat '%d')
        $FFUFileName = $FFUFileName -creplace '{HH}', (Get-Date -UFormat '%H')
        $FFUFileName = $FFUFileName -creplace '{hh}', (Get-Date -UFormat '%I')
        $FFUFileName = $FFUFileName -creplace '{mm}', (Get-Date -UFormat '%M')
        $FFUFileName = $FFUFileName -replace '{tt}', (Get-Date -UFormat '%p')
        Write-Host "FFU File Name: $FFUFileName"
        #If the custom FFU name template does not end with .ffu, append it
        if ($FFUFileName -notlike '*.ffu') {
            $FFUFileName += '.ffu'
            Write-Host "Appended .ffu to FFU file name: $FFUFileName"
        }
        $dismArgs = "/capture-ffu /imagefile=W:\$FFUFileName /capturedrive=\\.\PhysicalDrive0 /name:$WindowsRelease$WindowsVersion$SKU /Compress:Default"
        Write-Host "DISM arguments for capture: $dismArgs"
    }
    else {
        #If Office is installed, modify the file name of the FFU
        $Office = Get-ChildItem -Path 'M:\Program Files\Microsoft Office' -ErrorAction SilentlyContinue
        if ($Office) {
            $ffuFilePath = "W:\$WindowsRelease`_$WindowsVersion`_$SKU`_Office`_$BuildDate.ffu"
            Write-Host "Office is installed, using modified FFU file name: $ffuFilePath"
        }
        else {
            $ffuFilePath = "W:\$WindowsRelease`_$WindowsVersion`_$SKU`_Apps`_$BuildDate.ffu"
            Write-Host "Office is not installed, using modified FFU file name: $ffuFilePath"
        }
        $dismArgs = "/capture-ffu /imagefile=$ffuFilePath /capturedrive=\\.\PhysicalDrive0 /name:$WindowsRelease$WindowsVersion$SKU /Compress:Default"
        Write-Host "DISM arguments for capture: $dismArgs"
    }

    #Unload Registry
    Set-Location X:\
    Remove-Variable SKU
    Remove-Variable CurrentBuild
    if ($CurrentBuild -notin 14393, 17763) {
        Remove-Variable WindowsVersion
    }
    if ($Office) {
        Remove-Variable Office
    }

    try {
        Write-Host "Unloading registry hive HKLM\FFU..."
        $regUnloadResult = reg unload "HKLM\FFU" 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Registry unload failed with exit code $($LASTEXITCODE): $regUnloadResult"
        }
        Write-Host "Successfully unloaded registry hive."
    }
    catch {
        Write-Error "Failed to unload registry hive: $_"
        
    }

    Write-Host "Sleeping for 60 seconds to allow registry to unload prior to capture"
    Start-sleep 60

    try {
        Write-Host "Starting DISM FFU capture..."
        $dismProcess = Start-Process -FilePath dism.exe -ArgumentList $dismArgs -Wait -PassThru -ErrorAction Stop
        if ($dismProcess.ExitCode -ne 0) {
            throw "DISM capture failed with exit code $($dismProcess.ExitCode)"
        }
        Write-Host "DISM FFU capture completed successfully."
    }
    catch {
        Write-Error "FFU capture failed: $_"
        
    }

    try {
        Write-Host "Copying DISM log to network share..."
        xcopy X:\Windows\logs\dism\dism.log W:\ /Y | Out-Null
    }
    catch {
        Write-Warning "Failed to copy DISM log: $_"
    }
    Write-Host "DISM log copied to network share, shutting down..."
    wpeutil Shutdown

}
catch {
    Write-Error "An unexpected error occurred: $_"
    
}
