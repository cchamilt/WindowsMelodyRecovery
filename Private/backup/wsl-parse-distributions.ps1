# wsl-parse-distributions.ps1
# WSL Distribution Parse Script
# Parses WSL distribution discovery output into application state format

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$DiscoveryOutput
)

try {
    $wslData = $DiscoveryOutput | ConvertFrom-Json

    # Create array format expected by ApplicationState
    $applications = @()

    # Add WSL system as an "application"
    $wslSystemApp = @{
        Name = "WSL System"
        Version = $wslData.WSLVersion
        Status = if ($wslData.WSLAvailable) { "Available" } else { "Not Available" }
        Metadata = @{
            DistributionCount = $wslData.Distributions.Count
            DefaultDistribution = $wslData.DefaultDistribution
            RunningDistributions = ($wslData.Distributions | Where-Object { $_.State -eq "Running" }).Count
        }
    }

    $applications += $wslSystemApp

    # Add each distribution as an "application"
    foreach ($distro in $wslData.Distributions) {
        $distroApp = @{
            Name = "WSL-$($distro.Name)"
            Version = "WSL $($distro.Version)"
            Status = $distro.State
            Metadata = @{
                IsDefault = $distro.IsDefault
                DistributionName = $distro.Name
                WSLVersion = $distro.Version
            }
        }
        $applications += $distroApp
    }

    if ($applications.Count -eq 0) {
        Write-Output "[]"
    } else {
        Write-Output ($applications | ConvertTo-Json -Depth 10 -AsArray)
    }
} catch {
    Write-Error "Failed to parse WSL distribution data: $($_.Exception.Message)"
    Write-Output "[]"
}






