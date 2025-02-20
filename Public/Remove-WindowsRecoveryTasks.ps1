# Requires admin privileges
#Requires -RunAsAdministrator

function Remove-WindowsRecoveryTasks {
    [CmdletBinding()]
    param(
        [switch]$Force
    )

    # Task names
    $backupTaskName = "WindowsRecovery_Backup"
    $updateTaskName = "WindowsRecovery_Update"
    $taskPath = "\Custom Tasks"

    try {
        # Remove backup task
        $backupTask = Get-ScheduledTask -TaskName $backupTaskName -TaskPath $taskPath -ErrorAction SilentlyContinue
        if ($backupTask) {
            if ($Force -or (Read-Host "Remove backup task '$backupTaskName'? (Y/N)") -eq 'Y') {
                Unregister-ScheduledTask -TaskName $backupTaskName -TaskPath $taskPath -Confirm:$false
                Write-Host "Removed backup task: $backupTaskName" -ForegroundColor Green
            }
        } else {
            Write-Host "Backup task not found: $backupTaskName" -ForegroundColor Yellow
        }

        # Remove update task
        $updateTask = Get-ScheduledTask -TaskName $updateTaskName -TaskPath $taskPath -ErrorAction SilentlyContinue
        if ($updateTask) {
            if ($Force -or (Read-Host "Remove update task '$updateTaskName'? (Y/N)") -eq 'Y') {
                Unregister-ScheduledTask -TaskName $updateTaskName -TaskPath $taskPath -Confirm:$false
                Write-Host "Removed update task: $updateTaskName" -ForegroundColor Green
            }
        } else {
            Write-Host "Update task not found: $updateTaskName" -ForegroundColor Yellow
        }

        # Remove task path if empty
        $tasks = Get-ScheduledTask -TaskPath $taskPath -ErrorAction SilentlyContinue
        if ($tasks.Count -eq 0) {
            schtasks /DELETE /TN $taskPath /F | Out-Null
            Write-Host "Removed empty task path: $taskPath" -ForegroundColor Green
        }

        return $true
    } catch {
        Write-Host "Failed to remove tasks: $_" -ForegroundColor Red
        return $false
    }
}

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    Remove-WindowsRecoveryTasks @PSBoundParameters
}
