try {
    Write-Host "Backing up Touchpad settings..." -ForegroundColor Blue
    
    $backupPath = "$env:USERPROFILE\OneDrive - Fyber Labs\PCbackup\shared\Touchpad"
    
    # Create backup directory if it doesn't exist
    if (!(Test-Path -Path $backupPath)) {
        New-Item -ItemType Directory -Path $backupPath -Force
    }
    
    # Export Windows Precision Touchpad settings
    $touchpadRegPath = "$backupPath\touchpad_settings.reg"
    reg export "HKCU\Software\Microsoft\Windows\CurrentVersion\PrecisionTouchPad" $touchpadRegPath /y
    
    # Export Synaptics settings (if they exist)
    $synapticsRegPath = "$backupPath\synaptics_settings.reg"
    reg export "HKLM\SOFTWARE\Synaptics" $synapticsRegPath /y
    
    # Export Mouse properties (includes some touchpad settings)
    $mouseRegPath = "$backupPath\mouse_settings.reg"
    reg export "HKCU\Control Panel\Mouse" $mouseRegPath /y
    
    Write-Host "Touchpad settings backed up successfully to: $backupPath" -ForegroundColor Green
} catch {
    Write-Host "Failed to backup Touchpad settings: $_" -ForegroundColor Red
} 