function Install-WindowsMelodyRecoveryTasks {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
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
    }
    catch {
        Write-Warning "Could not verify administrator privileges: $_"
        return $false
    }

    # Get module configuration
    $config = Get-WindowsMelodyRecovery
    if (-not $config.BackupRoot) {
        throw "Module not initialized. Please run Initialize-WindowsMelodyRecovery first."
    }

    # Load task scripts on demand
    Import-PrivateScript -Category 'tasks'

    # Define scheduled tasks
    $tasks = @(
        @{
            Name        = "WindowsMelodyRecovery-Backup"
            Description = "Daily backup of Windows configuration"
            Action      = "powershell.exe"
            Arguments   = "-NoProfile -Command `"Backup-WindowsMelodyRecovery`""
            Trigger     = "Daily"
            StartTime   = "02:00"
        },
        @{
            Name        = "WindowsMelodyRecovery-Update"
            Description = "Weekly update of Windows configuration"
            Action      = "powershell.exe"
            Arguments   = "-NoProfile -Command `"Update-WindowsMelodyRecovery`""
            Trigger     = "Weekly"
            DaysOfWeek  = "Sunday"
            StartTime   = "03:00"
        }
    )

    # Prompt for confirmation
    if (!$NoPrompt) {
        Write-Warning -Message "`nThe following scheduled tasks will be created:"
        foreach ($task in $tasks) {
            Write-Information -MessageData "`nTask: $($task.Name)" -InformationAction Continue
            Write-Information -MessageData "Description: $($task.Description)" -InformationAction Continue
            Write-Information -MessageData "Schedule: $($task.Trigger) at $($task.StartTime)" -InformationAction Continue
            if ($task.DaysOfWeek) {
                Write-Information -MessageData "Days: $($task.DaysOfWeek)" -InformationAction Continue
            }
        }

        $response = Read-Host "`nDo you want to create these scheduled tasks? (Y/N)"
        if ($response -ne "Y" -and $response -ne "y") {
            Write-Warning -Message "Task creation cancelled."
            return
        }
    }

    # Create scheduled tasks
    foreach ($task in $tasks) {
        $taskName = $task.Name
        $taskPath = "\WindowsMelodyRecovery\"

        # Check if task already exists
        $existingTask = Get-ScheduledTask -TaskName $taskName -TaskPath $taskPath -ErrorAction SilentlyContinue
        if ($existingTask) {
            if (!$NoPrompt) {
                $response = Read-Host "Task '$taskName' already exists. Replace it? (Y/N)"
                if ($response -ne "Y" -and $response -ne "y") {
                    Write-Warning -Message "Skipping task '$taskName'"
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
            Write-Information -MessageData "Created scheduled task: $taskName" -InformationAction Continue
        }
        catch {
            Write-Warning "Failed to create scheduled task '$taskName': $_"
        }
    }

    Write-Information -MessageData "`nScheduled tasks installation completed." -InformationAction Continue
}







