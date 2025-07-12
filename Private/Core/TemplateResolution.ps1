# Private/Core/TemplateResolution.ps1

<#
.SYNOPSIS
    Main template resolution functionality for Windows Melody Recovery template inheritance.

.DESCRIPTION
    Provides the main orchestration function for template inheritance resolution,
    coordinating between machine context, configuration merging, conditional processing,
    and validation modules.

.NOTES
    Author: Windows Melody Recovery
    Version: 2.0
    Requires: PowerShell 5.1 or later
#>

# Import required modules
$script:ModuleRoot = Split-Path -Parent $PSScriptRoot

# Import dependency modules
. "$PSScriptRoot\MachineContext.ps1"
. "$PSScriptRoot\ConfigurationMerging.ps1"
. "$PSScriptRoot\ConditionalProcessing.ps1"
. "$PSScriptRoot\ConfigurationValidation.ps1"

function Resolve-WmrTemplateInheritance {
    <#
    .SYNOPSIS
        Resolves template inheritance by merging shared and machine-specific configurations.

    .DESCRIPTION
        Processes a template configuration to resolve inheritance patterns, applying
        shared configurations, machine-specific overrides, conditional sections,
        and custom inheritance rules.

    .PARAMETER TemplateConfig
        The parsed template configuration object.

    .PARAMETER MachineContext
        Context information about the current machine for inheritance resolution.

    .EXAMPLE
        $resolvedConfig = Resolve-WmrTemplateInheritance -TemplateConfig $template -MachineContext $context
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSObject])]
    param(
        [Parameter(Mandatory = $true)]
        [PSObject]$TemplateConfig,

        [Parameter(Mandatory = $true)]
        [PSObject]$MachineContext
    )

    Write-Verbose "Resolving template inheritance for template: $($TemplateConfig.metadata.name)"

    # Initialize resolved configuration with base template structure
    $resolvedConfig = @{
        metadata = $TemplateConfig.metadata
    }

    # If the template has a configuration section, use it as the base
    if ($TemplateConfig.configuration) {
        $configSections = @("files", "registry", "applications", "prerequisites", "stages")
        foreach ($section in $configSections) {
            if ($TemplateConfig.configuration.$section) {
                # Add inheritance metadata to base configuration items
                $items = $TemplateConfig.configuration.$section
                # Ensure we have an array, even if it's a single item
                if ($items -isnot [array]) {
                    $items = @($items)
                }

                foreach ($item in $items) {
                    if (-not $item.inheritance_source) {
                        $item | Add-Member -NotePropertyName "inheritance_source" -NotePropertyValue "base" -Force
                    }
                    if (-not $item.inheritance_priority) {
                        $item | Add-Member -NotePropertyName "inheritance_priority" -NotePropertyValue 30 -Force
                    }
                }

                # Initialize resolved config section with configuration section content
                $resolvedConfig[$section] = $items
            }
        }
    }

    # Convert to PSObject for easier manipulation
    $resolvedConfig = [PSCustomObject]$resolvedConfig

    # Copy any additional properties from the template config
    foreach ($property in $TemplateConfig.PSObject.Properties) {
        if ($property.Name -notin @("metadata", "configuration", "shared", "machine_specific", "inheritance_rules", "conditional_sections")) {
            $resolvedConfig | Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value -Force
        }
    }

    # Get inheritance configuration or use defaults
    $inheritanceConfig = Get-WmrInheritanceConfiguration -TemplateConfig $TemplateConfig

    try {
        # Step 1: Process shared configuration
        if ($TemplateConfig.shared) {
            Write-Verbose "Processing shared configuration sections"
            $resolvedConfig = Merge-WmrSharedConfiguration -ResolvedConfig $resolvedConfig -SharedConfig $TemplateConfig.shared -InheritanceConfig $inheritanceConfig
        }

        # Step 2: Apply machine-specific overrides
        if ($TemplateConfig.machine_specific) {
            Write-Verbose "Processing machine-specific configuration overrides"
            $applicableMachineConfigs = Get-WmrApplicableMachineConfigurations -MachineSpecificConfigs $TemplateConfig.machine_specific -MachineContext $MachineContext

            foreach ($machineConfig in $applicableMachineConfigs) {
                $resolvedConfig = Merge-WmrMachineSpecificConfiguration -ResolvedConfig $resolvedConfig -MachineConfig $machineConfig -InheritanceConfig $inheritanceConfig
            }
        }

        # Step 3: Apply inheritance rules
        if ($TemplateConfig.inheritance_rules) {
            Write-Verbose "Applying custom inheritance rules"
            $resolvedConfig = Invoke-WmrInheritanceRule -ResolvedConfig $resolvedConfig -InheritanceRules $TemplateConfig.inheritance_rules -MachineContext $MachineContext
        }

        # Step 4: Process conditional sections
        if ($TemplateConfig.conditional_sections) {
            Write-Verbose "Processing conditional sections"
            $resolvedConfig = Invoke-WmrConditionalSection -ResolvedConfig $resolvedConfig -ConditionalSections $TemplateConfig.conditional_sections -MachineContext $MachineContext
        }

        # Step 5: Validate final configuration
        $null = Test-WmrResolvedConfiguration -ResolvedConfig $resolvedConfig -InheritanceConfig $inheritanceConfig

        Write-Verbose "Template inheritance resolution completed successfully"
        return $resolvedConfig

    }
 catch {
        Write-Error "Failed to resolve template inheritance: $($_.Exception.Message)"
        throw
    }
}

function Get-WmrInheritanceConfiguration {
    <#
    .SYNOPSIS
        Gets inheritance configuration with defaults applied.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [PSObject]$TemplateConfig
    )

    $defaultConfig = @{
        inheritance_mode = "merge"
        machine_precedence = $true
        validation_level = "moderate"
        fallback_strategy = "use_shared"
    }

    $config = $defaultConfig.Clone()

    # Check for inheritance settings at the top level first
    foreach ($key in $defaultConfig.Keys) {
        if ($TemplateConfig.PSObject.Properties.Name -contains $key) {
            $config[$key] = $TemplateConfig.$key
        }
 elseif ($TemplateConfig -is [hashtable] -and $TemplateConfig.ContainsKey($key)) {
            $config[$key] = $TemplateConfig[$key]
        }
    }

    # Then check configuration section and override if found there
    if ($TemplateConfig.configuration) {
        if ($TemplateConfig.configuration -is [hashtable]) {
            foreach ($key in $TemplateConfig.configuration.Keys) {
                if ($key -in $defaultConfig.Keys) {
                    $config[$key] = $TemplateConfig.configuration[$key]
                }
            }
        }
 else {
            foreach ($property in $TemplateConfig.configuration.PSObject.Properties) {
                if ($property.Name -in $defaultConfig.Keys) {
                    $config[$property.Name] = $property.Value
                }
            }
        }
    }

    return $config
}

# Functions are available when dot-sourced, no need to export when not in module context






