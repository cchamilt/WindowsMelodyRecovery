function Restore-TouchpadSettings {
    try {
        Write-Host "Restoring Touchpad settings..." -ForegroundColor Blue
        $touchpadPath = Test-BackupPath -Path "Touchpad" -BackupType "Touchpad"
        
        if ($touchpadPath) {
            # Import touchpad registry settings
            $regFiles = Get-ChildItem -Path $touchpadPath -Filter "*.reg"
            foreach ($regFile in $regFiles) {
                reg import $regFile.FullName
            }
            reg import "$touchpadPath\mouse_settings.reg"
            
            Restart-Service -Name TabletInputService -Force
            Write-Host "Touchpad settings restored successfully" -ForegroundColor Green
        }
    } catch {
        Write-Host "Failed to restore Touchpad settings: $_" -ForegroundColor Red
    }
} 