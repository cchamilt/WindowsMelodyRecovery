function Initialize-Chezmoi {
    [CmdletBinding()]
    param()

    # Load environment configuration (optional - module will use fallback configuration)
    try {
        Import-Environment | Out-Null
    }
 catch {
        Write-Verbose "Using module configuration fallback"
    }

    try {
        Write-Information -MessageData "Setting up chezmoi for dotfile management..." -InformationAction Continue

        # Check if WSL is available
        if (!(Get-Command wsl -ErrorAction SilentlyContinue)) {
            Write-Error -Message "WSL is not available on this system. chezmoi setup requires WSL."
            return $false
        }

        # Check if any WSL distributions are installed
        try {
            $wslDistros = wsl --list --quiet 2>$null
            if (!$wslDistros -or $wslDistros.Count -eq 0) {
                Write-Error -Message "No WSL distributions found. Please install WSL first."
                return $false
            }
        }
 catch {
            Write-Error -Message "Could not access WSL distributions."
            return $false
        }

        Write-Information -MessageData "Found WSL distributions. Setting up chezmoi..." -InformationAction Continue

        # Ask user for dotfiles repository
        $gitRepo = Read-Host "Enter your dotfiles git repository URL (or press Enter to create empty repository)"

        if ($gitRepo) {
            Write-Warning -Message "Setting up chezmoi with repository: $gitRepo"
            try {
                Initialize-WSLChezmoi -GitRepository $gitRepo -InitializeRepo
                Write-Information -MessageData "✅ chezmoi setup completed with repository" -InformationAction Continue
            }
 catch {
                Write-Error -Message "❌ Failed to setup chezmoi with repository: $($_.Exception.Message)"
                Write-Warning -Message "Falling back to empty repository setup..."
                Initialize-WSLChezmoi
            }
        }
 else {
            Write-Warning -Message "Setting up empty chezmoi repository..."
            try {
                Initialize-WSLChezmoi
                Write-Information -MessageData "✅ chezmoi setup completed (empty repository)" -InformationAction Continue
            }
 catch {
                Write-Error -Message "❌ Failed to setup chezmoi: $($_.Exception.Message)"
                return $false
            }
        }

        # Provide guidance on next steps
        Write-Information -MessageData "`nchezmoi Setup Complete! 🎉" -InformationAction Continue
        Write-Information -MessageData "`nNext steps for dotfile management:" -InformationAction Continue
        Write-Warning -Message "• Add files to chezmoi: wsl chezmoi add ~/.bashrc"
        Write-Warning -Message "• Edit managed files: wsl chezmoi edit ~/.bashrc"
        Write-Warning -Message "• Apply changes: wsl chezmoi apply"
        Write-Warning -Message "• Check status: wsl chezmoi status"
        Write-Warning -Message "• View differences: wsl chezmoi diff"
        Write-Warning -Message "• Go to source directory: wsl chezmoi cd"
        Write-Information -MessageData "`nUseful aliases (available in WSL after restarting shell):" -InformationAction Continue
        Write-Warning -Message "• cm (chezmoi), cma (apply), cme (edit), cms (status), cmd (diff)"

        if (!$gitRepo) {
            Write-Information -MessageData "`n💡 To sync with a git repository later:" -InformationAction Continue
            Write-Warning -Message "• wsl chezmoi cd"
            Write-Warning -Message "• wsl git remote add origin <your-repo-url>"
            Write-Warning -Message "• wsl git push -u origin main"
        }

        return $true

    }
 catch {
        Write-Error -Message "Failed to setup chezmoi: $($_.Exception.Message)"
        return $false
    }
}











