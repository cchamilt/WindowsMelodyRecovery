# At the start of the script
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path

# Get configuration from the module
$config = Get-WindowsMissingRecovery
if (!$config.BackupRoot) {
    Write-Host "Configuration not initialized. Please run Initialize-WindowsMissingRecovery first." -ForegroundColor Yellow
    return
}

# Now load environment with configuration available
. (Join-Path $scriptPath "scripts\load-environment.ps1")

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

foreach ($script in $restoreScripts) {
    try {
        . (Join-Path $scriptPath "restore\$script")
    } catch {
        Write-Host "Failed to source $script : $_" -ForegroundColor Red
    }
}

Write-Host "Settings restoration completed!" -ForegroundColor Green 