function Setup-Chezmoi {
    [CmdletBinding()]
    param()

    # Load environment configuration (optional - module will use fallback configuration)
    try {
        Load-Environment | Out-Null
    } catch {
        Write-Verbose "Using module configuration fallback"
    }

    try {
        Write-Host "Setting up chezmoi for dotfile management..." -ForegroundColor Blue

        # Check if WSL is available
        if (!(Get-Command wsl -ErrorAction SilentlyContinue)) {
            Write-Host "WSL is not available on this system. chezmoi setup requires WSL." -ForegroundColor Red
            return $false
        }

        # Check if any WSL distributions are installed
        try {
            $wslDistros = wsl --list --quiet 2>$null
            if (!$wslDistros -or $wslDistros.Count -eq 0) {
                Write-Host "No WSL distributions found. Please install WSL first." -ForegroundColor Red
                return $false
            }
        } catch {
            Write-Host "Could not access WSL distributions." -ForegroundColor Red
            return $false
        }

        Write-Host "Found WSL distributions. Setting up chezmoi..." -ForegroundColor Green

        # Ask user for dotfiles repository
        $gitRepo = Read-Host "Enter your dotfiles git repository URL (or press Enter to create empty repository)"

        if ($gitRepo) {
            Write-Host "Setting up chezmoi with repository: $gitRepo" -ForegroundColor Yellow
            try {
                Setup-WSLChezmoi -GitRepository $gitRepo -InitializeRepo
                Write-Host "✅ chezmoi setup completed with repository" -ForegroundColor Green
            } catch {
                Write-Host "❌ Failed to setup chezmoi with repository: $($_.Exception.Message)" -ForegroundColor Red
                Write-Host "Falling back to empty repository setup..." -ForegroundColor Yellow
                Setup-WSLChezmoi
            }
        } else {
            Write-Host "Setting up empty chezmoi repository..." -ForegroundColor Yellow
            try {
                Setup-WSLChezmoi
                Write-Host "✅ chezmoi setup completed (empty repository)" -ForegroundColor Green
            } catch {
                Write-Host "❌ Failed to setup chezmoi: $($_.Exception.Message)" -ForegroundColor Red
                return $false
            }
        }

        # Provide guidance on next steps
        Write-Host "`nchezmoi Setup Complete! 🎉" -ForegroundColor Green
        Write-Host "`nNext steps for dotfile management:" -ForegroundColor Cyan
        Write-Host "• Add files to chezmoi: wsl chezmoi add ~/.bashrc" -ForegroundColor Yellow
        Write-Host "• Edit managed files: wsl chezmoi edit ~/.bashrc" -ForegroundColor Yellow
        Write-Host "• Apply changes: wsl chezmoi apply" -ForegroundColor Yellow
        Write-Host "• Check status: wsl chezmoi status" -ForegroundColor Yellow
        Write-Host "• View differences: wsl chezmoi diff" -ForegroundColor Yellow
        Write-Host "• Go to source directory: wsl chezmoi cd" -ForegroundColor Yellow
        Write-Host "`nUseful aliases (available in WSL after restarting shell):" -ForegroundColor Cyan
        Write-Host "• cm (chezmoi), cma (apply), cme (edit), cms (status), cmd (diff)" -ForegroundColor Yellow

        if (!$gitRepo) {
            Write-Host "`n💡 To sync with a git repository later:" -ForegroundColor Cyan
            Write-Host "• wsl chezmoi cd" -ForegroundColor Yellow
            Write-Host "• wsl git remote add origin <your-repo-url>" -ForegroundColor Yellow
            Write-Host "• wsl git push -u origin main" -ForegroundColor Yellow
        }

        return $true

    } catch {
        Write-Host "Failed to setup chezmoi: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}