<#
.SYNOPSIS
    Gets a list of all available hypervisors on the system

.DESCRIPTION
    Scans the system for supported hypervisors and returns information
    about each one's availability and capabilities.

.EXAMPLE
    Get-AvailableHypervisors
    # Returns: @(
    #     @{ Name = 'HyperV'; Available = $true; Version = '10.0.22631'; ... }
    # )

.EXAMPLE
    Get-AvailableHypervisors | Where-Object { $_.Available }
    # Returns only available hypervisors

.OUTPUTS
    System.Collections.Hashtable[]

.NOTES
    Module: FFU.Hypervisor
    Version: 1.0.0
#>
function Get-AvailableHypervisors {
    [CmdletBinding()]
    [OutputType([hashtable[]])]
    param()

    process {
        $results = @()

        # Check Hyper-V
        try {
            $hyperv = [HyperVProvider]::new()
            $details = $hyperv.GetAvailabilityDetails()
            $results += @{
                Name = 'HyperV'
                DisplayName = 'Microsoft Hyper-V'
                Available = $details.IsAvailable
                Version = $hyperv.Version
                Issues = $details.Issues
                Capabilities = $hyperv.GetCapabilities()
                Details = $details.Details
            }
        }
        catch {
            $results += @{
                Name = 'HyperV'
                DisplayName = 'Microsoft Hyper-V'
                Available = $false
                Version = 'Unknown'
                Issues = @("Error checking Hyper-V: $($_.Exception.Message)")
                Capabilities = @{}
                Details = @{}
            }
        }

        # Check VMware Workstation
        try {
            $vmware = [VMwareProvider]::new()
            $details = $vmware.GetAvailabilityDetails()
            $results += @{
                Name = 'VMware'
                DisplayName = 'VMware Workstation Pro'
                Available = $details.IsAvailable
                Version = $vmware.Version
                Issues = $details.Issues
                Capabilities = $vmware.GetCapabilities()
                Details = $details.Details
            }
        }
        catch {
            $results += @{
                Name = 'VMware'
                DisplayName = 'VMware Workstation Pro'
                Available = $false
                Version = 'Unknown'
                Issues = @("Error checking VMware: $($_.Exception.Message)")
                Capabilities = @{
                    SupportsTPM = $true
                    SupportsSecureBoot = $true
                    SupportsGeneration2 = $true  # EFI equivalent
                    SupportsDynamicMemory = $false
                    SupportsCheckpoints = $true  # Snapshots
                    SupportsNestedVirtualization = $true
                    SupportedDiskFormats = @('VHD', 'VMDK')
                    MaxMemoryGB = 128
                    MaxProcessors = 32
                }
                Details = @{}
            }
        }

        return $results
    }
}
