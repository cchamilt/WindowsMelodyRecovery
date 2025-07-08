# Private/Core/TemplateInheritance.ps1

<#
.SYNOPSIS
    Template inheritance processing functions for Windows Melody Recovery.

.DESCRIPTION
    Provides functions to process template inheritance, including shared vs machine-specific
    configuration merging, conditional sections, and inheritance rules.

.NOTES
    Author: Windows Melody Recovery
    Version: 2.0
    Requires: PowerShell 5.1 or later
#>

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
    param(
        [Parameter(Mandatory=$true)]
        [PSObject]$TemplateConfig,
        
        [Parameter(Mandatory=$true)]
        [PSObject]$MachineContext
    )
    
    Write-Verbose "Resolving template inheritance for template: $($TemplateConfig.metadata.name)"
    
    # Initialize resolved configuration with base template
    $resolvedConfig = $TemplateConfig | ConvertTo-Json -Depth 100 | ConvertFrom-Json
    
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
            $resolvedConfig = Apply-WmrInheritanceRules -ResolvedConfig $resolvedConfig -InheritanceRules $TemplateConfig.inheritance_rules -MachineContext $MachineContext
        }
        
        # Step 4: Process conditional sections
        if ($TemplateConfig.conditional_sections) {
            Write-Verbose "Processing conditional sections"
            $resolvedConfig = Apply-WmrConditionalSections -ResolvedConfig $resolvedConfig -ConditionalSections $TemplateConfig.conditional_sections -MachineContext $MachineContext
        }
        
        # Step 5: Validate final configuration
        Test-WmrResolvedConfiguration -ResolvedConfig $resolvedConfig -InheritanceConfig $inheritanceConfig
        
        Write-Verbose "Template inheritance resolution completed successfully"
        return $resolvedConfig
        
    } catch {
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
    param(
        [Parameter(Mandatory=$true)]
        [PSObject]$TemplateConfig
    )
    
    $defaultConfig = @{
        inheritance_mode = "merge"
        machine_precedence = $true
        validation_level = "moderate"
        fallback_strategy = "use_shared"
    }
    
    if ($TemplateConfig.configuration) {
        # Merge template configuration with defaults
        $config = $defaultConfig.Clone()
        foreach ($key in $TemplateConfig.configuration.PSObject.Properties.Name) {
            $config[$key] = $TemplateConfig.configuration.$key
        }
        return $config
    }
    
    return $defaultConfig
}

function Get-WmrMachineContext {
    <#
    .SYNOPSIS
        Gets machine context information for inheritance resolution.
    
    .DESCRIPTION
        Collects information about the current machine that can be used
        for inheritance resolution, including machine name, environment
        variables, hardware information, and software checks.
    
    .EXAMPLE
        $context = Get-WmrMachineContext
    #>
    [CmdletBinding()]
    param()
    
    Write-Verbose "Collecting machine context information"
    
    try {
        $context = @{
            MachineName = $env:COMPUTERNAME
            UserName = $env:USERNAME
            UserProfile = $env:USERPROFILE
            OSVersion = [System.Environment]::OSVersion.Version.ToString()
            Architecture = $env:PROCESSOR_ARCHITECTURE
            Domain = $env:USERDOMAIN
            EnvironmentVariables = @{}
            HardwareInfo = @{}
            SoftwareInfo = @{}
            Timestamp = Get-Date
        }
        
        # Collect relevant environment variables
        $relevantEnvVars = @("COMPUTERNAME", "USERNAME", "USERPROFILE", "PROCESSOR_ARCHITECTURE", "USERDOMAIN", "PROCESSOR_IDENTIFIER")
        foreach ($envVar in $relevantEnvVars) {
            $envValue = [System.Environment]::GetEnvironmentVariable($envVar)
            if ($envValue) {
                $context.EnvironmentVariables[$envVar] = $envValue
            }
        }
        
        # Collect basic hardware information
        try {
            $context.HardwareInfo.Processors = Get-CimInstance -ClassName Win32_Processor -ErrorAction SilentlyContinue | Select-Object Name, NumberOfCores, NumberOfLogicalProcessors
            $context.HardwareInfo.Memory = Get-CimInstance -ClassName Win32_PhysicalMemory -ErrorAction SilentlyContinue | Measure-Object -Property Capacity -Sum | Select-Object -ExpandProperty Sum
            $context.HardwareInfo.VideoControllers = Get-CimInstance -ClassName Win32_VideoController -ErrorAction SilentlyContinue | Select-Object Name, AdapterRAM
        } catch {
            Write-Warning "Failed to collect hardware information: $($_.Exception.Message)"
        }
        
        # Collect basic software information
        try {
            $context.SoftwareInfo.PowerShellVersion = $PSVersionTable.PSVersion.ToString()
            $context.SoftwareInfo.DotNetVersion = [System.Runtime.InteropServices.RuntimeInformation]::FrameworkDescription
        } catch {
            Write-Warning "Failed to collect software information: $($_.Exception.Message)"
        }
        
        Write-Verbose "Machine context collection completed"
        return $context
        
    } catch {
        Write-Error "Failed to collect machine context: $($_.Exception.Message)"
        throw
    }
}

function Get-WmrApplicableMachineConfigurations {
    <#
    .SYNOPSIS
        Gets machine-specific configurations that apply to the current machine.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [array]$MachineSpecificConfigs,
        
        [Parameter(Mandatory=$true)]
        [PSObject]$MachineContext
    )
    
    $applicableConfigs = @()
    
    foreach ($config in $MachineSpecificConfigs) {
        if (Test-WmrMachineSelectors -MachineSelectors $config.machine_selectors -MachineContext $MachineContext) {
            Write-Verbose "Machine-specific configuration '$($config.name)' applies to this machine"
            $applicableConfigs += $config
        }
    }
    
    # Sort by priority (higher priority first)
    $applicableConfigs = $applicableConfigs | Sort-Object { if ($_.priority) { $_.priority } else { 80 } } -Descending
    
    return $applicableConfigs
}

function Test-WmrMachineSelectors {
    <#
    .SYNOPSIS
        Tests if machine selectors match the current machine.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [array]$MachineSelectors,
        
        [Parameter(Mandatory=$true)]
        [PSObject]$MachineContext
    )
    
    foreach ($selector in $MachineSelectors) {
        $result = $false
        
        switch ($selector.type) {
            "machine_name" {
                $result = Test-WmrStringComparison -Value $MachineContext.MachineName -Expected $selector.value -Operator $selector.operator -CaseSensitive $selector.case_sensitive
            }
            "hostname_pattern" {
                $result = Test-WmrStringComparison -Value $MachineContext.MachineName -Expected $selector.value -Operator "matches" -CaseSensitive $selector.case_sensitive
            }
            "environment_variable" {
                $envValue = $MachineContext.EnvironmentVariables[$selector.value]
                if ($envValue) {
                    $result = Test-WmrStringComparison -Value $envValue -Expected $selector.expected_value -Operator $selector.operator -CaseSensitive $selector.case_sensitive
                }
            }
            "registry_value" {
                try {
                    $regValue = Get-ItemProperty -Path $selector.path -Name $selector.key_name -ErrorAction SilentlyContinue
                    if ($regValue) {
                        $result = Test-WmrStringComparison -Value $regValue.$($selector.key_name) -Expected $selector.expected_value -Operator $selector.operator -CaseSensitive $selector.case_sensitive
                    }
                } catch {
                    Write-Verbose "Failed to read registry value for selector: $($_.Exception.Message)"
                }
            }
            "script" {
                try {
                    $scriptBlock = [ScriptBlock]::Create($selector.script)
                    $scriptResult = & $scriptBlock $MachineContext
                    $result = Test-WmrStringComparison -Value $scriptResult -Expected $selector.expected_result -Operator $selector.operator -CaseSensitive $selector.case_sensitive
                } catch {
                    Write-Verbose "Failed to execute selector script: $($_.Exception.Message)"
                }
            }
        }
        
        if ($result) {
            return $true  # At least one selector matches
        }
    }
    
    return $false  # No selectors matched
}

function Test-WmrStringComparison {
    <#
    .SYNOPSIS
        Tests string comparison with various operators.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Value,
        
        [Parameter(Mandatory=$true)]
        [string]$Expected,
        
        [Parameter(Mandatory=$false)]
        [string]$Operator = "equals",
        
        [Parameter(Mandatory=$false)]
        [bool]$CaseSensitive = $false
    )
    
    if (-not $CaseSensitive) {
        $Value = $Value.ToLower()
        $Expected = $Expected.ToLower()
    }
    
    switch ($Operator) {
        "equals" { return $Value -eq $Expected }
        "not_equals" { return $Value -ne $Expected }
        "contains" { return $Value -like "*$Expected*" }
        "matches" { return $Value -match $Expected }
        "greater_than" { return $Value -gt $Expected }
        "less_than" { return $Value -lt $Expected }
        default { 
            Write-Warning "Unknown comparison operator: $Operator"
            return $false 
        }
    }
}

function Merge-WmrSharedConfiguration {
    <#
    .SYNOPSIS
        Merges shared configuration into the resolved configuration.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [PSObject]$ResolvedConfig,
        
        [Parameter(Mandatory=$true)]
        [PSObject]$SharedConfig,
        
        [Parameter(Mandatory=$true)]
        [hashtable]$InheritanceConfig
    )
    
    $configSections = @("files", "registry", "applications", "prerequisites", "stages")
    
    foreach ($section in $configSections) {
        if ($SharedConfig.$section) {
            Write-Verbose "Merging shared $section configuration"
            
            # Add inheritance metadata to shared items
            $sharedItems = $SharedConfig.$section
            foreach ($item in $sharedItems) {
                if (-not $item.inheritance_source) {
                    $item | Add-Member -NotePropertyName "inheritance_source" -NotePropertyValue "shared" -Force
                }
                if (-not $item.inheritance_priority) {
                    $item | Add-Member -NotePropertyName "inheritance_priority" -NotePropertyValue 50 -Force
                }
            }
            
            # Merge with existing configuration
            if ($ResolvedConfig.$section) {
                $ResolvedConfig.$section = @($ResolvedConfig.$section) + @($sharedItems)
            } else {
                $ResolvedConfig | Add-Member -NotePropertyName $section -NotePropertyValue $sharedItems -Force
            }
        }
    }
    
    return $ResolvedConfig
}

function Merge-WmrMachineSpecificConfiguration {
    <#
    .SYNOPSIS
        Merges machine-specific configuration into the resolved configuration.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [PSObject]$ResolvedConfig,
        
        [Parameter(Mandatory=$true)]
        [PSObject]$MachineConfig,
        
        [Parameter(Mandatory=$true)]
        [hashtable]$InheritanceConfig
    )
    
    $configSections = @("files", "registry", "applications", "prerequisites", "stages")
    $mergeStrategy = if ($MachineConfig.merge_strategy) { $MachineConfig.merge_strategy } else { "deep_merge" }
    
    foreach ($section in $configSections) {
        if ($MachineConfig.$section) {
            Write-Verbose "Merging machine-specific $section configuration using strategy: $mergeStrategy"
            
            # Add inheritance metadata to machine-specific items
            $machineItems = $MachineConfig.$section
            foreach ($item in $machineItems) {
                if (-not $item.inheritance_source) {
                    $item | Add-Member -NotePropertyName "inheritance_source" -NotePropertyValue "machine_specific" -Force
                }
                if (-not $item.inheritance_priority) {
                    $priority = if ($MachineConfig.priority) { $MachineConfig.priority } else { 80 }
                    $item | Add-Member -NotePropertyName "inheritance_priority" -NotePropertyValue $priority -Force
                }
            }
            
            switch ($mergeStrategy) {
                "replace" {
                    # Replace entire section
                    $ResolvedConfig.$section = $machineItems
                }
                "shallow_merge" {
                    # Simple append
                    if ($ResolvedConfig.$section) {
                        $ResolvedConfig.$section = @($ResolvedConfig.$section) + @($machineItems)
                    } else {
                        $ResolvedConfig | Add-Member -NotePropertyName $section -NotePropertyValue $machineItems -Force
                    }
                }
                "deep_merge" {
                    # Merge items with same inheritance tags or names
                    $ResolvedConfig.$section = Merge-WmrConfigurationItems -ExistingItems $ResolvedConfig.$section -NewItems $machineItems -InheritanceConfig $InheritanceConfig
                }
            }
        }
    }
    
    return $ResolvedConfig
}

function Merge-WmrConfigurationItems {
    <#
    .SYNOPSIS
        Merges configuration items with intelligent conflict resolution.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [array]$ExistingItems,
        
        [Parameter(Mandatory=$true)]
        [array]$NewItems,
        
        [Parameter(Mandatory=$true)]
        [hashtable]$InheritanceConfig
    )
    
    $mergedItems = @()
    
    # Start with existing items
    if ($ExistingItems) {
        $mergedItems = @($ExistingItems)
    }
    
    foreach ($newItem in $NewItems) {
        $matchingItem = $null
        
        # Find matching item by name or inheritance tags
        foreach ($existingItem in $mergedItems) {
            if ($existingItem.name -eq $newItem.name) {
                $matchingItem = $existingItem
                break
            }
            
            # Check for matching inheritance tags
            if ($existingItem.inheritance_tags -and $newItem.inheritance_tags) {
                $commonTags = $existingItem.inheritance_tags | Where-Object { $_ -in $newItem.inheritance_tags }
                if ($commonTags.Count -gt 0) {
                    $matchingItem = $existingItem
                    break
                }
            }
        }
        
        if ($matchingItem) {
            # Merge with existing item
            $mergedItem = Merge-WmrConfigurationItem -ExistingItem $matchingItem -NewItem $newItem -InheritanceConfig $InheritanceConfig
            $index = $mergedItems.IndexOf($matchingItem)
            $mergedItems[$index] = $mergedItem
        } else {
            # Add new item
            $mergedItems += $newItem
        }
    }
    
    return $mergedItems
}

function Merge-WmrConfigurationItem {
    <#
    .SYNOPSIS
        Merges two configuration items with conflict resolution.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [PSObject]$ExistingItem,
        
        [Parameter(Mandatory=$true)]
        [PSObject]$NewItem,
        
        [Parameter(Mandatory=$true)]
        [hashtable]$InheritanceConfig
    )
    
    # Determine which item has higher priority
    $existingPriority = if ($ExistingItem.inheritance_priority) { $ExistingItem.inheritance_priority } else { 50 }
    $newPriority = if ($NewItem.inheritance_priority) { $NewItem.inheritance_priority } else { 50 }
    
    $conflictResolution = "machine_wins"
    if ($NewItem.conflict_resolution) {
        $conflictResolution = $NewItem.conflict_resolution
    } elseif ($ExistingItem.conflict_resolution) {
        $conflictResolution = $ExistingItem.conflict_resolution
    }
    
    # Create merged item
    $mergedItem = $ExistingItem | ConvertTo-Json -Depth 100 | ConvertFrom-Json
    
    # Apply conflict resolution
    switch ($conflictResolution) {
        "machine_wins" {
            if ($NewItem.inheritance_source -eq "machine_specific") {
                # Machine-specific wins
                foreach ($prop in $NewItem.PSObject.Properties) {
                    $mergedItem.$($prop.Name) = $prop.Value
                }
            }
        }
        "shared_wins" {
            if ($ExistingItem.inheritance_source -eq "shared") {
                # Keep existing (shared wins)
                # No action needed
            } else {
                # New item wins
                foreach ($prop in $NewItem.PSObject.Properties) {
                    $mergedItem.$($prop.Name) = $prop.Value
                }
            }
        }
        "merge_both" {
            # Merge properties from both items
            foreach ($prop in $NewItem.PSObject.Properties) {
                if ($prop.Name -notin @("inheritance_source", "inheritance_priority", "conflict_resolution")) {
                    $mergedItem.$($prop.Name) = $prop.Value
                }
            }
        }
        default {
            # Default to higher priority wins
            if ($newPriority -gt $existingPriority) {
                foreach ($prop in $NewItem.PSObject.Properties) {
                    $mergedItem.$($prop.Name) = $prop.Value
                }
            }
        }
    }
    
    return $mergedItem
}

function Apply-WmrInheritanceRules {
    <#
    .SYNOPSIS
        Applies custom inheritance rules to the resolved configuration.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [PSObject]$ResolvedConfig,
        
        [Parameter(Mandatory=$true)]
        [array]$InheritanceRules,
        
        [Parameter(Mandatory=$true)]
        [PSObject]$MachineContext
    )
    
    foreach ($rule in $InheritanceRules) {
        Write-Verbose "Applying inheritance rule: $($rule.name)"
        
        # Check if rule applies to current configuration
        if (Test-WmrInheritanceRuleCondition -Rule $rule -ResolvedConfig $ResolvedConfig -MachineContext $MachineContext) {
            # Apply rule to applicable sections
            foreach ($section in $rule.applies_to) {
                if ($ResolvedConfig.$section) {
                    $ResolvedConfig.$section = Apply-WmrInheritanceRuleToSection -Items $ResolvedConfig.$section -Rule $rule -MachineContext $MachineContext
                }
            }
        }
    }
    
    return $ResolvedConfig
}

function Test-WmrInheritanceRuleCondition {
    <#
    .SYNOPSIS
        Tests if an inheritance rule condition is met.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [PSObject]$Rule,
        
        [Parameter(Mandatory=$true)]
        [PSObject]$ResolvedConfig,
        
        [Parameter(Mandatory=$true)]
        [PSObject]$MachineContext
    )
    
    if (-not $Rule.condition) {
        return $true  # No condition means always apply
    }
    
    # Check inheritance tags condition
    if ($Rule.condition.inheritance_tags) {
        $requiredTags = $Rule.condition.inheritance_tags.contains
        if ($requiredTags) {
            # Check if any items have the required tags
            $hasMatchingTags = $false
            foreach ($section in $Rule.applies_to) {
                if ($ResolvedConfig.$section) {
                    foreach ($item in $ResolvedConfig.$section) {
                        if ($item.inheritance_tags) {
                            $commonTags = $item.inheritance_tags | Where-Object { $_ -in $requiredTags }
                            if ($commonTags.Count -gt 0) {
                                $hasMatchingTags = $true
                                break
                            }
                        }
                    }
                    if ($hasMatchingTags) { break }
                }
            }
            return $hasMatchingTags
        }
    }
    
    # Check machine selectors condition
    if ($Rule.condition.machine_selectors) {
        return Test-WmrMachineSelectors -MachineSelectors $Rule.condition.machine_selectors -MachineContext $MachineContext
    }
    
    return $true
}

function Apply-WmrInheritanceRuleToSection {
    <#
    .SYNOPSIS
        Applies an inheritance rule to a configuration section.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [array]$Items,
        
        [Parameter(Mandatory=$true)]
        [PSObject]$Rule,
        
        [Parameter(Mandatory=$true)]
        [PSObject]$MachineContext
    )
    
    switch ($Rule.action) {
        "merge" {
            # Apply merge logic based on rule parameters
            if ($Rule.parameters.merge_level -eq "value") {
                # Merge at value level for registry items
                return Merge-WmrRegistryValues -Items $Items -Rule $Rule
            }
        }
        "transform" {
            # Apply transformation script
            if ($Rule.script) {
                $scriptBlock = [ScriptBlock]::Create($Rule.script)
                $transformedItems = @()
                foreach ($item in $Items) {
                    $transformedItem = & $scriptBlock $item $MachineContext
                    $transformedItems += $transformedItem
                }
                return $transformedItems
            }
        }
        "validate" {
            # Validate items and remove invalid ones
            $validItems = @()
            foreach ($item in $Items) {
                if (Test-WmrConfigurationItemValidity -Item $item -Rule $Rule) {
                    $validItems += $item
                }
            }
            return $validItems
        }
        "skip" {
            # Skip items that match rule condition
            $filteredItems = @()
            foreach ($item in $Items) {
                if (-not (Test-WmrRuleItemMatch -Item $item -Rule $Rule)) {
                    $filteredItems += $item
                }
            }
            return $filteredItems
        }
    }
    
    return $Items
}

function Apply-WmrConditionalSections {
    <#
    .SYNOPSIS
        Applies conditional sections based on machine conditions.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [PSObject]$ResolvedConfig,
        
        [Parameter(Mandatory=$true)]
        [array]$ConditionalSections,
        
        [Parameter(Mandatory=$true)]
        [PSObject]$MachineContext
    )
    
    foreach ($conditionalSection in $ConditionalSections) {
        Write-Verbose "Evaluating conditional section: $($conditionalSection.name)"
        
        if (Test-WmrConditionalSectionConditions -ConditionalSection $conditionalSection -MachineContext $MachineContext) {
            Write-Verbose "Applying conditional section: $($conditionalSection.name)"
            
            # Apply conditional section to resolved configuration
            $configSections = @("files", "registry", "applications", "prerequisites", "stages")
            foreach ($section in $configSections) {
                if ($conditionalSection.$section) {
                    # Add conditional items to resolved configuration
                    $conditionalItems = $conditionalSection.$section
                    foreach ($item in $conditionalItems) {
                        $item | Add-Member -NotePropertyName "inheritance_source" -NotePropertyValue "conditional" -Force
                        $item | Add-Member -NotePropertyName "conditional_section" -NotePropertyValue $conditionalSection.name -Force
                    }
                    
                    if ($ResolvedConfig.$section) {
                        $ResolvedConfig.$section = @($ResolvedConfig.$section) + @($conditionalItems)
                    } else {
                        $ResolvedConfig | Add-Member -NotePropertyName $section -NotePropertyValue $conditionalItems -Force
                    }
                }
            }
        }
    }
    
    return $ResolvedConfig
}

function Test-WmrConditionalSectionConditions {
    <#
    .SYNOPSIS
        Tests if conditional section conditions are met.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [PSObject]$ConditionalSection,
        
        [Parameter(Mandatory=$true)]
        [PSObject]$MachineContext
    )
    
    $logic = if ($ConditionalSection.logic) { $ConditionalSection.logic } else { "and" }
    $results = @()
    
    foreach ($condition in $ConditionalSection.conditions) {
        $result = $false
        
        try {
            switch ($condition.type) {
                "machine_name" {
                    $result = $MachineContext.MachineName -eq $condition.check
                }
                "os_version" {
                    $result = $MachineContext.OSVersion -match $condition.check
                }
                "hardware_check" {
                    $scriptBlock = [ScriptBlock]::Create($condition.check)
                    $checkResult = & $scriptBlock
                    $result = $checkResult -match $condition.expected_result
                }
                "software_check" {
                    $scriptBlock = [ScriptBlock]::Create($condition.check)
                    $checkResult = & $scriptBlock
                    $result = $checkResult -match $condition.expected_result
                }
                "custom_script" {
                    $scriptBlock = [ScriptBlock]::Create($condition.check)
                    $checkResult = & $scriptBlock $MachineContext
                    $result = $checkResult -match $condition.expected_result
                }
            }
        } catch {
            Write-Verbose "Conditional check failed: $($_.Exception.Message)"
            $onFailure = if ($condition.on_failure) { $condition.on_failure } else { "skip" }
            
            switch ($onFailure) {
                "skip" { $result = $false }
                "warn" { 
                    Write-Warning "Conditional check failed for '$($condition.type)': $($_.Exception.Message)"
                    $result = $false 
                }
                "fail" { throw "Conditional check failed for '$($condition.type)': $($_.Exception.Message)" }
            }
        }
        
        $results += $result
    }
    
    # Apply logic to combine results
    switch ($logic) {
        "and" { return ($results | Where-Object { $_ -eq $false }).Count -eq 0 }
        "or" { return ($results | Where-Object { $_ -eq $true }).Count -gt 0 }
        "not" { return ($results | Where-Object { $_ -eq $true }).Count -eq 0 }
        default { return $true }
    }
}

function Test-WmrResolvedConfiguration {
    <#
    .SYNOPSIS
        Validates the resolved configuration for consistency and completeness.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [PSObject]$ResolvedConfig,
        
        [Parameter(Mandatory=$true)]
        [hashtable]$InheritanceConfig
    )
    
    $validationLevel = $InheritanceConfig.validation_level
    
    Write-Verbose "Validating resolved configuration with level: $validationLevel"
    
    switch ($validationLevel) {
        "strict" {
            # Strict validation - check all requirements
            Test-WmrStrictConfigurationValidation -ResolvedConfig $ResolvedConfig
        }
        "moderate" {
            # Moderate validation - check critical requirements
            Test-WmrModerateConfigurationValidation -ResolvedConfig $ResolvedConfig
        }
        "relaxed" {
            # Relaxed validation - minimal checks
            Test-WmrRelaxedConfigurationValidation -ResolvedConfig $ResolvedConfig
        }
    }
    
    Write-Verbose "Configuration validation completed"
}

function Test-WmrStrictConfigurationValidation {
    <#
    .SYNOPSIS
        Performs strict validation of resolved configuration.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [PSObject]$ResolvedConfig
    )
    
    # Check for duplicate names within sections
    $configSections = @("files", "registry", "applications", "prerequisites")
    foreach ($section in $configSections) {
        if ($ResolvedConfig.$section) {
            $names = $ResolvedConfig.$section | ForEach-Object { $_.name }
            $duplicates = $names | Group-Object | Where-Object { $_.Count -gt 1 }
            if ($duplicates) {
                throw "Duplicate names found in $section section: $($duplicates.Name -join ', ')"
            }
        }
    }
    
    # Check for conflicting paths
    if ($ResolvedConfig.files) {
        $paths = $ResolvedConfig.files | ForEach-Object { $_.path }
        $duplicatePaths = $paths | Group-Object | Where-Object { $_.Count -gt 1 }
        if ($duplicatePaths) {
            Write-Warning "Duplicate file paths found: $($duplicatePaths.Name -join ', ')"
        }
    }
    
    # Check for required properties
    foreach ($section in $configSections) {
        if ($ResolvedConfig.$section) {
            foreach ($item in $ResolvedConfig.$section) {
                if (-not $item.name) {
                    throw "Missing required 'name' property in $section item"
                }
                if ($section -eq "files" -and -not $item.path) {
                    throw "Missing required 'path' property in files item: $($item.name)"
                }
                if ($section -eq "registry" -and -not $item.path) {
                    throw "Missing required 'path' property in registry item: $($item.name)"
                }
            }
        }
    }
}

function Test-WmrModerateConfigurationValidation {
    <#
    .SYNOPSIS
        Performs moderate validation of resolved configuration.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [PSObject]$ResolvedConfig
    )
    
    # Check for basic required properties
    $configSections = @("files", "registry", "applications")
    foreach ($section in $configSections) {
        if ($ResolvedConfig.$section) {
            foreach ($item in $ResolvedConfig.$section) {
                if (-not $item.name) {
                    Write-Warning "Missing 'name' property in $section item"
                }
            }
        }
    }
    
    # Check for obvious conflicts
    if ($ResolvedConfig.files) {
        $paths = $ResolvedConfig.files | ForEach-Object { $_.path }
        $duplicatePaths = $paths | Group-Object | Where-Object { $_.Count -gt 1 }
        if ($duplicatePaths) {
            Write-Warning "Duplicate file paths found: $($duplicatePaths.Name -join ', ')"
        }
    }
}

function Test-WmrRelaxedConfigurationValidation {
    <#
    .SYNOPSIS
        Performs relaxed validation of resolved configuration.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [PSObject]$ResolvedConfig
    )
    
    # Minimal validation - just check if configuration exists
    if (-not $ResolvedConfig) {
        throw "Resolved configuration is null or empty"
    }
    
    # Check if at least one section exists
    $configSections = @("files", "registry", "applications", "prerequisites", "stages")
    $hasContent = $false
    foreach ($section in $configSections) {
        if ($ResolvedConfig.$section -and $ResolvedConfig.$section.Count -gt 0) {
            $hasContent = $true
            break
        }
    }
    
    if (-not $hasContent) {
        Write-Warning "Resolved configuration appears to be empty"
    }
}

# Helper functions for specific merge operations
function Merge-WmrRegistryValues {
    <#
    .SYNOPSIS
        Merges registry values according to inheritance rules.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [array]$Items,
        
        [Parameter(Mandatory=$true)]
        [PSObject]$Rule
    )
    
    $conflictResolution = if ($Rule.parameters.conflict_resolution) { $Rule.parameters.conflict_resolution } else { "machine_wins" }
    
    # Group items by registry path
    $groupedItems = $Items | Group-Object -Property path
    
    $mergedItems = @()
    foreach ($group in $groupedItems) {
        if ($group.Count -eq 1) {
            $mergedItems += $group.Group[0]
        } else {
            # Merge multiple items for same path
            $mergedItem = $group.Group[0] | ConvertTo-Json -Depth 100 | ConvertFrom-Json
            
            # Apply conflict resolution
            foreach ($item in $group.Group[1..($group.Count-1)]) {
                switch ($conflictResolution) {
                    "machine_wins" {
                        if ($item.inheritance_source -eq "machine_specific") {
                            $mergedItem = $item
                        }
                    }
                    "shared_wins" {
                        if ($mergedItem.inheritance_source -eq "shared") {
                            # Keep merged item
                        } else {
                            $mergedItem = $item
                        }
                    }
                    default {
                        # Default to higher priority
                        $mergedPriority = if ($mergedItem.inheritance_priority) { $mergedItem.inheritance_priority } else { 50 }
                        $itemPriority = if ($item.inheritance_priority) { $item.inheritance_priority } else { 50 }
                        
                        if ($itemPriority -gt $mergedPriority) {
                            $mergedItem = $item
                        }
                    }
                }
            }
            
            $mergedItems += $mergedItem
        }
    }
    
    return $mergedItems
}

function Test-WmrConfigurationItemValidity {
    <#
    .SYNOPSIS
        Tests if a configuration item is valid according to a rule.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [PSObject]$Item,
        
        [Parameter(Mandatory=$true)]
        [PSObject]$Rule
    )
    
    # Basic validity checks
    if (-not $Item.name) {
        return $false
    }
    
    # Rule-specific validation
    if ($Rule.parameters.required_properties) {
        foreach ($prop in $Rule.parameters.required_properties) {
            if (-not $Item.$prop) {
                return $false
            }
        }
    }
    
    return $true
}

function Test-WmrRuleItemMatch {
    <#
    .SYNOPSIS
        Tests if an item matches a rule condition.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [PSObject]$Item,
        
        [Parameter(Mandatory=$true)]
        [PSObject]$Rule
    )
    
    # Check inheritance tags
    if ($Rule.condition.inheritance_tags) {
        $requiredTags = $Rule.condition.inheritance_tags.contains
        if ($Item.inheritance_tags) {
            $commonTags = $Item.inheritance_tags | Where-Object { $_ -in $requiredTags }
            return $commonTags.Count -gt 0
        }
    }
    
    # Check other conditions as needed
    return $false
}

# Export functions for module use
Export-ModuleMember -Function @(
    'Resolve-WmrTemplateInheritance',
    'Get-WmrMachineContext',
    'Get-WmrInheritanceConfiguration',
    'Test-WmrResolvedConfiguration',
    'Get-WmrApplicableMachineConfigurations',
    'Test-WmrMachineSelectors',
    'Test-WmrStringComparison',
    'Merge-WmrSharedConfiguration',
    'Merge-WmrMachineSpecificConfiguration',
    'Apply-WmrInheritanceRules',
    'Test-WmrInheritanceRuleCondition',
    'Apply-WmrConditionalSections',
    'Test-WmrConditionalSectionConditions',
    'Test-WmrStrictConfigurationValidation',
    'Test-WmrModerateConfigurationValidation',
    'Test-WmrRelaxedConfigurationValidation',
    'Merge-WmrRegistryValues',
    'Test-WmrConfigurationItemValidity',
    'Test-WmrRuleItemMatch'
) 