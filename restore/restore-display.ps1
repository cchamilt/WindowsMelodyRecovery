function Restore-DisplaySettings {
    try {
        Write-Host "Restoring Display settings..." -ForegroundColor Blue
        $displayPath = Test-BackupPath -Path "Display" -BackupType "Display"
        
        if ($displayPath) {
            # Import registry settings
            $regFiles = Get-ChildItem -Path $displayPath -Filter "*.reg"
            foreach ($regFile in $regFiles) {
                reg import $regFile.FullName
            }
            
            # Apply display configuration if it exists
            $configFile = "$displayPath\display_config.json"
            if (Test-Path $configFile) {
                $displayConfig = Get-Content $configFile | ConvertFrom-Json
                
                # Update display settings through CIM
                foreach ($display in $displayConfig) {
                    $currentDisplay = Get-CimInstance -ClassName Win32_VideoController | 
                        Where-Object { $_.DeviceID -eq $display.DeviceID }
                    
                    if ($currentDisplay) {
                        Set-CimInstance -InputObject $currentDisplay -Property @{
                            CurrentRefreshRate = $display.CurrentRefreshRate
                            CurrentHorizontalResolution = $display.CurrentHorizontalResolution
                            CurrentVerticalResolution = $display.CurrentVerticalResolution
                        }
                    }
                }
            }
            
            Write-Host "Display settings restored successfully" -ForegroundColor Green
        }
    } catch {
        Write-Host "Failed to restore Display settings: $_" -ForegroundColor Red
    }
} 