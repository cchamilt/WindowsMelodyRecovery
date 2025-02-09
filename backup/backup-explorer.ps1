param(
    [Parameter(Mandatory=$true)]
    [string]$BackupRootPath
)

try {
    Write-Host "Backing up Explorer settings..." -ForegroundColor Blue
    $backupPath = Initialize-BackupDirectory -Path "Explorer" -BackupType "Explorer" -BackupRootPath $BackupRootPath
    
    if ($backupPath) {
        # Export Explorer settings from registry
        $regPaths = @(
            "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer",
            "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
        )
        
        foreach ($regPath in $regPaths) {
            $regFile = "$backupPath\$($regPath.Split('\')[-1]).reg"
            reg export $regPath $regFile /y
        }
        
        Write-Host "Explorer settings backed up successfully to: $backupPath" -ForegroundColor Green
    }
} catch {
    Write-Host "Failed to backup Explorer settings: $_" -ForegroundColor Red
} 