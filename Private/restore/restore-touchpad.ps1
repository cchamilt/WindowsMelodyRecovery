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

function Restore-TouchpadSettings {
    param(
        [Parameter(Mandatory=$true)]
        [string]$BackupRootPath
    )
    
    try {
        Write-Host "Restoring Touchpad Settings..." -ForegroundColor Blue
        $backupPath = Test-BackupPath -Path "Touchpad" -BackupType "Touchpad Settings"
        
        if ($backupPath) {
            # Touchpad config locations
            $touchpadConfigs = @{
                # Touchpad settings
                "Settings" = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PrecisionTouchPad"
                # Touchpad gestures
                "Gestures" = "HKCU:\Software\Microsoft\Windows\CurrentVersion\PrecisionTouchPad\TouchpadSettings"
                # Touchpad sensitivity
                "Sensitivity" = "HKCU:\Software\Microsoft\Windows\CurrentVersion\PrecisionTouchPad\Status"
                # Touchpad scrolling
                "Scrolling" = "HKCU:\Software\Microsoft\Windows\CurrentVersion\PrecisionTouchPad\ScrollingSettings"
                # Touchpad tapping
                "Tapping" = "HKCU:\Software\Microsoft\Windows\CurrentVersion\PrecisionTouchPad\TappingSettings"
                # Touchpad three-finger
                "ThreeFinger" = "HKCU:\Software\Microsoft\Windows\CurrentVersion\PrecisionTouchPad\ThreeFingerGestureSettings"
                # Touchpad four-finger
                "FourFinger" = "HKCU:\Software\Microsoft\Windows\CurrentVersion\PrecisionTouchPad\FourFingerGestureSettings"
            }

            # Restore touchpad settings
            Write-Host "Checking touchpad components..." -ForegroundColor Yellow
            $touchpadServices = @(
                "TabletInputService",     # Touch Keyboard and Handwriting Panel Service
                "SynTPEnhService",        # Synaptics TouchPad Enhancements
                "PrecisionTouchpadService" # Windows Precision Touchpad
            )
            
            foreach ($service in $touchpadServices) {
                if ((Get-Service -Name $service -ErrorAction SilentlyContinue).Status -ne "Running") {
                    Start-Service -Name $service
                }
            }

            # Restore registry settings
            foreach ($config in $touchpadConfigs.GetEnumerator()) {
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

            # Restore touchpad device settings
            $deviceSettingsFile = Join-Path $backupPath "touchpad_device.json"
            if (Test-Path $deviceSettingsFile) {
                $deviceSettings = Get-Content $deviceSettingsFile | ConvertFrom-Json
                
                # Get current touchpad device
                $touchpad = Get-WmiObject Win32_PointingDevice | Where-Object {
                    $_.Name -like "*TouchPad*" -or $_.Name -like "*Precision TouchPad*"
                }

                if ($touchpad) {
                    # Apply device-specific settings
                    foreach ($setting in $deviceSettings.PSObject.Properties) {
                        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Enum\$($touchpad.PNPDeviceID)\Device Parameters" `
                            -Name $setting.Name -Value $setting.Value
                    }
                }
            }
            
            # Restore device states
            $deviceConfig = "$backupPath\touchpad_devices.json"
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
                    Restart-Service -Name $service -Force -ErrorAction SilentlyContinue
                }
            }
            
            Write-Host "Touchpad Settings restored successfully from: $backupPath" -ForegroundColor Green
            return $true
        }
        return $false
    } catch {
        Write-Host "Failed to restore Touchpad Settings: $_" -ForegroundColor Red
        return $false
    }
}

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Restore-TouchpadSettings -BackupRootPath $BackupRootPath
} 