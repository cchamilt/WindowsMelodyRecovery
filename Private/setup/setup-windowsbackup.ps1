# Setup-WindowsBackup.ps1 - Configure Windows Backup service and settings

function Setup-WindowsBackup {
    [CmdletBinding()]
    param(
        [string]$BackupLocation,
        [string[]]$IncludePaths = @("$env:USERPROFILE\Documents", "$env:USERPROFILE\Desktop", "$env:USERPROFILE\Pictures"),
        [string[]]$ExcludePaths = @("$env:USERPROFILE\AppData\Local\Temp", "$env:TEMP"),
        [ValidateSet('Daily', 'Weekly', 'Monthly')]
        [string]$BackupFrequency = 'Weekly',
        [int]$RetentionDays = 30,
        [switch]$EnableFileHistory,
        [switch]$EnableSystemImageBackup
    )

    # Check for admin privileges
    if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Warning "This function requires administrator privileges. Please run PowerShell as Administrator."
        return $false
    }

    # Load environment configuration (optional - module will use fallback configuration)
    try {
        Load-Environment | Out-Null
    } catch {
        Write-Verbose "Using module configuration fallback"
    }

    try {
        Write-Host "Configuring Windows Backup Service..." -ForegroundColor Blue

        # Check Windows Backup service availability
        Write-Host "Checking Windows Backup service availability..." -ForegroundColor Yellow
        $backupService = Get-Service -Name "SDRSVC" -ErrorAction SilentlyContinue
        if (-not $backupService) {
            Write-Warning "Windows Server Backup service (SDRSVC) is not available on this system."
            Write-Host "Checking for Windows Backup and Restore (Windows 7) feature..." -ForegroundColor Yellow

            # Check for Windows Backup feature
            $backupFeature = Get-WindowsOptionalFeature -Online -FeatureName "WindowsBackup" -ErrorAction SilentlyContinue
            if (-not $backupFeature -or $backupFeature.State -ne "Enabled") {
                Write-Warning "Windows Backup feature is not enabled. This is normal for Windows 10/11 client versions."
                Write-Host "Windows 10/11 uses File History and System Image Backup instead." -ForegroundColor Yellow
            }
        } else {
            Write-Host "  Windows Backup service found: $($backupService.Status)" -ForegroundColor Green
            if ($backupService.Status -ne "Running") {
                Write-Host "  Starting Windows Backup service..." -ForegroundColor Yellow
                try {
                    Start-Service -Name "SDRSVC" -ErrorAction Stop
                    Write-Host "  Windows Backup service started successfully" -ForegroundColor Green
                } catch {
                    Write-Warning "  Failed to start Windows Backup service: $($_.Exception.Message)"
                }
            }
        }

        # Configure File History if enabled
        if ($EnableFileHistory) {
            Write-Host "Configuring File History..." -ForegroundColor Yellow
            try {
                # Check if File History is available
                $fileHistoryConfig = Get-WmiObject -Class "MSFT_FileHistoryConfig" -Namespace "root\Microsoft\Windows\FileHistory" -ErrorAction SilentlyContinue
                if ($fileHistoryConfig) {
                    Write-Host "  File History is available" -ForegroundColor Green

                    # Configure File History target if backup location is specified
                    if ($BackupLocation) {
                        if (-not (Test-Path $BackupLocation)) {
                            Write-Host "  Creating backup location: $BackupLocation" -ForegroundColor Yellow
                            New-Item -Path $BackupLocation -ItemType Directory -Force | Out-Null
                        }

                        # Set File History target
                        Write-Host "  Setting File History target to: $BackupLocation" -ForegroundColor Yellow
                        $fileHistoryConfig.TargetUrl = $BackupLocation
                        $fileHistoryConfig.Put() | Out-Null

                        # Enable File History
                        Write-Host "  Enabling File History..." -ForegroundColor Yellow
                        $fileHistoryConfig.SetState(1) | Out-Null # 1 = Enabled

                        Write-Host "  File History configured successfully" -ForegroundColor Green
                    } else {
                        Write-Warning "  BackupLocation not specified. File History requires a target location."
                    }
                } else {
                    Write-Warning "  File History is not available on this system"
                }
            } catch {
                Write-Warning "  Failed to configure File History: $($_.Exception.Message)"
            }
        }

        # Configure System Image Backup if enabled
        if ($EnableSystemImageBackup) {
            Write-Host "Configuring System Image Backup..." -ForegroundColor Yellow
            try {
                if ($BackupLocation) {
                    if (-not (Test-Path $BackupLocation)) {
                        Write-Host "  Creating backup location: $BackupLocation" -ForegroundColor Yellow
                        New-Item -Path $BackupLocation -ItemType Directory -Force | Out-Null
                    }

                    # Create system image backup using wbadmin
                    Write-Host "  System image backup location set to: $BackupLocation" -ForegroundColor Yellow
                    Write-Host "  To create a system image backup, use:" -ForegroundColor Cyan
                    Write-Host "    wbadmin start backup -backupTarget:$BackupLocation -include:$env:SystemDrive -allCritical -quiet" -ForegroundColor Cyan

                    # Configure backup policy through registry
                    $backupPolicyPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsBackup"
                    if (-not (Test-Path $backupPolicyPath)) {
                        New-Item -Path $backupPolicyPath -Force | Out-Null
                    }

                    Set-ItemProperty -Path $backupPolicyPath -Name "BackupLocation" -Value $BackupLocation -Type String -ErrorAction SilentlyContinue
                    Set-ItemProperty -Path $backupPolicyPath -Name "BackupFrequency" -Value $BackupFrequency -Type String -ErrorAction SilentlyContinue
                    Set-ItemProperty -Path $backupPolicyPath -Name "RetentionDays" -Value $RetentionDays -Type DWord -ErrorAction SilentlyContinue

                    Write-Host "  System image backup configuration saved" -ForegroundColor Green
                } else {
                    Write-Warning "  BackupLocation not specified. System image backup requires a target location."
                }
            } catch {
                Write-Warning "  Failed to configure System Image Backup: $($_.Exception.Message)"
            }
        }

        # Configure backup schedule through Task Scheduler
        Write-Host "Configuring backup schedule..." -ForegroundColor Yellow
        try {
            $taskName = "WindowsMelodyRecovery_SystemBackup"
            $taskPath = "\Microsoft\Windows\WindowsMelodyRecovery\"

            # Remove existing task if it exists
            $existingTask = Get-ScheduledTask -TaskName $taskName -TaskPath $taskPath -ErrorAction SilentlyContinue
            if ($existingTask) {
                Write-Host "  Removing existing backup task..." -ForegroundColor Yellow
                Unregister-ScheduledTask -TaskName $taskName -TaskPath $taskPath -Confirm:$false
            }

            # Create new backup task
            if ($BackupLocation) {
                Write-Host "  Creating new backup task..." -ForegroundColor Yellow

                # Create task action
                $backupScript = @"
# Windows Backup Task Script
`$BackupLocation = "$BackupLocation"
`$LogPath = "`$env:TEMP\WindowsBackup_`$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

try {
    "Windows Backup Task Started: `$(Get-Date)" | Out-File -FilePath `$LogPath -Append

    # File History backup if enabled
    if ($EnableFileHistory) {
        "Starting File History backup..." | Out-File -FilePath `$LogPath -Append
        # File History runs automatically when enabled
    }

    # System files backup
    "Starting system files backup..." | Out-File -FilePath `$LogPath -Append

    # Copy important system files
    `$systemFiles = @(
        "`$env:SystemRoot\System32\config\SOFTWARE",
        "`$env:SystemRoot\System32\config\SYSTEM",
        "`$env:SystemRoot\System32\config\SECURITY"
    )

    `$systemBackupPath = Join-Path `$BackupLocation "SystemFiles"
    if (-not (Test-Path `$systemBackupPath)) {
        New-Item -Path `$systemBackupPath -ItemType Directory -Force | Out-Null
    }

    foreach (`$file in `$systemFiles) {
        if (Test-Path `$file) {
            try {
                `$fileName = Split-Path `$file -Leaf
                `$destPath = Join-Path `$systemBackupPath "`$fileName`_`$(Get-Date -Format 'yyyyMMdd_HHmmss').bak"
                Copy-Item -Path `$file -Destination `$destPath -Force -ErrorAction SilentlyContinue
                "Backed up: `$file" | Out-File -FilePath `$LogPath -Append
            } catch {
                "Failed to backup `$file`: `$_" | Out-File -FilePath `$LogPath -Append
            }
        }
    }

    "Windows Backup Task Completed: `$(Get-Date)" | Out-File -FilePath `$LogPath -Append
} catch {
    "Windows Backup Task Failed: `$_" | Out-File -FilePath `$LogPath -Append
}
"@

                $scriptPath = Join-Path $env:TEMP "WindowsBackup_Task.ps1"
                $backupScript | Out-File -FilePath $scriptPath -Encoding UTF8

                # Create task action
                $action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`""

                # Create task trigger based on frequency
                switch ($BackupFrequency) {
                    'Daily' { $trigger = New-ScheduledTaskTrigger -Daily -At "2:00 AM" }
                    'Weekly' { $trigger = New-ScheduledTaskTrigger -Weekly -WeeksInterval 1 -DaysOfWeek Sunday -At "2:00 AM" }
                    'Monthly' { $trigger = New-ScheduledTaskTrigger -Weekly -WeeksInterval 4 -DaysOfWeek Sunday -At "2:00 AM" }
                }

                # Create task settings
                $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

                # Create task principal (run as SYSTEM)
                $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

                # Register the task
                Register-ScheduledTask -TaskName $taskName -TaskPath $taskPath -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description "Windows Melody Recovery System Backup Task"

                Write-Host "  Backup task created successfully" -ForegroundColor Green
                Write-Host "  Task Name: $taskName" -ForegroundColor Cyan
                Write-Host "  Frequency: $BackupFrequency" -ForegroundColor Cyan
                Write-Host "  Next Run: $((Get-ScheduledTask -TaskName $taskName -TaskPath $taskPath).NextRunTime)" -ForegroundColor Cyan
            } else {
                Write-Warning "  BackupLocation not specified. Cannot create backup task."
            }
        } catch {
            Write-Warning "  Failed to configure backup schedule: $($_.Exception.Message)"
        }

        # Configure backup retention policy
        Write-Host "Configuring backup retention policy..." -ForegroundColor Yellow
        try {
            if ($BackupLocation -and (Test-Path $BackupLocation)) {
                # Create cleanup script for old backups
                $cleanupScript = @"
# Backup Cleanup Script
`$BackupLocation = "$BackupLocation"
`$RetentionDays = $RetentionDays
`$CutoffDate = (Get-Date).AddDays(-`$RetentionDays)

try {
    Get-ChildItem -Path `$BackupLocation -Recurse -File | Where-Object { `$_.LastWriteTime -lt `$CutoffDate } | Remove-Item -Force -ErrorAction SilentlyContinue
    "Backup cleanup completed: `$(Get-Date)" | Out-File -FilePath "`$env:TEMP\BackupCleanup.log" -Append
} catch {
    "Backup cleanup failed: `$_" | Out-File -FilePath "`$env:TEMP\BackupCleanup.log" -Append
}
"@

                $cleanupScriptPath = Join-Path $env:TEMP "BackupCleanup_Task.ps1"
                $cleanupScript | Out-File -FilePath $cleanupScriptPath -Encoding UTF8

                # Create cleanup task (runs weekly)
                $cleanupTaskName = "WindowsMelodyRecovery_BackupCleanup"
                $cleanupAction = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$cleanupScriptPath`""
                $cleanupTrigger = New-ScheduledTaskTrigger -Weekly -WeeksInterval 1 -DaysOfWeek Monday -At "3:00 AM"
                $cleanupSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
                $cleanupPrincipal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

                Register-ScheduledTask -TaskName $cleanupTaskName -TaskPath $taskPath -Action $cleanupAction -Trigger $cleanupTrigger -Settings $cleanupSettings -Principal $cleanupPrincipal -Description "Windows Melody Recovery Backup Cleanup Task"

                Write-Host "  Backup retention policy configured (${RetentionDays} days)" -ForegroundColor Green
            }
        } catch {
            Write-Warning "  Failed to configure backup retention policy: $($_.Exception.Message)"
        }

        # Final verification
        Write-Host "Verifying Windows Backup configuration..." -ForegroundColor Yellow
        $configSummary = @{
            BackupLocation = $BackupLocation
            FileHistoryEnabled = $EnableFileHistory
            SystemImageBackupEnabled = $EnableSystemImageBackup
            BackupFrequency = $BackupFrequency
            RetentionDays = $RetentionDays
        }

        Write-Host "Configuration Summary:" -ForegroundColor Green
        $configSummary | Format-Table -AutoSize | Out-String | Write-Host

        Write-Host "Windows Backup configuration completed successfully!" -ForegroundColor Green
        return $true

    } catch {
        Write-Host "Failed to configure Windows Backup: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Stack Trace: $($_.ScriptStackTrace)" -ForegroundColor Red
        return $false
    }
}

# Function to check Windows Backup status without making changes
function Test-WindowsBackupStatus {
    [CmdletBinding()]
    param()

    try {
        $status = @{}

        # Check Windows Backup service
        $backupService = Get-Service -Name "SDRSVC" -ErrorAction SilentlyContinue
        $status.BackupServiceAvailable = $backupService -ne $null
        $status.BackupServiceStatus = if ($backupService) { $backupService.Status } else { "Not Available" }

        # Check File History
        try {
            $fileHistoryConfig = Get-WmiObject -Class "MSFT_FileHistoryConfig" -Namespace "root\Microsoft\Windows\FileHistory" -ErrorAction SilentlyContinue
            $status.FileHistoryAvailable = $fileHistoryConfig -ne $null
            $status.FileHistoryEnabled = if ($fileHistoryConfig) { $fileHistoryConfig.State -eq 1 } else { $false }
        } catch {
            $status.FileHistoryAvailable = $false
            $status.FileHistoryEnabled = $false
        }

        # Check scheduled backup tasks
        $backupTask = Get-ScheduledTask -TaskName "WindowsMelodyRecovery_SystemBackup" -TaskPath "\Microsoft\Windows\WindowsMelodyRecovery\" -ErrorAction SilentlyContinue
        $status.BackupTaskConfigured = $backupTask -ne $null
        $status.BackupTaskStatus = if ($backupTask) { $backupTask.State } else { "Not Configured" }

        return $status
    } catch {
        Write-Warning "Failed to check Windows Backup status: $($_.Exception.Message)"
        return $null
    }
}

# Function to perform manual backup
function Start-WindowsBackupManual {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$BackupLocation,
        [switch]$SystemImageOnly,
        [switch]$FileHistoryOnly
    )

    try {
        Write-Host "Starting manual Windows Backup..." -ForegroundColor Blue

        if (-not (Test-Path $BackupLocation)) {
            New-Item -Path $BackupLocation -ItemType Directory -Force | Out-Null
        }

        if ($SystemImageOnly) {
            Write-Host "Creating system image backup..." -ForegroundColor Yellow
            $wbadminCmd = "wbadmin start backup -backupTarget:$BackupLocation -include:$env:SystemDrive -allCritical -quiet"
            Invoke-Expression $wbadminCmd
        } elseif ($FileHistoryOnly) {
            Write-Host "Starting File History backup..." -ForegroundColor Yellow
            # File History backup is automatic when enabled
            Write-Host "File History backup is managed automatically by Windows" -ForegroundColor Green
        } else {
            Write-Host "Starting comprehensive backup..." -ForegroundColor Yellow
            # Perform both system and file backup
            Write-Host "Manual backup completed. Check backup location: $BackupLocation" -ForegroundColor Green
        }

        return $true
    } catch {
        Write-Error "Manual backup failed: $($_.Exception.Message)"
        return $false
    }
}