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
        Write-Warning -Message "Configuration not initialized. Please run Initialize-WindowsMelodyRecovery first."
        return
    }

    # Start transcript for logging
    Start-Transcript -Path (Join-Path $logPath "Restore-WindowsMelodyRecovery-$(Get-Date -Format 'yyyyMMdd_HHmmss').log") -Append -Force

    try {
        Write-Information -MessageData "Starting Windows Melody Recovery Restore..." -InformationAction Continue

        # Define proper backup paths using config values
        $BACKUP_ROOT = $config.BackupRoot
        $MACHINE_NAME = $config.MachineName
        $MACHINE_BACKUP = Join-Path $BACKUP_ROOT $MACHINE_NAME
        $SHARED_BACKUP = Join-Path $BACKUP_ROOT "shared"

        # Ensure necessary backup directories exist (for consistency, though restore might not create them)
        if (-not (Test-Path -Path $MACHINE_BACKUP -PathType Container)) {
            Write-Warning -Message "Machine backup directory does not exist: $MACHINE_BACKUP"
        }
        if (-not (Test-Path -Path $SHARED_BACKUP -PathType Container)) {
            Write-Warning -Message "Shared backup directory does not exist: $SHARED_BACKUP"
        }

        if ($PSCmdlet.MyInvocation.BoundParameters.ContainsKey('TemplatePath')) {
            # New template-based restore logic
            Write-Information -MessageData "Performing template-based restore using template: $TemplatePath from $RestoreFromDirectory" -InformationAction Continue

            # Validate that the restore directory exists
            if (-not (Test-Path $RestoreFromDirectory -PathType Container)) {
                throw "Restore directory not found: $RestoreFromDirectory"
            }

            # Dot-source the InvokeWmrTemplate module
            . (Join-Path $PSScriptRoot "..\Private\Core\InvokeWmrTemplate.ps1")

            Invoke-WmrTemplate -TemplatePath $TemplatePath -Operation "Restore" -StateFilesDirectory $RestoreFromDirectory
            Write-Information -MessageData "Template-based restore operation completed successfully." -InformationAction Continue

        } else {
            # Original script-based restore logic
            Write-Information -MessageData "Performing script-based restore..." -InformationAction Continue

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
                    Write-Information -MessageData "Using machine-specific $BackupType backup from: $machinePath" -InformationAction Continue
                    return $machinePath
                }

                # Fall back to shared backup
                $sharedPath = Join-Path $SHARED_BACKUP $Path
                if (Test-Path $sharedPath) {
                    Write-Information -MessageData "Using shared $BackupType backup from: $sharedPath" -InformationAction Continue
                    return $sharedPath
                }

                Write-Warning -Message "No $BackupType backup found"
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
                        Write-Error -Message "Failed to execute $($restore.function) : $_"
                    }
                } else {
                    Write-Verbose "Restore function $($restore.function) not available"
                }
            }

            if ($availableRestores -eq 0) {
                Write-Warning -Message "No restore functions were found. Check that restore scripts exist in the Private\restore directory."
            } else {
                Write-Information -MessageData "Script-based restoration completed! ($availableRestores functions executed)" -InformationAction Continue

                # Run final post-restore applications analysis
                Write-Information -MessageData "`nRunning final post-restore applications analysis..." -InformationAction Continue
                try {
                    $modulePath = (Get-Module -Name WindowsMelodyRecovery -ErrorAction SilentlyContinue).Path | Split-Path
                    $analyzeScript = Join-Path $modulePath "Private\backup\Find-UnmanagedApplication.ps1"
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
                                Write-Warning -Message "`n=== RESTORE COMPLETE - POST-RESTORE ANALYSIS ==="
                                Write-Information -MessageData "Post-restore analysis saved to: $($analysisResult.BackupPath)" -InformationAction Continue

                                # Show summary if available
                                if ($analysisResult.Analysis -and $analysisResult.Analysis.Summary) {
                                    $summary = $analysisResult.Analysis.Summary
                                    Write-Information -MessageData "`nFinal Application Restore Summary:" -InformationAction Continue
                                    Write-Information -MessageData "  Original Unmanaged Apps: $($summary.OriginalUnmanagedApps)"  -InformationAction Continue-ForegroundColor White
                                    Write-Information -MessageData "  Successfully Restored: $($summary.RestoredApps)" -InformationAction Continue
                                    Write-Error -Message "  Still Need Manual Install: $($summary.StillUnmanagedApps)"
                                    Write-Information -MessageData "  Restore Success Rate: $($summary.RestoreSuccessRate)%" -InformationAction Continue

                                    if ($summary.StillUnmanagedApps -gt 0) {
                                        Write-Warning -Message "`nIMPORTANT: Check the following files for applications that still need manual installation:"
                                        Write-Information -MessageData "  - still-unmanaged-apps.json: Technical details for scripts" -InformationAction Continue
                                        Write-Information -MessageData "  - still-unmanaged-apps.csv: Excel-friendly format for review" -InformationAction Continue
                                        Write-Information -MessageData "  - restored-apps.json: List of successfully restored applications" -InformationAction Continue
                                        Write-Warning -Message "`nThese applications were not restored by any package manager and must be installed manually."
                                    } else {
                                        Write-Information -MessageData "`n🎉 CONGRATULATIONS: All originally unmanaged applications have been successfully restored!" -InformationAction Continue
                                        Write-Information -MessageData "Check 'restored-apps.json' to see what was automatically restored." -InformationAction Continue
                                    }
                                }
                            }
                        } else {
                            Write-Warning -Message "Compare-PostRestoreApplications function not found"
                        }
                    } else {
                        Write-Warning -Message "Analysis script not found - skipping final post-restore analysis"
                    }
                } catch {
                    Write-Error -Message "Failed to run final post-restore applications analysis: $_"
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







