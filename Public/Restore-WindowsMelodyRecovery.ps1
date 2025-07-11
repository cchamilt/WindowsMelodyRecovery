function Restore-WindowsMelodyRecovery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$TemplatePath,

        [Parameter(Mandatory=$false)]
        [string]$RestoreFromDirectory # The directory containing the state files from a previous backup
    )

    # Get configuration from the module
    $config = Get-WindowsMelodyRecovery
    if (!$config.BackupRoot) {
        Write-Host "Configuration not initialized. Please run Initialize-WindowsMelodyRecovery first." -ForegroundColor Yellow
        return
    }

    # Start transcript for logging
    Start-Transcript -Path (Join-Path $logPath "Restore-WindowsMelodyRecovery-$(Get-Date -Format 'yyyyMMdd_HHmmss').log") -Append -Force

    try {
        Write-Host "Starting Windows Melody Recovery Restore..." -ForegroundColor Cyan

        # Define proper backup paths using config values
        $BACKUP_ROOT = $config.BackupRoot
        $MACHINE_NAME = $config.MachineName
        $MACHINE_BACKUP = Join-Path $BACKUP_ROOT $MACHINE_NAME
        $SHARED_BACKUP = Join-Path $BACKUP_ROOT "shared"

        # Ensure necessary backup directories exist (for consistency, though restore might not create them)
        if (-not (Test-Path -Path $MACHINE_BACKUP -PathType Container)) {
            Write-Host "Machine backup directory does not exist: $MACHINE_BACKUP" -ForegroundColor Yellow
        }
        if (-not (Test-Path -Path $SHARED_BACKUP -PathType Container)) {
            Write-Host "Shared backup directory does not exist: $SHARED_BACKUP" -ForegroundColor Yellow
        }

        if ($PSCmdlet.MyInvocation.BoundParameters.ContainsKey('TemplatePath')) {
            # New template-based restore logic
            Write-Host "Performing template-based restore using template: $TemplatePath from $RestoreFromDirectory"

            # Validate that the restore directory exists
            if (-not (Test-Path $RestoreFromDirectory -PathType Container)) {
                throw "Restore directory not found: $RestoreFromDirectory"
            }

            # Dot-source the InvokeWmrTemplate module
            . (Join-Path $PSScriptRoot "..\Private\Core\InvokeWmrTemplate.ps1")

            Invoke-WmrTemplate -TemplatePath $TemplatePath -Operation "Restore" -StateFilesDirectory $RestoreFromDirectory
            Write-Host "Template-based restore operation completed successfully."

        } else {
            # Original script-based restore logic
            Write-Host "Performing script-based restore..."

            # Load restore scripts on demand
            Import-PrivateScripts -Category 'restore'

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

            $restoreFunctions = Get-ScriptsConfig -Category 'restore'

            if (-not $restoreFunctions) {
                Write-Warning "No restore configuration found. Using fallback minimal list."
                $restoreFunctions = @(
                    @{ name = "Applications"; function = "Restore-Applications"; script = "restore-applications.ps1"; enabled = $true; required = $true }
                )
            }

            $availableRestores = 0

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
                Write-Host "Script-based restoration completed! ($availableRestores functions executed)" -ForegroundColor Green

                # Run final post-restore applications analysis
                Write-Host "`nRunning final post-restore applications analysis..." -ForegroundColor Blue
                try {
                    $modulePath = (Get-Module -Name WindowsMelodyRecovery -ErrorAction SilentlyContinue).Path | Split-Path
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
        }
    } finally {
        Stop-Transcript
    }

    # Return results
    return @{
        Success = $true # Placeholder, actual success will depend on template invocation or script execution
        RestoreCount = $availableRestores # This will only be accurate for script-based restore
        BackupPath = $MACHINE_BACKUP # This will be the machine backup path for script-based, or relevant template path for template-based
    }
}