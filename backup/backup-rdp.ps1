param(
    [Parameter(Mandatory=$true)]
    [string]$BackupRootPath
)

try {
    Write-Host "Backing up Remote Desktop profiles..." -ForegroundColor Blue
    $backupPath = Initialize-BackupDirectory -Path "RDP" -BackupType "Remote Desktop" -BackupRootPath $BackupRootPath
    
    if ($backupPath) {
        # Source RDP directory
        $rdpSourcePath = "$env:USERPROFILE\Documents\Remote Desktop Connection Manager"
        
        # Copy RDP files
        if (Test-Path -Path $rdpSourcePath) {
            Copy-Item -Path "$rdpSourcePath\*.rdp" -Destination $backupPath -Force
            
            # Export RDP credentials from registry
            $regPath = "HKCU:\Software\Microsoft\Terminal Server Client"
            if (Test-Path $regPath) {
                reg export $regPath "$backupPath\rdp_credentials.reg" /y
            }
            
            Write-Host "Remote Desktop profiles backed up successfully to: $backupPath" -ForegroundColor Green
        } else {
            Write-Host "No Remote Desktop profiles found to backup" -ForegroundColor Yellow
        }
    }
} catch {
    Write-Host "Failed to backup Remote Desktop profiles: $_" -ForegroundColor Red
} 