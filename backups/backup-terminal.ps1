try {
    $terminalSettingsPath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
    $terminalBackupPath = "$env:USERPROFILE\OneDrive - Fyber Labs\PCbackup\shared\Terminal\settings.json"
    
    # Create backup directory if it doesn't exist
    $backupDir = Split-Path -Path $terminalBackupPath -Parent
    if (!(Test-Path -Path $backupDir)) {
        New-Item -ItemType Directory -Path $backupDir -Force
    }
    
    # Backup current settings
    if (Test-Path -Path $terminalSettingsPath) {
        Copy-Item -Path $terminalSettingsPath -Destination $terminalBackupPath -Force
        Write-Host "Windows Terminal settings backed up successfully" -ForegroundColor Green
    } else {
        Write-Host "No Windows Terminal settings found to backup" -ForegroundColor Yellow
    }
} catch {
    Write-Host "Failed to backup Windows Terminal settings: $_" -ForegroundColor Red
} 