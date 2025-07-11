# Requires admin privileges
#Requires -RunAsAdministrator

# Load environment
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path (Split-Path $scriptPath -Parent) "scripts\Import-Environment.ps1")

if (!(Import-Environment)) {
    Write-Error -Message "Failed to load environment configuration"
    exit 1
}

# Check for existing config.env
$configLocations = @(
    (Join-Path (Join-Path $env:BACKUP_ROOT $env:MACHINE_NAME) "config.env"),
    (Join-Path (Join-Path $env:BACKUP_ROOT "shared") "config.env")
)

$configFound = $false
foreach ($configFile in $configLocations) {
    if (Test-Path $configFile) {
        $configFound = $true
        break
    }
}

# Only prompt for email settings if no config.env found
if (!$configFound) {
    Write-Information -MessageData "`nNo email configuration found. Please configure notification settings:" -InformationAction Continue
    $fromAddress = Read-Host "Enter sender email address (Office 365)"
    $toAddress = Read-Host "Enter recipient email address"
    $emailPassword = Read-Host "Enter email app password" -AsSecureString

    # Convert secure string to plain text
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($emailPassword)
    $plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)

    # Create config.env content
    $configEnv = @"
# Email notification settings
BACKUP_EMAIL_FROM="$fromAddress"
BACKUP_EMAIL_TO="$toAddress"
BACKUP_EMAIL_PASSWORD="$plainPassword"
"@

    # Save to machine-specific backup directory
    $machineBackupDir = Join-Path $env:BACKUP_ROOT $env:MACHINE_NAME
    if (!(Test-Path $machineBackupDir)) {
        New-Item -ItemType Directory -Path $machineBackupDir -Force | Out-Null
    }
    $configEnv | Out-File (Join-Path $machineBackupDir "config.env") -Force

    # Reload environment to get new settings
    if (!(Import-Environment)) {
        Write-Error -Message "Failed to load updated configuration"
        exit 1
    }
}

# Task settings
$taskName = "WindowsMelodyRecovery_Backup"
$taskDescription = "Backup Windows configuration settings to OneDrive"
$backupScript = Join-Path $env:WINDOWS_CONFIG_PATH "Backup-WindowsMelodyRecovery.ps1"

# Verify backup script exists
if (!(Test-Path $backupScript)) {
    throw "Backup script not found at: $backupScript"
}

# Get current or default schedule
$taskPath = "\Custom Tasks"
$existingTask = Get-ScheduledTask -TaskName $taskName -TaskPath $taskPath -ErrorAction SilentlyContinue

if ($existingTask) {
    $currentTrigger = $existingTask.Triggers[0]
    $triggerTime = $currentTrigger.StartBoundary.Split('T')[1].Substring(0, 5)
    $dayOfWeek = $currentTrigger.DaysOfWeek

    Write-Warning -Message "Current schedule: Every $dayOfWeek at $triggerTime"
    $changeSchedule = Read-Host "Would you like to change the schedule? (y/N)"

    if ($changeSchedule -eq 'y') {
        $triggerTime = Read-Host "Enter time to run (HH:mm, 24hr format) [default: 02:00]"
        $dayOfWeek = Read-Host "Enter day of week to run [default: Sunday]"
    }
} else {
    $triggerTime = "02:00"  # Default 2 AM
    $dayOfWeek = "Sunday"   # Default Sunday
}

# Validate and set defaults if empty
if ([string]::IsNullOrWhiteSpace($triggerTime)) { $triggerTime = "02:00" }
if ([string]::IsNullOrWhiteSpace($dayOfWeek)) { $dayOfWeek = "Sunday" }

# Create task action
$action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$backupScript`"" `
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
    -LogonType S4U `
    -RunLevel Highest

try {
    # Remove existing task if it exists
    if ($existingTask) {
        Unregister-ScheduledTask -TaskName $taskName -TaskPath $taskPath -Confirm:$false
        Write-Warning -Message "Existing backup task removed"
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
        Write-Information -MessageData "Backup task registered successfully!" -InformationAction Continue
        Write-Warning -Message "Task Details:"
        Write-Information -MessageData "  Name: $taskName" -InformationAction Continue
        Write-Information -MessageData "  Path: $taskPath" -InformationAction Continue
        Write-Information -MessageData "  Script: $backupScript" -InformationAction Continue
        Write-Information -MessageData "  Schedule: Every $dayOfWeek at $triggerTime" -InformationAction Continue
        Write-Information -MessageData "  User: $currentUser" -InformationAction Continue
    } else {
        throw "Failed to register task"
    }

} catch {
    Write-Error -Message "Failed to register backup task: $_"
    exit 1
}

