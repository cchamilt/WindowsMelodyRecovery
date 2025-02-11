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

function Backup-SoundSettings {
    param(
        [Parameter(Mandatory=$true)]
        [string]$BackupRootPath
    )
    
    try {
        Write-Host "Backing up Sound Settings..." -ForegroundColor Blue
        $backupPath = Initialize-BackupDirectory -Path "Sound" -BackupType "Sound Settings" -BackupRootPath $BackupRootPath
        
        if ($backupPath) {
            # Export sound registry settings
            $regPaths = @(
                # Windows Audio settings
                "HKCU\Software\Microsoft\Multimedia\Audio",
                "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio",
                "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Drivers32",
                "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows",
                
                # Sound scheme and events
                "HKCU\AppEvents\Schemes",
                "HKCU\AppEvents\EventLabels",
                
                # Communication settings
                "HKCU\Software\Microsoft\Multimedia\Audio\DeviceCpl",
                
                # Spatial sound and enhancements
                "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Audio",
                "HKCU\Software\Microsoft\Windows\CurrentVersion\Audio"
            )

            foreach ($regPath in $regPaths) {
                $regFile = "$backupPath\$($regPath.Split('\')[-1]).reg"
                reg export $regPath $regFile /y 2>$null
            }

            # Export audio devices using WMI
            $audioDevices = Get-WmiObject Win32_SoundDevice | Select-Object -Property *
            $audioDevices | ConvertTo-Json -Depth 10 | Out-File "$backupPath\audio_devices.json" -Force

            # Export default devices and their states
            $defaultDevices = @{
                Playback = Get-AudioDevice -Playback
                Recording = Get-AudioDevice -Recording
                DefaultPlayback = Get-AudioDevice -Playback -Default
                DefaultRecording = Get-AudioDevice -Recording -Default
            }
            $defaultDevices | ConvertTo-Json -Depth 10 | Out-File "$backupPath\default_devices.json" -Force

            # Backup sound scheme files
            $schemePath = "$env:SystemRoot\Media"
            if (Test-Path $schemePath) {
                $schemeBackupPath = Join-Path $backupPath "SoundSchemes"
                New-Item -ItemType Directory -Path $schemeBackupPath -Force | Out-Null
                Copy-Item -Path "$schemePath\*.wav" -Destination $schemeBackupPath -Force
            }

            # Export per-app volume settings
            $appVolume = Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers" -ErrorAction SilentlyContinue
            if ($appVolume) {
                $appVolume | ConvertTo-Json | Out-File "$backupPath\app_volume.json" -Force
            }
            
            Write-Host "Sound Settings backed up successfully to: $backupPath" -ForegroundColor Green
            return $true
        }
        return $false
    } catch {
        Write-Host "Failed to backup Sound Settings: $_" -ForegroundColor Red
        return $false
    }
}

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Backup-SoundSettings -BackupRootPath $BackupRootPath
} 