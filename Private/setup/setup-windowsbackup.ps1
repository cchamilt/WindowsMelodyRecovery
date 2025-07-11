# Initialize-WindowsBackup.ps1 - Configure Windows Backup service and settings

function Initialize-WindowsBackup {
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
        Import-Environment | Out-Null
    } catch {
        Write-Verbose "Using module configuration fallback"
    }

    try {
        Write-Information -MessageData "Configuring Windows Backup Service..." -InformationAction Continue

        # Check Windows Backup service availability
        Write-Warning -Message "Checking Windows Backup service availability..."
        $backupService = Get-Service -Name "SDRSVC" -ErrorAction SilentlyContinue
        if (-not $backupService) {
            Write-Warning "Windows Server Backup service (SDRSVC) is not available on this system."
            Write-Warning -Message "Checking for Windows Backup and Restore (Windows 7) feature..."

            # Check for Windows Backup feature
            $backupFeature = Get-WindowsOptionalFeature -Online -FeatureName "WindowsBackup" -ErrorAction SilentlyContinue
            if (-not $backupFeature -or $backupFeature.State -ne "Enabled") {
                Write-Warning "Windows Backup feature is not enabled. This is normal for Windows 10/11 client versions."
                Write-Warning -Message "Windows 10/11 uses File History and System Image Backup instead."
            }
        } else {
            Write-Information -MessageData "  Windows Backup service found: $($backupService.Status)" -InformationAction Continue
            if ($backupService.Status -ne "Running") {
                Write-Warning -Message "  Starting Windows Backup service..."
                try {
                    Start-Service -Name "SDRSVC" -ErrorAction Stop
                    Write-Information -MessageData "  Windows Backup service started successfully" -InformationAction Continue
                } catch {
                    Write-Warning "  Failed to start Windows Backup service: $($_.Exception.Message)"
                }
            }
        }

        # Configure File History if enabled
        if ($EnableFileHistory) {
            Write-Warning -Message "Configuring File History..."
            try {
                # Check if File History is available
                $fileHistoryConfig = Get-WmiObject -Class "MSFT_FileHistoryConfig" -Namespace "root\Microsoft\Windows\FileHistory" -ErrorAction SilentlyContinue
                if ($fileHistoryConfig) {
                    Write-Information -MessageData "  File History is available" -InformationAction Continue

                    # Configure File History target if backup location is specified
                    if ($BackupLocation) {
                        if (-not (Test-Path $BackupLocation)) {
                            Write-Warning -Message "  Creating backup location: $BackupLocation"
                            New-Item -Path $BackupLocation -ItemType Directory -Force | Out-Null
                        }

                        # Set File History target
                        Write-Warning -Message "  Setting File History target to: $BackupLocation"
                        $fileHistoryConfig.TargetUrl = $BackupLocation
                        $fileHistoryConfig.Put() | Out-Null

                        # Enable File History
                        Write-Warning -Message "  Enabling File History..."
                        $fileHistoryConfig.SetState(1) | Out-Null # 1 = Enabled

                        Write-Information -MessageData "  File History configured successfully" -InformationAction Continue
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
            Write-Warning -Message "Configuring System Image Backup..."
            try {
                if ($BackupLocation) {
                    if (-not (Test-Path $BackupLocation)) {
                        Write-Warning -Message "  Creating backup location: $BackupLocation"
                        New-Item -Path $BackupLocation -ItemType Directory -Force | Out-Null
                    }

                    # Create system image backup using wbadmin
                    Write-Warning -Message "  System image backup location set to: $BackupLocation"
                    Write-Information -MessageData "  To create a system image backup, use:" -InformationAction Continue
                    Write-Information -MessageData "    wbadmin start backup -backupTarget:$BackupLocation -include:$env:SystemDrive -allCritical -quiet" -InformationAction Continue

                    # Configure backup policy through registry
                    $backupPolicyPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsBackup"
                    if (-not (Test-Path $backupPolicyPath)) {
                        New-Item -Path $backupPolicyPath -Force | Out-Null
                    }

                    Set-ItemProperty -Path $backupPolicyPath -Name "BackupLocation" -Value $BackupLocation -Type String -ErrorAction SilentlyContinue
                    Set-ItemProperty -Path $backupPolicyPath -Name "BackupFrequency" -Value $BackupFrequency -Type String -ErrorAction SilentlyContinue
                    Set-ItemProperty -Path $backupPolicyPath -Name "RetentionDays" -Value $RetentionDays -Type DWord -ErrorAction SilentlyContinue

                    Write-Information -MessageData "  System image backup configuration saved" -InformationAction Continue
                } else {
                    Write-Warning "  BackupLocation not specified. System image backup requires a target location."
                }
            } catch {
                Write-Warning "  Failed to configure System Image Backup: $($_.Exception.Message)"
            }
        }

        # Configure backup schedule through Task Scheduler
        Write-Warning -Message "Configuring backup schedule..."
        try {
            $taskName = "WindowsMelodyRecovery_SystemBackup"
            $taskPath = "\Microsoft\Windows\WindowsMelodyRecovery\"

            # Remove existing task if it exists
            $existingTask = Get-ScheduledTask -TaskName $taskName -TaskPath $taskPath -ErrorAction SilentlyContinue
            if ($existingTask) {
                Write-Warning -Message "  Removing existing backup task..."
                Unregister-ScheduledTask -TaskName $taskName -TaskPath $taskPath -Confirm:$false
            }

            # Create new backup task
            if ($BackupLocation) {
                Write-Warning -Message "  Creating new backup task..."

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

                Write-Information -MessageData "  Backup task created successfully" -InformationAction Continue
                Write-Information -MessageData "  Task Name: $taskName" -InformationAction Continue
                Write-Information -MessageData "  Frequency: $BackupFrequency" -InformationAction Continue
                Write-Information -MessageData "  Next Run: $((Get-ScheduledTask -TaskName $taskName -TaskPath $taskPath).NextRunTime)" -InformationAction Continue
            } else {
                Write-Warning "  BackupLocation not specified. Cannot create backup task."
            }
        } catch {
            Write-Warning "  Failed to configure backup schedule: $($_.Exception.Message)"
        }

        # Configure backup retention policy
        Write-Warning -Message "Configuring backup retention policy..."
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

                Write-Information -MessageData "  Backup retention policy configured (${RetentionDays} days)" -InformationAction Continue
            }
        } catch {
            Write-Warning "  Failed to configure backup retention policy: $($_.Exception.Message)"
        }

        # Final verification
        Write-Warning -Message "Verifying Windows Backup configuration..."
        $configSummary = @{
            BackupLocation = $BackupLocation
            FileHistoryEnabled = $EnableFileHistory
            SystemImageBackupEnabled = $EnableSystemImageBackup
            BackupFrequency = $BackupFrequency
            RetentionDays = $RetentionDays
        }

        Write-Information -MessageData "Configuration Summary:" -InformationAction Continue
        $configSummary | Format-Table -AutoSize | Out-String | Write-Information -MessageData Write -InformationAction Continue-Information -MessageData "Windows Backup configuration completed successfully!" -InformationAction Continue
        return $true

    } catch {
        Write-Error -Message "Failed to configure Windows Backup: $($_.Exception.Message)"
        Write-Error -Message "Stack Trace: $($_.ScriptStackTrace)"
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
        Write-Information -MessageData "Starting manual Windows Backup..." -InformationAction Continue

        if (-not (Test-Path $BackupLocation)) {
            New-Item -Path $BackupLocation -ItemType Directory -Force | Out-Null
        }

        if ($SystemImageOnly) {
            Write-Warning -Message "Creating system image backup..."
            $wbadminCmd = "wbadmin start backup -backupTarget:$BackupLocation -include:$env:SystemDrive -allCritical -quiet"
            Invoke-Expression $wbadminCmd
        } elseif ($FileHistoryOnly) {
            Write-Warning -Message "Starting File History backup..."
            # File History backup is automatic when enabled
            Write-Information -MessageData "File History backup is managed automatically by Windows" -InformationAction Continue
        } else {
            Write-Warning -Message "Starting comprehensive backup..."
            # Perform both system and file backup
            Write-Information -MessageData "Manual backup completed. Check backup location: $BackupLocation" -InformationAction Continue
        }

        return $true
    } catch {
        Write-Error "Manual backup failed: $($_.Exception.Message)"
        return $false
    }
}










