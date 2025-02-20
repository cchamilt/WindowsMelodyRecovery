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
            # Display config locations
            $displayConfigs = @{
                # Display adapter settings
                "Adapters" = "HKLM:\SYSTEM\CurrentControlSet\Control\Video"
                # Display monitor settings
                "Monitors" = "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\Configuration"
                # Display color settings
                "ColorCalibration" = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ICM\Calibration"
                # Display DPI settings
                "DPI" = "HKCU:\Control Panel\Desktop"
                # Display HDR settings
                "HDR" = "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\FeatureSettings"
                # Display scaling settings
                "Scaling" = "HKCU:\Control Panel\Desktop\WindowMetrics"
                # Display refresh rate settings
                "RefreshRate" = "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\Configuration"
                # Display orientation settings
                "Orientation" = "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\Rotation"
            }

            # Restore display settings
            Write-Host "Checking display components..." -ForegroundColor Yellow
            $displayServices = @(
                "DispBrokerDesktopSvc", # Display Enhancement Service
                "ICSSvc"                # Windows Mobile Hotspot Service
            )
            
            foreach ($service in $displayServices) {
                if ((Get-Service -Name $service -ErrorAction SilentlyContinue).Status -ne "Running") {
                    Start-Service -Name $service
                }
            }

            # Restore registry settings
            foreach ($config in $displayConfigs.GetEnumerator()) {
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

            # Restore display configurations
            $displayConfigFile = Join-Path $backupPath "display_config.json"
            if (Test-Path $displayConfigFile) {
                $displayConfig = Get-Content $displayConfigFile | ConvertFrom-Json
                
                # Apply display settings
                foreach ($display in $displayConfig.Displays) {
                    # Set display resolution
                    if ($display.Resolution) {
                        Set-DisplayResolution -Width $display.Resolution.Width `
                            -Height $display.Resolution.Height `
                            -Force
                    }
                    
                    # Set refresh rate
                    if ($display.RefreshRate) {
                        Set-DisplayRefreshRate -Frequency $display.RefreshRate -Force
                    }
                    
                    # Set scaling
                    if ($display.Scaling) {
                        Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" `
                            -Name "LogPixels" -Value $display.Scaling
                    }
                }
            }

            # Notify display settings change
            $signature = @"
                [DllImport("user32.dll")]
                public static extern int SendMessageTimeout(
                    IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam,
                    uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
"@
            $type = Add-Type -MemberDefinition $signature -Name WinAPI -Namespace Win32Functions -PassThru
            [IntPtr]$HWND_BROADCAST = [IntPtr]0xffff
            $WM_SETTINGCHANGE = 0x1a
            $result = [UIntPtr]::Zero
            $type::SendMessageTimeout($HWND_BROADCAST, $WM_SETTINGCHANGE, [UIntPtr]::Zero, "Policy", 2, 5000, [ref]$result) | Out-Null

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
            Write-Host "`nNote: Some settings may require a system restart to take effect" -ForegroundColor Yellow
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