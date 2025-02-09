function Restore-DefaultAppSettings {
    try {
        Write-Host "Restoring Default Apps settings..." -ForegroundColor Blue
        $defaultAppsPath = Test-BackupPath -Path "DefaultApps" -BackupType "Default Apps"
        
        if ($defaultAppsPath) {
            # Import default apps associations
            $appsFile = "$defaultAppsPath\defaultapps.xml"
            if (Test-Path $appsFile) {
                $process = Start-Process -FilePath "dism.exe" `
                    -ArgumentList "/Online /Import-DefaultAppAssociations:`"$appsFile`"" `
                    -Wait -PassThru -NoNewWindow
                
                if ($process.ExitCode -eq 0) {
                    Write-Host "Default Apps settings restored successfully" -ForegroundColor Green
                } else {
                    Write-Host "Failed to import Default Apps settings. Exit code: $($process.ExitCode)" -ForegroundColor Red
                }
            } else {
                Write-Host "Default Apps configuration file not found" -ForegroundColor Yellow
            }
        }
    } catch {
        Write-Host "Failed to restore Default Apps settings: $_" -ForegroundColor Red
    }
} 