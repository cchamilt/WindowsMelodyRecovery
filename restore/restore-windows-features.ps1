function Restore-WindowsFeatures {
    try {
        Write-Host "Restoring Windows Features..." -ForegroundColor Blue
        $featuresPath = Test-BackupPath -Path "WindowsFeatures" -BackupType "Windows Features"
        
        if ($featuresPath) {
            # Get current state
            $currentFeatures = Get-WindowsOptionalFeature -Online | 
                Where-Object { $_.State -eq "Enabled" } |
                Select-Object -ExpandProperty FeatureName

            $currentCapabilities = Get-WindowsCapability -Online | 
                Where-Object { $_.State -eq "Installed" } |
                Select-Object -ExpandProperty Name

            # Restore features
            $featuresFile = "$featuresPath\enabled_features.json"
            if (Test-Path $featuresFile) {
                $backupFeatures = Get-Content $featuresFile | ConvertFrom-Json
                
                foreach ($feature in $backupFeatures) {
                    if ($feature.FeatureName -notin $currentFeatures) {
                        Write-Host "Enabling feature: $($feature.FeatureName)" -ForegroundColor Yellow
                        Enable-WindowsOptionalFeature -Online -FeatureName $feature.FeatureName -NoRestart
                    }
                }
            }

            # Restore capabilities
            $capabilitiesFile = "$featuresPath\enabled_capabilities.json"
            if (Test-Path $capabilitiesFile) {
                $backupCapabilities = Get-Content $capabilitiesFile | ConvertFrom-Json
                
                foreach ($capability in $backupCapabilities) {
                    if ($capability.Name -notin $currentCapabilities) {
                        Write-Host "Adding capability: $($capability.Name)" -ForegroundColor Yellow
                        Add-WindowsCapability -Online -Name $capability.Name
                    }
                }
            }

            Write-Host "Windows Features restored successfully" -ForegroundColor Green
            Write-Host "Note: Some features may require a system restart to complete installation" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "Failed to restore Windows Features: $_" -ForegroundColor Red
    }
} 