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

function Restore-DisplaySettings {
    param(
        [Parameter(Mandatory=$true)]
        [string]$BackupRootPath
    )
    
    try {
        Write-Host "Restoring Display Settings..." -ForegroundColor Blue
        $backupPath = Test-BackupPath -Path "Display" -BackupType "Display Settings"
        
        if ($backupPath) {
            # Import registry settings first
            $regFiles = Get-ChildItem -Path $backupPath -Filter "*.reg"
            foreach ($regFile in $regFiles) {
                reg import $regFile.FullName | Out-Null
            }

            # Restore video controller settings where possible
            $videoControllersFile = "$backupPath\video_controllers.json"
            if (Test-Path $videoControllersFile) {
                $savedControllers = Get-Content $videoControllersFile | ConvertFrom-Json
                $currentControllers = Get-CimInstance -Namespace root\cimv2 -ClassName Win32_VideoController

                foreach ($current in $currentControllers) {
                    $saved = $savedControllers | Where-Object { $_.PNPDeviceID -eq $current.PNPDeviceID }
                    if ($saved) {
                        # Update supported settings
                        $current | Set-CimInstance -Property @{
                            VideoModeDescription = $saved.VideoModeDescription
                            CurrentRefreshRate = $saved.CurrentRefreshRate
                            CurrentBitsPerPixel = $saved.CurrentBitsPerPixel
                            CurrentHorizontalResolution = $saved.CurrentHorizontalResolution
                            CurrentVerticalResolution = $saved.CurrentVerticalResolution
                        }
                    }
                }
            }

            # Restore display configurations
            $displaysFile = "$backupPath\displays.json"
            if (Test-Path $displaysFile) {
                $savedDisplays = Get-Content $displaysFile | ConvertFrom-Json
                $currentDisplays = Get-WmiObject WmiMonitorID -Namespace root\wmi

                foreach ($current in $currentDisplays) {
                    $saved = $savedDisplays | Where-Object { $_.InstanceName -eq $current.InstanceName }
                    if ($saved -and $saved.Settings) {
                        # Apply saved display settings using WMI
                        $settings = Get-WmiObject -Namespace root\wmi -Class WmiMonitorBasicDisplayParams |
                            Where-Object { $_.InstanceName -eq $current.InstanceName }
                        
                        if ($settings) {
                            $settings.MaxHorizontalImageSize = $saved.Settings.MaxHorizontalImageSize
                            $settings.MaxVerticalImageSize = $saved.Settings.MaxVerticalImageSize
                            $settings.Put()
                        }
                    }
                }
            }

            # Restore color profiles
            $colorProfilesPath = Join-Path $backupPath "ColorProfiles"
            if (Test-Path $colorProfilesPath) {
                $systemColorPath = "$env:SystemRoot\System32\spool\drivers\color"
                if (!(Test-Path $systemColorPath)) {
                    New-Item -ItemType Directory -Path $systemColorPath -Force | Out-Null
                }
                
                Copy-Item -Path "$colorProfilesPath\*.icm" -Destination $systemColorPath -Force
                Copy-Item -Path "$colorProfilesPath\*.icc" -Destination $systemColorPath -Force
            }

            # Restart DWM to apply changes
            Get-Process dwm -ErrorAction SilentlyContinue | Stop-Process -Force
            
            Write-Host "Display Settings restored successfully from: $backupPath" -ForegroundColor Green
            return $true
        }
        return $false
    } catch {
        Write-Host "Failed to restore Display Settings: $_" -ForegroundColor Red
        return $false
    }
}

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Restore-DisplaySettings -BackupRootPath $BackupRootPath
} 