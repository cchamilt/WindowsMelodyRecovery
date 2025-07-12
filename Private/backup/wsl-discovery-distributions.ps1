# wsl-discovery-distributions.ps1
# WSL Distribution Discovery Script
# Discovers and reports WSL distribution information

[CmdletBinding()]
param()

try {
    if (!(Get-Command wsl -ErrorAction SilentlyContinue)) {
        $result = @{
            WSLAvailable = $false
            Distributions = @()
            WSLVersion = "Not Available"
            Message = "WSL not installed"
        }
        Write-Output ($result | ConvertTo-Json -Depth 5)
        return
    }

    $wslInfo = @{
        WSLAvailable = $true
        Distributions = @()
        WSLVersion = "Unknown"
        DefaultDistribution = ""
        Message = "WSL available"
    }

    try {
        $versionOutput = wsl --version 2>$null
        if ($versionOutput) {
            $wslInfo.WSLVersion = ($versionOutput | Select-Object -First 1).Trim()
        }
    }
    catch {
        $wslInfo.WSLVersion = "Legacy WSL 1"
    }

    try {
        $distroOutput = wsl --list --verbose 2>$null
        if ($distroOutput) {
            $distributions = @()
            foreach ($line in $distroOutput) {
                if ($line -match '^\s*([*\s])\s*(\S+)\s+(\S+)\s+(\d+)') {
                    $isDefault = $matches[1] -eq '*'
                    $name = $matches[2]
                    $state = $matches[3]
                    $version = $matches[4]

                    $distro = @{
                        Name = $name
                        State = $state
                        Version = $version
                        IsDefault = $isDefault
                    }

                    if ($isDefault) {
                        $wslInfo.DefaultDistribution = $name
                    }

                    $distributions += $distro
                }
            }
            $wslInfo.Distributions = $distributions
        }
    }
    catch {
        $wslInfo.Message = "Could not enumerate distributions"
    }

    Write-Output ($wslInfo | ConvertTo-Json -Depth 10)
}
catch {
    $errorResult = @{
        WSLAvailable = $false
        Distributions = @()
        WSLVersion = "Error"
        Message = "Error checking WSL: $($_.Exception.Message)"
    }
    Write-Output ($errorResult | ConvertTo-Json -Depth 5)
}






