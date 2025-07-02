function Backup-WindowsMelodyRecovery {
    <#
    .SYNOPSIS
    Backs up Windows system configuration and settings.
    
    .DESCRIPTION
    This function performs backup operations using either the new template system or legacy backup scripts.
    The template system provides better consistency and maintainability.
    
    .PARAMETER TemplatePath
    Optional path to a specific YAML template file, or "ALL" to run all templates.
    If not specified, uses legacy script-based backup system.
    Examples: "display.yaml", "ssh.yaml", "ALL", "C:\path\to\custom.yaml"
    
    .EXAMPLE
    Backup-WindowsMelodyRecovery
    Runs legacy script-based backup of all configured components.
    
    .EXAMPLE  
    Backup-WindowsMelodyRecovery -TemplatePath "display.yaml"
    Backs up display settings using the template system.
    
    .EXAMPLE
    Backup-WindowsMelodyRecovery -TemplatePath "ALL"
    Backs up all components using all available templates.
    #>
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
    $logPath = Join-Path $config.BackupRoot "Logs"
    if (-not (Test-Path $logPath)) {
        New-Item -ItemType Directory -Path $logPath -Force | Out-Null
    }
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

            # Dot-source the InvokeWmrTemplate module
            . (Join-Path $PSScriptRoot "..\Private\Core\InvokeWmrTemplate.ps1")

            if ($TemplatePath -eq "ALL") {
                # Run all available templates
                Write-Host "Running all available templates..." -ForegroundColor Cyan
                $templatesPath = Join-Path $PSScriptRoot "..\Templates\System"
                $templateFiles = Get-ChildItem -Path $templatesPath -Filter "*.yaml" -ErrorAction SilentlyContinue
                
                $successfulTemplates = 0
                $totalTemplates = $templateFiles.Count
                
                foreach ($templateFile in $templateFiles) {
                    try {
                        Write-Host "  Processing template: $($templateFile.Name)" -ForegroundColor Cyan
                        
                        # Create component-specific backup directory
                        $componentName = $templateFile.BaseName
                        $componentBackupDir = Join-Path $MACHINE_BACKUP $componentName
                        
                        if (-not (Test-Path $componentBackupDir)) {
                            New-Item -ItemType Directory -Path $componentBackupDir -Force | Out-Null
                        }
                        
                        Invoke-WmrTemplate -TemplatePath $templateFile.FullName -Operation "Backup" -StateFilesDirectory $componentBackupDir
                        $successfulTemplates++
                        Write-Host "    ✓ $($templateFile.Name) completed successfully" -ForegroundColor Green
                    } catch {
                        Write-Host "    ✗ $($templateFile.Name) failed: $($_.Exception.Message)" -ForegroundColor Red
                    }
                }
                
                Write-Host "Template-based backup completed: $successfulTemplates/$totalTemplates templates successful" -ForegroundColor Green
                return @{
                    Success = $successfulTemplates -gt 0
                    BackupCount = $successfulTemplates
                    BackupPath = $MACHINE_BACKUP
                    TotalTemplates = $totalTemplates
                    Method = "Templates"
                }
            } else {
                # Run single template
                $templateFullPath = if (Test-Path $TemplatePath) { 
                    $TemplatePath 
                } else { 
                    Join-Path $PSScriptRoot "..\Templates\System\$TemplatePath"
                }
                
                if (-not (Test-Path $templateFullPath)) {
                    throw "Template file not found: $templateFullPath"
                }
                
                # Create component-specific backup directory
                $templateName = (Get-Item $templateFullPath).BaseName
                $componentBackupDir = Join-Path $MACHINE_BACKUP $templateName
                
                if (-not (Test-Path $componentBackupDir)) {
                    New-Item -ItemType Directory -Path $componentBackupDir -Force | Out-Null
                }

                Invoke-WmrTemplate -TemplatePath $templateFullPath -Operation "Backup" -StateFilesDirectory $componentBackupDir
                Write-Host "Template-based backup operation completed successfully."
                
                return @{
                    Success = $true
                    BackupCount = 1
                    BackupPath = $componentBackupDir
                    Template = $templateName
                    Method = "Template"
                }
            }

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
                            Write-Host "`n=== BACKUP COMPLETE - POST-BACKUP ANALYSIS ===" -ForegroundColor Yellow
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

    # Return results (only reached for script-based backups)
    return @{
        Success = $availableBackups -gt 0
        BackupCount = $availableBackups
        BackupPath = $MACHINE_BACKUP
        Method = "Scripts"
    }
}

