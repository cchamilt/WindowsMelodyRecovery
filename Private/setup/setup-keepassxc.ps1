function Setup-KeePassXC {
    [CmdletBinding()]
    param()

    # Load environment configuration (optional - module will use fallback configuration)
    try {
        Load-Environment | Out-Null
    } catch {
        Write-Verbose "Using module configuration fallback"
    }

    try {
        Write-Host "Setting up KeePassXC..." -ForegroundColor Blue

        # Install KeePassXC
        Write-Host "Installing KeePassXC..." -ForegroundColor Yellow
        try {
            # Try winget first
            $wingetResult = winget list KeePassXC 2>$null
            if ($LASTEXITCODE -ne 0) {
                Write-Host "KeePassXC not found, installing..." -ForegroundColor Yellow
                winget install -e --id KeePassXCTeam.KeePassXC
            } else {
                Write-Host "KeePassXC is already installed" -ForegroundColor Green
            }
        } catch {
            # Fallback to chocolatey if winget fails
            if (Get-Command choco -ErrorAction SilentlyContinue) {
                Write-Host "Attempting to install via Chocolatey..." -ForegroundColor Yellow
                choco install keepassxc -y
            } else {
                Write-Warning "Failed to install KeePassXC. Please install manually."
                return $false
            }
        }

        Write-Host "KeePassXC setup completed!" -ForegroundColor Green
        Write-Host "You can configure your database location manually after installation." -ForegroundColor Yellow
        return $true

    } catch {
        Write-Host "Failed to setup KeePassXC: $_" -ForegroundColor Red
        return $false
    }
} 
