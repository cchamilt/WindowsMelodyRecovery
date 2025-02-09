try {
    Write-Host "Backing up Explorer settings..." -ForegroundColor Blue
    
    $backupPath = "$env:USERPROFILE\OneDrive - Fyber Labs\PCbackup\shared\Explorer"
    
    # Create backup directory if it doesn't exist
    if (!(Test-Path -Path $backupPath)) {
        New-Item -ItemType Directory -Path $backupPath -Force
    }
    
    # Export Explorer settings
    $explorerRegPath = "$backupPath\explorer_settings.reg"
    reg export "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer" $explorerRegPath /y
    
    # Export folder views
    $bagsMRURegPath = "$backupPath\explorer_bagsmru.reg"
    reg export "HKCU\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\BagMRU" $bagsMRURegPath /y
    
    # Export folder settings
    $bagsRegPath = "$backupPath\explorer_bags.reg"
    reg export "HKCU\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags" $bagsRegPath /y
    
    Write-Host "Explorer settings backed up successfully to: $backupPath" -ForegroundColor Green
} catch {
    Write-Host "Failed to backup Explorer settings: $_" -ForegroundColor Red
} 