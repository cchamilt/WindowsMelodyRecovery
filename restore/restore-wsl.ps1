function Restore-WSLSettings {
    try {
        Write-Host "Restoring WSL settings..." -ForegroundColor Blue
        $wslPath = Test-BackupPath -Path "WSL" -BackupType "WSL"
        
        if ($wslPath) {
            # Copy files to temp location for WSL access
            if (Test-Path "$wslPath\.bashrc") {
                Copy-Item "$wslPath\.bashrc" "$env:USERPROFILE\.wsl_bashrc_temp" -Force
            }
            
            if (Test-Path "$wslPath\packages.list") {
                Copy-Item "$wslPath\packages.list" "$env:USERPROFILE\.wsl_packages_temp" -Force
            }
            
            if (Test-Path "$wslPath\sources.list") {
                Copy-Item "$wslPath\sources.list" "$env:USERPROFILE\.wsl_sources_temp" -Force
            }
            
            if (Test-Path "$wslPath\sources.list.d.tar.gz") {
                Copy-Item "$wslPath\sources.list.d.tar.gz" "$env:USERPROFILE\.wsl_sources_d_temp.tar.gz" -Force
            }

            # Restore settings in WSL
            wsl -e bash -c @"
                # Restore .bashrc
                if [ -f ~/.bashrc ]; then
                    cp ~/.bashrc ~/.bashrc.backup
                fi
                if [ -f /mnt/c/Users/$env:USERNAME/.wsl_bashrc_temp ]; then
                    cp /mnt/c/Users/$env:USERNAME/.wsl_bashrc_temp ~/.bashrc
                    source ~/.bashrc
                fi

                # Restore package repositories
                if [ -f /mnt/c/Users/$env:USERNAME/.wsl_sources_temp ]; then
                    cp /mnt/c/Users/$env:USERNAME/.wsl_sources_temp /etc/apt/sources.list
                fi
                
                if [ -f /mnt/c/Users/$env:USERNAME/.wsl_sources_d_temp.tar.gz ]; then
                    tar xzf /mnt/c/Users/$env:USERNAME/.wsl_sources_d_temp.tar.gz -C /
                fi

                # Update package list
                apt-get update

                # Install packages from backup
                if [ -f /mnt/c/Users/$env:USERNAME/.wsl_packages_temp ]; then
                    echo "Installing packages from backup..."
                    xargs -a /mnt/c/Users/$env:USERNAME/.wsl_packages_temp apt-get install -y
                fi
"@ -u root

            # Cleanup temp files
            Remove-Item "$env:USERPROFILE\.wsl_*_temp*" -Force -ErrorAction SilentlyContinue
            
            Write-Host "WSL settings restored successfully" -ForegroundColor Green
        }
    } catch {
        Write-Host "Failed to restore WSL settings: $_" -ForegroundColor Red
    }
} 