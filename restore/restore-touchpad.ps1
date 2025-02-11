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
            # Import registry settings
            $regFiles = Get-ChildItem -Path $backupPath -Filter "*.reg"
            foreach ($regFile in $regFiles) {
                reg import $regFile.FullName | Out-Null
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