try {
    Write-Host "Backing up power settings..." -ForegroundColor Blue
    
    $backupPath = "$env:USERPROFILE\OneDrive - Fyber Labs\PCbackup\shared\Power"
    
    # Create backup directory if it doesn't exist
    if (!(Test-Path -Path $backupPath)) {
        New-Item -ItemType Directory -Path $backupPath -Force
    }
    
    # Export all power schemes
    $powerSchemesFile = "$backupPath\power_schemes.pow"
    powercfg /export "$powerSchemesFile"
    
    # Save active scheme GUID
    $activeScheme = (powercfg /getactivescheme) -split ' ' | Select-Object -Last 1
    $activeScheme | Set-Content "$backupPath\active_scheme.txt"
    
    # Export hibernate settings
    $hibernateState = powercfg /availablesleepstates | Select-String "Hibernation"
    $hibernateEnabled = $hibernateState -match "Hibernation is available"
    @{
        HibernateEnabled = $hibernateEnabled
        HibernateDiskSize = (powercfg /hibernatesize).ToString()
    } | ConvertTo-Json | Set-Content "$backupPath\hibernate_settings.json"
    
    Write-Host "Power settings backed up successfully to: $backupPath" -ForegroundColor Green
} catch {
    Write-Host "Failed to backup power settings: $_" -ForegroundColor Red
} 