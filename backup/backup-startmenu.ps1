param(
    [Parameter(Mandatory=$true)]
    [string]$BackupRootPath
)

try {
    Write-Host "Backing up Start Menu settings..." -ForegroundColor Blue
    $backupPath = Initialize-BackupDirectory -Path "StartMenu" -BackupType "Start Menu" -BackupRootPath $BackupRootPath
    
    if ($backupPath) {
        # Export Start Menu layout and settings
        $regPaths = @(
            "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced",
            "HKCU\Software\Microsoft\Windows\CurrentVersion\Start",
            "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\StartPage"
        )
        
        foreach ($regPath in $regPaths) {
            $regFile = "$backupPath\$($regPath.Split('\')[-1]).reg"
            reg export $regPath $regFile /y
        }
        
        # Export Start Menu layout XML
        $layoutPath = "$env:LOCALAPPDATA\Microsoft\Windows\Shell\LayoutModification.xml"
        if (Test-Path $layoutPath) {
            Copy-Item -Path $layoutPath -Destination "$backupPath\StartLayout.xml" -Force
        }
        
        Write-Host "Start Menu settings backed up successfully to: $backupPath" -ForegroundColor Green
    }
} catch {
    Write-Host "Failed to backup Start Menu settings: $_" -ForegroundColor Red
} 