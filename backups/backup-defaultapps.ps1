try {
    Write-Host "Backing up default apps and file associations..." -ForegroundColor Blue
    $backupPath = "$env:USERPROFILE\OneDrive - Fyber Labs\PCbackup\shared\DefaultApps"
    
    if (!(Test-Path -Path $backupPath)) {
        New-Item -ItemType Directory -Path $backupPath -Force
    }
    
    # Export default apps associations
    Dism /Online /Export-DefaultAppAssociations:"$backupPath\AppAssociations.xml"
    
    Write-Host "Default apps settings backed up successfully" -ForegroundColor Green
} catch {
    Write-Host "Failed to backup default apps settings: $_" -ForegroundColor Red
} 