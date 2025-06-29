function Install-WindowsMissingRecoveryTasks {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [switch]$NoPrompt
    )

    # Check if we're on Windows platform
    if ($PSVersionTable.Platform -ne "Win32NT" -and $PSVersionTable.OS -notlike "*Windows*") {
        Write-Warning "Scheduled tasks are only supported on Windows. Current platform: $($PSVersionTable.Platform), OS: $($PSVersionTable.OS)"
        return $false
    }

    # Verify running as admin (Windows-specific check)
    try {
        if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            Write-Warning "This function requires elevation. Please run PowerShell as Administrator."
            return $false
        }
    } catch {
        Write-Warning "Could not verify administrator privileges: $_"
        return $false
    }

    # Get module configuration
    $config = Get-WindowsMissingRecovery
    if (-not $config.BackupRoot) {
        throw "Module not initialized. Please run Initialize-WindowsMissingRecovery first."
    }

    # Load task scripts on demand
    Import-PrivateScripts -Category 'tasks'

    # Define scheduled tasks
    $tasks = @(
        @{
            Name = "WindowsMissingRecovery-Backup"
            Description = "Daily backup of Windows configuration"
            Action = "powershell.exe"
            Arguments = "-NoProfile -Command `"Backup-WindowsMissingRecovery`""
            Trigger = "Daily"
            StartTime = "02:00"
        },
        @{
            Name = "WindowsMissingRecovery-Update"
            Description = "Weekly update of Windows configuration"
            Action = "powershell.exe"
            Arguments = "-NoProfile -Command `"Update-WindowsMissingRecovery`""
            Trigger = "Weekly"
            DaysOfWeek = "Sunday"
            StartTime = "03:00"
        }
    )

    # Prompt for confirmation
    if (!$NoPrompt) {
        Write-Host "`nThe following scheduled tasks will be created:" -ForegroundColor Yellow
        foreach ($task in $tasks) {
            Write-Host "`nTask: $($task.Name)" -ForegroundColor Cyan
            Write-Host "Description: $($task.Description)" -ForegroundColor Cyan
            Write-Host "Schedule: $($task.Trigger) at $($task.StartTime)" -ForegroundColor Cyan
            if ($task.DaysOfWeek) {
                Write-Host "Days: $($task.DaysOfWeek)" -ForegroundColor Cyan
            }
        }

        $response = Read-Host "`nDo you want to create these scheduled tasks? (Y/N)"
        if ($response -ne "Y" -and $response -ne "y") {
            Write-Host "Task creation cancelled." -ForegroundColor Yellow
            return
        }
    }

    # Create scheduled tasks
    foreach ($task in $tasks) {
        $taskName = $task.Name
        $taskPath = "\WindowsMissingRecovery\"

        # Check if task already exists
        $existingTask = Get-ScheduledTask -TaskName $taskName -TaskPath $taskPath -ErrorAction SilentlyContinue
        if ($existingTask) {
            if (!$NoPrompt) {
                $response = Read-Host "Task '$taskName' already exists. Replace it? (Y/N)"
                if ($response -ne "Y" -and $response -ne "y") {
                    Write-Host "Skipping task '$taskName'" -ForegroundColor Yellow
                    continue
                }
            }
            Unregister-ScheduledTask -TaskName $taskName -TaskPath $taskPath -Confirm:$false
        }

        # Create task action
        $action = New-ScheduledTaskAction -Execute $task.Action -Argument $task.Arguments

        # Create task trigger
        $trigger = switch ($task.Trigger) {
            "Daily" { 
                New-ScheduledTaskTrigger -Daily -At $task.StartTime 
            }
            "Weekly" { 
                New-ScheduledTaskTrigger -Weekly -DaysOfWeek $task.DaysOfWeek -At $task.StartTime 
            }
            default { 
                throw "Unsupported trigger type: $($task.Trigger)" 
            }
        }

        # Create task settings
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

        # Create task principal
        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

        # Register the task
        try {
            Register-ScheduledTask -TaskName $taskName -TaskPath $taskPath -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description $task.Description -Force
            Write-Host "Created scheduled task: $taskName" -ForegroundColor Green
        } catch {
            Write-Warning "Failed to create scheduled task '$taskName': $_"
        }
    }

    Write-Host "`nScheduled tasks installation completed." -ForegroundColor Green
}