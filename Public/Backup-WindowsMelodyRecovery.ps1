function Backup-WindowsMelodyRecovery {
    <#
    .SYNOPSIS
        Backs up Windows system configuration and applications using templates.

    .DESCRIPTION
        Performs a comprehensive backup of Windows system settings, applications, and configurations
        using the Windows Melody Recovery template system.

    .PARAMETER TemplatePath
        Specific template to run. Use "ALL" to run all templates.

    .PARAMETER BackupRoot
        Override the default backup root path.

    .EXAMPLE
        Backup-WindowsMelodyRecovery

    .EXAMPLE
        Backup-WindowsMelodyRecovery -TemplatePath "ALL"

    .EXAMPLE
        Backup-WindowsMelodyRecovery -TemplatePath "applications.yaml"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$TemplatePath,

        [Parameter(Mandatory=$false)]
        [string]$BackupRoot
    )

    # Get configuration
    $config = Get-WindowsMelodyRecovery
    if (-not $config -or -not $config.BackupRoot) {
        throw "Windows Melody Recovery is not initialized. Run Initialize-WindowsMelodyRecovery first."
    }

    # Set backup paths
    $BACKUP_ROOT = if ($BackupRoot) { $BackupRoot } else { $config.BackupRoot }
    $MACHINE_BACKUP = Join-Path $BACKUP_ROOT $config.MachineName
    $SHARED_BACKUP = Join-Path $BACKUP_ROOT "shared"

    # Create backup directories
    if (-not (Test-Path $MACHINE_BACKUP)) {
        New-Item -ItemType Directory -Path $MACHINE_BACKUP -Force | Out-Null
    }
    if (-not (Test-Path $SHARED_BACKUP)) {
        New-Item -ItemType Directory -Path $SHARED_BACKUP -Force | Out-Null
    }

    # Start logging
    $logPath = Join-Path $MACHINE_BACKUP "backup-log.txt"
    Start-Transcript -Path $logPath -Append

    Write-Host "Starting Windows Melody Recovery backup..." -ForegroundColor Green
    Write-Host "Machine: $($config.MachineName)" -ForegroundColor Cyan
    Write-Host "Backup Path: $MACHINE_BACKUP" -ForegroundColor Cyan

    try {
        # Use template-based backup
        if ($PSCmdlet.MyInvocation.BoundParameters.ContainsKey('TemplatePath')) {
            if ($TemplatePath -eq "ALL") {
                # Run all templates
                $templateDir = Join-Path $PSScriptRoot "..\Templates\System"
                $templateFiles = Get-ChildItem -Path $templateDir -Filter "*.yaml" -ErrorAction SilentlyContinue

                if (-not $templateFiles) {
                    throw "No template files found in $templateDir"
                }

                $totalTemplates = $templateFiles.Count
                $successfulTemplates = 0

                Write-Host "Processing $totalTemplates templates..." -ForegroundColor Blue

                foreach ($templateFile in $templateFiles) {
                    try {
                        Write-Host "Processing template: $($templateFile.Name)" -ForegroundColor Cyan

                        # Create component-specific backup directory
                        $componentName = $templateFile.BaseName
                        $componentBackupDir = Join-Path $MACHINE_BACKUP $componentName

                        if (-not (Test-Path $componentBackupDir)) {
                            New-Item -ItemType Directory -Path $componentBackupDir -Force | Out-Null
                        }

                        Invoke-WmrTemplate -TemplatePath $templateFile.FullName -Operation "Backup" -StateFilesDirectory $componentBackupDir
                        $successfulTemplates++
                        Write-Host "Template completed: $($templateFile.Name)" -ForegroundColor Green
                    } catch {
                        Write-Host "Template failed: $($templateFile.Name) - $($_.Exception.Message)" -ForegroundColor Red
                    }
                }

                Write-Host "Template backup completed: $successfulTemplates/$totalTemplates successful" -ForegroundColor Green
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
                Write-Host "Template backup completed successfully" -ForegroundColor Green

                return @{
                    Success = $true
                    BackupCount = 1
                    BackupPath = $componentBackupDir
                    Template = $templateName
                    Method = "Template"
                }
            }
        } else {
            # Default template backup
            $templateDir = Join-Path $PSScriptRoot "..\Templates\System"
            $templateFiles = Get-ChildItem -Path $templateDir -Filter "*.yaml" -ErrorAction SilentlyContinue

            if ($templateFiles) {
                $totalTemplates = $templateFiles.Count
                $successfulTemplates = 0

                Write-Host "Processing $totalTemplates templates..." -ForegroundColor Blue

                foreach ($templateFile in $templateFiles) {
                    try {
                        Write-Host "Processing: $($templateFile.Name)" -ForegroundColor Cyan

                        $componentName = $templateFile.BaseName
                        $componentBackupDir = Join-Path $MACHINE_BACKUP $componentName

                        if (-not (Test-Path $componentBackupDir)) {
                            New-Item -ItemType Directory -Path $componentBackupDir -Force | Out-Null
                        }

                        Invoke-WmrTemplate -TemplatePath $templateFile.FullName -Operation "Backup" -StateFilesDirectory $componentBackupDir
                        $successfulTemplates++
                        Write-Host "Completed: $($templateFile.Name)" -ForegroundColor Green
                    } catch {
                        Write-Host "Failed: $($templateFile.Name)" -ForegroundColor Red
                    }
                }

                Write-Host "Backup completed: $successfulTemplates templates processed" -ForegroundColor Green
                return @{
                    Success = $successfulTemplates -gt 0
                    BackupCount = $successfulTemplates
                    BackupPath = $MACHINE_BACKUP
                    Method = "Templates"
                }
            } else {
                Write-Host "No templates found, using script-based backup" -ForegroundColor Yellow

                # Fallback to script-based backup
                Import-PrivateScripts -Category 'backup'

                $backupFunctions = Get-ScriptsConfig -Category 'backup'
                if (-not $backupFunctions) {
                    $backupFunctions = @(
                        @{ name = "Applications"; function = "Backup-Applications"; enabled = $true }
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
                            Write-Host "Executed: $($backup.function)" -ForegroundColor Green
                        } catch {
                            Write-Host "Failed: $($backup.function)" -ForegroundColor Red
                        }
                    }
                }

                Write-Host "Script backup completed: $availableBackups functions executed" -ForegroundColor Green
                return @{
                    Success = $availableBackups -gt 0
                    BackupCount = $availableBackups
                    BackupPath = $MACHINE_BACKUP
                    Method = "Scripts"
                }
            }
        }
    } finally {
        Stop-Transcript
    }
}

