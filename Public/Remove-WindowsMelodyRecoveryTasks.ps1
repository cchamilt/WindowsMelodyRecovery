# Requires admin privileges
function Remove-WindowsMelodyRecoveryTask {
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

    # Define tasks to remove
    $tasks = @(
        "WindowsMelodyRecovery-Backup",
        "WindowsMelodyRecovery-Update"
    )

    # Prompt for confirmation
    if (!$NoPrompt) {
        Write-Warning -Message "`nThe following scheduled tasks will be removed:"
        foreach ($task in $tasks) {
            Write-Information -MessageData "  - $task" -InformationAction Continue
        }

        $response = Read-Host "`nDo you want to remove these scheduled tasks? (Y/N)"
        if ($response -ne "Y" -and $response -ne "y") {
            Write-Warning -Message "Task removal cancelled."
            return
        }
    }

    # Remove scheduled tasks
    $taskPath = "\WindowsMelodyRecovery\"
    $removedCount = 0

    foreach ($taskName in $tasks) {
        try {
            $existingTask = Get-ScheduledTask -TaskName $taskName -TaskPath $taskPath -ErrorAction SilentlyContinue
            if ($existingTask) {
                Unregister-ScheduledTask -TaskName $taskName -TaskPath $taskPath -Confirm:$false
                Write-Information -MessageData "Removed scheduled task: $taskName" -InformationAction Continue
                $removedCount++
            }
 else {
                Write-Warning -Message "Task '$taskName' not found, skipping..."
            }
        }
 catch {
            Write-Warning "Failed to remove scheduled task '$taskName': $_"
        }
    }

    Write-Information -MessageData "`nScheduled tasks removal completed. Removed $removedCount tasks." -InformationAction Continue
}

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    Remove-WindowsMelodyRecoveryTasks @PSBoundParameters
}








