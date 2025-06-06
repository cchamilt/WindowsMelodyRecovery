function Restore-WindowsMissingRecovery {
    [CmdletBinding()]
    param()

    # Get configuration from the module
    $config = Get-WindowsMissingRecovery
    if (!$config.BackupRoot) {
        Write-Host "Configuration not initialized. Please run Initialize-WindowsMissingRecovery first." -ForegroundColor Yellow
        return
    }

    # Load restore scripts on demand
    Import-PrivateScripts -Category 'restore'

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

# Load restore configuration from configurable scripts list
$restoreFunctions = Get-ScriptsConfig -Category 'restore'

if (-not $restoreFunctions) {
    Write-Warning "No restore configuration found. Using fallback minimal list."
    # Fallback to minimal essential restores
    $restoreFunctions = @(
        @{ name = "Applications"; function = "Restore-Applications"; script = "restore-applications.ps1"; enabled = $true; required = $true }
    )
}

$availableRestores = 0

# Check which restore functions are available and run them
foreach ($restore in $restoreFunctions) {
    if (Get-Command $restore.function -ErrorAction SilentlyContinue) {
        try {
            $params = @{
                BackupRootPath = $MACHINE_BACKUP
                MachineBackupPath = $MACHINE_BACKUP
                SharedBackupPath = $SHARED_BACKUP
            }
            & $restore.function @params
            $availableRestores++
            Write-Verbose "Successfully executed $($restore.function)"
        } catch {
            Write-Host "Failed to execute $($restore.function) : $_" -ForegroundColor Red
        }
    } else {
        Write-Verbose "Restore function $($restore.function) not available"
    }
}

if ($availableRestores -eq 0) {
    Write-Host "No restore functions were found. Check that restore scripts exist in the Private\restore directory." -ForegroundColor Yellow
} else {
    Write-Host "Settings restoration completed! ($availableRestores functions executed)" -ForegroundColor Green
    
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

    # Return results
    return @{
        Success = $availableRestores -gt 0
        RestoreCount = $availableRestores
        BackupPath = $MACHINE_BACKUP
    }
}