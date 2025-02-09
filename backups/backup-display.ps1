try {
    Write-Host "Backing up display settings..." -ForegroundColor Blue
    $backupPath = "$env:USERPROFILE\OneDrive - Fyber Labs\PCbackup\shared\Display"
    
    if (!(Test-Path -Path $backupPath)) {
        New-Item -ItemType Directory -Path $backupPath -Force
    }
    
    # Export DPI and scaling settings
    reg export "HKCU\Control Panel\Desktop" "$backupPath\dpi_settings.reg" /y
    reg export "HKCU\Software\Microsoft\Windows\CurrentVersion\ThemeManager" "$backupPath\theme_settings.reg" /y
    
    Write-Host "Display settings backed up successfully" -ForegroundColor Green
} catch {
    Write-Host "Failed to backup display settings: $_" -ForegroundColor Red
} 