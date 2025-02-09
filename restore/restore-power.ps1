function Restore-PowerSettings {
    try {
        Write-Host "Restoring Power settings..." -ForegroundColor Blue
        $powerPath = Test-BackupPath -Path "Power" -BackupType "Power"
        
        if ($powerPath) {
            # Import power scheme
            $schemePath = "$powerPath\power_scheme.pow"
            if (Test-Path $schemePath) {
                # Import the power scheme
                $output = powercfg /import $schemePath
                if ($LASTEXITCODE -eq 0) {
                    # Get the GUID of the imported scheme
                    $schemeGuid = $output | Select-String -Pattern "GUID: (.+) \(" | ForEach-Object { $_.Matches.Groups[1].Value }
                    
                    if ($schemeGuid) {
                        # Set as active scheme
                        powercfg /setactive $schemeGuid
                        Write-Host "Power settings restored successfully" -ForegroundColor Green
                    } else {
                        Write-Host "Failed to get power scheme GUID" -ForegroundColor Red
                    }
                } else {
                    Write-Host "Failed to import power scheme" -ForegroundColor Red
                }
            } else {
                Write-Host "Power scheme file not found" -ForegroundColor Yellow
            }
            
            if (Test-Path "$powerPath\hibernate_settings.json") {
                $hibernateSettings = Get-Content "$powerPath\hibernate_settings.json" | ConvertFrom-Json
                if ($hibernateSettings.HibernateEnabled) {
                    powercfg /hibernate on
                    if ($hibernateSettings.HibernateDiskSize) {
                        powercfg /hibernatesize $hibernateSettings.HibernateDiskSize
                    }
                } else {
                    powercfg /hibernate off
                }
            }
        }
    } catch {
        Write-Host "Failed to restore Power settings: $_" -ForegroundColor Red
    }
} 