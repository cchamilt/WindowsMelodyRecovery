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
        Write-Information -MessageData "Setting up custom profiles..." -InformationAction Continue

        # Check if chezmoi is installed
        $chezmoiInstalled = $false
        try {
            $null = Get-Command chezmoi -ErrorAction Stop
            $chezmoiInstalled = $true
            Write-Information -MessageData "Chezmoi is already installed." -InformationAction Continue
        } catch {
            Write-Warning -Message "Chezmoi is not installed."
        }

        if (-not $chezmoiInstalled) {
            $installResponse = Read-Host "Would you like to install chezmoi? (Y/N)"

            if ($installResponse -eq 'Y' -or $installResponse -eq 'y') {
                Write-Warning -Message "Installing chezmoi via winget..."
                try {
                    winget install twpayne.chezmoi
                    if ($LASTEXITCODE -eq 0) {
                        Write-Information -MessageData "Chezmoi installed successfully!" -InformationAction Continue
                    } else {
                        Write-Warning "Failed to install chezmoi. Please install manually."
                        return $false
                    }
                } catch {
                    Write-Warning "Failed to install chezmoi. Please install manually."
                    return $false
                }
            } else {
                Write-Warning -Message "Chezmoi installation cancelled."
                return $false
            }
        }

        Write-Information -MessageData "Custom profiles setup completed!" -InformationAction Continue
        return $true

    } catch {
        Write-Error -Message "Failed to setup custom profiles"
        return $false
    }
}

