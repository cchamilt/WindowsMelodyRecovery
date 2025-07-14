# wsl-discovery-packages.ps1
# WSL Package Discovery Script
# Discovers installed packages across different package managers in WSL

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$PackageManager = "apt"  # apt, npm, pip, all
)

function Get-WSLAptPackage {
    try {
        if (!(Get-Command wsl -ErrorAction SilentlyContinue)) {
            return @()
        }

        $result = wsl --exec bash -c "if command -v dpkg >/dev/null 2>&1; then dpkg --get-selections | head -1000; else echo 'dpkg not available'; fi" 2>$null

        if ($result -and $result -ne "dpkg not available") {
            $packages = @()
            foreach ($line in $result) {
                if ($line -and $line.Contains("`t")) {
                    $parts = $line.Split("`t")
                    if ($parts.Length -eq 2) {
                        $packages += @{
                            Name = $parts[0].Trim()
                            Status = $parts[1].Trim()
                            PackageManager = "apt"
                        }
                    }
                }
            }
            return $packages
        }
    }
    catch {
        Write-Warning "Failed to get APT packages: $($_.Exception.Message)"
    }
    return @()
}

# Create alias for plural form
Set-Alias -Name Get-WSLAptPackages -Value Get-WSLAptPackage

function Get-WSLNpmPackage {
    try {
        if (!(Get-Command wsl -ErrorAction SilentlyContinue)) {
            return @()
        }

        $result = wsl --exec bash -c "if command -v npm >/dev/null 2>&1; then npm list -g --depth=0 --json 2>/dev/null || echo '{\"dependencies\":{}}'; else echo '{\"dependencies\":{}}'; fi" 2>$null

        if ($result) {
            $npmData = $result | ConvertFrom-Json
            $packages = @()
            if ($npmData.dependencies) {
                foreach ($pkg in $npmData.dependencies.PSObject.Properties) {
                    $packages += @{
                        Name = $pkg.Name
                        Version = $pkg.Value.version
                        Status = "installed"
                        PackageManager = "npm"
                    }
                }
            }
            return $packages
        }
    }
    catch {
        Write-Warning "Failed to get NPM packages: $($_.Exception.Message)"
    }
    return @()
}

# Create alias for plural form
Set-Alias -Name Get-WSLNpmPackages -Value Get-WSLNpmPackage

function Get-WSLPipPackage {
    try {
        if (!(Get-Command wsl -ErrorAction SilentlyContinue)) {
            return @()
        }

        $result = wsl --exec bash -c "if command -v pip >/dev/null 2>&1; then pip list --format=json 2>/dev/null || echo '[]'; elif command -v pip3 >/dev/null 2>&1; then pip3 list --format=json 2>/dev/null || echo '[]'; else echo '[]'; fi" 2>$null

        if ($result) {
            $pipPackages = $result | ConvertFrom-Json
            $packages = @()
            foreach ($pkg in $pipPackages) {
                $packages += @{
                    Name = $pkg.name
                    Version = $pkg.version
                    Status = "installed"
                    PackageManager = "pip"
                }
            }
            return $packages
        }
    }
    catch {
        Write-Warning "Failed to get PIP packages: $($_.Exception.Message)"
    }
    return @()
}

# Create alias for plural form
Set-Alias -Name Get-WSLPipPackages -Value Get-WSLPipPackage

# Main execution
try {
    $allPackages = @()

    switch ($PackageManager.ToLower()) {
        "apt" {
            $allPackages += Get-WSLAptPackages
        }
        "npm" {
            $allPackages += Get-WSLNpmPackages
        }
        "pip" {
            $allPackages += Get-WSLPipPackages
        }
        "all" {
            $allPackages += Get-WSLAptPackages
            $allPackages += Get-WSLNpmPackages
            $allPackages += Get-WSLPipPackages
        }
        default {
            Write-Warning "Unknown package manager: $PackageManager. Using 'all'."
            $allPackages += Get-WSLAptPackages
            $allPackages += Get-WSLNpmPackages
            $allPackages += Get-WSLPipPackages
        }
    }

    if ($allPackages.Count -eq 0) {
        Write-Output "[]"
    }
    else {
        Write-Output ($allPackages | ConvertTo-Json -Depth 5)
    }
}
catch {
    Write-Error "Failed to discover WSL packages: $($_.Exception.Message)"
    Write-Output "[]"
}






