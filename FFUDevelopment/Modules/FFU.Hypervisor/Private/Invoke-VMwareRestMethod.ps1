<#
.SYNOPSIS
    Wrapper for VMware Workstation REST API calls

.DESCRIPTION
    Provides a consistent interface for making REST API calls to vmrest.
    Handles authentication, error handling, retries, and response parsing.

.PARAMETER Endpoint
    The API endpoint path (e.g., '/vms', '/vms/{id}/power')

.PARAMETER Method
    HTTP method (GET, POST, PUT, DELETE). Default is GET.

.PARAMETER Body
    Request body for POST/PUT operations. Will be converted to JSON.

.PARAMETER Port
    vmrest port. Default 8697.

.PARAMETER Credential
    PSCredential for vmrest authentication.

.PARAMETER RetryCount
    Number of retries on transient failures. Default 3.

.PARAMETER TimeoutSeconds
    Request timeout in seconds. Default 30.

.OUTPUTS
    The deserialized response from the API, or throws on error.

.EXAMPLE
    # Get all VMs
    $vms = Invoke-VMwareRestMethod -Endpoint '/vms'

.EXAMPLE
    # Power on a VM
    Invoke-VMwareRestMethod -Endpoint "/vms/$vmId/power" -Method PUT -Body @{command='on'}

.EXAMPLE
    # Create a VM from clone
    $body = @{
        name = 'NewVM'
        parentId = $sourceVmId
    }
    Invoke-VMwareRestMethod -Endpoint '/vms' -Method POST -Body $body

.NOTES
    Module: FFU.Hypervisor
    Version: 1.0.0

    VMware REST API Reference:
    https://docs.vmware.com/en/VMware-Workstation-Pro/17/com.vmware.ws.using.doc/GUID-9FAAA4DD-1320-450D-B684-2845B311640F.html
#>

function Invoke-VMwareRestMethod {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Endpoint,

        [Parameter(Mandatory = $false)]
        [ValidateSet('GET', 'POST', 'PUT', 'DELETE', 'PATCH')]
        [string]$Method = 'GET',

        [Parameter(Mandatory = $false)]
        [object]$Body,

        [Parameter(Mandatory = $false)]
        [int]$Port = 8697,

        [Parameter(Mandatory = $false)]
        [PSCredential]$Credential,

        [Parameter(Mandatory = $false)]
        [int]$RetryCount = 3,

        [Parameter(Mandatory = $false)]
        [int]$TimeoutSeconds = 30
    )

    # Build the full URL
    $baseUrl = "http://127.0.0.1:$Port/api"
    $uri = $baseUrl + $Endpoint.TrimStart('/')
    $uri = $uri.TrimEnd('/')

    # If Endpoint doesn't start with /, add it
    if (-not $Endpoint.StartsWith('/')) {
        $uri = "$baseUrl/$Endpoint"
    }

    # Build request parameters
    $params = @{
        Uri = $uri
        Method = $Method
        ContentType = 'application/vnd.vmware.vmw.rest-v1+json'
        TimeoutSec = $TimeoutSeconds
        ErrorAction = 'Stop'
    }

    # Add credential if provided
    if ($Credential) {
        $params['Credential'] = $Credential
    }

    # Add body for POST/PUT/PATCH
    if ($Body -and $Method -in @('POST', 'PUT', 'PATCH')) {
        if ($Body -is [string]) {
            $params['Body'] = $Body
        }
        else {
            $params['Body'] = $Body | ConvertTo-Json -Depth 10
        }
    }

    # Retry loop
    $lastError = $null
    $attempt = 0

    while ($attempt -lt $RetryCount) {
        $attempt++

        try {
            WriteLog "VMware API: $Method $Endpoint (attempt $attempt/$RetryCount)"

            $response = Invoke-RestMethod @params

            # Log success
            if ($response) {
                WriteLog "VMware API: Success"
            }

            return $response
        }
        catch [System.Net.WebException] {
            $lastError = $_
            $statusCode = $null

            if ($_.Exception.Response) {
                $statusCode = [int]$_.Exception.Response.StatusCode

                # Read error response body
                try {
                    $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
                    $errorBody = $reader.ReadToEnd()
                    $reader.Close()

                    if ($errorBody) {
                        $errorJson = $errorBody | ConvertFrom-Json -ErrorAction SilentlyContinue
                        if ($errorJson.message) {
                            $lastError = "$statusCode - $($errorJson.message)"
                        }
                        elseif ($errorJson.error) {
                            $lastError = "$statusCode - $($errorJson.error)"
                        }
                        else {
                            $lastError = "$statusCode - $errorBody"
                        }
                    }
                }
                catch {
                    # Ignore parse errors
                }
            }

            # Don't retry on client errors (4xx) except 429 (rate limit)
            if ($statusCode -and $statusCode -ge 400 -and $statusCode -lt 500 -and $statusCode -ne 429) {
                WriteLog "VMware API: Client error $statusCode - not retrying"
                throw "VMware API error: $lastError"
            }

            WriteLog "VMware API: Error on attempt $attempt - $lastError"

            if ($attempt -lt $RetryCount) {
                $delay = [Math]::Pow(2, $attempt)  # Exponential backoff
                WriteLog "Waiting $delay seconds before retry..."
                Start-Sleep -Seconds $delay
            }
        }
        catch {
            $lastError = $_.Exception.Message
            WriteLog "VMware API: Exception on attempt $attempt - $lastError"

            if ($attempt -lt $RetryCount) {
                $delay = [Math]::Pow(2, $attempt)
                Start-Sleep -Seconds $delay
            }
        }
    }

    throw "VMware API call failed after $RetryCount attempts: $lastError"
}

<#
.SYNOPSIS
    Gets all VMs from VMware Workstation
#>
function Get-VMwareVMList {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [int]$Port = 8697,
        [PSCredential]$Credential
    )

    try {
        $response = Invoke-VMwareRestMethod -Endpoint '/vms' -Port $Port -Credential $Credential
        return $response
    }
    catch {
        WriteLog "WARNING: Failed to get VM list: $($_.Exception.Message)"
        return @()
    }
}

<#
.SYNOPSIS
    Gets a specific VM by ID
#>
function Get-VMwareVM {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$VMId,

        [int]$Port = 8697,
        [PSCredential]$Credential
    )

    try {
        $response = Invoke-VMwareRestMethod -Endpoint "/vms/$VMId" -Port $Port -Credential $Credential
        return $response
    }
    catch {
        WriteLog "WARNING: Failed to get VM $VMId : $($_.Exception.Message)"
        return $null
    }
}

<#
.SYNOPSIS
    Gets the power state of a VM
#>
function Get-VMwarePowerState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$VMId,

        [int]$Port = 8697,
        [PSCredential]$Credential
    )

    try {
        $response = Invoke-VMwareRestMethod -Endpoint "/vms/$VMId/power" -Port $Port -Credential $Credential
        return $response.power_state
    }
    catch {
        WriteLog "WARNING: Failed to get power state for VM $VMId : $($_.Exception.Message)"
        return 'unknown'
    }
}

<#
.SYNOPSIS
    Sets the power state of a VM
#>
function Set-VMwarePowerState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$VMId,

        [Parameter(Mandatory = $true)]
        [ValidateSet('on', 'off', 'shutdown', 'suspend', 'pause', 'unpause', 'reset')]
        [string]$State,

        [int]$Port = 8697,
        [PSCredential]$Credential
    )

    try {
        $body = $State  # VMware REST API expects just the command string
        $response = Invoke-VMwareRestMethod -Endpoint "/vms/$VMId/power" -Method PUT -Body $body -Port $Port -Credential $Credential
        return $response
    }
    catch {
        WriteLog "ERROR: Failed to set power state '$State' for VM $VMId : $($_.Exception.Message)"
        throw
    }
}

<#
.SYNOPSIS
    Gets the IP address of a VM
#>
function Get-VMwareVMIPAddress {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$VMId,

        [int]$Port = 8697,
        [PSCredential]$Credential,

        [int]$TimeoutSeconds = 120,
        [int]$PollIntervalSeconds = 5
    )

    $startTime = Get-Date

    while (((Get-Date) - $startTime).TotalSeconds -lt $TimeoutSeconds) {
        try {
            $response = Invoke-VMwareRestMethod -Endpoint "/vms/$VMId/ip" -Port $Port -Credential $Credential
            if ($response.ip) {
                return $response.ip
            }
        }
        catch {
            # IP might not be available yet
        }

        Start-Sleep -Seconds $PollIntervalSeconds
    }

    WriteLog "WARNING: Could not get IP address for VM $VMId within $TimeoutSeconds seconds"
    return $null
}

<#
.SYNOPSIS
    Registers a VM with VMware Workstation
#>
function Register-VMwareVM {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$VMXPath,

        [string]$VMName,

        [int]$Port = 8697,
        [PSCredential]$Credential
    )

    try {
        $body = @{
            name = if ($VMName) { $VMName } else { [System.IO.Path]::GetFileNameWithoutExtension($VMXPath) }
            path = $VMXPath
        }

        $response = Invoke-VMwareRestMethod -Endpoint '/vms/registration' -Method POST -Body $body -Port $Port -Credential $Credential
        WriteLog "Registered VM: $($body.name)"
        return $response
    }
    catch {
        WriteLog "ERROR: Failed to register VM from $VMXPath : $($_.Exception.Message)"
        throw
    }
}

<#
.SYNOPSIS
    Unregisters (removes) a VM from VMware Workstation
#>
function Unregister-VMwareVM {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$VMId,

        [int]$Port = 8697,
        [PSCredential]$Credential
    )

    try {
        $response = Invoke-VMwareRestMethod -Endpoint "/vms/$VMId" -Method DELETE -Port $Port -Credential $Credential
        WriteLog "Unregistered VM: $VMId"
        return $response
    }
    catch {
        WriteLog "ERROR: Failed to unregister VM $VMId : $($_.Exception.Message)"
        throw
    }
}

<#
.SYNOPSIS
    Updates VM settings (CPU, memory, etc.)
#>
function Set-VMwareVMSettings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$VMId,

        [int]$Processors,
        [int]$MemoryMB,

        [int]$Port = 8697,
        [PSCredential]$Credential
    )

    try {
        $body = @{}

        if ($Processors -gt 0) {
            $body['processors'] = $Processors
        }

        if ($MemoryMB -gt 0) {
            $body['memory'] = $MemoryMB
        }

        if ($body.Count -eq 0) {
            WriteLog "No settings to update"
            return
        }

        $response = Invoke-VMwareRestMethod -Endpoint "/vms/$VMId" -Method PUT -Body $body -Port $Port -Credential $Credential
        WriteLog "Updated VM settings: $VMId"
        return $response
    }
    catch {
        WriteLog "ERROR: Failed to update VM settings: $($_.Exception.Message)"
        throw
    }
}
