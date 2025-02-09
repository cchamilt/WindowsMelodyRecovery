function Restore-SoundSettings {
    try {
        Write-Host "Restoring Sound settings..." -ForegroundColor Blue
        $soundPath = Test-BackupPath -Path "Sound" -BackupType "Sound"
        
        if ($soundPath) {
            # Import sound registry settings
            $regFiles = Get-ChildItem -Path $soundPath -Filter "*.reg"
            foreach ($regFile in $regFiles) {
                reg import $regFile.FullName
            }
            
            # Restore audio device configuration if it exists
            $deviceConfig = "$soundPath\audio_devices.json"
            if (Test-Path $deviceConfig) {
                $audioDevices = Get-Content $deviceConfig | ConvertFrom-Json
                foreach ($device in $audioDevices) {
                    if ($device.Status -eq 'OK') {
                        $existingDevice = Get-PnpDevice -FriendlyName $device.Name -ErrorAction SilentlyContinue
                        if ($existingDevice -and $existingDevice.Status -ne 'OK') {
                            Enable-PnpDevice -InstanceId $existingDevice.InstanceId -Confirm:$false
                        }
                    }
                }
            }
            
            # Restart audio service to apply changes
            Restart-Service -Name Audiosrv -Force
            Write-Host "Sound settings restored successfully" -ForegroundColor Green
        }
    } catch {
        Write-Host "Failed to restore Sound settings: $_" -ForegroundColor Red
    }
} 