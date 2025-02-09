param(
    [Parameter(Mandatory=$true)]
    [string]$BackupRootPath
)

try {
    Write-Host "Backing up Keyboard settings..." -ForegroundColor Blue
    $backupPath = Initialize-BackupDirectory -Path "Keyboard" -BackupType "Keyboard" -BackupRootPath $BackupRootPath
    
    if ($backupPath) {
        # Export keyboard settings from registry
        $regPaths = @(
            "HKCU\Control Panel\Keyboard",
            "HKCU\Keyboard Layout",
            "HKCU\Software\Microsoft\Input"
        )
        
        foreach ($regPath in $regPaths) {
            $regFile = "$backupPath\$($regPath.Split('\')[-1]).reg"
            reg export $regPath $regFile /y
        }
        
        Write-Host "Keyboard settings backed up successfully to: $backupPath" -ForegroundColor Green
    }
} catch {
    Write-Host "Failed to backup Keyboard settings: $_" -ForegroundColor Red
} 