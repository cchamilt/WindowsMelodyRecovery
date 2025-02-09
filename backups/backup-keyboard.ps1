try {
    Write-Host "Backing up keyboard settings..." -ForegroundColor Blue
    $backupPath = "$env:USERPROFILE\OneDrive - Fyber Labs\PCbackup\shared\Keyboard"
    
    if (!(Test-Path -Path $backupPath)) {
        New-Item -ItemType Directory -Path $backupPath -Force
    }
    
    # Export keyboard layouts and input methods
    reg export "HKCU\Keyboard Layout" "$backupPath\keyboard_layout.reg" /y
    reg export "HKCU\Software\Microsoft\Input" "$backupPath\input_settings.reg" /y
    
    Write-Host "Keyboard settings backed up successfully" -ForegroundColor Green
} catch {
    Write-Host "Failed to backup keyboard settings: $_" -ForegroundColor Red
} 