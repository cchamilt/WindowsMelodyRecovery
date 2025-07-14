# Private/Core/TemplateInheritance.ps1

<#
.SYNOPSIS
    Template inheritance processing functions for Windows Melody Recovery.

.DESCRIPTION
    Provides functions to process template inheritance, including shared vs machine-specific
    configuration merging, conditional sections, and inheritance rules.

    This module serves as the main entry point for template inheritance functionality,
    importing and re-exporting functions from specialized modules for better maintainability.

.NOTES
    Author: Windows Melody Recovery
    Version: 2.0
    Requires: PowerShell 5.1 or later
#>

# Import dependencies
Import-Module WindowsMelodyRecovery -ErrorAction Stop

function Resolve-WmrTemplateInheritance {
    <#
    .SYNOPSIS
        Resolves the inheritance hierarchy for a given template.

    .DESCRIPTION
        This function processes the inheritance rules and merges configurations
        based on the template's inheritance structure.

    .PARAMETER TemplatePath
        The path to the template file.

    .PARAMETER MachineContext
        A hashtable containing the machine context information.

    .PARAMETER InheritanceConfiguration
        A hashtable containing the inheritance rules and configuration.

    .PARAMETER OutputPath
        The path where the resolved configuration will be saved.

    .PARAMETER Force
        If true, overwrites the output file if it exists.

    .PARAMETER Debug
        If true, enables debug output.

    .PARAMETER Verbose
        If true, enables verbose output.

    .PARAMETER WhatIf
        If true, shows what would happen without actually changing anything.

    .PARAMETER Confirm
        If true, asks for confirmation before overwriting.

    .EXAMPLE
        Resolve-WmrTemplateInheritance -TemplatePath "C:\Templates\MyTemplate.xml" -MachineContext $machineContext -InheritanceConfiguration $inheritanceConfig -OutputPath "C:\ResolvedConfig\MyResolvedConfig.xml" -Force $true -Debug $true -Verbose $true -WhatIf $false -Confirm $true

    .NOTES
        This function is the main entry point for template inheritance processing.
        It calls various specialized modules to perform the actual work.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$TemplatePath,

        [Parameter(Mandatory = $true)]
        [hashtable]$MachineContext,

        [Parameter(Mandatory = $true)]
        [hashtable]$InheritanceConfiguration,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath,

        [Parameter(Mandatory = $false)]
        [switch]$Force
    )

    # Validate template path
    if (-not (Test-Path $TemplatePath)) {
        Write-Error "Template file not found at $TemplatePath"
        return
    }

    # Validate output path
    if (Test-Path $OutputPath -PathType Container) {
        if ($Force) {
            Remove-Item -Path $OutputPath -Recurse -Force -WhatIf:$WhatIf -Confirm:$Confirm
        }
        else {
            Write-Error "Output directory already exists at $OutputPath. Use -Force to overwrite."
            return
        }
    }

    # Get template resolution
    $templateResolution = Get-WmrTemplateResolution -TemplatePath $TemplatePath -Debug:$Debug -Verbose:$Verbose -WhatIf:$WhatIf -Confirm:$Confirm
    if ($null -eq $templateResolution) {
        Write-Error "Failed to resolve template at $TemplatePath"
        return
    }

    # Get machine context
    $machineContext = Get-WmrMachineContext -MachineContext $MachineContext -Debug:$Debug -Verbose:$Verbose -WhatIf:$WhatIf -Confirm:$Confirm
    if ($null -eq $machineContext) {
        Write-Error "Failed to get machine context"
        return
    }

    # Get inheritance configuration
    $inheritanceConfig = Get-WmrInheritanceConfiguration -InheritanceConfiguration $InheritanceConfiguration -Debug:$Debug -Verbose:$Verbose -WhatIf:$WhatIf -Confirm:$Confirm
    if ($null -eq $inheritanceConfig) {
        Write-Error "Failed to get inheritance configuration"
        return
    }

    # Process inheritance rules
    $resolvedConfig = Invoke-WmrInheritanceRule -TemplateResolution $templateResolution -MachineContext $machineContext -InheritanceConfiguration $inheritanceConfig -Debug:$Debug -Verbose:$Verbose -WhatIf:$WhatIf -Confirm:$Confirm
    if ($null -eq $resolvedConfig) {
        Write-Error "Failed to process inheritance rules"
        return
    }

    # Validate resolved configuration
    $isValid = Test-WmrResolvedConfiguration -ResolvedConfiguration $resolvedConfig -Debug:$Debug -Verbose:$Verbose -WhatIf:$WhatIf -Confirm:$Confirm
    if (-not $isValid) {
        Write-Error "Resolved configuration failed validation"
        return
    }

    # Save resolved configuration
    Save-WmrResolvedConfiguration -ResolvedConfiguration $resolvedConfig -OutputPath $OutputPath -Force:$Force -Debug:$Debug -Verbose:$Verbose -WhatIf:$WhatIf -Confirm:$Confirm
    if ($LastExitCode -ne 0) {
        Write-Error "Failed to save resolved configuration to $OutputPath"
        return
    }

    Write-Output "Template inheritance resolved successfully to $OutputPath"
}

# Re-export all functions for backward compatibility (only when in module context)
if ($MyInvocation.MyCommand.CommandType -eq 'ExternalScript') {
    # Only export when loaded as a module, not when dot-sourcing
    try {
        Export-ModuleMember -Function @(
            # Main template resolution functions
            'Resolve-WmrTemplateInheritance',
            'Get-WmrInheritanceConfiguration',

            # Machine context functions
            'Get-WmrMachineContext',
            'Get-WmrApplicableMachineConfiguration',

            # Configuration merging functions
            'Merge-WmrSharedConfiguration',
            'Merge-WmrMachineSpecificConfiguration',
            'Merge-WmrConfigurationItem',
            'Merge-WmrSingleConfigurationItem',
            'Merge-WmrRegistryValue',

            # Conditional processing functions
            'Invoke-WmrInheritanceRule',
            'Invoke-WmrInheritanceRuleToSection',
            'Invoke-WmrConditionalSection',

            # Configuration validation functions
            'Test-WmrResolvedConfiguration',
            'Test-WmrStrictConfigurationValidation',
            'Test-WmrModerateConfigurationValidation',
            'Test-WmrRelaxedConfigurationValidation',
            'Test-WmrConfigurationItemValidity'
        )
    }
    catch {
        # Silently ignore Export-ModuleMember errors when not in module context
        Write-Debug "Export-ModuleMember not available in current context, functions available via dot-sourcing"
    }
}

# Functions are available when dot-sourced, no need to export when not in module context






