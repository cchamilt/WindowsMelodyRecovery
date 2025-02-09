try {
    Write-Host "Backing up touchscreen state..." -ForegroundColor Blue
    
    $backupPath = "$env:USERPROFILE\OneDrive - Fyber Labs\PCbackup\shared\Touchscreen"
    
    # Create backup directory if it doesn't exist
    if (!(Test-Path -Path $backupPath)) {
        New-Item -ItemType Directory -Path $backupPath -Force
    }
    
    # Get and save touchscreen device states
    $touchscreenDevices = Get-PnpDevice | Where-Object { 
        $_.Class -eq "HIDClass" -and 
        $_.FriendlyName -match "touch screen|touchscreen|touch input"
    }
    
    $deviceStates = $touchscreenDevices | Select-Object InstanceId, Status, FriendlyName
    $deviceStates | ConvertTo-Json | Set-Content "$backupPath\touchscreen_state.json"
    
    Write-Host "Touchscreen state backed up successfully to: $backupPath" -ForegroundColor Green
} catch {
    Write-Host "Failed to backup touchscreen state: $_" -ForegroundColor Red
} 