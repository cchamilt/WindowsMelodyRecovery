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
            # Sound config locations
            $soundConfigs = @{
                # Audio devices
                "Devices" = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e96c-e325-11ce-bfc1-08002be10318}"
                # Sound settings
                "Settings" = "HKCU:\Software\Microsoft\Multimedia\Audio"
                # Sound scheme
                "Scheme" = "HKCU:\AppEvents\Schemes"
                # Sound effects
                "Effects" = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Audio"
                # Volume mixer
                "Mixer" = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Multimedia\Audio"
                # Communications settings
                "Communications" = "HKCU:\Software\Microsoft\Multimedia\Audio\DeviceCpl"
                # Spatial sound
                "Spatial" = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Audio\SpatialSound"
                # Audio enhancements
                "Enhancements" = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Audio\AudioEnhancements"
            }

            # Restore sound settings
            Write-Host "Checking audio components..." -ForegroundColor Yellow
            $audioServices = @(
                "Audiosrv",            # Windows Audio
                "AudioEndpointBuilder", # Windows Audio Endpoint Builder
                "MMCSS"                # Multimedia Class Scheduler
            )
            
            foreach ($service in $audioServices) {
                if ((Get-Service -Name $service -ErrorAction SilentlyContinue).Status -ne "Running") {
                    Start-Service -Name $service
                }
            }

            # Restore registry settings
            foreach ($config in $soundConfigs.GetEnumerator()) {
                $backupItem = Join-Path $backupPath $config.Key
                if (Test-Path $backupItem) {
                    Write-Host "Restoring $($config.Key) settings..." -ForegroundColor Yellow
                    if ((Get-Item $backupItem) -is [System.IO.DirectoryInfo]) {
                        # Skip temporary files during restore
                        $excludeFilter = @("*.tmp", "~*.*", "*.bak", "*.old")
                        Copy-Item $backupItem $config.Value -Recurse -Force -Exclude $excludeFilter
                    } else {
                        Copy-Item $backupItem $config.Value -Force
                    }
                    Write-Host "Restored configuration: $($config.Key)" -ForegroundColor Green
                }
            }

            # Restore audio devices
            $devicesFile = Join-Path $backupPath "audio_devices.json"
            if (Test-Path $devicesFile) {
                $devices = Get-Content $devicesFile | ConvertFrom-Json
                foreach ($device in $devices) {
                    # Set default audio device
                    if ($device.IsDefault) {
                        $audioDevice = Get-AudioDevice -List | Where-Object { $_.ID -eq $device.ID }
                        if ($audioDevice) {
                            Set-AudioDevice -ID $device.ID
                        }
                    }
                }
            }

            # Restore sound scheme
            $schemeFile = Join-Path $backupPath "sound_scheme.json"
            if (Test-Path $schemeFile) {
                $scheme = Get-Content $schemeFile | ConvertFrom-Json
                foreach ($sound in $scheme.Sounds) {
                    $soundPath = Join-Path $backupPath "Sounds\$($sound.FileName)"
                    if (Test-Path $soundPath) {
                        Copy-Item $soundPath "$env:SystemRoot\Media\" -Force
                        Set-ItemProperty -Path $sound.RegistryPath -Name $sound.Event -Value $sound.FileName
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