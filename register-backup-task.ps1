# Get the current script directory
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$backupScript = Join-Path $scriptPath "backup.ps1"

# Task parameters
$taskName = "Windows Settings Backup"
$taskDescription = "Weekly backup of Windows settings and configurations to OneDrive"

# Check if task already exists
$existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue

# Get current or default schedule
if ($existingTask) {
    $currentTrigger = $existingTask.Triggers[0]
    $triggerTime = $currentTrigger.StartBoundary.Split('T')[1].Substring(0, 5)
    $dayOfWeek = $currentTrigger.DaysOfWeek
    
    Write-Host "Current schedule: Every $dayOfWeek at $triggerTime" -ForegroundColor Yellow
    $changeSchedule = Read-Host "Would you like to change the schedule? (y/N)"
    
    if ($changeSchedule -eq 'y') {
        $triggerTime = Read-Host "Enter time to run (HH:mm, 24hr format) [default: 03:00]" 
        $dayOfWeek = Read-Host "Enter day of week to run [default: Sunday]"
    }
}
else {
    $triggerTime = "03:00"  # Default 3 AM
    $dayOfWeek = "Sunday"   # Default Sunday
}

# Validate and set defaults if empty
if ([string]::IsNullOrWhiteSpace($triggerTime)) { $triggerTime = "03:00" }
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
    -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$tempScriptPath`""

# Create task trigger
$trigger = New-ScheduledTaskTrigger `
    -Weekly `
    -DaysOfWeek $dayOfWeek `
    -At $triggerTime

# Task settings
$settings = New-ScheduledTaskSettingsSet `
    -StartWhenAvailable `
    -DontStopOnIdleEnd `
    -RestartInterval (New-TimeSpan -Minutes 1) `
    -RestartCount 3

# Register the task (will run with current user's credentials)
try {
    $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -RunLevel Highest
    
    # Unregister existing task if it exists
    if ($existingTask) {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
        Write-Host "Existing backup task removed" -ForegroundColor Yellow
    }
    
    Register-ScheduledTask `
        -TaskName $taskName `
        -Description $taskDescription `
        -Action $action `
        -Trigger $trigger `
        -Settings $settings `
        -Principal $principal `
        -Force

    Write-Host "Backup task scheduled successfully!" -ForegroundColor Green
    Write-Host "Task will run every $dayOfWeek at $triggerTime" -ForegroundColor Green
} catch {
    Write-Host "Failed to schedule backup task: $_" -ForegroundColor Red
} finally {
    # Clean up temporary script
    if (Test-Path $tempScriptPath) {
        Remove-Item $tempScriptPath -Force
    }
} 