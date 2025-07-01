function Backup-WindowsMelodyRecovery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$TemplatePath
    )

    # Check if configuration is properly set up
    $config = Get-WindowsMelodyRecovery
    if (!$config.BackupRoot) {
        Write-Host "Configuration not initialized. Please run Initialize-WindowsMelodyRecovery first." -ForegroundColor Yellow
        return
    }

    # Start transcript for logging
    Start-Transcript -Path (Join-Path $logPath "Backup-WindowsMelodyRecovery-$(Get-Date -Format 'yyyyMMdd_HHmmss').log") -Append -Force

    try {
        Write-Host "Starting Windows Melody Recovery Backup..." -ForegroundColor Cyan

        # Define proper backup paths using config values
        $BACKUP_ROOT = $config.BackupRoot
        $MACHINE_NAME = $config.MachineName
        $MACHINE_BACKUP = Join-Path $BACKUP_ROOT $MACHINE_NAME
        $SHARED_BACKUP = Join-Path $BACKUP_ROOT "shared"

        # Ensure necessary backup directories exist
        if (-not (Test-Path -Path $MACHINE_BACKUP -PathType Container)) {
            try {
                New-Item -ItemType Directory -Path $MACHINE_BACKUP -Force | Out-Null
                Write-Host "Created machine backup directory at: $MACHINE_BACKUP" -ForegroundColor Green
            } catch {
                Write-Host "Failed to create machine backup directory: $_" -ForegroundColor Red
                throw "Failed to create machine backup directory."
            }
        }
        if (-not (Test-Path -Path $SHARED_BACKUP -PathType Container)) {
            try {
                New-Item -ItemType Directory -Path $SHARED_BACKUP -Force | Out-Null
                Write-Host "Created shared backup directory at: $SHARED_BACKUP" -ForegroundColor Green
            } catch {
                Write-Host "Failed to create shared backup directory: $_" -ForegroundColor Red
                throw "Failed to create shared backup directory."
            }
        }

        if ($PSCmdlet.MyInvocation.BoundParameters.ContainsKey('TemplatePath')) {
            # New template-based backup logic
            Write-Host "Performing template-based backup using template: $TemplatePath"

            # Create a timestamped directory for the current backup's state files
            $Timestamp = (Get-Date -Format "yyyyMMdd_HHmmss")
            $CurrentBackupDir = Join-Path $BACKUP_ROOT "template_backup_$Timestamp"

            # Ensure the template backup directory exists
            if (-not (Test-Path $CurrentBackupDir -PathType Container)) {
                New-Item -ItemType Directory -Path $CurrentBackupDir -Force | Out-Null
                Write-Host "Created template backup directory for state files: $CurrentBackupDir"
            }

            # Dot-source the InvokeWmrTemplate module
            . (Join-Path $PSScriptRoot "..\Private\Core\InvokeWmrTemplate.ps1")

            Invoke-WmrTemplate -TemplatePath $TemplatePath -Operation "Backup" -StateFilesDirectory $CurrentBackupDir
            Write-Host "Template-based backup operation completed successfully."

        } else {
            # Original script-based backup logic
            Write-Host "Performing script-based backup..."

            # Load backup scripts on demand
            Import-PrivateScripts -Category 'backup'

            # Define this function directly in the script to avoid dependency issues
            function Test-BackupPath {
                param (
                    [Parameter(Mandatory=$true)]
                    [string]$Path,

                    [Parameter(Mandatory=$true)]
                    [string]$BackupType,
                    
                    [Parameter(Mandatory=$true)]
                    [string]$MACHINE_BACKUP,
                    
                    [Parameter(Mandatory=$true)]
                    [string]$SHARED_BACKUP
                )
                
                # First check machine-specific backup
                $machinePath = Join-Path $MACHINE_BACKUP $Path
                if (Test-Path $machinePath) {
                    Write-Host "Using machine-specific $BackupType backup from: $machinePath" -ForegroundColor Green
                    return $machinePath
                }
                
                # Fall back to shared backup
                $sharedPath = Join-Path $SHARED_BACKUP $Path
                if (Test-Path $sharedPath) {
                    Write-Host "Using shared $BackupType backup from: $sharedPath" -ForegroundColor Green
                    return $sharedPath
                }
                
                Write-Host "No $BackupType backup found" -ForegroundColor Yellow
                return $null
            }

            $backupFunctions = Get-ScriptsConfig -Category 'backup'

            if (-not $backupFunctions) {
                Write-Warning "No backup configuration found. Using fallback minimal list."
                $backupFunctions = @(
                    @{ name = "Applications"; function = "Backup-Applications"; script = "backup-applications.ps1"; enabled = $true; required = $true }
                )
            }

            $availableBackups = 0

            foreach ($backup in $backupFunctions) {
                if (Get-Command $backup.function -ErrorAction SilentlyContinue) {
                    try {
                        $params = @{
                            BackupRootPath = $MACHINE_BACKUP
                            MachineBackupPath = $MACHINE_BACKUP
                            SharedBackupPath = $SHARED_BACKUP
                        }
                        & $backup.function @params
                        $availableBackups++
                        Write-Verbose "Successfully executed $($backup.function)"
                    } catch {
                        Write-Host "Failed to execute $($backup.function) : $_" -ForegroundColor Red
                    }
                } else {
                    Write-Verbose "Backup function $($backup.function) not available"
                }
            }

            if ($availableBackups -eq 0) {
                Write-Host "No backup functions were found. Check that backup scripts exist in the Private\backup directory." -ForegroundColor Yellow
            } else {
                Write-Host "Script-based backup completed! ($availableBackups functions executed)" -ForegroundColor Green
            }

            # Run final post-backup applications analysis
            Write-Host "`nRunning final post-backup applications analysis..." -ForegroundColor Blue
            try {
                $modulePath = (Get-Module -Name WindowsMelodyRecovery -ErrorAction SilentlyContinue).Path | Split-Path
                $analyzeScript = Join-Path $modulePath "Private\backup\analyze-unmanaged.ps1"
                if (Test-Path $analyzeScript) {
                    . $analyzeScript
                    if (Get-Command Compare-UnmanagedApplications -ErrorAction SilentlyContinue) {
                        $params = @{
                            BackupRootPath = $MACHINE_BACKUP
                            MachineBackupPath = $MACHINE_BACKUP
                            SharedBackupPath = $SHARED_BACKUP
                        }
                        $analysisResult = & Compare-UnmanagedApplications @params -ErrorAction Stop
                        if ($analysisResult.Success) {
                            Write-Host "`n=== BACKUP COMPLETE - POST-BACKUP ANALYSIS ===`" -ForegroundColor Yellow
                            Write-Host "Post-backup analysis saved to: $($analysisResult.BackupPath)" -ForegroundColor Green

                            if ($analysisResult.Analysis -and $analysisResult.Analysis.Summary) {
                                $summary = $analysisResult.Analysis.Summary
                                Write-Host "`nApplication Backup Summary:" -ForegroundColor Green
                                Write-Host "  Total Applications Scanned: $($summary.TotalApplications)" -ForegroundColor White
                                Write-Host "  Managed (Backed Up by Pkg Mgr): $($summary.ManagedApplications)" -ForegroundColor Green
                                Write-Host "  Unmanaged (Need Manual Backup): $($summary.UnmanagedApplications)" -ForegroundColor Red
                                Write-Host "  Coverage: $($summary.Coverage)%" -ForegroundColor Cyan

                                if ($summary.UnmanagedApplications -gt 0) {
                                    Write-Host "`nIMPORTANT: Consider manually backing up configuration for the following applications:" -ForegroundColor Yellow
                                    Write-Host "  - unmanaged-apps.json: Technical details for scripts" -ForegroundColor Cyan
                                    Write-Host "  - unmanaged-apps.csv: Excel-friendly format for review" -ForegroundColor Cyan
                                    Write-Host "  - managed-apps.json: List of automatically managed applications" -ForegroundColor Green
                                    Write-Host "`nThese applications were not managed by any known package manager." -ForegroundColor Yellow
                                } else {
                                    Write-Host "`n🎉 CONGRATULATIONS: All applications are managed by a package manager or custom script!" -ForegroundColor Green
                                }
                            }
                        }
                    } else {
                        Write-Host "Compare-UnmanagedApplications function not found" -ForegroundColor Yellow
                    }
                } else {
                    Write-Host "Analysis script not found - skipping final post-backup analysis" -ForegroundColor Yellow
                }
            } catch {
                Write-Host "Failed to run final post-backup applications analysis: $_" -ForegroundColor Red
            }
        }
    } finally {
        Stop-Transcript
    }

    # Return results
    return @{
        Success = $availableBackups -gt 0
        BackupCount = $availableBackups
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
        $machineName = if ($MACHINE_NAME) { $MACHINE_NAME } else { $env:COMPUTERNAME }
        $backupLocation = if ($MACHINE_BACKUP) { $MACHINE_BACKUP } else { "Unknown" }
        $currentTime = if ($timestamp) { $timestamp } else { Get-Date -Format "yyyy-MM-dd HH:mm:ss" }
        
        $body = @"
Backup Status Report from $machineName
Timestamp: $currentTime

Summary:
    Total Errors: $($Errors.Count)
    Backup Location: $backupLocation

Errors encountered during backup:
$($Errors | ForEach-Object { "    * $_`n" })

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
            
        Write-Host "Email notification sent successfully" -ForegroundColor Green
    } catch {
        Write-Host "Failed to send email notification: $_" -ForegroundColor Red
    }
}

# Send email notification if there were any errors
if ($backupErrors.Count -gt 0) {
    $errorCount = $backupErrors.Count
    $machineName = if ($MACHINE_NAME) { $MACHINE_NAME } else { $env:COMPUTERNAME }
    $subject = "⚠️ Backup Failed on $machineName ($errorCount issues)"
    Send-BackupNotification -Errors $backupErrors -Subject $subject
}

# Update task registration path references
$taskScript = Join-Path (Split-Path $MyInvocation.MyCommand.Path) "tasks\register-backup-task.ps1"

