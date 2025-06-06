# At the start of the script
$scriptPath = $PSScriptRoot
$modulePath = Split-Path -Parent $scriptPath

# Simple path references using $PSScriptRoot and $modulePath
$restoreDir = Join-Path $scriptPath "restore"
$privateRestoreDir = Join-Path $modulePath "Private\restore"

# Get configuration from the module
$config = Get-WindowsMissingRecovery
if (!$config.BackupRoot) {
    Write-Host "Configuration not initialized. Please run Initialize-WindowsMissingRecovery first." -ForegroundColor Yellow
    return
}

# Now load environment if needed
$loadEnvPath = Join-Path $modulePath "Private\scripts\load-environment.ps1"

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
    
    # Run final post-restore applications analysis
    Write-Host "`nRunning final post-restore applications analysis..." -ForegroundColor Blue
    try {
        $analyzeScript = Join-Path $modulePath "Private\backup\analyze-unmanaged.ps1"
        if (Test-Path $analyzeScript) {
            . $analyzeScript
            if (Get-Command Compare-PostRestoreApplications -ErrorAction SilentlyContinue) {
                $params = @{
                    BackupRootPath = $MACHINE_BACKUP
                    MachineBackupPath = $MACHINE_BACKUP
                    SharedBackupPath = $SHARED_BACKUP
                }
                $analysisResult = & Compare-PostRestoreApplications @params -ErrorAction Stop
                if ($analysisResult.Success) {
                    Write-Host "`n=== RESTORE COMPLETE - POST-RESTORE ANALYSIS ===" -ForegroundColor Yellow
                    Write-Host "Post-restore analysis saved to: $($analysisResult.BackupPath)" -ForegroundColor Green
                    
                    # Show summary if available
                    if ($analysisResult.Analysis -and $analysisResult.Analysis.Summary) {
                        $summary = $analysisResult.Analysis.Summary
                        Write-Host "`nFinal Application Restore Summary:" -ForegroundColor Green
                        Write-Host "  Original Unmanaged Apps: $($summary.OriginalUnmanagedApps)" -ForegroundColor White
                        Write-Host "  Successfully Restored: $($summary.RestoredApps)" -ForegroundColor Green
                        Write-Host "  Still Need Manual Install: $($summary.StillUnmanagedApps)" -ForegroundColor Red
                        Write-Host "  Restore Success Rate: $($summary.RestoreSuccessRate)%" -ForegroundColor Cyan
                        
                        if ($summary.StillUnmanagedApps -gt 0) {
                            Write-Host "`nIMPORTANT: Check the following files for applications that still need manual installation:" -ForegroundColor Yellow
                            Write-Host "  - still-unmanaged-apps.json: Technical details for scripts" -ForegroundColor Cyan
                            Write-Host "  - still-unmanaged-apps.csv: Excel-friendly format for review" -ForegroundColor Cyan
                            Write-Host "  - restored-apps.json: List of successfully restored applications" -ForegroundColor Green
                            Write-Host "`nThese applications were not restored by any package manager and must be installed manually." -ForegroundColor Yellow
                        } else {
                            Write-Host "`n🎉 CONGRATULATIONS: All originally unmanaged applications have been successfully restored!" -ForegroundColor Green
                            Write-Host "Check 'restored-apps.json' to see what was automatically restored." -ForegroundColor Cyan
                        }
                    }
                }
            } else {
                Write-Host "Compare-PostRestoreApplications function not found" -ForegroundColor Yellow
            }
        } else {
            Write-Host "Analysis script not found - skipping final post-restore analysis" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "Failed to run final post-restore applications analysis: $_" -ForegroundColor Red
    }
}

# Start system updates
Write-Host "`nStarting system updates..." -ForegroundColor Green 