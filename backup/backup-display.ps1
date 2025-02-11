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

function Backup-DisplaySettings {
    param(
        [Parameter(Mandatory=$true)]
        [string]$BackupRootPath
    )
    
    try {
        Write-Host "Backing up Display Settings..." -ForegroundColor Blue
        $backupPath = Initialize-BackupDirectory -Path "Display" -BackupType "Display Settings" -BackupRootPath $BackupRootPath
        
        if ($backupPath) {
            # Export display registry settings
            $regPaths = @(
                # Display settings
                "HKCU\Control Panel\Desktop",
                "HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers",
                "HKLM\SYSTEM\CurrentControlSet\Control\Video",
                "HKLM\SYSTEM\CurrentControlSet\Hardware Profiles\Current\System\CurrentControlSet\Control\Video",
                
                # Visual Effects and DWM
                "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects",
                "HKCU\Software\Microsoft\Windows\DWM",
                
                # Color calibration
                "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ICM",
                "HKCU\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ICM",
                
                # DPI settings
                "HKCU\Control Panel\Desktop\WindowMetrics",
                "HKCU\Software\Microsoft\Windows\CurrentVersion\ThemeManager",
                
                # HDR and advanced color
                "HKCU\Software\Microsoft\Windows\CurrentVersion\VideoSettings",
                "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\HDR"
            )

            foreach ($regPath in $regPaths) {
                $regFile = "$backupPath\$($regPath.Split('\')[-1]).reg"
                reg export $regPath $regFile /y 2>$null
            }

            # Export Win32_VideoController configuration
            $videoControllers = Get-CimInstance -Namespace root\cimv2 -ClassName Win32_VideoController | Select-Object -Property *
            $videoControllers | ConvertTo-Json -Depth 10 | Out-File "$backupPath\video_controllers.json" -Force

            # Get display configuration using WMI
            $displays = Get-WmiObject WmiMonitorID -Namespace root\wmi | ForEach-Object {
                @{
                    InstanceName = $_.InstanceName
                    ManufacturerName = [System.Text.Encoding]::ASCII.GetString($_.ManufacturerName).Trim("`0")
                    ProductCodeID = [System.Text.Encoding]::ASCII.GetString($_.ProductCodeID).Trim("`0")
                    SerialNumberID = [System.Text.Encoding]::ASCII.GetString($_.SerialNumberID).Trim("`0")
                    UserFriendlyName = [System.Text.Encoding]::ASCII.GetString($_.UserFriendlyName).Trim("`0")
                    Settings = Get-WmiObject -Namespace root\wmi -Class WmiMonitorBasicDisplayParams | Where-Object { $_.InstanceName -eq $_.InstanceName }
                }
            }
            $displays | ConvertTo-Json -Depth 10 | Out-File "$backupPath\displays.json" -Force

            # Export CCD profiles
            $ccdPath = "$env:SystemRoot\System32\spool\drivers\color"
            if (Test-Path $ccdPath) {
                $ccdBackupPath = Join-Path $backupPath "ColorProfiles"
                New-Item -ItemType Directory -Path $ccdBackupPath -Force | Out-Null
                Copy-Item -Path "$ccdPath\*.icm" -Destination $ccdBackupPath -Force
                Copy-Item -Path "$ccdPath\*.icc" -Destination $ccdBackupPath -Force
            }
            
            Write-Host "Display Settings backed up successfully to: $backupPath" -ForegroundColor Green
            return $true
        }
        return $false
    } catch {
        Write-Host "Failed to backup Display Settings: $_" -ForegroundColor Red
        return $false
    }
}

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Backup-DisplaySettings -BackupRootPath $BackupRootPath
} 