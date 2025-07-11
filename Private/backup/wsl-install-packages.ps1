# wsl-install-packages.ps1
# WSL Package Install Script
# Restores WSL packages from backup data

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$StateJson
)

function Install-WSLAptPackages {
    param([array]$AptPackages)

    if ($AptPackages.Count -eq 0) {
        Write-Warning -Message "No APT packages to restore"
        return
    }

    $installedPackages = $AptPackages | Where-Object { $_.Status -eq "install" }
    if ($installedPackages.Count -gt 0) {
        $packageNames = $installedPackages | ForEach-Object { $_.Name }
        $packageList = $packageNames -join " "
        Write-Warning -Message "Restoring $($installedPackages.Count) APT packages in WSL..."

        try {
            wsl --exec bash -c "sudo apt-get update && sudo apt-get install -y $packageList"
            Write-Information -MessageData "Successfully restored APT packages" -InformationAction Continue
        } catch {
            Write-Warning "Failed to restore some APT packages: $($_.Exception.Message)"
        }
    }
}

function Install-WSLNpmPackages {
    param([array]$NpmPackages)

    if ($NpmPackages.Count -eq 0) {
        Write-Warning -Message "No NPM packages to restore"
        return
    }

    Write-Warning -Message "Restoring $($NpmPackages.Count) NPM global packages in WSL..."

    foreach ($pkg in $NpmPackages) {
        try {
            $packageSpec = if ($pkg.Version) { "$($pkg.Name)@$($pkg.Version)" } else { $pkg.Name }
            wsl --exec bash -c "npm install -g $packageSpec"
            Write-Information -MessageData "  Installed $packageSpec" -InformationAction Continue
        } catch {
            Write-Warning "  Failed to install $($pkg.Name): $($_.Exception.Message)"
        }
    }
}

function Install-WSLPipPackages {
    param([array]$PipPackages)

    if ($PipPackages.Count -eq 0) {
        Write-Warning -Message "No PIP packages to restore"
        return
    }

    Write-Warning -Message "Restoring $($PipPackages.Count) PIP packages in WSL..."

    foreach ($pkg in $PipPackages) {
        try {
            $packageSpec = if ($pkg.Version) { "$($pkg.Name)==$($pkg.Version)" } else { $pkg.Name }
            wsl --exec bash -c "pip install $packageSpec"
            Write-Information -MessageData "  Installed $packageSpec" -InformationAction Continue
        } catch {
            Write-Warning "  Failed to install $($pkg.Name): $($_.Exception.Message)"
        }
    }
}

# Main execution
try {
    if (!(Get-Command wsl -ErrorAction SilentlyContinue)) {
        Write-Warning "WSL not available for package restoration"
        return
    }

    $packages = $StateJson | ConvertFrom-Json

    if ($packages.Count -eq 0) {
        Write-Warning -Message "No packages found in backup to restore"
        return
    }

    # Group packages by package manager
    $aptPackages = $packages | Where-Object { $_.PackageManager -eq "apt" }
    $npmPackages = $packages | Where-Object { $_.PackageManager -eq "npm" }
    $pipPackages = $packages | Where-Object { $_.PackageManager -eq "pip" }

    # Install packages by manager
    Install-WSLAptPackages -AptPackages $aptPackages
    Install-WSLNpmPackages -NpmPackages $npmPackages
    Install-WSLPipPackages -PipPackages $pipPackages

    Write-Information -MessageData "WSL package restoration completed" -InformationAction Continue

} catch {
    Write-Error "Failed to restore WSL packages: $($_.Exception.Message)"
}






