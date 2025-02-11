[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$BackupRootPath = $null
)

# Load environment if not provided
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path (Split-Path $scriptPath -Parent) "scripts\load-environment.ps1")

if (!$BackupRootPath) {
    if (!(Load-Environment)) {
        Write-Host "Failed to load environment configuration" -ForegroundColor Red
        exit 1
    }
    $BackupRootPath = "$env:BACKUP_ROOT\$env:MACHINE_NAME"
}

function Restore-SoundSettings {
    param(
        [Parameter(Mandatory=$true)]
        [string]$BackupRootPath
    )
    
    try {
        Write-Host "Restoring Sound Settings..." -ForegroundColor Blue
        $backupPath = Test-BackupPath -Path "Sound" -BackupType "Sound Settings"
        
        if ($backupPath) {
            # Import registry settings first
            $regFiles = Get-ChildItem -Path $backupPath -Filter "*.reg"
            foreach ($regFile in $regFiles) {
                reg import $regFile.FullName | Out-Null
            }

            # Restore audio devices configuration
            $audioDevicesFile = "$backupPath\audio_devices.json"
            if (Test-Path $audioDevicesFile) {
                $savedDevices = Get-Content $audioDevicesFile | ConvertFrom-Json
                $currentDevices = Get-WmiObject Win32_SoundDevice

                foreach ($current in $currentDevices) {
                    $saved = $savedDevices | Where-Object { $_.DeviceID -eq $current.DeviceID }
                    if ($saved) {
                        # Update supported properties
                        $current.Status = $saved.Status
                        $current.Put()
                    }
                }
            }

            # Restore default devices
            $defaultDevicesFile = "$backupPath\default_devices.json"
            if (Test-Path $defaultDevicesFile) {
                $defaultDevices = Get-Content $defaultDevicesFile | ConvertFrom-Json
                
                # Set default playback device
                if ($defaultDevices.DefaultPlayback) {
                    $device = Get-AudioDevice -List | Where-Object { 
                        $_.ID -eq $defaultDevices.DefaultPlayback.ID -or 
                        $_.Name -eq $defaultDevices.DefaultPlayback.Name 
                    }
                    if ($device) {
                        Set-AudioDevice -ID $device.ID
                    }
                }

                # Set default recording device
                if ($defaultDevices.DefaultRecording) {
                    $device = Get-AudioDevice -List | Where-Object { 
                        $_.ID -eq $defaultDevices.DefaultRecording.ID -or 
                        $_.Name -eq $defaultDevices.DefaultRecording.Name 
                    }
                    if ($device) {
                        Set-AudioDevice -ID $device.ID
                    }
                }
            }

            # Restore sound schemes
            $schemesPath = Join-Path $backupPath "SoundSchemes"
            if (Test-Path $schemesPath) {
                $systemMediaPath = "$env:SystemRoot\Media"
                if (!(Test-Path $systemMediaPath)) {
                    New-Item -ItemType Directory -Path $systemMediaPath -Force | Out-Null
                }
                Copy-Item -Path "$schemesPath\*.wav" -Destination $systemMediaPath -Force
            }

            # Restore per-app volume settings
            $appVolumeFile = "$backupPath\app_volume.json"
            if (Test-Path $appVolumeFile) {
                $appVolume = Get-Content $appVolumeFile | ConvertFrom-Json
                foreach ($app in $appVolume.PSObject.Properties) {
                    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers" `
                        -Name $app.Name -Value $app.Value -Type String -ErrorAction SilentlyContinue
                }
            }

            # Restart audio service to apply changes
            Restart-Service -Name Audiosrv -Force
            
            Write-Host "Sound Settings restored successfully from: $backupPath" -ForegroundColor Green
            return $true
        }
        return $false
    } catch {
        Write-Host "Failed to restore Sound Settings: $_" -ForegroundColor Red
        return $false
    }
}

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Restore-SoundSettings -BackupRootPath $BackupRootPath
} 