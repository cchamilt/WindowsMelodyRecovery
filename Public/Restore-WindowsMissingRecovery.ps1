# At the start of the script
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$modulePath = Split-Path -Parent $scriptPath
$restoreDir = Join-Path $modulePath "Private\restore"

# Get configuration from the module
$config = Get-WindowsMissingRecovery
if (!$config.BackupRoot) {
    Write-Host "Configuration not initialized. Please run Initialize-WindowsMissingRecovery first." -ForegroundColor Yellow
    return
}

# Now load environment with configuration available
. (Join-Path $modulePath "Private\scripts\load-environment.ps1")

# Define proper backup paths using config values
$BACKUP_ROOT = $config.BackupRoot
$MACHINE_NAME = $config.MachineName
$MACHINE_BACKUP = Join-Path $BACKUP_ROOT $MACHINE_NAME
$SHARED_BACKUP = Join-Path $BACKUP_ROOT "shared"

# Ensure shared backup directory exists
if (!(Test-Path -Path $SHARED_BACKUP)) {
    try {
        New-Item -ItemType Directory -Path $SHARED_BACKUP -Force | Out-Null
        Write-Host "Created shared backup directory at: $SHARED_BACKUP" -ForegroundColor Green
    } catch {
        Write-Host "Failed to create shared backup directory: $_" -ForegroundColor Red
    }
}

function Test-BackupPath {
    param (
        [string]$Path,
        [string]$BackupType
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

# Check if restore directory exists
if (!(Test-Path -Path $restoreDir)) {
    try {
        New-Item -ItemType Directory -Path $restoreDir -Force | Out-Null
        Write-Host "Created restore scripts directory at: $restoreDir" -ForegroundColor Green
        Write-Host "Note: You need to add restore scripts to this directory." -ForegroundColor Yellow
    } catch {
        Write-Host "Failed to create restore scripts directory: $_" -ForegroundColor Red
    }
}

# Source all restore scripts
$restoreScripts = @(
    "restore-terminal.ps1",
    "restore-explorer.ps1",
    "restore-touchpad.ps1",
    "restore-touchscreen.ps1",
    "restore-power.ps1",
    "restore-display.ps1",
    "restore-sound.ps1",
    "restore-keyboard.ps1",
    "restore-startmenu.ps1",
    "restore-wsl.ps1",
    "restore-defaultapps.ps1",
    "restore-network.ps1",
    "restore-rdp.ps1",
    "restore-vpn.ps1",
    "restore-ssh.ps1",
    "restore-wsl-ssh.ps1",
    "restore-powershell.ps1",
    "restore-windows-features.ps1",
    "restore-applications.ps1",
    "restore-system-settings.ps1",
    "restore-browsers.ps1",
    "restore-keepassxc.ps1",
    "restore-onenote.ps1",
    "restore-outlook.ps1",
    "restore-word.ps1",
    "restore-excel.ps1",
    "restore-visio.ps1"
)

$successfullyLoaded = 0
foreach ($script in $restoreScripts) {
    $scriptFile = Join-Path $restoreDir $script
    if (Test-Path $scriptFile) {
        try {
            . $scriptFile
            $successfullyLoaded++
            Write-Host "Successfully loaded $script" -ForegroundColor Green
        } catch {
            Write-Host "Failed to source $script : $_" -ForegroundColor Red
        }
    } else {
        Write-Host "Restore script not found: $script" -ForegroundColor Yellow
    }
}

if ($successfullyLoaded -eq 0) {
    Write-Host "No restore scripts were found or loaded. Create scripts in: $restoreDir" -ForegroundColor Yellow
} else {
    Write-Host "Settings restoration completed! ($successfullyLoaded scripts loaded)" -ForegroundColor Green
} 