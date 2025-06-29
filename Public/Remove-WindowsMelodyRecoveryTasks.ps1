# Requires admin privileges
function Remove-WindowsMelodyRecoveryTasks {
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

    # Define tasks to remove
    $tasks = @(
        "WindowsMelodyRecovery-Backup",
        "WindowsMelodyRecovery-Update"
    )

    # Prompt for confirmation
    if (!$NoPrompt) {
        Write-Host "`nThe following scheduled tasks will be removed:" -ForegroundColor Yellow
        foreach ($task in $tasks) {
            Write-Host "  - $task" -ForegroundColor Cyan
        }

        $response = Read-Host "`nDo you want to remove these scheduled tasks? (Y/N)"
        if ($response -ne "Y" -and $response -ne "y") {
            Write-Host "Task removal cancelled." -ForegroundColor Yellow
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
                Write-Host "Removed scheduled task: $taskName" -ForegroundColor Green
                $removedCount++
            } else {
                Write-Host "Task '$taskName' not found, skipping..." -ForegroundColor Yellow
            }
        } catch {
            Write-Warning "Failed to remove scheduled task '$taskName': $_"
        }
    }

    Write-Host "`nScheduled tasks removal completed. Removed $removedCount tasks." -ForegroundColor Green
}

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    Remove-WindowsMelodyRecoveryTasks @PSBoundParameters
}
