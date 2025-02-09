function Restore-KeyboardSettings {
    try {
        Write-Host "Restoring Keyboard settings..." -ForegroundColor Blue
        $keyboardPath = Test-BackupPath -Path "Keyboard" -BackupType "Keyboard"
        
        if ($keyboardPath) {
            # Import registry settings
            $regFiles = Get-ChildItem -Path $keyboardPath -Filter "*.reg"
            foreach ($regFile in $regFiles) {
                reg import $regFile.FullName
            }
            
            # Restart input services to apply changes
            $services = @(
                "TabletInputService",
                "TextInputManagementService"
            )
            
            foreach ($service in $services) {
                if (Get-Service -Name $service -ErrorAction SilentlyContinue) {
                    Restart-Service -Name $service -Force
                }
            }
            
            Write-Host "Keyboard settings restored successfully" -ForegroundColor Green
        }
    } catch {
        Write-Host "Failed to restore Keyboard settings: $_" -ForegroundColor Red
    }
} 