# Requires admin privileges
#Requires -RunAsAdministrator

try {
    # At the start after admin check
    $scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
    . (Join-Path $scriptPath "scripts\load-environment.ps1")

    if (!(Load-Environment)) {
        Write-Host "Failed to load environment configuration" -ForegroundColor Red
        exit 1
    }

    Write-Host "Registering system update task..." -ForegroundColor Blue

    # Get the current script directory
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $updateScript = Join-Path $scriptDir "update.ps1"

    # Verify update script exists
    if (!(Test-Path $updateScript)) {
        throw "Update script not found at: $updateScript"
    }

    # Task configuration
    $taskName = "System Auto Update"
    $taskDescription = "Monthly system update for packages, modules, and applications"
    $taskPath = "\Custom Tasks"

    # Prompt for email settings
    Write-Host "Configure update notification settings:" -ForegroundColor Blue
    $fromAddress = Read-Host "Enter sender email address (Office 365)"
    $toAddress = Read-Host "Enter recipient email address"
    $emailPassword = Read-Host "Enter email app password" -AsSecureString

    # Convert secure string to plain text for script
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($emailPassword)
    $plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)

    # Create task action with provided email settings
    $actionScript = @"
`$env:BACKUP_EMAIL_FROM = '$fromAddress'
`$env:BACKUP_EMAIL_TO = '$toAddress'
`$env:BACKUP_EMAIL_PASSWORD = '$plainPassword'
& '$updateScript'
"@

    # Save the script to a temporary file
    $tempScriptPath = Join-Path $scriptDir "temp_update.ps1"
    $actionScript | Out-File -FilePath $tempScriptPath -Force

    # Create the task action to run PowerShell with the update script
    $action = New-ScheduledTaskAction -Execute "powershell.exe" `
        -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$tempScriptPath`"" `
        -WorkingDirectory $scriptDir

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
        -LogonType Password `
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
        -Description $taskDescription

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
} finally {
    # Clean up temporary script
    if (Test-Path $tempScriptPath) {
        Remove-Item $tempScriptPath -Force
    }
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