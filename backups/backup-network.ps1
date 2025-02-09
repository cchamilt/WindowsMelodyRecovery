try {
    Write-Host "Backing up network profiles..." -ForegroundColor Blue
    $backupPath = "$env:USERPROFILE\OneDrive - Fyber Labs\PCbackup\shared\Network"
    
    if (!(Test-Path -Path $backupPath)) {
        New-Item -ItemType Directory -Path $backupPath -Force
    }
    
    # Export network profiles
    netsh wlan export profile folder="$backupPath" key=clear
    
    # Export VPN connections
    reg export "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\NetworkList" "$backupPath\network_profiles.reg" /y
    
    Write-Host "Network profiles backed up successfully" -ForegroundColor Green
} catch {
    Write-Host "Failed to backup network profiles: $_" -ForegroundColor Red
} 