[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory=$false)]
    [string]$BackupRootPath = $null,
    
    [Parameter(Mandatory=$false)]
    [string]$MachineBackupPath = $null,
    
    [Parameter(Mandatory=$false)]
    [string]$SharedBackupPath = $null,
    
    [Parameter(Mandatory=$false)]
    [switch]$Force,
    
    [Parameter(Mandatory=$false)]
    [string[]]$Include = @(),
    
    [Parameter(Mandatory=$false)]
    [string[]]$Exclude = @(),
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipVerification
)

# Load environment script from the correct location
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$modulePath = Split-Path -Parent (Split-Path -Parent $scriptPath)

# Load environment using the core function
if (!(Load-Environment)) {
    throw "Failed to load environment. Please run Initialize-WindowsMelodyRecovery first."
}

# Get module configuration
$config = Get-WindowsMelodyRecovery
if (!$config.IsInitialized) {
    throw "Module not initialized. Please run Initialize-WindowsMelodyRecovery first."
}

if (!$BackupRootPath) {
    $BackupRootPath = Join-Path $config.BackupRoot $config.MachineName
}

function Backup-WSLSettings {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory=$true)]
        [string]$BackupRootPath,
        
        [Parameter(Mandatory=$false)]
        [switch]$Force,
        
        [Parameter(Mandatory=$false)]
        [string[]]$Include = @(),
        
        [Parameter(Mandatory=$false)]
        [string[]]$Exclude = @(),
        
        [Parameter(Mandatory=$false)]
        [switch]$SkipVerification,

        # For testing purposes
        [Parameter(DontShow)]
        [switch]$WhatIf
    )
    
    $backupItems = @()
    $errors = @()
    
    try {
        Write-Host "Starting WSL backup..." -ForegroundColor Blue
        
        # Check if WSL is available
        if (!(Get-Command wsl -ErrorAction SilentlyContinue)) {
            Write-Host "WSL not found on this system. Skipping WSL backup." -ForegroundColor Yellow
            return @{
                Success = $true
                BackupItems = @()
                Errors = @()
                Message = "WSL not available - backup skipped"
            }
        }
        
        # Check if any WSL distributions are installed
        try {
            $wslDistros = wsl --list --quiet 2>$null
            if (!$wslDistros -or $wslDistros.Count -eq 0) {
                Write-Host "No WSL distributions found. Skipping WSL backup." -ForegroundColor Yellow
                return @{
                    Success = $true
                    BackupItems = @()
                    Errors = @()
                    Message = "No WSL distributions found - backup skipped"
                }
            }
        } catch {
            Write-Host "Could not enumerate WSL distributions. Skipping WSL backup." -ForegroundColor Yellow
            return @{
                Success = $true
                BackupItems = @()
                Errors = @()
                Message = "Could not access WSL - backup skipped"
            }
        }
        
        $wslBackupPath = Join-Path $BackupRootPath "WSL"
        
        if ($WhatIf) {
            Write-Host "WhatIf: Would create WSL backup directory: $wslBackupPath" -ForegroundColor Yellow
        } else {
            # Create WSL backup directory
            if (!(Test-Path $wslBackupPath)) {
                New-Item -ItemType Directory -Path $wslBackupPath -Force | Out-Null
            }
        }
        
        # 1. Backup WSL Packages
        Write-Host "Backing up WSL packages..." -ForegroundColor Yellow
        if ($WhatIf) {
            Write-Host "WhatIf: Would backup WSL packages" -ForegroundColor Yellow
            $backupItems += "WSL Packages (WhatIf)"
        } else {
            try {
                # Convert Windows path to WSL path
                $wslPackageBackupPath = $wslBackupPath + "/packages"
                $wslPackageBackupPathLinux = $wslPackageBackupPath -replace '\\', '/' -replace 'C:', '/mnt/c'
                
                $packageBackupScript = @"
#!/bin/bash
set -e

BACKUP_DIR="$wslPackageBackupPathLinux"

echo "Backing up WSL packages to: \$BACKUP_DIR"
mkdir -p "\$BACKUP_DIR"

# Export APT packages
echo "Exporting APT packages..."
dpkg --get-selections > "\$BACKUP_DIR/apt-packages.txt"
apt list --installed > "\$BACKUP_DIR/apt-installed.txt" 2>/dev/null || true

# Export APT sources
echo "Backing up APT sources..."
sudo cp -r /etc/apt/sources.list* "\$BACKUP_DIR/" 2>/dev/null || true

# Export NPM packages
echo "Exporting NPM packages..."
if command -v npm &> /dev/null; then
    npm list -g --depth=0 > "\$BACKUP_DIR/npm-packages.txt" 2>/dev/null || echo "No global NPM packages found"
    npm config list > "\$BACKUP_DIR/npm-config.txt" 2>/dev/null || true
fi

# Export PIP packages
echo "Exporting PIP packages..."
if command -v pip &> /dev/null; then
    pip list --format=freeze > "\$BACKUP_DIR/pip-packages.txt" 2>/dev/null || echo "No PIP packages found"
fi

# Export Snap packages
echo "Exporting Snap packages..."
if command -v snap &> /dev/null; then
    snap list > "\$BACKUP_DIR/snap-packages.txt" 2>/dev/null || echo "No Snap packages found"
fi

# Export Flatpak packages
echo "Exporting Flatpak packages..."
if command -v flatpak &> /dev/null; then
    flatpak list > "\$BACKUP_DIR/flatpak-packages.txt" 2>/dev/null || echo "No Flatpak packages found"
fi

echo "Package backup completed!"
"@
                
                Invoke-WSLScript -ScriptContent $packageBackupScript
                $backupItems += "WSL Packages"
                Write-Host "✅ WSL packages backed up" -ForegroundColor Green
                
            } catch {
                $errors += "Failed to backup WSL packages: $($_.Exception.Message)"
                Write-Host "❌ Failed to backup WSL packages: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
        
        # 2. Backup WSL Configuration Files
        Write-Host "Backing up WSL configuration..." -ForegroundColor Yellow
        if ($WhatIf) {
            Write-Host "WhatIf: Would backup WSL configuration files" -ForegroundColor Yellow
            $backupItems += "WSL Configuration (WhatIf)"
        } else {
            try {
                # Convert Windows path to WSL path
                $wslConfigBackupPath = $wslBackupPath + "/config"
                $wslConfigBackupPathLinux = $wslConfigBackupPath -replace '\\', '/' -replace 'C:', '/mnt/c'
                
                $configBackupScript = @"
#!/bin/bash
set -e

BACKUP_DIR="$wslConfigBackupPathLinux"

echo "Backing up WSL configuration files to: \$BACKUP_DIR"
mkdir -p "\$BACKUP_DIR"

# Backup system configuration files
echo "Backing up system configs..."
sudo cp /etc/wsl.conf "\$BACKUP_DIR/" 2>/dev/null || echo "No wsl.conf found"
sudo cp /etc/fstab "\$BACKUP_DIR/" 2>/dev/null || echo "No custom fstab found"
sudo cp /etc/hosts "\$BACKUP_DIR/" 2>/dev/null || echo "No custom hosts found"
sudo cp /etc/environment "\$BACKUP_DIR/" 2>/dev/null || echo "No custom environment found"
sudo cp /etc/sudoers "\$BACKUP_DIR/" 2>/dev/null || echo "No custom sudoers found"

# Backup user shell configuration
echo "Backing up user configs..."
cp ~/.bashrc "\$BACKUP_DIR/bashrc" 2>/dev/null || echo "No .bashrc found"
cp ~/.bash_profile "\$BACKUP_DIR/bash_profile" 2>/dev/null || echo "No .bash_profile found"
cp ~/.profile "\$BACKUP_DIR/profile" 2>/dev/null || echo "No .profile found"
cp ~/.zshrc "\$BACKUP_DIR/zshrc" 2>/dev/null || echo "No .zshrc found"

# Backup Git configuration
cp ~/.gitconfig "\$BACKUP_DIR/gitconfig" 2>/dev/null || echo "No .gitconfig found"
cp -r ~/.ssh "\$BACKUP_DIR/ssh" 2>/dev/null || echo "No .ssh directory found"

# Backup development tool configurations
cp ~/.vimrc "\$BACKUP_DIR/vimrc" 2>/dev/null || echo "No .vimrc found"
cp ~/.tmux.conf "\$BACKUP_DIR/tmux.conf" 2>/dev/null || echo "No .tmux.conf found"

# Set proper permissions for Windows access
sudo chmod -R 644 "\$BACKUP_DIR"/* 2>/dev/null || true
sudo chmod 600 "\$BACKUP_DIR/ssh"/* 2>/dev/null || true

echo "Configuration backup completed!"
"@
                
                Invoke-WSLScript -ScriptContent $configBackupScript -AsRoot
                $backupItems += "WSL Configuration"
                Write-Host "✅ WSL configuration backed up" -ForegroundColor Green
                
            } catch {
                $errors += "Failed to backup WSL configuration: $($_.Exception.Message)"
                Write-Host "❌ Failed to backup WSL configuration: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
        
        # 3. Backup WSL Home Directory (selective)
        Write-Host "Backing up WSL home directory..." -ForegroundColor Yellow
        if ($WhatIf) {
            Write-Host "WhatIf: Would backup WSL home directory" -ForegroundColor Yellow
            $backupItems += "WSL Home Directory (WhatIf)"
        } else {
            try {
                # Convert Windows path to WSL path
                $wslHomeBackupPath = $wslBackupPath + "/home"
                $wslHomeBackupPathLinux = $wslHomeBackupPath -replace '\\', '/' -replace 'C:', '/mnt/c'
                
                $homeBackupScript = @"
#!/bin/bash
set -e

USER_NAME=\$(whoami)
SOURCE_DIR="/home/\$USER_NAME"
BACKUP_DIR="$wslHomeBackupPathLinux"

echo "Backing up WSL home directory to: \$BACKUP_DIR"
mkdir -p "\$BACKUP_DIR"

# Use rsync with specific inclusions for important files only
rsync -avz --progress \
    --include='Documents/' --include='Documents/**' \
    --include='Scripts/' --include='Scripts/**' \
    --include='bin/' --include='bin/**' \
    --include='.local/bin/' --include='.local/bin/**' \
    --include='.config/' --include='.config/**' \
    --exclude='work/*/repos' \
    --exclude='.cache' \
    --exclude='.npm' \
    --exclude='.local/share/Trash' \
    --exclude='snap' \
    --exclude='*.log' \
    --exclude='.vscode-server' \
    --exclude='.docker' \
    --exclude='node_modules' \
    --exclude='__pycache__' \
    --exclude='*.tmp' \
    --exclude='*.temp' \
    "\$SOURCE_DIR/" "\$BACKUP_DIR/"

echo "Home directory backup completed!"
"@
                
                Invoke-WSLScript -ScriptContent $homeBackupScript
                $backupItems += "WSL Home Directory"
                Write-Host "✅ WSL home directory backed up" -ForegroundColor Green
                
            } catch {
                $errors += "Failed to backup WSL home directory: $($_.Exception.Message)"
                Write-Host "❌ Failed to backup WSL home directory: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
        
        # 4. Backup chezmoi configuration
        Write-Host "Backing up chezmoi configuration..." -ForegroundColor Yellow
        if ($WhatIf) {
            Write-Host "WhatIf: Would backup chezmoi configuration" -ForegroundColor Yellow
            $backupItems += "chezmoi Configuration (WhatIf)"
        } else {
            try {
                Backup-WSLChezmoi -BackupPath $wslBackupPath
                $backupItems += "chezmoi Configuration"
                Write-Host "✅ chezmoi configuration backed up" -ForegroundColor Green
            } catch {
                $errors += "Failed to backup chezmoi configuration: $($_.Exception.Message)"
                Write-Host "❌ Failed to backup chezmoi configuration: $($_.Exception.Message)" -ForegroundColor Red
            }
        }

        # 5. Generate WSL Distribution Info
        Write-Host "Backing up WSL distribution info..." -ForegroundColor Yellow
        if ($WhatIf) {
            Write-Host "WhatIf: Would backup WSL distribution info" -ForegroundColor Yellow
            $backupItems += "WSL Distribution Info (WhatIf)"
        } else {
            try {
                $wslInfoPath = Join-Path $wslBackupPath "wsl-info.txt"
                $wslInfo = @()
                $wslInfo += "WSL Distribution Information - $(Get-Date)"
                $wslInfo += "=" * 50
                $wslInfo += ""
                
                # Get WSL version
                try {
                    $wslVersion = wsl --version 2>$null
                    if ($wslVersion) {
                        $wslInfo += "WSL Version:"
                        $wslInfo += $wslVersion
                        $wslInfo += ""
                    }
                } catch {
                    $wslInfo += "WSL Version: Could not determine"
                    $wslInfo += ""
                }
                
                # Get distribution list
                $wslInfo += "Installed Distributions:"
                try {
                    $distros = wsl --list --verbose 2>$null
                    if ($distros) {
                        $wslInfo += $distros
                    }
                } catch {
                    $wslInfo += "Could not list distributions"
                }
                
                $wslInfo | Out-File -FilePath $wslInfoPath -Encoding UTF8
                $backupItems += "WSL Distribution Info"
                Write-Host "✅ WSL distribution info backed up" -ForegroundColor Green
                
            } catch {
                $errors += "Failed to backup WSL distribution info: $($_.Exception.Message)"
                Write-Host "❌ Failed to backup WSL distribution info: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
        
        # Return results
        $success = $errors.Count -eq 0
        $message = if ($success) { 
            "WSL backup completed successfully" 
        } else { 
            "WSL backup completed with $($errors.Count) errors" 
        }
        
        Write-Host $message -ForegroundColor $(if ($success) { "Green" } else { "Yellow" })
        
        return @{
            Success = $success
            BackupItems = $backupItems
            Errors = $errors
            Message = $message
        }
        
    } catch {
        $errors += "WSL backup failed: $($_.Exception.Message)"
        Write-Host "❌ WSL backup failed: $($_.Exception.Message)" -ForegroundColor Red
        
        return @{
            Success = $false
            BackupItems = $backupItems
            Errors = $errors
            Message = "WSL backup failed"
        }
    }
}

# Main execution
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    $result = Backup-WSLSettings -BackupRootPath $BackupRootPath -Force:$Force -Include $Include -Exclude $Exclude -SkipVerification:$SkipVerification
    if (-not $result.Success) {
        exit 1
    }
} 

