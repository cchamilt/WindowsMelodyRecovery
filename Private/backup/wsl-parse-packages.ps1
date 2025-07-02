# wsl-parse-packages.ps1
# WSL Package Parse Script
# Parses WSL package discovery output into application state format

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$DiscoveryOutput
)

try {
    $packages = $DiscoveryOutput | ConvertFrom-Json
    
    # Create array format expected by ApplicationState
    $applications = @()
    
    # Ensure packages is treated as an array
    if ($packages -eq $null) {
        $packages = @()
    } elseif ($packages -isnot [array]) {
        $packages = @($packages)
    }
    
    foreach ($pkg in $packages) {
        if ($pkg -ne $null -and $pkg.Name) {
            $application = @{
                Name = $pkg.Name
                Version = if ($pkg.Version) { $pkg.Version } else { "Unknown" }
                Status = if ($pkg.Status) { $pkg.Status } else { "Unknown" }
                PackageManager = if ($pkg.PackageManager) { $pkg.PackageManager } else { "Unknown" }
            }
            
            $applications += $application
        }
    }
    
    if ($applications.Count -eq 0) {
        Write-Output "[]"
    } else {
        Write-Output ($applications | ConvertTo-Json -Depth 5)
    }
} catch {
    Write-Error "Failed to parse WSL package data: $($_.Exception.Message)"
    Write-Output "[]"
} 