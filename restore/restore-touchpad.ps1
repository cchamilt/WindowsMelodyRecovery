function Restore-TouchpadSettings {
    try {
        Write-Host "Restoring Touchpad settings..." -ForegroundColor Blue
        $touchpadPath = Test-BackupPath -Path "Touchpad" -BackupType "Touchpad"
        
        if ($touchpadPath) {
            # Import registry settings
            $regFiles = Get-ChildItem -Path $touchpadPath -Filter "*.reg"
            foreach ($regFile in $regFiles) {
                reg import $regFile.FullName
            }
            
            # Restore device states
            $deviceConfig = "$touchpadPath\touchpad_devices.json"
            if (Test-Path $deviceConfig) {
                $touchpadDevices = Get-Content $deviceConfig | ConvertFrom-Json
                foreach ($device in $touchpadDevices) {
                    $existingDevice = Get-PnpDevice -InstanceId $device.InstanceId -ErrorAction SilentlyContinue
                    if ($existingDevice) {
                        if ($device.IsEnabled -and $existingDevice.Status -ne 'OK') {
                            Write-Host "Enabling touchpad device: $($device.FriendlyName)" -ForegroundColor Yellow
                            Enable-PnpDevice -InstanceId $device.InstanceId -Confirm:$false
                        } elseif (-not $device.IsEnabled -and $existingDevice.Status -eq 'OK') {
                            Write-Host "Disabling touchpad device: $($device.FriendlyName)" -ForegroundColor Yellow
                            Disable-PnpDevice -InstanceId $device.InstanceId -Confirm:$false
                        }
                    }
                }
            }
            
            # Restart touchpad services
            $services = @(
                "TabletInputService",
                "SynTPEnh",
                "ETDService"
            )
            
            foreach ($service in $services) {
                if (Get-Service -Name $service -ErrorAction SilentlyContinue) {
                    Restart-Service -Name $service -Force
                }
            }
            
            Restart-Service -Name TabletInputService -Force
            Write-Host "Touchpad settings restored successfully" -ForegroundColor Green
        }
    } catch {
        Write-Host "Failed to restore Touchpad settings: $_" -ForegroundColor Red
    }
} 