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

function Restore-SystemSettings {
    param(
        [Parameter(Mandatory=$true)]
        [string]$BackupRootPath
    )
    
    try {
        Write-Host "Restoring System Settings..." -ForegroundColor Blue
        $backupPath = Test-BackupPath -Path "SystemSettings" -BackupType "System Settings"
        
        if ($backupPath) {
            # System config locations
            $systemConfigs = @{
                # System environment variables
                "Environment" = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment"
                # User environment variables
                "UserEnvironment" = "HKCU:\Environment"
                # System performance settings
                "Performance" = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects"
                # Power settings
                "Power" = "HKLM:\SYSTEM\CurrentControlSet\Control\Power"
                # Time and region settings
                "TimeZone" = "HKLM:\SYSTEM\CurrentControlSet\Control\TimeZoneInformation"
                # System restore settings
                "SystemRestore" = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore"
                # Page file settings
                "PageFile" = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"
                # Remote settings
                "Remote" = "HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance"
                # Security settings
                "Security" = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
                # Printer settings
                "Printers" = "HKLM:\SYSTEM\CurrentControlSet\Control\Print\Printers"
            }

            # Restore system settings
            Write-Host "Checking system components..." -ForegroundColor Yellow
            $systemServices = @(
                "Schedule", "Power", "PlugPlay", "SystemRestore",
                "Spooler", "RemoteRegistry"
            )
            
            foreach ($service in $systemServices) {
                if ((Get-Service -Name $service -ErrorAction SilentlyContinue).Status -ne "Running") {
                    Start-Service -Name $service
                }
            }

            # Restore registry settings
            foreach ($config in $systemConfigs.GetEnumerator()) {
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

            # Restore scheduled tasks
            $tasksFile = Join-Path $backupPath "scheduled_tasks.xml"
            if (Test-Path $tasksFile) {
                Write-Host "Restoring scheduled tasks..." -ForegroundColor Yellow
                Register-ScheduledTask -Xml (Get-Content $tasksFile | Out-String) -TaskName "Restored_Task" -Force
            }

            # Restore mapped drives
            $drivesFile = Join-Path $backupPath "mapped_drives.xml"
            if (Test-Path $drivesFile) {
                Write-Host "Restoring mapped drives..." -ForegroundColor Yellow
                Import-Clixml $drivesFile | ForEach-Object {
                    New-PSDrive -Name $_.Name -PSProvider FileSystem -Root $_.Root -Persist -Scope Global
                }
            }

            # Restore system restore points
            $restorePointsFile = Join-Path $backupPath "restore_points.xml"
            if (Test-Path $restorePointsFile) {
                Write-Host "Restoring system restore points..." -ForegroundColor Yellow
                Import-Clixml $restorePointsFile | ForEach-Object {
                    Checkpoint-Computer -Description $_.Description -RestorePointType $_.Type
                }
            }

            Write-Host "System Settings restored successfully from: $backupPath" -ForegroundColor Green
            Write-Host "`nNote: Some settings may require a system restart to take effect" -ForegroundColor Yellow
            return $true
        }
        return $false
    } catch {
        Write-Host "Failed to restore System Settings: $_" -ForegroundColor Red
        return $false
    }
}

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Restore-SystemSettings -BackupRootPath $BackupRootPath
} 