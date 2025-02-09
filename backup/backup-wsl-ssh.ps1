param(
    [Parameter(Mandatory=$true)]
    [string]$BackupRootPath
)

try {
    Write-Host "Backing up WSL SSH settings..." -ForegroundColor Blue
    $backupPath = Initialize-BackupDirectory -Path "WSL-SSH" -BackupType "WSL SSH" -BackupRootPath $BackupRootPath
    
    if ($backupPath) {
        # Create a temporary directory for WSL to copy files to
        $tempDir = "$env:USERPROFILE\.wsl_ssh_temp"
        if (Test-Path $tempDir) {
            Remove-Item -Path $tempDir -Recurse -Force
        }
        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
        
        # Copy SSH files from WSL to temp directory
        wsl -e bash -c @"
            if [ -d ~/.ssh ]; then
                cp -r ~/.ssh/* /mnt/c/Users/$env:USERNAME/.wsl_ssh_temp/
                echo "SSH files copied from WSL"
            else
                echo "No SSH directory found in WSL"
                exit 1
            fi
"@
        
        if ($LASTEXITCODE -eq 0) {
            # Copy files from temp to backup location
            Copy-Item -Path "$tempDir\*" -Destination $backupPath -Recurse -Force
            
            # Set proper permissions on backup files
            icacls $backupPath /inheritance:r
            icacls $backupPath /grant:r "${env:USERNAME}:(OI)(CI)F"
            
            Write-Host "WSL SSH settings backed up successfully to: $backupPath" -ForegroundColor Green
        } else {
            Write-Host "No SSH files found in WSL to backup" -ForegroundColor Yellow
        }
        
        # Cleanup temp directory
        Remove-Item -Path $tempDir -Recurse -Force
    }
} catch {
    Write-Host "Failed to backup WSL SSH settings: $_" -ForegroundColor Red
} 