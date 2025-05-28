# At the start of the script
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$modulePath = Split-Path -Parent $scriptPath

# Detect if we're running from PowerShell or WindowsPowerShell path
$psModulePaths = $env:PSModulePath -split ';'
$windowsPowerShellPath = $psModulePaths | Where-Object { $_ -like "*WindowsPowerShell*" } | Select-Object -First 1
$powerShellPath = $psModulePaths | Where-Object { $_ -like "*PowerShell*" -and $_ -notlike "*WindowsPowerShell*" } | Select-Object -First 1

# Check if modulePath is in the expected location, if not try to find the correct path
if (!(Test-Path (Join-Path $modulePath "Private\restore"))) {
    # Try finding module in both PS and Windows PS paths
    $possiblePaths = @()
    if ($windowsPowerShellPath) {
        $possiblePaths += Join-Path $windowsPowerShellPath "Modules\WindowsMissingRecovery"
    }
    if ($powerShellPath) {
        $possiblePaths += Join-Path $powerShellPath "Modules\WindowsMissingRecovery"
    }

    foreach ($path in $possiblePaths) {
        if (Test-Path $path) {
            Write-Host "Found module at: $path" -ForegroundColor Green
            $modulePath = $path
            break
        }
    }
}

$restoreDir = Join-Path $modulePath "Public\restore"
$privateRestoreDir = Join-Path $modulePath "Private\restore"

# Get configuration from the module
$config = Get-WindowsMissingRecovery
if (!$config.BackupRoot) {
    Write-Host "Configuration not initialized. Please run Initialize-WindowsMissingRecovery first." -ForegroundColor Yellow
    return
}

# Now load environment with configuration available
$privateScriptsDir = Join-Path $modulePath "Private\scripts"
$loadEnvPath = Join-Path $privateScriptsDir "load-environment.ps1"

if (Test-Path $loadEnvPath) {
    . $loadEnvPath
} else {
    Write-Warning "Could not find load-environment.ps1 at: $loadEnvPath"
}

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

# Check if restore directories exist - try both public and private locations
$restoreDirs = @($restoreDir, $privateRestoreDir)
$restoreScriptPaths = @()

foreach ($dir in $restoreDirs) {
    if (!(Test-Path -Path $dir)) {
        try {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            Write-Host "Created restore scripts directory at: $dir" -ForegroundColor Green
        } catch {
            Write-Host "Failed to create restore scripts directory: $_" -ForegroundColor Red
        }
    } else {
        # Find any scripts in this directory
        Get-ChildItem -Path $dir -Filter "restore-*.ps1" | ForEach-Object {
            $restoreScriptPaths += $_.FullName
            Write-Host "Found restore script: $($_.Name)" -ForegroundColor Green
        }
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

# Try loading the scripts we found in the directories first
foreach ($scriptPath in $restoreScriptPaths) {
    try {
        # Define the Test-BackupPath function with explicit parameters
        & $scriptPath
        $successfullyLoaded++
        Write-Host "Successfully loaded $(Split-Path -Leaf $scriptPath)" -ForegroundColor Green
    } catch {
        Write-Host "Failed to source $(Split-Path -Leaf $scriptPath) : $_" -ForegroundColor Red
    }
}

# If no scripts were found in the directories, try the default paths for each script
if ($successfullyLoaded -eq 0) {
    foreach ($script in $restoreScripts) {
        $found = $false
        foreach ($dir in $restoreDirs) {
            $scriptFile = Join-Path $dir $script
            if (Test-Path $scriptFile) {
                try {
                    # Load the script directly, with direct variables
                    & $scriptFile -BackupRootPath "$BACKUP_ROOT\$MACHINE_NAME" -MachineBackupPath $MACHINE_BACKUP -SharedBackupPath $SHARED_BACKUP
                    $successfullyLoaded++
                    Write-Host "Successfully loaded $script" -ForegroundColor Green
                    $found = $true
                    break
                } catch {
                    Write-Host "Failed to source $script : $_" -ForegroundColor Red
                }
            }
        }
        
        if (-not $found) {
            Write-Host "Restore script not found: $script" -ForegroundColor Yellow
        }
    }
}

if ($successfullyLoaded -eq 0) {
    Write-Host "No restore scripts were found or loaded. Create scripts in: $restoreDir or $privateRestoreDir" -ForegroundColor Yellow
} else {
    Write-Host "Settings restoration completed! ($successfullyLoaded scripts loaded)" -ForegroundColor Green
}

# Start system updates
Write-Host "Starting system updates..." -ForegroundColor Green 