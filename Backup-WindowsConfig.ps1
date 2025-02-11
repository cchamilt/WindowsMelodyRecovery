# At the start of the script
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptPath "scripts\load-environment.ps1")

if (!(Load-Environment)) {
    Write-Host "Failed to load environment configuration" -ForegroundColor Red
    exit 1
}

# Then use the environment variables
$MACHINE_BACKUP = "$env:BACKUP_ROOT\$env:MACHINE_NAME"

# Define common paths
$BACKUP_ROOT = "$env:USERPROFILE\OneDrive - Fyber Labs\PCbackup"
$MACHINE_NAME = $env:COMPUTERNAME

function Initialize-BackupDirectory {
    param (
        [string]$Path,
        [string]$BackupType,
        [string]$BackupRootPath
    )
    
    # Create machine-specific backup directory if it doesn't exist
    $backupPath = "$BackupRootPath\$Path"
    if (!(Test-Path -Path $backupPath)) {
        try {
            New-Item -ItemType Directory -Path $backupPath -Force | Out-Null
            Write-Host "Created backup directory for $BackupType at: $backupPath" -ForegroundColor Green
        } catch {
            Write-Host "Failed to create backup directory for $BackupType : $_" -ForegroundColor Red
            return $null
        }
    }
    
    return $backupPath
}

# Define all backup functions and their corresponding scripts
$backupFunctions = @(
    @{ Name = "Terminal Settings"; Function = "Backup-TerminalSettings"; Script = "backup-terminal.ps1" },
    @{ Name = "Explorer Settings"; Function = "Backup-ExplorerSettings"; Script = "backup-explorer.ps1" },
    @{ Name = "Touchpad Settings"; Function = "Backup-TouchpadSettings"; Script = "backup-touchpad.ps1" },
    @{ Name = "Touchscreen Settings"; Function = "Backup-TouchscreenSettings"; Script = "backup-touchscreen.ps1" },
    @{ Name = "Power Settings"; Function = "Backup-PowerSettings"; Script = "backup-power.ps1" },
    @{ Name = "Display Settings"; Function = "Backup-DisplaySettings"; Script = "backup-display.ps1" },
    @{ Name = "Sound Settings"; Function = "Backup-SoundSettings"; Script = "backup-sound.ps1" },
    @{ Name = "Keyboard Settings"; Function = "Backup-KeyboardSettings"; Script = "backup-keyboard.ps1" },
    @{ Name = "Start Menu Settings"; Function = "Backup-StartMenuSettings"; Script = "backup-startmenu.ps1" },
    @{ Name = "WSL Settings"; Function = "Backup-WSLSettings"; Script = "backup-wsl.ps1" },
    @{ Name = "Default App Settings"; Function = "Backup-DefaultAppSettings"; Script = "backup-defaultapps.ps1" },
    @{ Name = "Network Settings"; Function = "Backup-NetworkSettings"; Script = "backup-network.ps1" },
    @{ Name = "Remote Desktop Settings"; Function = "Backup-RDPSettings"; Script = "backup-rdp.ps1" },
    @{ Name = "Azure VPN Settings"; Function = "Backup-VPNSettings"; Script = "backup-vpn.ps1" },
    @{ Name = "SSH Settings"; Function = "Backup-SSHSettings"; Script = "backup-ssh.ps1" },
    @{ Name = "WSL SSH Settings"; Function = "Backup-WSLSSHSettings"; Script = "backup-wsl-ssh.ps1" },
    @{ Name = "PowerShell Settings"; Function = "Backup-PowerShellSettings"; Script = "backup-powershell.ps1" },
    @{ Name = "Windows Features"; Function = "Backup-WindowsFeatures"; Script = "backup-windows-features.ps1" },
    @{ Name = "Applications"; Function = "Backup-Applications"; Script = "backup-applications.ps1" },
    @{ Name = "System Settings"; Function = "Backup-SystemSettings"; Script = "backup-system-settings.ps1" },
    @{ Name = "Browser Settings"; Function = "Backup-BrowserSettings"; Script = "backup-browsers.ps1" },
    @{ Name = "KeePassXC Settings"; Function = "Backup-KeePassXCSettings"; Script = "backup-keepassxc.ps1" },
    @{ Name = "OneNote Settings"; Function = "Backup-OneNoteSettings"; Script = "backup-onenote.ps1" },
    @{ Name = "Outlook Settings"; Function = "Backup-OutlookSettings"; Script = "backup-outlook.ps1" },
    @{ Name = "Word Settings"; Function = "Backup-WordSettings"; Script = "backup-word.ps1" },
    @{ Name = "Excel Settings"; Function = "Backup-ExcelSettings"; Script = "backup-excel.ps1" },
    @{ Name = "Visio Settings"; Function = "Backup-VisioSettings"; Script = "backup-visio.ps1" }
)

# Create machine backup directory if it doesn't exist
if (!(Test-Path -Path $MACHINE_BACKUP)) {
    try {
        New-Item -ItemType Directory -Path $MACHINE_BACKUP -Force | Out-Null
        Write-Host "Created machine backup directory at: $MACHINE_BACKUP" -ForegroundColor Green
    } catch {
        Write-Host "Failed to create machine backup directory: $_" -ForegroundColor Red
        exit 1
    }
}

# Collect any errors during backup
$backupErrors = @()

# Create a temporary file for capturing console output
$tempLogFile = [System.IO.Path]::GetTempFileName()

try {
    # Start transcript to capture all console output
    Start-Transcript -Path $tempLogFile -Append

    # Source all backup scripts
    foreach ($backup in $backupFunctions) {
        try {
            . (Join-Path $scriptPath "backup\$($backup.Script)")
        } catch {
            $errorMessage = "Failed to source $($backup.Script) : $_"
            Write-Host $errorMessage -ForegroundColor Red
            $backupErrors += $errorMessage
        }
    }

    # Run all backup functions with backup path
    foreach ($backup in $backupFunctions) {
        try {
            & $backup.Function -BackupRootPath $MACHINE_BACKUP
        } catch {
            $errorMessage = "Failed to backup $($backup.Name): $_"
            Write-Host $errorMessage -ForegroundColor Red
            $backupErrors += $errorMessage
        }
    }

    Write-Host "Settings backup completed!" -ForegroundColor Green

    # Add timestamp to backup log
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logFile = "$MACHINE_BACKUP\backup_history.log"
    Add-Content -Path $logFile -Value "Backup completed at: $timestamp"

    # Git backup handling
    try {
        Write-Host "Checking for Git repositories in backup directories..." -ForegroundColor Blue
        
        # Function to handle Git operations for a directory
        function Invoke-GitBackup {
            param (
                [string]$Path,
                [string]$BackupType
            )
            
            if (Test-Path (Join-Path $Path ".git")) {
                Push-Location $Path
                try {
                    # Check if there are changes
                    $status = git status --porcelain
                    if ($status) {
                        Write-Host "Changes detected in $BackupType repository" -ForegroundColor Yellow
                        
                        # Stage all changes
                        git add -A
                        
                        # Commit with timestamp and machine name
                        $commitMessage = "Automated backup from $MACHINE_NAME at $timestamp"
                        git commit -m $commitMessage
                        
                        # Check if remote exists and push
                        $remoteExists = git remote get-url origin 2>$null
                        if ($remoteExists) {
                            Write-Host "Pushing changes to remote repository..." -ForegroundColor Blue
                            git push origin
                            Write-Host "$BackupType backup pushed to remote" -ForegroundColor Green
                        } else {
                            Write-Host "No remote repository configured for $BackupType" -ForegroundColor Yellow
                        }
                    } else {
                        Write-Host "No changes detected in $BackupType repository" -ForegroundColor Green
                    }
                } catch {
                    Write-Host "Git operations failed for $BackupType : $_" -ForegroundColor Red
                } finally {
                    Pop-Location
                }


            }

        }
        
        # Check main backup root
        Invoke-GitBackup -Path $BACKUP_ROOT -BackupType "Main backup"
        
        # Check machine-specific backup
        Invoke-GitBackup -Path $MACHINE_BACKUP -BackupType "Machine backup"
        
        # Check shared backup
        $SHARED_BACKUP = "$BACKUP_ROOT\shared"
        Invoke-GitBackup -Path $SHARED_BACKUP -BackupType "Shared backup"
        
        Write-Host "Git backup operations completed!" -ForegroundColor Green
    } catch {
        $errorMessage = "Failed to process Git repositories: $_"
        Write-Host $errorMessage -ForegroundColor Red
        $backupErrors += $errorMessage
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

