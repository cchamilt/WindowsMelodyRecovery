function Setup-CustomProfiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [switch]$Force
    )

    # Load environment configuration (optional - module will use fallback configuration)
    try {
        Load-Environment | Out-Null
    } catch {
        Write-Verbose "Using module configuration fallback"
    }

    try {
        Write-Host "Setting up custom profiles..." -ForegroundColor Blue
        
        # Check if chezmoi is installed
        $chezmoiInstalled = $false
        try {
            $null = Get-Command chezmoi -ErrorAction Stop
            $chezmoiInstalled = $true
            Write-Host "Chezmoi is already installed." -ForegroundColor Green
        } catch {
            Write-Host "Chezmoi is not installed." -ForegroundColor Yellow
        }
        
        if (-not $chezmoiInstalled) {
            $installResponse = Read-Host "Would you like to install chezmoi? (Y/N)"
            
            if ($installResponse -eq 'Y' -or $installResponse -eq 'y') {
                Write-Host "Installing chezmoi via winget..." -ForegroundColor Yellow
                try {
                    winget install twpayne.chezmoi
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host "Chezmoi installed successfully!" -ForegroundColor Green
                    } else {
                        Write-Warning "Failed to install chezmoi. Please install manually."
                        return $false
                    }
                } catch {
                    Write-Warning "Failed to install chezmoi. Please install manually."
                    return $false
                }
            } else {
                Write-Host "Chezmoi installation cancelled." -ForegroundColor Yellow
                return $false
            }
        }

        Write-Host "Custom profiles setup completed!" -ForegroundColor Green
        return $true

    } catch {
        Write-Host "Failed to setup custom profiles" -ForegroundColor Red
        return $false
    }
} 
