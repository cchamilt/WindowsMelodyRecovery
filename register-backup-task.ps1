# Requires admin privileges
#Requires -RunAsAdministrator

# Get the current script directory
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$backupScript = Join-Path $scriptPath "backup.ps1"

# Verify backup script exists
if (!(Test-Path $backupScript)) {
    throw "Backup script not found at: $backupScript"
}

# Task parameters
$taskName = "Windows Settings Backup"
$taskDescription = "Weekly backup of Windows settings and configurations to OneDrive"
$taskPath = "\Custom Tasks"

# Check if task already exists
$existingTask = Get-ScheduledTask -TaskName $taskName -TaskPath $taskPath -ErrorAction SilentlyContinue

# Get current or default schedule
if ($existingTask) {
    $currentTrigger = $existingTask.Triggers[0]
    $triggerTime = $currentTrigger.StartBoundary.Split('T')[1].Substring(0, 5)
    $dayOfWeek = $currentTrigger.DaysOfWeek
    
    Write-Host "Current schedule: Every $dayOfWeek at $triggerTime" -ForegroundColor Yellow
    $changeSchedule = Read-Host "Would you like to change the schedule? (y/N)"
    
    if ($changeSchedule -eq 'y') {
        $triggerTime = Read-Host "Enter time to run (HH:mm, 24hr format) [default: 02:00]" 
        $dayOfWeek = Read-Host "Enter day of week to run [default: Sunday]"
    }
}
else {
    $triggerTime = "02:00"  # Default 2 AM
    $dayOfWeek = "Sunday"   # Default Sunday
}

# Validate and set defaults if empty
if ([string]::IsNullOrWhiteSpace($triggerTime)) { $triggerTime = "02:00" }
if ([string]::IsNullOrWhiteSpace($dayOfWeek)) { $dayOfWeek = "Sunday" }

# Prompt for email settings
Write-Host "Configure backup notification settings:" -ForegroundColor Blue
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
& '$backupScript'
"@

# Save the script to a temporary file
$tempScriptPath = Join-Path $scriptPath "temp_backup.ps1"
$actionScript | Out-File -FilePath $tempScriptPath -Force

# Create task action
$action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$tempScriptPath`"" `
    -WorkingDirectory $scriptPath

# Create task trigger
$trigger = New-ScheduledTaskTrigger `
    -Weekly `
    -DaysOfWeek $dayOfWeek `
    -At $triggerTime

# Task settings with improved reliability
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

try {
    # Remove existing task if it exists
    if ($existingTask) {
        Unregister-ScheduledTask -TaskName $taskName -TaskPath $taskPath -Confirm:$false
        Write-Host "Existing backup task removed" -ForegroundColor Yellow
    }
    
    # Register the new task
    $task = Register-ScheduledTask `
        -TaskName $taskName `
        -TaskPath $taskPath `
        -Description $taskDescription `
        -Action $action `
        -Trigger $trigger `
        -Settings $settings `
        -Principal $principal `
        -Force

    # Verify task was created
    if ($task) {
        Write-Host "Backup task registered successfully!" -ForegroundColor Green
        Write-Host "Task Details:" -ForegroundColor Yellow
        Write-Host "  Name: $taskName"
        Write-Host "  Path: $taskPath"
        Write-Host "  Script: $backupScript"
        Write-Host "  Schedule: Every $dayOfWeek at $triggerTime"
        Write-Host "  User: $currentUser"
    } else {
        throw "Failed to register task"
    }

} catch {
    Write-Host "Failed to register backup task: $_" -ForegroundColor Red
    exit 1
} finally {
    # Clean up temporary script
    if (Test-Path $tempScriptPath) {
        Remove-Item $tempScriptPath -Force
    }
}

# Offer to run the backup now
Write-Host "`nWould you like to run the backup now? (Y/N)" -ForegroundColor Yellow
$response = Read-Host
if ($response -eq "Y" -or $response -eq "y") {
    try {
        Write-Host "Running backup..." -ForegroundColor Blue
        & $backupScript
    } catch {
        Write-Host "Failed to run backup: $_" -ForegroundColor Red
    }
} 