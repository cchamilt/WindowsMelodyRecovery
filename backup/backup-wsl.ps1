param(
    [Parameter(Mandatory=$true)]
    [string]$BackupRootPath
)

try {
    Write-Host "Backing up WSL settings..." -ForegroundColor Blue
    $backupPath = Initialize-BackupDirectory -Path "WSL" -BackupType "WSL" -BackupRootPath $BackupRootPath
    
    if ($backupPath) {
        # Create etc backup directory
        New-Item -ItemType Directory -Path "$backupPath\etc" -Force | Out-Null

        # Backup WSL configs
        wsl -e bash -c @"
            if [ -f ~/.bashrc ]; then
                cp ~/.bashrc /mnt/c/Users/$env:USERNAME/.wsl_bashrc_temp
                echo "Bashrc copied successfully"
            else
                echo "No .bashrc found"
                exit 1
            fi

            # Get list of manually installed packages (excluding dependencies)
            echo "Exporting package list..."
            apt-mark showmanual > /mnt/c/Users/$env:USERNAME/.wsl_packages_temp
            
            # Backup important /etc configurations
            echo "Backing up system configurations..."
            cd /etc
            tar czf /mnt/c/Users/$env:USERNAME/.wsl_etc_temp.tar.gz \
                apt/ \
                bash.bashrc \
                environment \
                fstab \
                hosts \
                locale.gen \
                passwd \
                profile \
                resolv.conf \
                ssh/ \
                sudoers \
                timezone \
                wsl.conf \
                X11/ \
                --exclude='*.old' \
                --exclude='*.bak' \
                --exclude='*~' \
                2>/dev/null

            # Get list of all repositories
            echo "Exporting repository list..."
            cp /etc/apt/sources.list /mnt/c/Users/$env:USERNAME/.wsl_sources_temp
            if [ -d /etc/apt/sources.list.d ]; then
                tar czf /mnt/c/Users/$env:USERNAME/.wsl_sources_d_temp.tar.gz /etc/apt/sources.list.d/
            fi
"@ -u root

        # Copy files from temp to backup location
        if (Test-Path "$env:USERPROFILE\.wsl_bashrc_temp") {
            Copy-Item "$env:USERPROFILE\.wsl_bashrc_temp" "$backupPath\.bashrc" -Force
            Remove-Item "$env:USERPROFILE\.wsl_bashrc_temp" -Force
        }
        
        if (Test-Path "$env:USERPROFILE\.wsl_packages_temp") {
            Copy-Item "$env:USERPROFILE\.wsl_packages_temp" "$backupPath\packages.list" -Force
            Remove-Item "$env:USERPROFILE\.wsl_packages_temp" -Force
        }
        
        if (Test-Path "$env:USERPROFILE\.wsl_sources_temp") {
            Copy-Item "$env:USERPROFILE\.wsl_sources_temp" "$backupPath\sources.list" -Force
            Remove-Item "$env:USERPROFILE\.wsl_sources_temp" -Force
        }
        
        if (Test-Path "$env:USERPROFILE\.wsl_sources_d_temp.tar.gz") {
            Copy-Item "$env:USERPROFILE\.wsl_sources_d_temp.tar.gz" "$backupPath\sources.list.d.tar.gz" -Force
            Remove-Item "$env:USERPROFILE\.wsl_sources_d_temp.tar.gz" -Force
        }

        if (Test-Path "$env:USERPROFILE\.wsl_etc_temp.tar.gz") {
            Copy-Item "$env:USERPROFILE\.wsl_etc_temp.tar.gz" "$backupPath\etc.tar.gz" -Force
            Remove-Item "$env:USERPROFILE\.wsl_etc_temp.tar.gz" -Force
        }

        Write-Host "WSL settings backed up successfully to: $backupPath" -ForegroundColor Green
    }
} catch {
    Write-Host "Failed to backup WSL settings: $_" -ForegroundColor Red
} 