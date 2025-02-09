function Restore-ExplorerSettings {
    try {
        Write-Host "Restoring Explorer settings..." -ForegroundColor Blue
        $explorerPath = Test-BackupPath -Path "Explorer" -BackupType "Explorer"
        
        if ($explorerPath) {
            # Import registry settings
            $regFiles = Get-ChildItem -Path $explorerPath -Filter "*.reg"
            foreach ($regFile in $regFiles) {
                reg import $regFile.FullName
            }
            
            # Restart explorer to apply changes
            Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
            Start-Process explorer
            
            Write-Host "Explorer settings restored successfully" -ForegroundColor Green
        }
    } catch {
        Write-Host "Failed to restore Explorer settings: $_" -ForegroundColor Red
    }
} 