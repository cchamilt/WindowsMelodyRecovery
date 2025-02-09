param(
    [Parameter(Mandatory=$true)]
    [string]$BackupRootPath
)

try {
    Write-Host "Backing up Sound settings..." -ForegroundColor Blue
    $backupPath = Initialize-BackupDirectory -Path "Sound" -BackupType "Sound" -BackupRootPath $BackupRootPath
    
    if ($backupPath) {
        # Export sound settings from registry
        $regPaths = @(
            "HKCU\AppEvents\Schemes",
            "HKCU\Software\Microsoft\Multimedia\Audio",
            "HKCU\Software\Microsoft\Windows\CurrentVersion\MMDevices\Audio"
        )
        
        foreach ($regPath in $regPaths) {
            $regFile = "$backupPath\$($regPath.Split('\')[-1]).reg"
            reg export $regPath $regFile /y
        }
        
        # Export current audio devices configuration
        $audioDevices = Get-CimInstance -Class Win32_SoundDevice | Select-Object Name, DeviceID, Status
        $audioDevices | ConvertTo-Json | Out-File "$backupPath\audio_devices.json" -Force
        
        Write-Host "Sound settings backed up successfully to: $backupPath" -ForegroundColor Green
    }
} catch {
    Write-Host "Failed to backup Sound settings: $_" -ForegroundColor Red
} 