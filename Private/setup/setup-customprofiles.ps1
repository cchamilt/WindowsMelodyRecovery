# Setup-CustomProfiles.ps1 - Configure chezmoi for dotfile management

function Test-ChezmoiInstalled {
    return (Get-Command chezmoi -ErrorAction SilentlyContinue) -ne $null
}

function Install-Chezmoi {
    Write-Host "`nInstalling chezmoi..." -ForegroundColor Yellow
    
    try {
        # Try winget first (Windows Package Manager)
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            Write-Host "Installing via winget..." -ForegroundColor Gray
            winget install twpayne.chezmoi --accept-source-agreements --accept-package-agreements
            if ($LASTEXITCODE -eq 0) {
                Write-Host "Chezmoi installed successfully via winget!" -ForegroundColor Green
                Write-Host "Please restart PowerShell and run this script again." -ForegroundColor Yellow
                return $false  # Return false to indicate restart needed
            }
        }
        
        # Try chocolatey as fallback
        if (Get-Command choco -ErrorAction SilentlyContinue) {
            Write-Host "Installing via Chocolatey..." -ForegroundColor Gray
            choco install chezmoi -y
            if ($LASTEXITCODE -eq 0) {
                Write-Host "Chezmoi installed successfully via Chocolatey!" -ForegroundColor Green
                Write-Host "Please restart PowerShell and run this script again." -ForegroundColor Yellow
                return $false  # Return false to indicate restart needed
            }
        }
        
        # Try scoop as another fallback
        if (Get-Command scoop -ErrorAction SilentlyContinue) {
            Write-Host "Installing via Scoop..." -ForegroundColor Gray
            scoop install chezmoi
            if ($LASTEXITCODE -eq 0) {
                Write-Host "Chezmoi installed successfully via Scoop!" -ForegroundColor Green
                Write-Host "Please restart PowerShell and run this script again." -ForegroundColor Yellow
                return $false  # Return false to indicate restart needed
            }
        }
        
        # Manual installation as last resort
        Write-Host "Downloading chezmoi binary manually..." -ForegroundColor Gray
        $tempDir = $env:TEMP
        $chezmoiExe = Join-Path $tempDir "chezmoi.exe"
        
        # Download the latest release
        $downloadUrl = "https://github.com/twpayne/chezmoi/releases/latest/download/chezmoi_windows_amd64.exe"
        Invoke-WebRequest -Uri $downloadUrl -OutFile $chezmoiExe
        
        # Move to a location in PATH
        $installDir = "$env:LOCALAPPDATA\Programs\chezmoi"
        if (!(Test-Path $installDir)) {
            New-Item -ItemType Directory -Path $installDir -Force | Out-Null
        }
        
        $finalPath = Join-Path $installDir "chezmoi.exe"
        Move-Item -Path $chezmoiExe -Destination $finalPath -Force
        
        # Add to PATH if not already there
        $currentPath = [Environment]::GetEnvironmentVariable("PATH", "User")
        if ($currentPath -notlike "*$installDir*") {
            [Environment]::SetEnvironmentVariable("PATH", "$currentPath;$installDir", "User")
            $env:PATH = "$env:PATH;$installDir"
        }
        
        Write-Host "Chezmoi installed manually to: $finalPath" -ForegroundColor Green
        return $true
        
    } catch {
        Write-Error "Failed to install chezmoi: $($_.Exception.Message)"
        return $false
    }
}

function Initialize-ChezmoiRepo {
    param(
        [string]$BackupPath
    )
    
    $dotfilesPath = Join-Path $BackupPath "dotfiles"
    
    Write-Host "`nSetting up chezmoi repository..." -ForegroundColor Yellow
    Write-Host "Repository location: $dotfilesPath" -ForegroundColor Gray
    
    try {
        # Create the dotfiles directory in backup location
        if (!(Test-Path $dotfilesPath)) {
            New-Item -ItemType Directory -Path $dotfilesPath -Force | Out-Null
            Write-Host "Created dotfiles directory: $dotfilesPath" -ForegroundColor Green
        }
        
        # Initialize chezmoi with the backup location
        $env:CHEZMOI_SOURCE_DIR = $dotfilesPath
        chezmoi init --source=$dotfilesPath
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Chezmoi initialized successfully!" -ForegroundColor Green
            
            # Create a basic .chezmoiroot file to organize the repo
            $chezmoiRoot = Join-Path $dotfilesPath ".chezmoiroot"
            if (!(Test-Path $chezmoiRoot)) {
                "# Chezmoi root configuration" | Out-File -FilePath $chezmoiRoot -Encoding UTF8
            }
            
            return $true
        } else {
            Write-Error "Failed to initialize chezmoi repository"
            return $false
        }
        
    } catch {
        Write-Error "Failed to initialize chezmoi repository: $($_.Exception.Message)"
        return $false
    }
}

function Add-CommonDotfiles {
    param(
        [string]$DotfilesPath
    )
    
    Write-Host "`nAdding common configuration files to chezmoi..." -ForegroundColor Yellow
    
    $commonFiles = @(
        @{ Path = $PROFILE; Name = "PowerShell Profile"; Required = $false },
        @{ Path = "$env:USERPROFILE\.gitconfig"; Name = "Git Config"; Required = $false },
        @{ Path = "$env:APPDATA\Code\User\settings.json"; Name = "VS Code Settings"; Required = $false },
        @{ Path = "$env:USERPROFILE\.ssh\config"; Name = "SSH Config"; Required = $false }
    )
    
    $addedFiles = 0
    
    foreach ($file in $commonFiles) {
        if (Test-Path $file.Path) {
            Write-Host "Found $($file.Name): $($file.Path)" -ForegroundColor Gray
            $response = Read-Host "Add to chezmoi? (Y/N)"
            
            if ($response -eq 'Y' -or $response -eq 'y') {
                try {
                    chezmoi add $file.Path
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host "  ✓ Added $($file.Name)" -ForegroundColor Green
                        $addedFiles++
                    } else {
                        Write-Warning "  ✗ Failed to add $($file.Name)"
                    }
                } catch {
                    Write-Warning "  ✗ Error adding $($file.Name): $($_.Exception.Message)"
                }
            }
        } else {
            Write-Host "$($file.Name) not found at: $($file.Path)" -ForegroundColor DarkGray
        }
    }
    
    if ($addedFiles -gt 0) {
        Write-Host "`nAdded $addedFiles configuration files to chezmoi." -ForegroundColor Green
        Write-Host "Run 'chezmoi status' to see managed files." -ForegroundColor Cyan
        Write-Host "Run 'chezmoi diff' to see what would change." -ForegroundColor Cyan
        Write-Host "Run 'chezmoi apply' to apply changes." -ForegroundColor Cyan
    } else {
        Write-Host "`nNo files were added to chezmoi." -ForegroundColor Yellow
    }
    
    return $addedFiles -gt 0
}

function Show-ChezmoiUsage {
    Write-Host "`n" + "="*60 -ForegroundColor Cyan
    Write-Host "Chezmoi Setup Complete!" -ForegroundColor Green
    Write-Host "="*60 -ForegroundColor Cyan
    
    Write-Host "`nCommon chezmoi commands:" -ForegroundColor Yellow
    Write-Host "  chezmoi add <file>     - Add a file to chezmoi management" -ForegroundColor White
    Write-Host "  chezmoi edit <file>    - Edit a managed file" -ForegroundColor White
    Write-Host "  chezmoi status         - Show status of managed files" -ForegroundColor White
    Write-Host "  chezmoi diff           - Show differences" -ForegroundColor White
    Write-Host "  chezmoi apply          - Apply changes to your system" -ForegroundColor White
    Write-Host "  chezmoi cd             - Change to chezmoi source directory" -ForegroundColor White
    
    Write-Host "`nTo set up on another machine:" -ForegroundColor Yellow
    Write-Host "  1. Install chezmoi on the target machine" -ForegroundColor White
    Write-Host "  2. Copy your dotfiles directory from the backup location" -ForegroundColor White
    Write-Host "  3. Run: chezmoi init --source=<path-to-dotfiles>" -ForegroundColor White
    Write-Host "  4. Run: chezmoi apply" -ForegroundColor White
    
    $dotfilesPath = Join-Path $backupRoot "dotfiles"
    Write-Host "`nYour dotfiles are stored in: $dotfilesPath" -ForegroundColor Cyan
    Write-Host "This location is backed up with your other Windows recovery data." -ForegroundColor Gray
}

function Setup-CustomProfiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [switch]$Force
    )

    # Get module configuration
    $config = Get-WindowsMissingRecovery
    if (-not $config -or -not $config.BackupRoot) {
        Write-Warning "Module not properly initialized. Please run Initialize-WindowsMissingRecovery first."
        return $false
    }

    $backupRoot = $config.BackupRoot
    $machineName = $config.MachineName

    Write-Host "Setting up chezmoi for dotfile management..." -ForegroundColor Cyan
    Write-Host "This will help you manage your configuration files (dotfiles) across machines." -ForegroundColor Gray

# Main execution
try {
    # Check if chezmoi is installed
    if (-not (Test-ChezmoiInstalled)) {
        Write-Host "Chezmoi is not installed." -ForegroundColor Yellow
        $installResponse = Read-Host "Would you like to install chezmoi? (Y/N)"
        
        if ($installResponse -eq 'Y' -or $installResponse -eq 'y') {
            if (-not (Install-Chezmoi)) {
                Write-Error "Failed to install chezmoi. Please install manually from: https://chezmoi.io/install/"
                return $false
            }
            
            # Refresh PATH to ensure chezmoi is available
            if (-not (Test-ChezmoiInstalled)) {
                Write-Host "Please restart PowerShell and run this script again." -ForegroundColor Yellow
                return $false
            }
        } else {
            Write-Host "Chezmoi installation cancelled. Cannot proceed with setup." -ForegroundColor Yellow
            return $false
        }
    } else {
        Write-Host "✓ Chezmoi is already installed." -ForegroundColor Green
    }
    
    # Initialize chezmoi repository in backup location
    $dotfilesPath = Join-Path $backupRoot "dotfiles"
    
    if (Test-Path $dotfilesPath) {
        Write-Host "Dotfiles directory already exists: $dotfilesPath" -ForegroundColor Yellow
        if (-not $Force) {
            $overwriteResponse = Read-Host "Reinitialize chezmoi repository? (Y/N)"
            if ($overwriteResponse -ne 'Y' -and $overwriteResponse -ne 'y') {
                Write-Host "Skipping repository initialization." -ForegroundColor Yellow
            } else {
                Initialize-ChezmoiRepo -BackupPath $backupRoot
            }
        } else {
            Initialize-ChezmoiRepo -BackupPath $backupRoot
        }
    } else {
        Initialize-ChezmoiRepo -BackupPath $backupRoot
    }
    
    # Add common dotfiles
    Add-CommonDotfiles -DotfilesPath $dotfilesPath
    
    # Show usage information
    Show-ChezmoiUsage
    
    Write-Host "`nChezmoi setup completed successfully!" -ForegroundColor Green
    return $true
    
} catch {
    Write-Error "Error during chezmoi setup: $($_.Exception.Message)"
    return $false
}
}
