# Private/Core/ConditionalProcessing.ps1

<#
.SYNOPSIS
    Conditional processing and rule application functionality for Windows Melody Recovery template inheritance.

.DESCRIPTION
    Provides functions to apply inheritance rules, process conditional sections,
    and handle complex rule-based configuration transformations.

.NOTES
    Author: Windows Melody Recovery
    Version: 2.0
    Requires: PowerShell 5.1 or later
#>

function Invoke-WmrInheritanceRule {
    <#
    .SYNOPSIS
        Applies inheritance rules to the resolved configuration.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSObject])]
    param(
        [Parameter(Mandatory = $true)]
        [PSObject]$ResolvedConfig,

        [Parameter(Mandatory = $true)]
        [array]$InheritanceRules,

        [Parameter(Mandatory = $true)]
        [PSObject]$MachineContext
    )

    foreach ($rule in $InheritanceRules) {
        Write-Verbose "Processing inheritance rule: $($rule.name)"

        # Check if rule conditions are met
        $ruleMet = $true
        if ($rule.condition) {
            if ($rule.condition.machine_selectors) {
                $ruleMet = $false
                foreach ($selector in $rule.condition.machine_selectors) {
                    $result = $false
                    switch ($selector.type) {
                        "machine_name" {
                            $caseSensitive = if ($null -ne $selector.case_sensitive -and $selector.case_sensitive -ne "") { [bool]$selector.case_sensitive } else { $false }
                            if ($caseSensitive) {
                                $result = $MachineContext.MachineName -ceq $selector.value
                            }
                            else {
                                $result = $MachineContext.MachineName -eq $selector.value
                            }
                        }
                        "hostname_pattern" {
                            $caseSensitive = if ($null -ne $selector.case_sensitive -and $selector.case_sensitive -ne "") { [bool]$selector.case_sensitive } else { $false }
                            if ($caseSensitive) {
                                $result = $MachineContext.MachineName -cmatch $selector.value
                            }
                            else {
                                $result = $MachineContext.MachineName -match $selector.value
                            }
                        }
                        "environment_variable" {
                            $envValue = $MachineContext.EnvironmentVariables[$selector.value]
                            if ($envValue) {
                                $caseSensitive = if ($null -ne $selector.case_sensitive -and $selector.case_sensitive -ne "") { [bool]$selector.case_sensitive } else { $false }
                                if ($caseSensitive) {
                                    $result = $envValue -ceq $selector.expected_value
                                }
                                else {
                                    $result = $envValue -eq $selector.expected_value
                                }
                            }
                        }
                        "registry_value" {
                            try {
                                $regValue = Get-ItemProperty -Path $selector.path -Name $selector.key_name -ErrorAction SilentlyContinue
                                if ($regValue) {
                                    $caseSensitive = if ($null -ne $selector.case_sensitive -and $selector.case_sensitive -ne "") { [bool]$selector.case_sensitive } else { $false }
                                    if ($caseSensitive) {
                                        $result = $regValue.$($selector.key_name) -ceq $selector.expected_value
                                    }
                                    else {
                                        $result = $regValue.$($selector.key_name) -eq $selector.expected_value
                                    }
                                }
                            }
                            catch {
                                Write-Verbose "Failed to read registry value for selector: $($_.Exception.Message)"
                            }
                        }
                        "script" {
                            try {
                                $scriptBlock = [ScriptBlock]::Create($selector.script)
                                $scriptResult = & $scriptBlock $MachineContext
                                $caseSensitive = if ($null -ne $selector.case_sensitive -and $selector.case_sensitive -ne "") { [bool]$selector.case_sensitive } else { $false }
                                if ($caseSensitive) {
                                    $result = $scriptResult -ceq $selector.expected_result
                                }
                                else {
                                    $result = $scriptResult -eq $selector.expected_result
                                }
                            }
                            catch {
                                Write-Verbose "Failed to execute selector script: $($_.Exception.Message)"
                            }
                        }
                    }
                    if ($result) {
                        $ruleMet = $true
                        break
                    }
                }
            }
        }

        if ($ruleMet) {
            Write-Verbose "Applying inheritance rule: $($rule.name)"

            # Apply rule to matching configuration sections
            foreach ($section in $rule.applies_to) {
                if ($ResolvedConfig.$section) {
                    $ResolvedConfig.$section = Invoke-WmrInheritanceRuleToSection -Items $ResolvedConfig.$section -Rule $rule -MachineContext $MachineContext
                }
            }
        }
        else {
            Write-Verbose "Inheritance rule '$($rule.name)' conditions not met, skipping"
        }
    }

    return $ResolvedConfig
}

function Invoke-WmrInheritanceRuleToSection {
    <#
    .SYNOPSIS
        Applies an inheritance rule to a specific configuration section.
    #>
    [CmdletBinding()]
    [OutputType([System.Array])]
    param(
        [Parameter(Mandatory = $true)]
        [array]$Items,

        [Parameter(Mandatory = $true)]
        [PSObject]$Rule,

        [Parameter(Mandatory = $true)]
        [PSObject]$MachineContext
    )

    # Filter items that match the rule conditions
    $matchingItems = @()
    $nonMatchingItems = @()

    foreach ($item in $Items) {
        $itemMatch = $true
        if ($Rule.item_selectors) {
            if ($Rule.item_selectors.inheritance_tags) {
                if ($item.inheritance_tags) {
                    $commonTags = $item.inheritance_tags | Where-Object { $_ -in $Rule.item_selectors.inheritance_tags.contains }
                    if ($commonTags.Count -eq 0) {
                        $itemMatch = $false
                    }
                }
                else {
                    $itemMatch = $false
                }
            }
        }

        if ($itemMatch) {
            $matchingItems += $item
        }
        else {
            $nonMatchingItems += $item
        }
    }

    # Apply rule action to matching items
    switch ($Rule.action) {
        "merge" {
            # Merge matching items using rule parameters
            if ($Rule.parameters.merge_level -eq "value") {
                $matchingItems = Merge-WmrRegistryValue -Items $matchingItems -Rule $Rule
            }
        }
        "replace" {
            # Replace matching items with rule-specified values
            if ($Rule.parameters.replacement_values) {
                foreach ($item in $matchingItems) {
                    foreach ($key in $Rule.parameters.replacement_values.Keys) {
                        $item.$key = $Rule.parameters.replacement_values[$key]
                    }
                }
            }
        }
        "transform" {
            # Transform matching items using rule script
            if ($Rule.parameters.transform_script) {
                $scriptBlock = [ScriptBlock]::Create($Rule.parameters.transform_script)
                $transformedItems = @()
                foreach ($item in $matchingItems) {
                    $transformedItem = & $scriptBlock $item $MachineContext
                    $transformedItems += $transformedItem
                }
                $matchingItems = $transformedItems
            }
            elseif ($Rule.script) {
                $scriptBlock = [ScriptBlock]::Create($Rule.script)
                $transformedItems = @()
                foreach ($item in $matchingItems) {
                    $transformedItem = & $scriptBlock $item $MachineContext
                    $transformedItems += $transformedItem
                }
                return $transformedItems
            }
        }
        "validate" {
            # Validate items and remove invalid ones
            $validItems = @()
            foreach ($item in $matchingItems) {
                $isValid = $true
                if ($Rule.parameters.validation_script) {
                    $scriptBlock = [ScriptBlock]::Create($Rule.parameters.validation_script)
                    $isValid = & $scriptBlock $item $MachineContext
                }
                if ($isValid) {
                    $validItems += $item
                }
            }
            $matchingItems = $validItems
        }
        default {
            Write-Warning "Unknown inheritance rule action: $($Rule.action)"
        }
    }

    # Return combined items
    return @($nonMatchingItems) + @($matchingItems)
}

function Invoke-WmrConditionalSection {
    <#
    .SYNOPSIS
        Applies conditional sections to the resolved configuration.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSObject])]
    param(
        [Parameter(Mandatory = $true)]
        [PSObject]$ResolvedConfig,

        [Parameter(Mandatory = $true)]
        [array]$ConditionalSections,

        [Parameter(Mandatory = $true)]
        [PSObject]$MachineContext
    )

    foreach ($section in $ConditionalSections) {
        Write-Verbose "Processing conditional section: $($section.name)"

        # Check if conditions are met
        $sectionMet = $true
        if ($section.condition) {
            if ($section.condition.machine_selectors) {
                $sectionMet = $false
                foreach ($selector in $section.condition.machine_selectors) {
                    $result = $false
                    switch ($selector.type) {
                        "machine_name" {
                            $caseSensitive = if ($null -ne $selector.case_sensitive -and $selector.case_sensitive -ne "") { [bool]$selector.case_sensitive } else { $false }
                            if ($caseSensitive) {
                                $result = $MachineContext.MachineName -ceq $selector.value
                            }
                            else {
                                $result = $MachineContext.MachineName -eq $selector.value
                            }
                        }
                        "hostname_pattern" {
                            $caseSensitive = if ($null -ne $selector.case_sensitive -and $selector.case_sensitive -ne "") { [bool]$selector.case_sensitive } else { $false }
                            if ($caseSensitive) {
                                $result = $MachineContext.MachineName -cmatch $selector.value
                            }
                            else {
                                $result = $MachineContext.MachineName -match $selector.value
                            }
                        }
                        "environment_variable" {
                            $envValue = $MachineContext.EnvironmentVariables[$selector.value]
                            if ($envValue) {
                                $caseSensitive = if ($null -ne $selector.case_sensitive -and $selector.case_sensitive -ne "") { [bool]$selector.case_sensitive } else { $false }
                                if ($caseSensitive) {
                                    $result = $envValue -ceq $selector.expected_value
                                }
                                else {
                                    $result = $envValue -eq $selector.expected_value
                                }
                            }
                        }
                        "registry_value" {
                            try {
                                $regValue = Get-ItemProperty -Path $selector.path -Name $selector.key_name -ErrorAction SilentlyContinue
                                if ($regValue) {
                                    $caseSensitive = if ($null -ne $selector.case_sensitive -and $selector.case_sensitive -ne "") { [bool]$selector.case_sensitive } else { $false }
                                    if ($caseSensitive) {
                                        $result = $regValue.$($selector.key_name) -ceq $selector.expected_value
                                    }
                                    else {
                                        $result = $regValue.$($selector.key_name) -eq $selector.expected_value
                                    }
                                }
                            }
                            catch {
                                Write-Verbose "Failed to read registry value for selector: $($_.Exception.Message)"
                            }
                        }
                        "script" {
                            try {
                                $scriptBlock = [ScriptBlock]::Create($selector.script)
                                $scriptResult = & $scriptBlock $MachineContext
                                $caseSensitive = if ($null -ne $selector.case_sensitive -and $selector.case_sensitive -ne "") { [bool]$selector.case_sensitive } else { $false }
                                if ($caseSensitive) {
                                    $result = $scriptResult -ceq $selector.expected_result
                                }
                                else {
                                    $result = $scriptResult -eq $selector.expected_result
                                }
                            }
                            catch {
                                Write-Verbose "Failed to execute selector script: $($_.Exception.Message)"
                            }
                        }
                    }
                    if ($result) {
                        $sectionMet = $true
                        break
                    }
                }
            }
        }
        if ($sectionMet) {
            Write-Verbose "Applying conditional section: $($section.name)"

            # Apply conditional configuration
            $configSections = @("files", "registry", "applications", "prerequisites", "stages")
            foreach ($configSection in $configSections) {
                if ($section.$configSection) {
                    # Add conditional items to resolved configuration
                    foreach ($item in $section.$configSection) {
                        if (-not $item.inheritance_source) {
                            $item | Add-Member -NotePropertyName "inheritance_source" -NotePropertyValue "conditional" -Force
                        }
                        if (-not $item.inheritance_priority) {
                            $item | Add-Member -NotePropertyName "inheritance_priority" -NotePropertyValue 70 -Force
                        }
                        if (-not $item.conditional_section) {
                            $item | Add-Member -NotePropertyName "conditional_section" -NotePropertyValue $section.name -Force
                        }
                    }

                    if ($ResolvedConfig.$configSection) {
                        $ResolvedConfig.$configSection = @($ResolvedConfig.$configSection) + @($section.$configSection)
                    }
                    else {
                        $ResolvedConfig | Add-Member -NotePropertyName $configSection -NotePropertyValue $section.$configSection -Force
                    }
                }
            }
        }
        else {
            Write-Verbose "Conditional section '$($section.name)' conditions not met, skipping"
        }
    }

    return $ResolvedConfig
}

# Functions are available when dot-sourced, no need to export when not in module context






