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
$loadEnvPath = Join-Path $modulePath "Private\scripts\load-environment.ps1"

# Source the load-environment script
if (Test-Path $loadEnvPath) {
    . $loadEnvPath
} else {
    Write-Host "Cannot find load-environment.ps1 at: $loadEnvPath" -ForegroundColor Red
}

# Get module configuration
$config = Get-WindowsMissingRecovery
if (!$config.IsInitialized) {
    throw "Module not initialized. Please run Initialize-WindowsMissingRecovery first."
}

if (!$BackupRootPath) {
    $BackupRootPath = Join-Path $config.BackupRoot $config.MachineName
}

function Restore-WSLSettings {
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
    
    $restoredItems = @()
    $errors = @()
    
    try {
        Write-Host "Starting WSL restore..." -ForegroundColor Blue
        
        # Check if WSL is available
        if (!(Get-Command wsl -ErrorAction SilentlyContinue)) {
            Write-Host "WSL not found on this system. Skipping WSL restore." -ForegroundColor Yellow
            return @{
                Success = $true
                RestoredItems = @()
                Errors = @()
                Message = "WSL not available - restore skipped"
            }
        }
        
        # Check if any WSL distributions are installed
        try {
            $wslDistros = wsl --list --quiet 2>$null
            if (!$wslDistros -or $wslDistros.Count -eq 0) {
                Write-Host "No WSL distributions found. Skipping WSL restore." -ForegroundColor Yellow
                return @{
                    Success = $true
                    RestoredItems = @()
                    Errors = @()
                    Message = "No WSL distributions found - restore skipped"
                }
            }
        } catch {
            Write-Host "Could not enumerate WSL distributions. Skipping WSL restore." -ForegroundColor Yellow
            return @{
                Success = $true
                RestoredItems = @()
                Errors = @()
                Message = "Could not access WSL - restore skipped"
            }
        }
        
        $wslBackupPath = Join-Path $BackupRootPath "WSL"
        
        if (!(Test-Path $wslBackupPath)) {
            Write-Host "No WSL backup found at: $wslBackupPath" -ForegroundColor Yellow
            return @{
                Success = $true
                RestoredItems = @()
                Errors = @()
                Message = "No WSL backup found - restore skipped"
            }
        }
        
        # 1. Restore WSL Configuration Files
        Write-Host "Restoring WSL configuration..." -ForegroundColor Yellow
        if ($WhatIf) {
            Write-Host "WhatIf: Would restore WSL configuration files" -ForegroundColor Yellow
            $restoredItems += "WSL Configuration (WhatIf)"
        } else {
            try {
                $configRestoreScript = @"
#!/bin/bash
set -e

USER_NAME=\$(whoami)
BACKUP_DIR="/mnt/c/Users/\$USER_NAME/OneDrive - Fyber Labs/work/fyberlabs/repos/desktop-setup/WSL-Backup/config"

if [ ! -d "\$BACKUP_DIR" ]; then
    echo "No WSL configuration backup found at: \$BACKUP_DIR"
    exit 0
fi

echo "Restoring WSL configuration files..."

# Restore system configuration files (requires sudo)
echo "Restoring system configs..."
if [ -f "\$BACKUP_DIR/wsl.conf" ]; then
    sudo cp "\$BACKUP_DIR/wsl.conf" /etc/ && echo "Restored wsl.conf"
fi

if [ -f "\$BACKUP_DIR/fstab" ]; then
    sudo cp "\$BACKUP_DIR/fstab" /etc/ && echo "Restored fstab"
fi

if [ -f "\$BACKUP_DIR/hosts" ]; then
    sudo cp "\$BACKUP_DIR/hosts" /etc/ && echo "Restored hosts"
fi

if [ -f "\$BACKUP_DIR/environment" ]; then
    sudo cp "\$BACKUP_DIR/environment" /etc/ && echo "Restored environment"
fi

# Restore user shell configuration
echo "Restoring user configs..."
if [ -f "\$BACKUP_DIR/bashrc" ]; then
    cp "\$BACKUP_DIR/bashrc" ~/.bashrc && echo "Restored .bashrc"
fi

if [ -f "\$BACKUP_DIR/bash_profile" ]; then
    cp "\$BACKUP_DIR/bash_profile" ~/.bash_profile && echo "Restored .bash_profile"
fi

if [ -f "\$BACKUP_DIR/profile" ]; then
    cp "\$BACKUP_DIR/profile" ~/.profile && echo "Restored .profile"
fi

if [ -f "\$BACKUP_DIR/zshrc" ]; then
    cp "\$BACKUP_DIR/zshrc" ~/.zshrc && echo "Restored .zshrc"
fi

# Restore Git configuration
if [ -f "\$BACKUP_DIR/gitconfig" ]; then
    cp "\$BACKUP_DIR/gitconfig" ~/.gitconfig && echo "Restored .gitconfig"
fi

# Restore SSH configuration (with proper permissions)
if [ -d "\$BACKUP_DIR/ssh" ]; then
    mkdir -p ~/.ssh
    cp -r "\$BACKUP_DIR/ssh"/* ~/.ssh/ 2>/dev/null || true
    chmod 700 ~/.ssh
    chmod 600 ~/.ssh/* 2>/dev/null || true
    echo "Restored SSH configuration"
fi

# Restore development tool configurations
if [ -f "\$BACKUP_DIR/vimrc" ]; then
    cp "\$BACKUP_DIR/vimrc" ~/.vimrc && echo "Restored .vimrc"
fi

if [ -f "\$BACKUP_DIR/tmux.conf" ]; then
    cp "\$BACKUP_DIR/tmux.conf" ~/.tmux.conf && echo "Restored .tmux.conf"
fi

echo "Configuration restore completed!"
"@
                
                Invoke-WSLScript -ScriptContent $configRestoreScript -AsRoot
                $restoredItems += "WSL Configuration"
                Write-Host "✅ WSL configuration restored" -ForegroundColor Green
                
            } catch {
                $errors += "Failed to restore WSL configuration: $($_.Exception.Message)"
                Write-Host "❌ Failed to restore WSL configuration: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
        
        # 2. Restore WSL Packages
        Write-Host "Restoring WSL packages..." -ForegroundColor Yellow
        if ($WhatIf) {
            Write-Host "WhatIf: Would restore WSL packages" -ForegroundColor Yellow
            $restoredItems += "WSL Packages (WhatIf)"
        } else {
            try {
                $packageRestoreScript = @"
#!/bin/bash
set -e

USER_NAME=\$(whoami)
BACKUP_DIR="/mnt/c/Users/\$USER_NAME/OneDrive - Fyber Labs/work/fyberlabs/repos/desktop-setup/WSL-Backup/packages"

if [ ! -d "\$BACKUP_DIR" ]; then
    echo "No WSL packages backup found at: \$BACKUP_DIR"
    exit 0
fi

echo "Restoring WSL packages for user: \$USER_NAME"

# Update package lists first
echo "Updating package lists..."
sudo apt update

# Restore APT packages
if [ -f "\$BACKUP_DIR/apt-packages.txt" ]; then
    echo "Restoring APT packages..."
    sudo dpkg --set-selections < "\$BACKUP_DIR/apt-packages.txt"
    sudo apt-get dselect-upgrade -y
    echo "APT packages restored"
fi

# Restore APT sources (if backed up)
if [ -f "\$BACKUP_DIR/sources.list" ]; then
    echo "Restoring APT sources..."
    sudo cp "\$BACKUP_DIR/sources.list" /etc/apt/
    sudo apt update
    echo "APT sources restored"
fi

# Restore NPM packages
if [ -f "\$BACKUP_DIR/npm-packages.txt" ] && command -v npm &> /dev/null; then
    echo "Restoring NPM packages..."
    # Extract package names and install them
    grep -E "^[├└]" "\$BACKUP_DIR/npm-packages.txt" | sed 's/[├└─ ]//g' | cut -d'@' -f1 | while read package; do
        if [ -n "\$package" ] && [ "\$package" != "npm" ]; then
            npm install -g "\$package" 2>/dev/null || echo "Failed to install \$package"
        fi
    done
    echo "NPM packages restored"
fi

# Restore PIP packages
if [ -f "\$BACKUP_DIR/pip-packages.txt" ] && command -v pip &> /dev/null; then
    echo "Restoring PIP packages..."
    pip install -r "\$BACKUP_DIR/pip-packages.txt"
    echo "PIP packages restored"
fi

# Restore Snap packages
if [ -f "\$BACKUP_DIR/snap-packages.txt" ] && command -v snap &> /dev/null; then
    echo "Restoring Snap packages..."
    tail -n +2 "\$BACKUP_DIR/snap-packages.txt" | while read line; do
        package=\$(echo "\$line" | awk '{print \$1}')
        if [ -n "\$package" ]; then
            sudo snap install "\$package" 2>/dev/null || echo "Failed to install snap package: \$package"
        fi
    done
    echo "Snap packages restored"
fi

# Restore Flatpak packages
if [ -f "\$BACKUP_DIR/flatpak-packages.txt" ] && command -v flatpak &> /dev/null; then
    echo "Restoring Flatpak packages..."
    tail -n +2 "\$BACKUP_DIR/flatpak-packages.txt" | while read line; do
        package=\$(echo "\$line" | awk '{print \$1}')
        if [ -n "\$package" ]; then
            flatpak install -y "\$package" 2>/dev/null || echo "Failed to install flatpak package: \$package"
        fi
    done
    echo "Flatpak packages restored"
fi

echo "Package restore completed!"
"@
                
                Invoke-WSLScript -ScriptContent $packageRestoreScript -AsRoot
                $restoredItems += "WSL Packages"
                Write-Host "✅ WSL packages restored" -ForegroundColor Green
                
            } catch {
                $errors += "Failed to restore WSL packages: $($_.Exception.Message)"
                Write-Host "❌ Failed to restore WSL packages: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
        
        # 3. Restore WSL Home Directory (selective)
        Write-Host "Restoring WSL home directory..." -ForegroundColor Yellow
        if ($WhatIf) {
            Write-Host "WhatIf: Would restore WSL home directory" -ForegroundColor Yellow
            $restoredItems += "WSL Home Directory (WhatIf)"
        } else {
            try {
                $homeRestoreScript = @"
#!/bin/bash
set -e

USER_NAME=\$(whoami)
SOURCE_DIR="/mnt/c/Users/\$USER_NAME/OneDrive - Fyber Labs/work/fyberlabs/repos/desktop-setup/WSL-Backup/home"
TARGET_DIR="/home/\$USER_NAME"

if [ ! -d "\$SOURCE_DIR" ]; then
    echo "No WSL home backup found at: \$SOURCE_DIR"
    exit 0
fi

echo "Restoring WSL home directory..."

# Use rsync to restore files
rsync -avz --progress "\$SOURCE_DIR/" "\$TARGET_DIR/"

# Fix permissions
chmod 755 "\$TARGET_DIR"
find "\$TARGET_DIR" -type d -exec chmod 755 {} \;
find "\$TARGET_DIR" -type f -exec chmod 644 {} \;

# Make scripts executable
find "\$TARGET_DIR/bin" -type f -exec chmod +x {} \; 2>/dev/null || true
find "\$TARGET_DIR/.local/bin" -type f -exec chmod +x {} \; 2>/dev/null || true
find "\$TARGET_DIR/Scripts" -type f -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true

echo "Home directory restore completed!"
"@
                
                Invoke-WSLScript -ScriptContent $homeRestoreScript
                $restoredItems += "WSL Home Directory"
                Write-Host "✅ WSL home directory restored" -ForegroundColor Green
                
            } catch {
                $errors += "Failed to restore WSL home directory: $($_.Exception.Message)"
                Write-Host "❌ Failed to restore WSL home directory: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
        
        # 4. Restore chezmoi configuration
        Write-Host "Restoring chezmoi configuration..." -ForegroundColor Yellow
        if ($WhatIf) {
            Write-Host "WhatIf: Would restore chezmoi configuration" -ForegroundColor Yellow
            $restoredItems += "chezmoi Configuration (WhatIf)"
        } else {
            try {
                Restore-WSLChezmoi -BackupPath $wslBackupPath
                $restoredItems += "chezmoi Configuration"
                Write-Host "✅ chezmoi configuration restored" -ForegroundColor Green
            } catch {
                $errors += "Failed to restore chezmoi configuration: $($_.Exception.Message)"
                Write-Host "❌ Failed to restore chezmoi configuration: $($_.Exception.Message)" -ForegroundColor Red
            }
        }

        # 5. Display WSL Distribution Info (if available)
        $wslInfoPath = Join-Path $wslBackupPath "wsl-info.txt"
        if (Test-Path $wslInfoPath) {
            Write-Host "`nWSL Distribution Info from backup:" -ForegroundColor Cyan
            Get-Content $wslInfoPath | Write-Host -ForegroundColor Gray
        }
        
        # 6. Post-restore recommendations
        if ($restoredItems.Count -gt 0 -and !$WhatIf) {
            Write-Host "`nPost-restore recommendations:" -ForegroundColor Cyan
            Write-Host "• Restart your WSL distribution: wsl --shutdown && wsl" -ForegroundColor Yellow
            Write-Host "• Reload shell configuration: source ~/.bashrc (or ~/.zshrc)" -ForegroundColor Yellow
            Write-Host "• Verify package installations and update if needed" -ForegroundColor Yellow
            Write-Host "• Check SSH key permissions if you use SSH" -ForegroundColor Yellow
            Write-Host "• Check chezmoi status: chezmoi status" -ForegroundColor Yellow
            Write-Host "• Apply any pending dotfile changes: chezmoi apply" -ForegroundColor Yellow
        }
        
        # Return results
        $success = $errors.Count -eq 0
        $message = if ($success) { 
            "WSL restore completed successfully" 
        } else { 
            "WSL restore completed with $($errors.Count) errors" 
        }
        
        Write-Host $message -ForegroundColor $(if ($success) { "Green" } else { "Yellow" })
        
        return @{
            Success = $success
            RestoredItems = $restoredItems
            Errors = $errors
            Message = $message
        }
        
    } catch {
        $errors += "WSL restore failed: $($_.Exception.Message)"
        Write-Host "❌ WSL restore failed: $($_.Exception.Message)" -ForegroundColor Red
        
        return @{
            Success = $false
            RestoredItems = $restoredItems
            Errors = $errors
            Message = "WSL restore failed"
        }
    }
}

# Main execution
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    $result = Restore-WSLSettings -BackupRootPath $BackupRootPath -Force:$Force -Include $Include -Exclude $Exclude -SkipVerification:$SkipVerification
    if (-not $result.Success) {
        exit 1
    }
} 