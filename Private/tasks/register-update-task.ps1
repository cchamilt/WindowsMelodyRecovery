function Register-WmrUpdateTask {
    # Requires admin privileges
    #Requires -RunAsAdministrator

    try {
        Import-Module WindowsMelodyRecovery -ErrorAction Stop

        Write-Information -MessageData "Registering system update task..." -InformationAction Continue

        # Use environment variable for update script path
        $updateScript = Join-Path $env:WINDOWS_CONFIG_PATH "Update-WindowsMelodyRecovery.ps1"

        # Verify update script exists
        if (!(Test-Path $updateScript)) {
            throw "Update script not found at: $updateScript"
        }

        # Task configuration
        $taskName = "System Auto Update"
        $taskDescription = "Monthly system update for packages, modules, and applications"
        $taskPath = "\Custom Tasks"

        # Create the task action to run PowerShell with the update script
        $action = New-ScheduledTaskAction -Execute "powershell.exe" `
            -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$updateScript`"" `
            -WorkingDirectory $env:WINDOWS_CONFIG_PATH

        # Create monthly trigger (run at 3 AM on the first day of each month)
        $trigger = New-ScheduledTaskTrigger `
            -Weekly `
            -WeeksInterval 4 `
            -DaysOfWeek Monday `
            -At 3am

        # Task settings
        $settings = New-ScheduledTaskSettingsSet `
            -AllowStartIfOnBatteries `
            -DontStopIfGoingOnBatteries `
            -StartWhenAvailable `
            -RunOnlyIfNetworkAvailable `
            -WakeToRun `
            -DontStopOnIdleEnd `
            -RestartInterval (New-TimeSpan -Minutes 1) `
            -RestartCount 3

        # Get the current user for task principal
        $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

        # Create principal with highest privileges
        $principal = New-ScheduledTaskPrincipal `
            -UserId $currentUser `
            -LogonType S4U `
            -RunLevel Highest

        # Remove existing task if it exists
        Get-ScheduledTask -TaskName $taskName -TaskPath $taskPath -ErrorAction SilentlyContinue |
            Unregister-ScheduledTask -Confirm:$false

        # Register the new task
        $task = Register-ScheduledTask `
            -TaskName $taskName `
            -TaskPath $taskPath `
            -Action $action `
            -Trigger $trigger `
            -Settings $settings `
            -Principal $principal `
            -Description $taskDescription `
            -Force

        # Verify task was created
        if ($task) {
            Write-Information -MessageData "System update task registered successfully!" -InformationAction Continue
            Write-Warning -Message "Task Details:"
            Write-Information -MessageData "  Name: $taskName" -InformationAction Continue
            Write-Information -MessageData "  Path: $taskPath" -InformationAction Continue
            Write-Information -MessageData "  Script: $updateScript" -InformationAction Continue
            Write-Information -MessageData "  Schedule: Monthly at 3 AM on the 1st" -InformationAction Continue
            Write-Information -MessageData "  User: $currentUser" -InformationAction Continue
        }
        else {
            throw "Failed to register task"
        }

    }
    catch {
        Write-Error -Message "Failed to register system update task: $_"
        exit 1
    }

    # Offer to run the update now
    Write-Warning -Message "`nWould you like to run the system update now? (Y/N)"
    $response = Read-Host
    if ($response -eq "Y" -or $response -eq "y") {
        try {
            Write-Information -MessageData "Running system update..." -InformationAction Continue
            & $updateScript
        }
        catch {
            Write-Error -Message "Failed to run system update: $_"
        }
    }
}

Export-ModuleMember -Function 'Register-WmrUpdateTask'








