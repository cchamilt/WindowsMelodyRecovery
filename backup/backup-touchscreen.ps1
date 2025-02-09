param(
    [Parameter(Mandatory=$true)]
    [string]$BackupRootPath
)

try {
    Write-Host "Backing up Touchscreen settings..." -ForegroundColor Blue
    $backupPath = Initialize-BackupDirectory -Path "Touchscreen" -BackupType "Touchscreen" -BackupRootPath $BackupRootPath
    
    if ($backupPath) {
        # Export touchscreen settings from registry
        $regPaths = @(
            "HKLM\SYSTEM\CurrentControlSet\Services\HID\TouchScreen",
            "HKLM\SOFTWARE\Microsoft\TouchPrediction",
            "HKLM\SOFTWARE\Microsoft\Touchscreen"
        )
        
        foreach ($regPath in $regPaths) {
            $regFile = "$backupPath\$($regPath.Split('\')[-1]).reg"
            reg export $regPath $regFile /y
        }
        
        # Export current touchscreen device configuration
        $touchDevices = Get-CimInstance -ClassName Win32_PnPEntity | 
            Where-Object { $_.PNPClass -eq "TouchScreen" } | 
            Select-Object Name, DeviceID, Status
        
        if ($touchDevices) {
            $touchDevices | ConvertTo-Json | Out-File "$backupPath\touch_devices.json" -Force
        }
        
        Write-Host "Touchscreen settings backed up successfully to: $backupPath" -ForegroundColor Green
    }
} catch {
    Write-Host "Failed to backup Touchscreen settings: $_" -ForegroundColor Red
} 