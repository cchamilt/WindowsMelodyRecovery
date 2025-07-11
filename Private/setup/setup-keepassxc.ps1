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
        Write-Information -MessageData "Setting up KeePassXC..." -InformationAction Continue

        # Install KeePassXC
        Write-Warning -Message "Installing KeePassXC..."
        try {
            # Try winget first
            $wingetResult = winget list KeePassXC 2>$null
            if ($LASTEXITCODE -ne 0) {
                Write-Warning -Message "KeePassXC not found, installing..."
                winget install -e --id KeePassXCTeam.KeePassXC
            } else {
                Write-Information -MessageData "KeePassXC is already installed" -InformationAction Continue
            }
        } catch {
            # Fallback to chocolatey if winget fails
            if (Get-Command choco -ErrorAction SilentlyContinue) {
                Write-Warning -Message "Attempting to install via Chocolatey..."
                choco install keepassxc -y
            } else {
                Write-Warning "Failed to install KeePassXC. Please install manually."
                return $false
            }
        }

        Write-Information -MessageData "KeePassXC setup completed!" -InformationAction Continue
        Write-Warning -Message "You can configure your database location manually after installation."
        return $true

    } catch {
        Write-Error -Message "Failed to setup KeePassXC: $_"
        return $false
    }
}

