param(
    [Parameter(Mandatory=$true)]
    [string]$BackupRootPath
)

try {
    Write-Host "Backing up WSL settings..." -ForegroundColor Blue
    $backupPath = Initialize-BackupDirectory -Path "WSL" -BackupType "WSL" -BackupRootPath $BackupRootPath
    
    if ($backupPath) {
        # Export WSL bash profile
        wsl -e bash -c @"
            if [ -f ~/.bashrc ]; then
                cp ~/.bashrc /mnt/c/Users/$env:USERNAME/.wsl_bashrc_temp
            fi
"@
        
        if (Test-Path "$env:USERPROFILE\.wsl_bashrc_temp") {
            Move-Item -Path "$env:USERPROFILE\.wsl_bashrc_temp" -Destination "$backupPath\.bashrc" -Force
            Write-Host "WSL bash profile backed up successfully" -ForegroundColor Green
        } else {
            Write-Host "No WSL bash profile found to backup" -ForegroundColor Yellow
        }
    }
} catch {
    Write-Host "Failed to backup WSL settings: $_" -ForegroundColor Red
} 