function Restore-WSLSettings {
    try {
        Write-Host "Restoring WSL settings..." -ForegroundColor Blue
        $wslPath = Test-BackupPath -Path "WSL" -BackupType "WSL"
        
        if ($wslPath) {
            # Restore WSL bash profile
            $bashrcFile = "$wslPath\.bashrc"
            if (Test-Path $bashrcFile) {
                # Create a temporary copy for WSL to access
                Copy-Item -Path $bashrcFile -Destination "$env:USERPROFILE\.wsl_bashrc_temp" -Force
                
                # Copy .bashrc to WSL home directory
                wsl -e bash -c @"
                    if [ -f ~/.bashrc ]; then
                        cp ~/.bashrc ~/.bashrc.backup
                    fi
                    cp /mnt/c/Users/$env:USERNAME/.wsl_bashrc_temp ~/.bashrc
                    source ~/.bashrc
"@
                # Clean up temp file
                Remove-Item -Path "$env:USERPROFILE\.wsl_bashrc_temp" -Force
                Write-Host "WSL bash profile restored successfully" -ForegroundColor Green
            } else {
                Write-Host "WSL bash profile not found" -ForegroundColor Yellow
            }
        }
    } catch {
        Write-Host "Failed to restore WSL settings: $_" -ForegroundColor Red
    }
} 