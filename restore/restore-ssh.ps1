function Restore-SSHSettings {
    try {
        Write-Host "Restoring SSH configurations..." -ForegroundColor Blue
        $sshPath = Test-BackupPath -Path "SSH" -BackupType "SSH"
        
        if ($sshPath) {
            # Destination SSH directory
            $sshDestPath = "$env:USERPROFILE\.ssh"
            
            # Create .ssh directory if it doesn't exist
            if (!(Test-Path -Path $sshDestPath)) {
                New-Item -ItemType Directory -Path $sshDestPath -Force | Out-Null
            }
            
            # Set proper directory permissions
            icacls $sshDestPath /inheritance:r
            icacls $sshDestPath /grant:r "${env:USERNAME}:(OI)(CI)F"
            
            # Copy all SSH files
            Copy-Item -Path "$sshPath\*" -Destination $sshDestPath -Force -Recurse
            
            # Set proper permissions on private keys
            Get-ChildItem -Path $sshDestPath -Filter "id_*" | ForEach-Object {
                if ($_.Name -notmatch '\.pub$') {
                    icacls $_.FullName /inheritance:r
                    icacls $_.FullName /grant:r "${env:USERNAME}:F"
                }
            }
            
            Write-Host "SSH configurations restored successfully" -ForegroundColor Green
            
            # Ensure SSH agent is running
            $sshAgent = Get-Service -Name "ssh-agent" -ErrorAction SilentlyContinue
            if ($sshAgent) {
                if ($sshAgent.Status -ne "Running") {
                    Start-Service ssh-agent
                    Set-Service -Name ssh-agent -StartupType Automatic
                }
                Write-Host "SSH agent service is running" -ForegroundColor Green
            }
        }
    } catch {
        Write-Host "Failed to restore SSH configurations: $_" -ForegroundColor Red
    }
} 