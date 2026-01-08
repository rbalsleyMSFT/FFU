<#
.SYNOPSIS
    Factory function to get a hypervisor provider instance

.DESCRIPTION
    Returns an appropriate hypervisor provider based on the specified type.
    Supports 'HyperV', 'VMware', and 'Auto' (auto-detect best available).

.PARAMETER Type
    The type of hypervisor provider to return:
    - 'HyperV': Microsoft Hyper-V provider
    - 'VMware': VMware Workstation Pro provider (not yet implemented)
    - 'Auto': Automatically detect and return the best available provider

.PARAMETER Validate
    If specified, validates that the provider is available before returning it.
    Throws an error if the requested provider is not available.

.EXAMPLE
    $provider = Get-HypervisorProvider -Type 'HyperV'
    $vm = $provider.CreateVM($config)

.EXAMPLE
    $provider = Get-HypervisorProvider -Type 'Auto' -Validate
    # Returns the first available provider

.OUTPUTS
    IHypervisorProvider

.NOTES
    Module: FFU.Hypervisor
    Version: 1.0.0
#>
function Get-HypervisorProvider {
    [CmdletBinding()]
    [OutputType([object])]  # Returns IHypervisorProvider-derived class
    param(
        [Parameter(Mandatory = $false)]
        [ValidateSet('HyperV', 'VMware', 'Auto')]
        [string]$Type = 'Auto',

        [Parameter(Mandatory = $false)]
        [switch]$Validate
    )

    process {
        $provider = $null

        switch ($Type) {
            'HyperV' {
                $provider = [HyperVProvider]::new()
            }
            'VMware' {
                $provider = [VMwareProvider]::new()
            }
            'Auto' {
                # Try providers in order of preference: Hyper-V first, then VMware
                $hyperv = [HyperVProvider]::new()
                if ($hyperv.TestAvailable()) {
                    $provider = $hyperv
                    WriteLog "Auto-detected hypervisor: Hyper-V"
                }
                else {
                    # Try VMware if Hyper-V is not available
                    $vmware = [VMwareProvider]::new()
                    if ($vmware.TestAvailable()) {
                        $provider = $vmware
                        WriteLog "Auto-detected hypervisor: VMware Workstation"
                    }
                    else {
                        throw "No supported hypervisor found on this system. " +
                              "Please ensure Hyper-V is enabled or VMware Workstation Pro is installed."
                    }
                }
            }
        }

        if ($Validate -and $provider) {
            $available = $provider.TestAvailable()
            if (-not $available) {
                $details = $provider.GetAvailabilityDetails()
                $issues = $details.Issues -join '; '
                throw "Hypervisor '$($provider.Name)' is not available: $issues"
            }
        }

        return $provider
    }
}
