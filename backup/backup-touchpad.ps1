param(
    [Parameter(Mandatory=$true)]
    [string]$BackupRootPath
)

try {
    Write-Host "Backing up Touchpad settings..." -ForegroundColor Blue
    $backupPath = Initialize-BackupDirectory -Path "Touchpad" -BackupType "Touchpad" -BackupRootPath $BackupRootPath
    
    if ($backupPath) {
        # Export touchpad settings from registry
        $regPaths = @(
            "HKCU\Software\Microsoft\Windows\CurrentVersion\PrecisionTouchPad",
            "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\PrecisionTouchPad",
            "HKLM\SYSTEM\CurrentControlSet\Services\MouseLikeTouchPad"
        )
        
        foreach ($regPath in $regPaths) {
            $regFile = "$backupPath\$($regPath.Split('\')[-1]).reg"
            reg export $regPath $regFile /y
        }
        
        Write-Host "Touchpad settings backed up successfully to: $backupPath" -ForegroundColor Green
    }
} catch {
    Write-Host "Failed to backup Touchpad settings: $_" -ForegroundColor Red
} 