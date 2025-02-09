function Restore-TerminalSettings {
    try {
        Write-Host "Restoring Terminal settings..." -ForegroundColor Blue
        $terminalPath = Test-BackupPath -Path "Terminal" -BackupType "Terminal"
        
        if ($terminalPath) {
            $settingsFile = "$terminalPath\settings.json"
            if (Test-Path $settingsFile) {
                $destPath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
                
                # Create destination directory if it doesn't exist
                $destDir = Split-Path -Parent $destPath
                if (!(Test-Path $destDir)) {
                    New-Item -ItemType Directory -Path $destDir -Force | Out-Null
                }
                
                Copy-Item -Path $settingsFile -Destination $destPath -Force
                Write-Host "Terminal settings restored successfully" -ForegroundColor Green
            } else {
                Write-Host "Terminal settings file not found" -ForegroundColor Yellow
            }
        }
    } catch {
        Write-Host "Failed to restore Terminal settings: $_" -ForegroundColor Red
    }
} 