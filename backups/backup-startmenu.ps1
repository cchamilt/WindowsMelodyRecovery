try {
    Write-Host "Backing up Start Menu and Taskbar settings..." -ForegroundColor Blue
    $backupPath = "$env:USERPROFILE\OneDrive - Fyber Labs\PCbackup\shared\StartMenu"
    
    if (!(Test-Path -Path $backupPath)) {
        New-Item -ItemType Directory -Path $backupPath -Force
    }
    
    # Export Start Menu layout
    Export-StartLayout -Path "$backupPath\startlayout.xml"
    
    # Export taskbar settings
    reg export "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband" "$backupPath\taskbar.reg" /y
    
    Write-Host "Start Menu and Taskbar settings backed up successfully" -ForegroundColor Green
} catch {
    Write-Host "Failed to backup Start Menu settings: $_" -ForegroundColor Red
} 