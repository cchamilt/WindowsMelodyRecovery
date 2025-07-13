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
        [Parameter(Mandatory = $false)]
        [string]$TemplatePath,

        [Parameter(Mandatory = $false)]
        [string]$BackupRoot
    )

    # Get configuration
    $config = Get-WindowsMelodyRecovery
    if (-not $config -or -not $config.BackupRoot) {
        throw "Windows Melody Recovery is not initialized. Run Initialize-WindowsMelodyRecovery first."
    }

    # Set backup paths
    $BACKUP_ROOT = if ($BackupRoot) { $BackupRoot } else { $config.BackupRoot }
    $MACHINE_BACKUP_ROOT = Join-Path $BACKUP_ROOT $config.MachineName
    $SHARED_BACKUP = Join-Path $BACKUP_ROOT "shared"

    # Create timestamped backup directory
    $timestamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
    $backupId = "$timestamp-$([System.Guid]::NewGuid().ToString('N').Substring(0,8))"
    $MACHINE_BACKUP = Join-Path $MACHINE_BACKUP_ROOT $backupId

    # Create backup directories
    if (-not (Test-Path $MACHINE_BACKUP_ROOT)) {
        New-Item -ItemType Directory -Path $MACHINE_BACKUP_ROOT -Force | Out-Null
    }
    if (-not (Test-Path $MACHINE_BACKUP)) {
        New-Item -ItemType Directory -Path $MACHINE_BACKUP -Force | Out-Null
    }
    if (-not (Test-Path $SHARED_BACKUP)) {
        New-Item -ItemType Directory -Path $SHARED_BACKUP -Force | Out-Null
    }

    # Start logging
    $logPath = Join-Path $MACHINE_BACKUP "backup-log.txt"
    Start-Transcript -Path $logPath -Append

    Write-Information -MessageData "Starting Windows Melody Recovery backup..." -InformationAction Continue
    Write-Information -MessageData "Machine: $($config.MachineName)" -InformationAction Continue
    Write-Information -MessageData "Backup Path: $MACHINE_BACKUP" -InformationAction Continue
    Write-Information -MessageData "Backup ID: $backupId" -InformationAction Continue

    # Helper function to create manifest
    function New-BackupManifest {
        param(
            [string]$MachineName,
            [string]$BackupPath,
            [string]$BackupType,
            [string]$BackupId,
            [int]$ComponentCount,
            [string[]]$Components,
            [hashtable]$ComponentMetadata = @{}
        )

        $manifest = @{
            MachineName = $MachineName
            BackupType = $BackupType
            BackupId = $BackupId
            Timestamp = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss.fffffffK')
            CreatedDate = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss.fffffffK')
            BackupPath = $BackupPath
            ComponentCount = $ComponentCount
            Components = @()
            Templates = $Components
            ModuleVersion = "1.0.0"
            Version = "1.0"
        }

        # Add component metadata
        foreach ($component in $Components) {
            $componentDir = Join-Path $BackupPath $component
            $fileCount = 0
            if (Test-Path $componentDir) {
                $fileCount = (Get-ChildItem -Path $componentDir -Recurse -File -ErrorAction SilentlyContinue).Count
            }

            $manifest.Components += @{
                Name = $component
                Template = "$component.yaml"
                Files = $fileCount
                BackupPath = $componentDir
                Status = if ($fileCount -gt 0) { "Success" } else { "NoData" }
            }
        }

        $manifestPath = Join-Path $BackupPath "manifest.json"
        $manifest | ConvertTo-Json -Depth 3 | Set-Content -Path $manifestPath -Encoding UTF8
        return $manifestPath
    }

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
                $processedComponents = @()

                Write-Information -MessageData "Processing $totalTemplates templates..." -InformationAction Continue

                foreach ($templateFile in $templateFiles) {
                    try {
                        Write-Information -MessageData "Processing template: $($templateFile.Name)" -InformationAction Continue

                        # Create component-specific backup directory
                        $componentName = $templateFile.BaseName
                        $componentBackupDir = Join-Path $MACHINE_BACKUP $componentName

                        if (-not (Test-Path $componentBackupDir)) {
                            New-Item -ItemType Directory -Path $componentBackupDir -Force | Out-Null
                        }

                        Invoke-WmrTemplate -TemplatePath $templateFile.FullName -Operation "Backup" -StateFilesDirectory $componentBackupDir
                        $successfulTemplates++
                        $processedComponents += $componentName
                        Write-Information -MessageData "Template completed: $($templateFile.Name)" -InformationAction Continue
                    }
                    catch {
                        Write-Error -Message "Template failed: $($templateFile.Name) - $($_.Exception.Message)"
                    }
                }

                Write-Information -MessageData "Template backup completed: $successfulTemplates/$totalTemplates successful" -InformationAction Continue

                # Create backup manifest
                $manifestPath = New-BackupManifest -MachineName $config.MachineName -BackupPath $MACHINE_BACKUP -BackupType "Complete" -BackupId $backupId -ComponentCount $successfulTemplates -Components $processedComponents
                Write-Information -MessageData "Backup manifest created: $manifestPath" -InformationAction Continue

                return @{
                    Success = $successfulTemplates -gt 0
                    BackupCount = $successfulTemplates
                    BackupPath = $MACHINE_BACKUP
                    TotalTemplates = $totalTemplates
                    Method = "Templates"
                    ManifestPath = $manifestPath
                    BackupId = $backupId
                }
            }
            else {
                # Run single template
                $templateFullPath = if (Test-Path $TemplatePath) {
                    $TemplatePath
                }
                else {
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
                Write-Information -MessageData "Template backup completed successfully" -InformationAction Continue

                # Create backup manifest
                $manifestPath = New-BackupManifest -MachineName $config.MachineName -BackupPath $MACHINE_BACKUP -BackupType "Single" -BackupId $backupId -ComponentCount 1 -Components @($templateName)
                Write-Information -MessageData "Backup manifest created: $manifestPath" -InformationAction Continue

                return @{
                    Success = $true
                    BackupCount = 1
                    BackupPath = $componentBackupDir
                    Template = $templateName
                    Method = "Template"
                    ManifestPath = $manifestPath
                    BackupId = $backupId
                }
            }
        }
        else {
            # Default template backup
            $templateDir = Join-Path $PSScriptRoot "..\Templates\System"
            $templateFiles = Get-ChildItem -Path $templateDir -Filter "*.yaml" -ErrorAction SilentlyContinue

            if ($templateFiles) {
                $totalTemplates = $templateFiles.Count
                $successfulTemplates = 0
                $processedComponents = @()

                Write-Information -MessageData "Processing $totalTemplates templates..." -InformationAction Continue

                foreach ($templateFile in $templateFiles) {
                    try {
                        Write-Information -MessageData "Processing: $($templateFile.Name)" -InformationAction Continue

                        $componentName = $templateFile.BaseName
                        $componentBackupDir = Join-Path $MACHINE_BACKUP $componentName

                        if (-not (Test-Path $componentBackupDir)) {
                            New-Item -ItemType Directory -Path $componentBackupDir -Force | Out-Null
                        }

                        Invoke-WmrTemplate -TemplatePath $templateFile.FullName -Operation "Backup" -StateFilesDirectory $componentBackupDir
                        $successfulTemplates++
                        $processedComponents += $componentName
                        Write-Information -MessageData "Completed: $($templateFile.Name)" -InformationAction Continue
                    }
                    catch {
                        Write-Error -Message "Failed: $($templateFile.Name) - Error: $($_.Exception.Message)"
                        Write-Verbose -Message "Stack trace: $($_.ScriptStackTrace)"
                    }
                }

                Write-Information -MessageData "Backup completed: $successfulTemplates templates processed" -InformationAction Continue

                # Create backup manifest
                $manifestPath = New-BackupManifest -MachineName $config.MachineName -BackupPath $MACHINE_BACKUP -BackupType "Complete" -BackupId $backupId -ComponentCount $successfulTemplates -Components $processedComponents
                Write-Information -MessageData "Backup manifest created: $manifestPath" -InformationAction Continue

                return @{
                    Success = $successfulTemplates -gt 0
                    BackupCount = $successfulTemplates
                    BackupPath = $MACHINE_BACKUP
                    Method = "Templates"
                    ManifestPath = $manifestPath
                    BackupId = $backupId
                }
            }
            else {
                Write-Warning -Message "No templates found, using script-based backup"

                # Fallback to script-based backup
                Import-PrivateScript -Category 'backup'

                $backupFunctions = Get-ScriptsConfig -Category 'backup'
                if (-not $backupFunctions) {
                    $backupFunctions = @(
                        @{ name = "Applications"; function = "Backup-Applications"; enabled = $true }
                    )
                }

                $availableBackups = 0
                $scriptComponents = @()
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
                            $scriptComponents += $backup.name
                            Write-Information -MessageData "Executed: $($backup.function)" -InformationAction Continue
                        }
                        catch {
                            Write-Error -Message "Failed: $($backup.function)"
                        }
                    }
                }

                Write-Information -MessageData "Script backup completed: $availableBackups functions executed" -InformationAction Continue

                # Create backup manifest
                $manifestPath = New-BackupManifest -MachineName $config.MachineName -BackupPath $MACHINE_BACKUP -BackupType "Script" -BackupId $backupId -ComponentCount $availableBackups -Components $scriptComponents
                Write-Information -MessageData "Backup manifest created: $manifestPath" -InformationAction Continue

                return @{
                    Success = $availableBackups -gt 0
                    BackupCount = $availableBackups
                    BackupPath = $MACHINE_BACKUP
                    Method = "Scripts"
                    ManifestPath = $manifestPath
                    BackupId = $backupId
                }
            }
        }
    }
    finally {
        Stop-Transcript
    }
}









