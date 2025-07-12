# Private/Core/ConfigurationMerging.ps1

<#
.SYNOPSIS
    Configuration merging and conflict resolution functionality for Windows Melody Recovery template inheritance.

.DESCRIPTION
    Provides functions to merge shared and machine-specific configurations with sophisticated
    conflict resolution, priority handling, and merge strategies.

.NOTES
    Author: Windows Melody Recovery
    Version: 2.0
    Requires: PowerShell 5.1 or later
#>

function Merge-WmrSharedConfiguration {
    <#
    .SYNOPSIS
        Merges shared configuration into the resolved configuration.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSObject])]
    param(
        [Parameter(Mandatory = $true)]
        [PSObject]$ResolvedConfig,

        [Parameter(Mandatory = $true)]
        [PSObject]$SharedConfig,

        [Parameter(Mandatory = $true)]
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
            }
            else {
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
    [OutputType([System.Management.Automation.PSObject])]
    param(
        [Parameter(Mandatory = $true)]
        [PSObject]$ResolvedConfig,

        [Parameter(Mandatory = $true)]
        [PSObject]$MachineConfig,

        [Parameter(Mandatory = $true)]
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
                    if ($ResolvedConfig.PSObject.Properties.Name -contains $section) {
                        $ResolvedConfig.$section = $machineItems
                    }
                    else {
                        $ResolvedConfig | Add-Member -NotePropertyName $section -NotePropertyValue $machineItems -Force
                    }
                }
                "shallow_merge" {
                    # Simple append
                    if ($ResolvedConfig.PSObject.Properties.Name -contains $section -and $ResolvedConfig.$section) {
                        $ResolvedConfig.$section = @($ResolvedConfig.$section) + @($machineItems)
                    }
                    else {
                        $ResolvedConfig | Add-Member -NotePropertyName $section -NotePropertyValue $machineItems -Force
                    }
                }
                "deep_merge" {
                    # Merge items with same inheritance tags or names
                    $mergedItems = Merge-WmrConfigurationItem -ExistingItems $ResolvedConfig.$section -NewItems $machineItems -InheritanceConfig $InheritanceConfig
                    if ($ResolvedConfig.PSObject.Properties.Name -contains $section) {
                        $ResolvedConfig.$section = $mergedItems
                    }
                    else {
                        $ResolvedConfig | Add-Member -NotePropertyName $section -NotePropertyValue $mergedItems -Force
                    }
                }
            }
        }
    }

    return $ResolvedConfig
}

function Merge-WmrConfigurationItem {
    <#
    .SYNOPSIS
        Merges configuration items with intelligent conflict resolution.
    #>
    [CmdletBinding()]
    [OutputType([System.Array])]
    param(
        [Parameter(Mandatory = $false)]
        [array]$ExistingItems,

        [Parameter(Mandatory = $true)]
        [array]$NewItems,

        [Parameter(Mandatory = $true)]
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
            $mergedItem = Merge-WmrSingleConfigurationItem -ExistingItem $matchingItem -NewItem $newItem -InheritanceConfig $InheritanceConfig
            $index = $mergedItems.IndexOf($matchingItem)
            $mergedItems[$index] = $mergedItem
        }
        else {
            # Add new item
            $mergedItems += $newItem
        }
    }

    return $mergedItems
}

function Merge-WmrSingleConfigurationItem {
    <#
    .SYNOPSIS
        Merges two configuration items with conflict resolution.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSObject])]
    param(
        [Parameter(Mandatory = $true)]
        [PSObject]$ExistingItem,

        [Parameter(Mandatory = $true)]
        [PSObject]$NewItem,

        [Parameter(Mandatory = $true)]
        [hashtable]$InheritanceConfig
    )

    # Determine which item has higher priority
    $existingPriority = if ($ExistingItem.inheritance_priority) { $ExistingItem.inheritance_priority } else { 50 }
    $newPriority = if ($NewItem.inheritance_priority) { $NewItem.inheritance_priority } else { 50 }

    # Determine conflict resolution strategy
    $conflictResolution = "machine_wins"
    if ($NewItem.conflict_resolution) {
        $conflictResolution = $NewItem.conflict_resolution
    }
    elseif ($ExistingItem.conflict_resolution) {
        $conflictResolution = $ExistingItem.conflict_resolution
    }
    elseif ($InheritanceConfig.machine_precedence) {
        $conflictResolution = "machine_wins"
    }
    else {
        $conflictResolution = "shared_wins"
    }

    # Apply conflict resolution
    switch ($conflictResolution) {
        "machine_wins" {
            if ($NewItem.inheritance_source -eq "machine_specific") {
                # Machine-specific completely replaces shared
                Write-Verbose "Machine-specific item wins, replacing shared configuration"
                return $NewItem
            }
            elseif ($InheritanceConfig.machine_precedence -and $newPriority -gt $existingPriority) {
                # Higher priority wins when machine precedence is enabled
                Write-Verbose "Higher priority item wins due to machine precedence"
                return $NewItem
            }
            else {
                # Keep existing item but update inheritance info
                Write-Verbose "Keeping existing item (no machine override)"
                return $ExistingItem
            }
        }
        "shared_wins" {
            if ($ExistingItem.inheritance_source -eq "shared") {
                # Keep existing (shared wins)
                Write-Verbose "Shared item wins, keeping existing"
                return $ExistingItem
            }
            else {
                # New item wins
                Write-Verbose "New item wins over non-shared existing"
                return $NewItem
            }
        }
        "merge_both" {
            # Create merged item by deep copying existing and adding new properties
            $mergedItem = $ExistingItem | ConvertTo-Json -Depth 100 | ConvertFrom-Json

            # Merge properties from new item (excluding metadata)
            foreach ($prop in $NewItem.PSObject.Properties) {
                if ($prop.Name -notin @("inheritance_source", "inheritance_priority", "conflict_resolution")) {
                    try {
                        $mergedItem | Add-Member -NotePropertyName $prop.Name -NotePropertyValue $prop.Value -Force
                    }
                    catch {
                        Write-Verbose "Failed to set property $($prop.Name): $($_.Exception.Message)"
                    }
                }
            }

            Write-Verbose "Merged both items"
            return $mergedItem
        }
        default {
            # Default to higher priority wins
            if ($newPriority -gt $existingPriority) {
                Write-Verbose "New item wins by priority ($newPriority > $existingPriority)"
                return $NewItem
            }
            else {
                Write-Verbose "Existing item wins by priority ($existingPriority >= $newPriority)"
                return $ExistingItem
            }
        }
    }
}

function Merge-WmrRegistryValue {
    <#
    .SYNOPSIS
        Merges registry values according to inheritance rules.
    #>
    [CmdletBinding()]
    [OutputType([System.Array])]
    param(
        [Parameter(Mandatory = $true)]
        [array]$Items,

        [Parameter(Mandatory = $true)]
        [PSObject]$Rule
    )

    $conflictResolution = if ($Rule.parameters.conflict_resolution) { $Rule.parameters.conflict_resolution } else { "machine_wins" }

    # Group items by registry path
    $groupedItems = $Items | Group-Object -Property path

    $mergedItems = @()
    foreach ($group in $groupedItems) {
        if ($group.Count -eq 1) {
            $mergedItems += $group.Group[0]
        }
        else {
            # Merge multiple items for same path
            $mergedItem = $group.Group[0] | ConvertTo-Json -Depth 100 | ConvertFrom-Json

            # Apply conflict resolution
            foreach ($item in $group.Group[1..($group.Count - 1)]) {
                switch ($conflictResolution) {
                    "machine_wins" {
                        if ($item.inheritance_source -eq "machine_specific") {
                            $mergedItem = $item
                        }
                    }
                    "shared_wins" {
                        if ($mergedItem.inheritance_source -eq "shared") {
                            # Keep merged item
                        }
                        else {
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

# Functions are available when dot-sourced, no need to export when not in module context






