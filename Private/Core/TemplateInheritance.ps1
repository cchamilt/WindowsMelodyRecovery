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

# Import all specialized modules
. "$PSScriptRoot\MachineContext.ps1"
. "$PSScriptRoot\ConfigurationMerging.ps1"
. "$PSScriptRoot\ConditionalProcessing.ps1"
. "$PSScriptRoot\ConfigurationValidation.ps1"
. "$PSScriptRoot\TemplateResolution.ps1"

# Re-export all functions for backward compatibility
Export-ModuleMember -Function @(
    # Main template resolution functions
    'Resolve-WmrTemplateInheritance',
    'Get-WmrInheritanceConfiguration',

    # Machine context functions
    'Get-WmrMachineContext',
    'Get-WmrApplicableMachineConfigurations',
    'Test-WmrMachineSelector',
    'Test-WmrStringComparison',

    # Configuration merging functions
    'Merge-WmrSharedConfiguration',
    'Merge-WmrMachineSpecificConfiguration',
    'Merge-WmrConfigurationItem',
    'Merge-WmrSingleConfigurationItem',
    'Merge-WmrRegistryValue',

    # Conditional processing functions
    'Invoke-WmrInheritanceRule',
    'Test-WmrInheritanceRuleCondition',
    'Invoke-WmrInheritanceRuleToSection',
    'Invoke-WmrConditionalSection',
    'Test-WmrConditionalSectionCondition',
    'Test-WmrRuleItemMatch',

    # Configuration validation functions
    'Test-WmrResolvedConfiguration',
    'Test-WmrStrictConfigurationValidation',
    'Test-WmrModerateConfigurationValidation',
    'Test-WmrRelaxedConfigurationValidation',
    'Test-WmrConfigurationItemValidity'
)