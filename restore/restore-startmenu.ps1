function Restore-StartMenuSettings {
    try {
        Write-Host "Restoring Start Menu settings..." -ForegroundColor Blue
        $startMenuPath = Test-BackupPath -Path "StartMenu" -BackupType "Start Menu"
        
        if ($startMenuPath) {
            # Import registry settings
            $regFiles = Get-ChildItem -Path $startMenuPath -Filter "*.reg"
            foreach ($regFile in $regFiles) {
                reg import $regFile.FullName
            }
            
            # Restore Start Menu layout if it exists
            $layoutFile = "$startMenuPath\StartLayout.xml"
            if (Test-Path $layoutFile) {
                $layoutDestination = "$env:LOCALAPPDATA\Microsoft\Windows\Shell\LayoutModification.xml"
                Copy-Item -Path $layoutFile -Destination $layoutDestination -Force
                
                # Restart explorer to apply changes
                Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
                Start-Process explorer
            }
            
            Write-Host "Start Menu settings restored successfully" -ForegroundColor Green
        }
    } catch {
        Write-Host "Failed to restore Start Menu settings: $_" -ForegroundColor Red
    }
} 