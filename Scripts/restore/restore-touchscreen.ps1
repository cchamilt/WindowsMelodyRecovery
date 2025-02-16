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

function Restore-TouchscreenSettings {
    param(
        [Parameter(Mandatory=$true)]
        [string]$BackupRootPath
    )
    
    try {
        Write-Host "Restoring Touchscreen Settings..." -ForegroundColor Blue
        $backupPath = Test-BackupPath -Path "Touchscreen" -BackupType "Touchscreen Settings"
        
        if ($backupPath) {
            # Touchscreen config locations
            $touchscreenConfigs = @{
                # Touchscreen settings
                "Settings" = "HKLM:\SYSTEM\CurrentControlSet\Services\HidIr"
                # Touch input settings
                "Input" = "HKCU:\Software\Microsoft\Windows\CurrentVersion\TouchInput"
                # Pen and touch settings
                "PenTouch" = "HKCU:\Software\Microsoft\Windows\CurrentVersion\PenWorkspace"
                # Touch keyboard settings
                "Keyboard" = "HKCU:\Software\Microsoft\TabletTip\1.7"
                # Touch feedback
                "Feedback" = "HKCU:\Control Panel\TouchFeedback"
                # Touch gestures
                "Gestures" = "HKCU:\Software\Microsoft\Windows\CurrentVersion\TouchGestures"
                # Touch prediction
                "Prediction" = "HKCU:\Software\Microsoft\Windows\CurrentVersion\TouchPrediction"
            }

            # Restore touchscreen settings
            Write-Host "Checking touchscreen components..." -ForegroundColor Yellow
            $touchscreenServices = @(
                "TabletInputService",     # Touch Keyboard and Handwriting Panel Service
                "TouchServicesHost",      # Touch Keyboard and Handwriting Panel Host
                "PenService"             # Windows Pen and Touch Input Service
            )
            
            foreach ($service in $touchscreenServices) {
                if ((Get-Service -Name $service -ErrorAction SilentlyContinue).Status -ne "Running") {
                    Start-Service -Name $service
                }
            }

            # Restore registry settings
            foreach ($config in $touchscreenConfigs.GetEnumerator()) {
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

            # Restore touchscreen device settings
            $deviceSettingsFile = Join-Path $backupPath "touchscreen_device.json"
            if (Test-Path $deviceSettingsFile) {
                $deviceSettings = Get-Content $deviceSettingsFile | ConvertFrom-Json
                
                # Get current touchscreen device
                $touchscreen = Get-WmiObject Win32_PointingDevice | Where-Object {
                    $_.Name -like "*Touch Screen*" -or $_.PNPClass -eq "TouchScreen"
                }

                if ($touchscreen) {
                    # Apply device-specific settings
                    foreach ($setting in $deviceSettings.PSObject.Properties) {
                        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Enum\$($touchscreen.PNPDeviceID)\Device Parameters" `
                            -Name $setting.Name -Value $setting.Value
                    }
                }
            }

            # Restore calibration data
            $calibrationFile = Join-Path $backupPath "calibration.dat"
            if (Test-Path $calibrationFile) {
                $calibrationPath = "$env:SystemRoot\System32\calibration.dat"
                Copy-Item $calibrationFile $calibrationPath -Force
            }
            
            # Restore device states
            $deviceConfig = "$backupPath\touchscreen_devices.json"
            if (Test-Path $deviceConfig) {
                $touchscreenDevices = Get-Content $deviceConfig | ConvertFrom-Json
                foreach ($device in $touchscreenDevices) {
                    $existingDevice = Get-PnpDevice -InstanceId $device.InstanceId -ErrorAction SilentlyContinue
                    if ($existingDevice) {
                        if ($device.IsEnabled -and $existingDevice.Status -ne 'OK') {
                            Write-Host "Enabling touchscreen device: $($device.FriendlyName)" -ForegroundColor Yellow
                            Enable-PnpDevice -InstanceId $device.InstanceId -Confirm:$false
                        } elseif (-not $device.IsEnabled -and $existingDevice.Status -eq 'OK') {
                            Write-Host "Disabling touchscreen device: $($device.FriendlyName)" -ForegroundColor Yellow
                            Disable-PnpDevice -InstanceId $device.InstanceId -Confirm:$false
                        }
                    }
                }
            }
            
            # Restart touch-related services
            $services = @(
                "TabletInputService",
                "TouchServiced",
                "WacomPenService"
            )
            
            foreach ($service in $services) {
                if (Get-Service -Name $service -ErrorAction SilentlyContinue) {
                    Restart-Service -Name $service -Force -ErrorAction SilentlyContinue
                }
            }
            
            Write-Host "Touchscreen Settings restored successfully from: $backupPath" -ForegroundColor Green
            return $true
        }
        return $false
    } catch {
        Write-Host "Failed to restore Touchscreen Settings: $_" -ForegroundColor Red
        return $false
    }
}

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Restore-TouchscreenSettings -BackupRootPath $BackupRootPath
} 