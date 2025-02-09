try {
    Write-Host "Backing up sound settings..." -ForegroundColor Blue
    $backupPath = "$env:USERPROFILE\OneDrive - Fyber Labs\PCbackup\shared\Sound"
    
    if (!(Test-Path -Path $backupPath)) {
        New-Item -ItemType Directory -Path $backupPath -Force
    }
    
    # Export sound scheme and device preferences
    reg export "HKCU\AppEvents\Schemes" "$backupPath\sound_schemes.reg" /y
    reg export "HKCU\Software\Microsoft\Multimedia\Audio" "$backupPath\audio_settings.reg" /y
    
    Write-Host "Sound settings backed up successfully" -ForegroundColor Green
} catch {
    Write-Host "Failed to backup sound settings: $_" -ForegroundColor Red
} 