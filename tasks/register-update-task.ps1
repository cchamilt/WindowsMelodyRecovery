# Requires admin privileges
#Requires -RunAsAdministrator

try {
    # At the start after admin check
    $scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
    . (Join-Path (Split-Path $scriptPath -Parent) "scripts\load-environment.ps1")

    if (!(Load-Environment)) {
        Write-Host "Failed to load environment configuration" -ForegroundColor Red
        exit 1
    }

    Write-Host "Registering system update task..." -ForegroundColor Blue

    # Use environment variable for update script path
    $updateScript = Join-Path $env:WINDOWS_CONFIG_PATH "Update-WindowsConfig.ps1"

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
    $trigger = New-ScheduledTaskTrigger -Monthly -DaysOfMonth 1 -At 3am

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
        Write-Host "System update task registered successfully!" -ForegroundColor Green
        Write-Host "Task Details:" -ForegroundColor Yellow
        Write-Host "  Name: $taskName"
        Write-Host "  Path: $taskPath"
        Write-Host "  Script: $updateScript"
        Write-Host "  Schedule: Monthly at 3 AM on the 1st"
        Write-Host "  User: $currentUser"
    } else {
        throw "Failed to register task"
    }

} catch {
    Write-Host "Failed to register system update task: $_" -ForegroundColor Red
    exit 1
}

# Offer to run the update now
Write-Host "`nWould you like to run the system update now? (Y/N)" -ForegroundColor Yellow
$response = Read-Host
if ($response -eq "Y" -or $response -eq "y") {
    try {
        Write-Host "Running system update..." -ForegroundColor Blue
        & $updateScript
    } catch {
        Write-Host "Failed to run system update: $_" -ForegroundColor Red
    }
} 