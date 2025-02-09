param(
    [Parameter(Mandatory=$true)]
    [string]$BackupRootPath
)

try {
    Write-Host "Backing up Display settings..." -ForegroundColor Blue
    $backupPath = Initialize-BackupDirectory -Path "Display" -BackupType "Display" -BackupRootPath $BackupRootPath
    
    if ($backupPath) {
        # Export display settings from registry
        $regPaths = @(
            "HKCU\Control Panel\Desktop",
            "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects",
            "HKCU\Software\Microsoft\Windows\DWM"
        )
        
        foreach ($regPath in $regPaths) {
            $regFile = "$backupPath\$($regPath.Split('\')[-1]).reg"
            reg export $regPath $regFile /y
        }
        
        # Export current display configuration
        $displaySettings = Get-CimInstance -Namespace root\cimv2 -ClassName Win32_VideoController | Select-Object -Property *
        $displaySettings | ConvertTo-Json | Out-File "$backupPath\display_config.json" -Force
        
        Write-Host "Display settings backed up successfully to: $backupPath" -ForegroundColor Green
    }
} catch {
    Write-Host "Failed to backup Display settings: $_" -ForegroundColor Red
} 