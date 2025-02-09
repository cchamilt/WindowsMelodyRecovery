function Restore-TouchscreenSettings {
    try {
        Write-Host "Restoring Touchscreen settings..." -ForegroundColor Blue
        $touchscreenPath = Test-BackupPath -Path "Touchscreen" -BackupType "Touchscreen"
        
        if ($touchscreenPath) {
            # Import touchscreen registry settings
            $regFiles = Get-ChildItem -Path $touchscreenPath -Filter "*.reg"
            foreach ($regFile in $regFiles) {
                reg import $regFile.FullName
            }
            
            # Apply device configuration if it exists
            $deviceConfig = "$touchscreenPath\touch_devices.json"
            if (Test-Path $deviceConfig) {
                $touchDevices = Get-Content $deviceConfig | ConvertFrom-Json
                foreach ($device in $touchDevices) {
                    $existingDevice = Get-PnpDevice -InstanceId $device.DeviceID -ErrorAction SilentlyContinue
                    if ($existingDevice) {
                        if ($device.Status -eq 'OK' -and $existingDevice.Status -ne 'OK') {
                            Enable-PnpDevice -InstanceId $device.DeviceID -Confirm:$false
                        }
                    }
                }
            }
            
            Write-Host "Touchscreen settings restored successfully" -ForegroundColor Green
        }
    } catch {
        Write-Host "Failed to restore Touchscreen settings: $_" -ForegroundColor Red
    }
} 