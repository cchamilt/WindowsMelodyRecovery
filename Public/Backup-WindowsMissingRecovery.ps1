function Backup-WindowsMissingRecovery {
    [CmdletBinding()]
    param()

    # Check if configuration is properly set up
    $config = Get-WindowsMissingRecovery
    if (!$config.BackupRoot) {
        Write-Host "Backup not configured. Please run Initialize-WindowsMissingRecovery first." -ForegroundColor Yellow
        Write-Host "Type 'Initialize-WindowsMissingRecovery' to set up your Windows recovery configuration." -ForegroundColor Cyan
        return
    }

    # Load backup scripts on demand
    Import-PrivateScripts -Category 'backup'

    # Define proper backup paths using config values
    $BACKUP_ROOT = $config.BackupRoot
    $MACHINE_NAME = $config.MachineName
    $MACHINE_BACKUP = Join-Path $BACKUP_ROOT $MACHINE_NAME

    # Verify machine name is correct (not the default when we want a specific machine)
    if ([string]::IsNullOrWhiteSpace($MACHINE_NAME) -or $MACHINE_NAME -eq "System.Collections.Hashtable") {
        $MACHINE_NAME = $env:COMPUTERNAME
        Write-Host "Machine name not properly configured. Using current computer name: $MACHINE_NAME" -ForegroundColor Yellow
        
        # Update configuration with proper machine name
        Set-WindowsMissingRecovery -MachineName $MACHINE_NAME
        
        # Update the machine backup path
        $MACHINE_BACKUP = Join-Path $BACKUP_ROOT $MACHINE_NAME
    }

    # Ensure machine backup directory exists
    if (!(Test-Path -Path $MACHINE_BACKUP)) {
        try {
            New-Item -ItemType Directory -Path $MACHINE_BACKUP -Force | Out-Null
            Write-Host "Created machine backup directory at: $MACHINE_BACKUP" -ForegroundColor Green
        } catch {
            Write-Host "Failed to create machine backup directory: $_" -ForegroundColor Red
            return
        }
    }

    # Load backup configuration from configurable scripts list
    $backupFunctions = Get-ScriptsConfig -Category 'backup'
    
    if (-not $backupFunctions) {
        Write-Warning "No backup configuration found. Using fallback minimal list."
        # Fallback to minimal essential backups
        $backupFunctions = @(
            @{ name = "Applications"; function = "Backup-Applications"; script = "backup-applications.ps1"; enabled = $true; required = $true }
        )
    }

    # Collect any errors during backup
    $backupErrors = @()

    # Create a temporary file for capturing console output
    $tempLogFile = [System.IO.Path]::GetTempFileName()

    try {
        # Start transcript to capture all console output
        Start-Transcript -Path $tempLogFile -Append

        # Backup scripts are now loaded via Import-PrivateScripts
        $BackupRootPath = Join-Path $config.BackupRoot $config.MachineName
        $availableBackups = @()
        
        # Check which backup functions are available after loading scripts
        foreach ($backup in $backupFunctions) {
            if (Get-Command $backup.function -ErrorAction SilentlyContinue) {
                $availableBackups += $backup
            } else {
                Write-Verbose "Backup function $($backup.function) not available"
            }
        }

        # Run all available backup functions
        if ($availableBackups.Count -eq 0) {
            Write-Host "No backup functions are available. Check that backup scripts exist in the Private\backup directory." -ForegroundColor Yellow
        } else {
            Write-Host "Found $($availableBackups.Count) available backup functions" -ForegroundColor Green
            
            # Run all backup functions with backup path
            foreach ($backup in $availableBackups) {
                try {
                    $params = @{
                        BackupRootPath = $MACHINE_BACKUP
                        MachineBackupPath = $MACHINE_BACKUP
                        SharedBackupPath = Join-Path $BACKUP_ROOT "shared"
                    }
                    & $backup.function @params -ErrorAction Stop
                } catch {
                    $errorMessage = "Failed to backup $($backup.name): $_"
                    Write-Host $errorMessage -ForegroundColor Red
                    $backupErrors += $errorMessage
                }
            }

            Write-Host "Settings backup completed!" -ForegroundColor Green
        }

        # Add timestamp to backup log
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $logFile = Join-Path $MACHINE_BACKUP "backup_history.log"

        try {
            Add-Content -Path $logFile -Value "Backup completed at: $timestamp" -ErrorAction Stop
            Write-Host "Backup log updated at: $logFile" -ForegroundColor Green
        } catch {
            Write-Host "Failed to update backup log: $_" -ForegroundColor Yellow
        }

    } finally {
        # Stop transcript
        Stop-Transcript

        # Read the console output and look for error patterns
        $consoleOutput = Get-Content -Path $tempLogFile -Raw
        $errorPatterns = @(
            'error',
            'exception',
            'failed',
            'failure',
            'unable to'
        )

        foreach ($pattern in $errorPatterns) {
            if ($consoleOutput -match "(?im)$pattern") {
                $matchs = [regex]::Matches($consoleOutput, "(?im).*$pattern.*")
                foreach ($match in $matchs) {
                    $errorMessage = "Console output error: $($match.Value.Trim())"
                    if ($backupErrors -notcontains $errorMessage) {
                        $backupErrors += $errorMessage
                    }
                }
            }
        }

        # Clean up temporary file
        Remove-Item -Path $tempLogFile -Force
    }

    # Return results
    return @{
        Success = $backupErrors.Count -eq 0
        Errors = $backupErrors
        BackupPath = $MACHINE_BACKUP
    }
}

# Email notification function
function Send-BackupNotification {
    param (
        [string[]]$Errors,
        [string]$Subject,
        [string]$SmtpServer = "smtp.office365.com",
        [int]$Port = 587
    )
    
    # Email configuration - load from environment variables for security
    $fromAddress = $env:BACKUP_EMAIL_FROM
    $toAddress = $env:BACKUP_EMAIL_TO
    $emailPassword = $env:BACKUP_EMAIL_PASSWORD
    
    # Check if email configuration exists
    if (!$fromAddress -or !$toAddress -or !$emailPassword) {
        Write-Host "Email notification skipped - environment variables not configured" -ForegroundColor Yellow
        return
    }
    
    try {
        # Create email body with more detailed information
        $body = @"
Backup Status Report from $MACHINE_NAME
Timestamp: $timestamp

Summary:
- Total Errors: $($Errors.Count)
- Backup Location: $MACHINE_BACKUP

Errors encountered during backup:
$($Errors | ForEach-Object { "- $_`n" })

This is an automated message.
"@
        
        # Create credential object
        $securePassword = ConvertTo-SecureString $emailPassword -AsPlainText -Force
        $credential = New-Object System.Management.Automation.PSCredential ($fromAddress, $securePassword)
        
        # Send email
        Send-MailMessage `
            -From $fromAddress `
            -To $toAddress `
            -Subject $Subject `
            -Body $body `
            -SmtpServer $SmtpServer `
            -Port $Port `
            -UseSsl `
            -Credential $credential
            
        Write-Host "Backup notification email sent successfully" -ForegroundColor Green
    } catch {
        Write-Host "Failed to send email notification: $_" -ForegroundColor Red
    }
}

# Send email notification if there were any errors
if ($backupErrors.Count -gt 0) {
    $subject = "⚠️ Backup Failed on $MACHINE_NAME ($($backupErrors.Count) errors)"
    Send-BackupNotification -Errors $backupErrors -Subject $subject
}

# Update task registration path references
$taskScript = Join-Path (Split-Path $MyInvocation.MyCommand.Path) "tasks\register-backup-task.ps1"

