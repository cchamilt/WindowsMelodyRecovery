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
        [Parameter(Mandatory=$true)]
        [PSObject]$ResolvedConfig,

        [Parameter(Mandatory=$true)]
        [array]$InheritanceRules,

        [Parameter(Mandatory=$true)]
        [PSObject]$MachineContext
    )

    foreach ($rule in $InheritanceRules) {
        Write-Verbose "Processing inheritance rule: $($rule.name)"

        # Check if rule conditions are met
        if (Test-WmrInheritanceRuleCondition -Rule $rule -MachineContext $MachineContext) {
            Write-Verbose "Applying inheritance rule: $($rule.name)"

            # Apply rule to matching configuration sections
            foreach ($section in $rule.applies_to) {
                if ($ResolvedConfig.$section) {
                    $ResolvedConfig.$section = Invoke-WmrInheritanceRuleToSection -Items $ResolvedConfig.$section -Rule $rule -MachineContext $MachineContext
                }
            }
        } else {
            Write-Verbose "Inheritance rule '$($rule.name)' conditions not met, skipping"
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
    [OutputType([System.Boolean])]
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
        # Import Test-WmrMachineSelector from MachineContext module
        return Test-WmrMachineSelector -MachineSelectors $Rule.condition.machine_selectors -MachineContext $MachineContext
    }

    return $true
}

function Invoke-WmrInheritanceRuleToSection {
    <#
    .SYNOPSIS
        Applies an inheritance rule to a specific configuration section.
    #>
    [CmdletBinding()]
    [OutputType([System.Array])]
    param(
        [Parameter(Mandatory=$true)]
        [array]$Items,

        [Parameter(Mandatory=$true)]
        [PSObject]$Rule,

        [Parameter(Mandatory=$true)]
        [PSObject]$MachineContext
    )

    # Filter items that match the rule conditions
    $matchingItems = @()
    $nonMatchingItems = @()

    foreach ($item in $Items) {
        if (Test-WmrRuleItemMatch -Item $item -Rule $Rule) {
            $matchingItems += $item
        } else {
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
            } elseif ($Rule.script) {
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
                if (Test-WmrConfigurationItemValidity -Item $item -Rule $Rule) {
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
        [Parameter(Mandatory=$true)]
        [PSObject]$ResolvedConfig,

        [Parameter(Mandatory=$true)]
        [array]$ConditionalSections,

        [Parameter(Mandatory=$true)]
        [PSObject]$MachineContext
    )

    foreach ($section in $ConditionalSections) {
        Write-Verbose "Processing conditional section: $($section.name)"

        # Check if conditions are met
        if (Test-WmrConditionalSectionCondition -ConditionalSection $section -MachineContext $MachineContext) {
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
                    }

                    if ($ResolvedConfig.$configSection) {
                        $ResolvedConfig.$configSection = @($ResolvedConfig.$configSection) + @($section.$configSection)
                    } else {
                        $ResolvedConfig | Add-Member -NotePropertyName $configSection -NotePropertyValue $section.$configSection -Force
                    }
                }
            }
        } else {
            Write-Verbose "Conditional section '$($section.name)' conditions not met, skipping"
        }
    }

    return $ResolvedConfig
}

function Test-WmrConditionalSectionCondition {
    <#
    .SYNOPSIS
        Tests if conditional section conditions are met.
    #>
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param(
        [Parameter(Mandatory=$true)]
        [PSObject]$ConditionalSection,

        [Parameter(Mandatory=$true)]
        [PSObject]$MachineContext
    )

    if (-not $ConditionalSection.conditions) {
        return $true  # No conditions means always apply
    }

    $logic = if ($ConditionalSection.logic) { $ConditionalSection.logic } else { "and" }
    $conditionResults = @()

    foreach ($condition in $ConditionalSection.conditions) {
        $result = $false

        switch ($condition.type) {
            "custom_script" {
                try {
                    $scriptBlock = [ScriptBlock]::Create($condition.check)
                    $scriptResult = & $scriptBlock $MachineContext
                    $result = Test-WmrStringComparison -Value $scriptResult -Expected $condition.expected_result -Operator "equals"
                } catch {
                    Write-Verbose "Failed to execute conditional script: $($_.Exception.Message)"
                    $result = $false
                }
            }
            "hardware_check" {
                try {
                    $scriptBlock = [ScriptBlock]::Create($condition.check)
                    $checkResult = & $scriptBlock
                    $result = $checkResult -match $condition.expected_result
                } catch {
                    Write-Verbose "Failed to execute hardware check: $($_.Exception.Message)"
                    $result = $false
                }
            }
            "environment_variable" {
                $envValue = $MachineContext.EnvironmentVariables[$condition.variable]
                if ($envValue) {
                    $result = Test-WmrStringComparison -Value $envValue -Expected $condition.expected_value -Operator $condition.operator
                } else {
                    $result = $false
                }
            }
            default {
                Write-Warning "Unknown conditional section condition type: $($condition.type)"
                $result = $false
            }
        }

        $conditionResults += $result
    }

    # Apply logic
    switch ($logic) {
        "and" {
            return ($conditionResults -notcontains $false)
        }
        "or" {
            return ($conditionResults -contains $true)
        }
        "not" {
            return ($conditionResults -notcontains $true)
        }
        default {
            Write-Warning "Unknown conditional logic: $logic"
            return $false
        }
    }
}

function Test-WmrRuleItemMatch {
    <#
    .SYNOPSIS
        Tests if an item matches a rule condition.
    #>
    [CmdletBinding()]
    [OutputType([System.Boolean])]
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

# Functions are available when dot-sourced, no need to export when not in module context