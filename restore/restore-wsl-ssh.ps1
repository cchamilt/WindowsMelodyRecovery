function Restore-WSLSSHSettings {
    try {
        Write-Host "Restoring WSL SSH settings..." -ForegroundColor Blue
        $sshPath = Test-BackupPath -Path "WSL-SSH" -BackupType "WSL SSH"
        
        if ($sshPath) {
            # Create a temporary directory for WSL to access
            $tempDir = "$env:USERPROFILE\.wsl_ssh_temp"
            if (Test-Path $tempDir) {
                Remove-Item -Path $tempDir -Recurse -Force
            }
            New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
            
            # Copy SSH files to temp directory
            Copy-Item -Path "$sshPath\*" -Destination $tempDir -Recurse -Force
            
            # Restore SSH files to WSL
            wsl -e bash -c @"
                # Backup existing .ssh directory if it exists
                if [ -d ~/.ssh ]; then
                    mv ~/.ssh ~/.ssh.backup
                fi
                
                # Create new .ssh directory
                mkdir -p ~/.ssh
                
                # Copy files from Windows temp directory
                cp -r /mnt/c/Users/$env:USERNAME/.wsl_ssh_temp/* ~/.ssh/
                
                # Set proper permissions
                chmod 700 ~/.ssh
                chmod 600 ~/.ssh/id_*
                chmod 644 ~/.ssh/*.pub
                chmod 644 ~/.ssh/known_hosts
                chmod 644 ~/.ssh/config
                
                # Start SSH agent if needed
                eval \$(ssh-agent -s)
"@
            
            # Cleanup temp directory
            Remove-Item -Path $tempDir -Recurse -Force
            
            Write-Host "WSL SSH settings restored successfully" -ForegroundColor Green
        }
    } catch {
        Write-Host "Failed to restore WSL SSH settings: $_" -ForegroundColor Red
    }
} 