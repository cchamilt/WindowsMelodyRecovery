# Private/Core/InvokeWmrTemplate.ps1

# Requires:
#   - Private/Core/PathUtilities.ps1 (for Convert-WmrPath)
#   - Private/Core/WindowsMelodyRecovery.Template.psm1 (for Read-WmrTemplateConfig, Test-WmrTemplateSchema)
#   - Private/Core/Prerequisites.ps1 (for Test-WmrPrerequisites)
#   - Private/Core/FileState.ps1 (for Get-WmrFileState, Set-WmrFileState)
#   - Private/Core/RegistryState.ps1 (for Get-WmrRegistryState, Set-WmrRegistryState)
#   - Private/Core/ApplicationState.ps1 (for Get-WmrApplicationState, Set-WmrApplicationState, Uninstall-WmrApplicationState)
#   - Private/Core/EncryptionUtilities.ps1 (for Protect-WmrData, Unprotect-WmrData) - implicitly used by state functions
#   - Private/Core/TemplateInheritance.ps1 (for template inheritance processing)

function Invoke-WmrTemplate {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TemplatePath,

        [Parameter(Mandatory = $true)]
        [ValidateSet("Backup", "Restore", "Sync", "Uninstall")]
        [string]$Operation,

        [Parameter(Mandatory = $true)]
        [string]$StateFilesDirectory # Base directory for storing/reading dynamic state files
    )

    Write-Information -MessageData "Invoking template: $TemplatePath for $Operation operation..." -InformationAction Continue
    if ($WhatIfPreference) {
        Write-Warning -Message "*** RUNNING IN WHATIF MODE - NO ACTUAL CHANGES WILL BE MADE ***" -BackgroundColor DarkRed
    }

    # 1. Import necessary modules/functions
    try {
        # Dot-source PowerShell scripts (they contain Export-ModuleMember which fails when imported as modules)
        . (Join-Path $PSScriptRoot "PathUtilities.ps1")
        . (Join-Path $PSScriptRoot "Prerequisites.ps1")
        . (Join-Path $PSScriptRoot "FileState.ps1")
        . (Join-Path $PSScriptRoot "RegistryState.ps1")
        . (Join-Path $PSScriptRoot "ApplicationState.ps1")
        . (Join-Path $PSScriptRoot "EncryptionUtilities.ps1")

        # Import the actual PowerShell module
        Import-Module (Join-Path $PSScriptRoot "WindowsMelodyRecovery.Template.psm1") -Force
    }
 catch {
        throw "Failed to load required core modules: $($_.Exception.Message)"
    }

    # 2. Read and validate the template configuration
    $templateConfig = $null
    try {
        $templateConfig = Read-WmrTemplateConfig -TemplatePath $TemplatePath
        Test-WmrTemplateSchema -TemplateConfig $templateConfig

        # Check if template uses inheritance features
        $usesInheritance = $templateConfig.shared -or $templateConfig.machine_specific -or $templateConfig.inheritance_rules -or $templateConfig.conditional_sections

        if ($usesInheritance) {
            Write-Warning -Message "Template uses inheritance features - resolving configuration..."

            # Import inheritance processing module
            . (Join-Path $PSScriptRoot "TemplateInheritance.ps1")

            # Get machine context for inheritance resolution
            $machineContext = Get-WmrMachineContext

            # Resolve template inheritance
            $templateConfig = Resolve-WmrTemplateInheritance -TemplateConfig $templateConfig -MachineContext $machineContext

            Write-Information -MessageData "Template inheritance resolved successfully" -InformationAction Continue
        }
    }
 catch {
        throw "Template validation failed: $($_.Exception.Message)"
    }

    # 3. Create template-scoped state directory
    # Extract template name from path and create scoped directory
    $templateName = [System.IO.Path]::GetFileNameWithoutExtension($TemplatePath)
    $templateStateDirectory = Join-Path $StateFilesDirectory $templateName

    # Ensure the template's scoped state directory exists
    if (-not (Test-Path $templateStateDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $templateStateDirectory -Force | Out-Null
        Write-Information -MessageData "Created template state directory: $templateStateDirectory" -InformationAction Continue
    }

    # 4. Check prerequisites
    try {
        if (-not (Test-WmrPrerequisites -TemplateConfig $templateConfig -Operation $Operation)) {
            throw "Prerequisites not met for $Operation operation. Aborting."
        }
    }
 catch {
        throw "Prerequisite check failed: $($_.Exception.Message)"
    }

    # 5. Execute pre-update stages (if applicable)
    if ($templateConfig.stages.prereqs -and ($Operation -eq "Restore" -or $Operation -eq "Sync")) {
        Write-Information -MessageData "Running pre-update stages..." -InformationAction Continue
        foreach ($stageItem in $templateConfig.stages.prereqs) {
            Invoke-WmrStageItem -StageItem $stageItem -Operation $Operation
        }
    }

    # 6. Process files, registry, and applications based on operation
    if ($Operation -eq "Backup" -or $Operation -eq "Sync") {
        Write-Information -MessageData "Performing backup/sync operations..." -InformationAction Continue
        if ($templateConfig.files) {
            foreach ($file in $templateConfig.files) {
                if ($file.action -eq "backup" -or $file.action -eq "sync") {
                    Get-WmrFileState -FileConfig $file -StateFilesDirectory $templateStateDirectory -WhatIf:$WhatIfPreference
                }
            }
        }
        if ($templateConfig.registry) {
            foreach ($reg in $templateConfig.registry) {
                if ($reg.action -eq "backup" -or $reg.action -eq "sync") {
                    Get-WmrRegistryState -RegistryConfig $reg -StateFilesDirectory $templateStateDirectory -WhatIf:$WhatIfPreference
                }
            }
        }
        if ($templateConfig.applications) {
            foreach ($app in $templateConfig.applications) {
                Get-WmrApplicationState -AppConfig $app -StateFilesDirectory $templateStateDirectory -WhatIf:$WhatIfPreference
            }
        }
    }

    if ($Operation -eq "Restore" -or $Operation -eq "Sync") {
        Write-Information -MessageData "Performing restore/sync operations..." -InformationAction Continue
        if ($templateConfig.files) {
            foreach ($file in $templateConfig.files) {
                if ($file.action -eq "restore" -or $file.action -eq "sync") {
                    Set-WmrFileState -FileConfig $file -StateFilesDirectory $templateStateDirectory -WhatIf:$WhatIfPreference
                }
            }
        }
        if ($templateConfig.registry) {
            foreach ($reg in $templateConfig.registry) {
                if ($reg.action -eq "restore" -or $reg.action -eq "sync") {
                    Set-WmrRegistryState -RegistryConfig $reg -StateFilesDirectory $templateStateDirectory -WhatIf:$WhatIfPreference
                }
            }
        }
        if ($templateConfig.applications) {
            foreach ($app in $templateConfig.applications) {
                Set-WmrApplicationState -AppConfig $app -StateFilesDirectory $templateStateDirectory -WhatIf:$WhatIfPreference
            }
        }
    }

    if ($Operation -eq "Uninstall") {
        Write-Information -MessageData "Performing uninstall operations..." -InformationAction Continue
        if ($templateConfig.applications) {
            foreach ($app in $templateConfig.applications) {
                Uninstall-WmrApplicationState -AppConfig $app -StateFilesDirectory $templateStateDirectory -WhatIf:$WhatIfPreference
            }
        }
    }

    # 7. Execute post-update stages (if applicable)
    if ($templateConfig.stages.post_update -and ($Operation -eq "Restore" -or $Operation -eq "Sync")) {
        Write-Information -MessageData "Running post-update stages..." -InformationAction Continue
        foreach ($stageItem in $templateConfig.stages.post_update) {
            Invoke-WmrStageItem -StageItem $stageItem -Operation $Operation
        }
    }

    # 8. Execute cleanup stages (if applicable)
    if ($templateConfig.stages.cleanup) {
        Write-Information -MessageData "Running cleanup stages..." -InformationAction Continue
        foreach ($stageItem in $templateConfig.stages.cleanup) {
            Invoke-WmrStageItem -StageItem $stageItem -Operation $Operation
        }
    }

    Write-Information -MessageData "Template invocation completed for $Operation operation." -InformationAction Continue
}

function Invoke-WmrStageItem {
    param(
        [Parameter(Mandatory = $true)]
        [PSObject]$StageItem,

        [Parameter(Mandatory = $true)]
        [string]$Operation
    )

    Write-Information -MessageData "    Executing stage item: $($StageItem.name) (Type: $($StageItem.type))" -InformationAction Continue

    try {
        $scriptOutput = ""
        if ($StageItem.type -eq "script") {
            if ($StageItem.path) {
                $scriptOutput = & $StageItem.path $StageItem.parameters
            }
 elseif ($StageItem.inline_script) {
                $scriptBlock = [ScriptBlock]::Create($StageItem.inline_script)
                $scriptOutput = & $scriptBlock $StageItem.parameters
            }
        }

        if ($StageItem.type -eq "check") {
            if ($StageItem.path) {
                $scriptOutput = & $StageItem.path $StageItem.parameters
            }
 elseif ($StageItem.inline_script) {
                $scriptBlock = [ScriptBlock]::Create($StageItem.inline_script)
                $scriptOutput = & $scriptBlock $StageItem.parameters
            }
            if ($scriptOutput -notmatch $StageItem.expected_output) {
                throw "Check `'$($StageItem.name)`' failed. Expected output did not match. Output: `n$scriptOutput`n"
            }
        }
        Write-Information -MessageData "    Stage item `'$($StageItem.name)`' completed successfully." -InformationAction Continue
    }
 catch {
        Write-Warning "    Stage item `'$($StageItem.name)`' failed: $($_.Exception.Message)"
        # Depending on severity, we might want to throw here to stop the whole process.
        # For now, it's a warning, but a robust implementation might have `on_fail` policy for stages.
    }
}

# Functions are available via dot-sourcing - no Export-ModuleMember needed
# Available functions: Invoke-WmrTemplate, Invoke-WmrStageItem







