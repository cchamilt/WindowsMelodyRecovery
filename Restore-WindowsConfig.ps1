# At the start of the script
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptPath "scripts\load-environment.ps1")

if (!(Load-Environment)) {
    Write-Host "Failed to load environment configuration" -ForegroundColor Red
    exit 1
}

$MACHINE_BACKUP = "$env:BACKUP_ROOT\$env:MACHINE_NAME"
$SHARED_BACKUP = "$env:BACKUP_ROOT\shared"

function Test-BackupPath {
    param (
        [string]$Path,
        [string]$BackupType
    )
    
    # First check machine-specific backup
    $machinePath = "$MACHINE_BACKUP\$Path"
    if (Test-Path $machinePath) {
        Write-Host "Using machine-specific $BackupType backup from: $machinePath" -ForegroundColor Green
        return $machinePath
    }
    
    # Fall back to shared backup
    $sharedPath = "$SHARED_BACKUP\$Path"
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
    "restore-system-settings.ps1"
)

foreach ($script in $restoreScripts) {
    try {
        . (Join-Path $scriptPath "restore\$script")
    } catch {
        Write-Host "Failed to source $script : $_" -ForegroundColor Red
    }
}

Write-Host "Settings restoration completed!" -ForegroundColor Green 