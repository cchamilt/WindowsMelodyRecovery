# Configuration Validation Functions for Windows Melody Recovery
# This module provides comprehensive validation for configuration consistency,
# shared configuration merging, and configuration inheritance patterns.

<#
.SYNOPSIS
    Tests configuration consistency across machine-specific and shared configurations.

.DESCRIPTION
    Validates that configuration structures are consistent between machine-specific
    and shared configurations, ensuring compatibility during merge operations.

.PARAMETER MachineConfig
    The machine-specific configuration hashtable to validate.

.PARAMETER SharedConfig
    The shared configuration hashtable to validate against.

.PARAMETER RequiredKeys
    Array of keys that must be present in both configurations.

.PARAMETER OptionalKeys
    Array of keys that may be present in either configuration.

.PARAMETER ValidationRules
    Custom validation rules to apply during consistency checking.

.EXAMPLE
    $result = Test-ConfigurationConsistency -MachineConfig $machineConfig -SharedConfig $sharedConfig -RequiredKeys @('BackupRoot', 'CloudProvider')
    
.OUTPUTS
    Returns a validation result object with Success, Errors, and Warnings properties.
#>
function Test-ConfigurationConsistency {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$MachineConfig,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$SharedConfig,
        
        [Parameter(Mandatory = $false)]
        [string[]]$RequiredKeys = @(),
        
        [Parameter(Mandatory = $false)]
        [string[]]$OptionalKeys = @(),
        
        [Parameter(Mandatory = $false)]
        [hashtable]$ValidationRules = @{}
    )
    
    $result = @{
        Success = $true
        Errors = @()
        Warnings = @()
        ValidationDetails = @{
            MachineConfigKeys = @($MachineConfig.Keys)
            SharedConfigKeys = @($SharedConfig.Keys)
            MissingRequiredKeys = @()
            TypeMismatches = @()
            StructuralInconsistencies = @()
            ValidationRuleResults = @()
        }
    }
    
    Write-Verbose "Starting configuration consistency validation..."
    Write-Verbose "Machine config keys: $($MachineConfig.Keys -join ', ')"
    Write-Verbose "Shared config keys: $($SharedConfig.Keys -join ', ')"
    
    # Validate required keys presence
    foreach ($key in $RequiredKeys) {
        $machineHasKey = $MachineConfig.ContainsKey($key)
        $sharedHasKey = $SharedConfig.ContainsKey($key)
        
        if (-not $machineHasKey -and -not $sharedHasKey) {
            $result.Errors += "Required key '$key' is missing from both machine and shared configurations"
            $result.ValidationDetails.MissingRequiredKeys += $key
            $result.Success = $false
        }
        elseif (-not $sharedHasKey) {
            $result.Warnings += "Required key '$key' is missing from shared configuration but present in machine configuration"
        }
    }
    
    # Validate type consistency for common keys
    $commonKeys = $MachineConfig.Keys | Where-Object { $SharedConfig.ContainsKey($_) }
    
    foreach ($key in $commonKeys) {
        $machineValue = $MachineConfig[$key]
        $sharedValue = $SharedConfig[$key]
        
        # Skip null values for type checking
        if ($null -eq $machineValue -or $null -eq $sharedValue) {
            continue
        }
        
        $machineType = $machineValue.GetType().Name
        $sharedType = $sharedValue.GetType().Name
        
        if ($machineType -ne $sharedType) {
            # Allow certain type conversions
            $allowedConversions = @{
                'String' = @('Int32', 'Boolean')
                'Int32' = @('String', 'Double')
                'Boolean' = @('String', 'Int32')
                'Hashtable' = @('PSCustomObject')
                'PSCustomObject' = @('Hashtable')
            }
            
            $isAllowedConversion = $allowedConversions.ContainsKey($machineType) -and 
                                 $allowedConversions[$machineType] -contains $sharedType
            
            if (-not $isAllowedConversion) {
                $result.Errors += "Type mismatch for key '$key': Machine config has type '$machineType', shared config has type '$sharedType'"
                $result.ValidationDetails.TypeMismatches += @{
                    Key = $key
                    MachineType = $machineType
                    SharedType = $sharedType
                }
                $result.Success = $false
            }
        }
        
        # Validate nested structure consistency
        if ($machineValue -is [hashtable] -and $sharedValue -is [hashtable]) {
            $nestedResult = Test-ConfigurationConsistency -MachineConfig $machineValue -SharedConfig $sharedValue -RequiredKeys $RequiredKeys -OptionalKeys $OptionalKeys -ValidationRules $ValidationRules
            
            if (-not $nestedResult.Success) {
                $result.Errors += "Nested structure inconsistency in key '$key': $($nestedResult.Errors -join '; ')"
                $result.ValidationDetails.StructuralInconsistencies += @{
                    Key = $key
                    NestedErrors = $nestedResult.Errors
                }
                $result.Success = $false
            }
            
            if ($nestedResult.Warnings.Count -gt 0) {
                $result.Warnings += $nestedResult.Warnings | ForEach-Object { "Nested warning in key '$key': $_" }
            }
        }
    }
    
    # Apply custom validation rules
    foreach ($ruleName in $ValidationRules.Keys) {
        $rule = $ValidationRules[$ruleName]
        
        try {
            Write-Verbose "Applying validation rule: $ruleName"
            $ruleResult = & $rule -MachineConfig $MachineConfig -SharedConfig $SharedConfig
            
            $result.ValidationDetails.ValidationRuleResults += @{
                RuleName = $ruleName
                Success = $ruleResult.Success
                Message = $ruleResult.Message
            }
            
            if (-not $ruleResult.Success) {
                $result.Errors += "Validation rule '$ruleName' failed: $($ruleResult.Message)"
                $result.Success = $false
            }
        }
        catch {
            $result.Errors += "Validation rule '$ruleName' threw an exception: $($_.Exception.Message)"
            $result.Success = $false
        }
    }
    
    Write-Verbose "Configuration consistency validation completed. Success: $($result.Success)"
    return $result
}

<#
.SYNOPSIS
    Validates shared configuration merging operations.

.DESCRIPTION
    Ensures that shared configuration merging follows proper inheritance rules
    and produces consistent results across different scenarios.

.PARAMETER BaseConfig
    The base (shared) configuration to merge from.

.PARAMETER OverrideConfig
    The override (machine-specific) configuration to merge.

.PARAMETER ExpectedKeys
    Array of keys that should be present in the merged result.

.PARAMETER MergingRules
    Custom rules for how specific keys should be merged.

.EXAMPLE
    $result = Validate-SharedConfigurationMerging -BaseConfig $sharedConfig -OverrideConfig $machineConfig -ExpectedKeys @('BackupRoot', 'CloudProvider')
    
.OUTPUTS
    Returns a validation result with merging analysis and recommendations.
#>
function Validate-SharedConfigurationMerging {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$BaseConfig,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$OverrideConfig,
        
        [Parameter(Mandatory = $false)]
        [string[]]$ExpectedKeys = @(),
        
        [Parameter(Mandatory = $false)]
        [hashtable]$MergingRules = @{}
    )
    
    $result = @{
        Success = $true
        Errors = @()
        Warnings = @()
        MergedConfig = $null
        MergingAnalysis = @{
            OverriddenKeys = @()
            PreservedKeys = @()
            AddedKeys = @()
            MissingExpectedKeys = @()
            UnexpectedBehavior = @()
        }
    }
    
    Write-Verbose "Starting shared configuration merging validation..."
    
    try {
        # Perform the merge operation
        $mergedConfig = Merge-Configurations -Base $BaseConfig -Override $OverrideConfig
        $result.MergedConfig = $mergedConfig
        
        # Analyze merging results
        $allKeys = @($BaseConfig.Keys) + @($OverrideConfig.Keys) | Sort-Object -Unique
        
        foreach ($key in $allKeys) {
            $inBase = $BaseConfig.ContainsKey($key)
            $inOverride = $OverrideConfig.ContainsKey($key)
            $inMerged = $mergedConfig.ContainsKey($key)
            
            if ($inOverride -and $inBase) {
                # Key exists in both - should be overridden
                if ($mergedConfig[$key] -eq $OverrideConfig[$key]) {
                    $result.MergingAnalysis.OverriddenKeys += $key
                } else {
                    $result.Errors += "Key '$key' was not properly overridden during merge"
                    $result.MergingAnalysis.UnexpectedBehavior += @{
                        Key = $key
                        Expected = $OverrideConfig[$key]
                        Actual = $mergedConfig[$key]
                        Issue = "Override not applied"
                    }
                    $result.Success = $false
                }
            }
            elseif ($inOverride -and -not $inBase) {
                # Key only in override - should be added
                if ($inMerged -and $mergedConfig[$key] -eq $OverrideConfig[$key]) {
                    $result.MergingAnalysis.AddedKeys += $key
                } else {
                    $result.Errors += "Key '$key' from override configuration was not properly added during merge"
                    $result.Success = $false
                }
            }
            elseif ($inBase -and -not $inOverride) {
                # Key only in base - should be preserved
                if ($inMerged -and $mergedConfig[$key] -eq $BaseConfig[$key]) {
                    $result.MergingAnalysis.PreservedKeys += $key
                } else {
                    $result.Errors += "Key '$key' from base configuration was not properly preserved during merge"
                    $result.Success = $false
                }
            }
        }
        
        # Validate expected keys are present
        foreach ($key in $ExpectedKeys) {
            if (-not $mergedConfig.ContainsKey($key)) {
                $result.Errors += "Expected key '$key' is missing from merged configuration"
                $result.MergingAnalysis.MissingExpectedKeys += $key
                $result.Success = $false
            }
        }
        
        # Apply custom merging rules
        foreach ($ruleName in $MergingRules.Keys) {
            $rule = $MergingRules[$ruleName]
            
            try {
                Write-Verbose "Applying merging rule: $ruleName"
                $ruleResult = & $rule -BaseConfig $BaseConfig -OverrideConfig $OverrideConfig -MergedConfig $mergedConfig
                
                if (-not $ruleResult.Success) {
                    $result.Errors += "Merging rule '$ruleName' failed: $($ruleResult.Message)"
                    $result.Success = $false
                }
            }
            catch {
                $result.Errors += "Merging rule '$ruleName' threw an exception: $($_.Exception.Message)"
                $result.Success = $false
            }
        }
        
        # Generate recommendations
        if ($result.MergingAnalysis.OverriddenKeys.Count -gt 0) {
            $result.Warnings += "The following keys were overridden by machine configuration: $($result.MergingAnalysis.OverriddenKeys -join ', ')"
        }
        
        if ($result.MergingAnalysis.AddedKeys.Count -gt 0) {
            $result.Warnings += "The following keys were added from machine configuration: $($result.MergingAnalysis.AddedKeys -join ', ')"
        }
        
    }
    catch {
        $result.Errors += "Merge operation failed: $($_.Exception.Message)"
        $result.Success = $false
    }
    
    Write-Verbose "Shared configuration merging validation completed. Success: $($result.Success)"
    return $result
}

<#
.SYNOPSIS
    Tests configuration inheritance patterns.

.DESCRIPTION
    Validates that configuration inheritance follows proper hierarchical patterns
    and maintains consistency across different levels of configuration.

.PARAMETER ConfigurationHierarchy
    Array of configuration hashtables ordered from lowest to highest priority.

.PARAMETER InheritanceRules
    Rules defining how inheritance should work for specific keys.

.PARAMETER ValidationSchema
    Schema defining required and optional keys at each level.

.EXAMPLE
    $hierarchy = @($moduleDefaults, $sharedConfig, $machineConfig)
    $result = Test-ConfigurationInheritance -ConfigurationHierarchy $hierarchy -InheritanceRules $rules
    
.OUTPUTS
    Returns a validation result with inheritance analysis and final merged configuration.
#>
function Test-ConfigurationInheritance {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable[]]$ConfigurationHierarchy,
        
        [Parameter(Mandatory = $false)]
        [hashtable]$InheritanceRules = @{},
        
        [Parameter(Mandatory = $false)]
        [hashtable]$ValidationSchema = @{}
    )
    
    $result = @{
        Success = $true
        Errors = @()
        Warnings = @()
        FinalConfiguration = $null
        InheritanceAnalysis = @{
            LevelCount = $ConfigurationHierarchy.Count
            InheritanceChain = @()
            KeyOrigins = @{}
            OverrideHistory = @()
            SchemaValidation = @()
        }
    }
    
    Write-Verbose "Starting configuration inheritance validation with $($ConfigurationHierarchy.Count) levels..."
    
    if ($ConfigurationHierarchy.Count -eq 0) {
        $result.Errors += "Configuration hierarchy is empty"
        $result.Success = $false
        return $result
    }
    
    try {
        # Start with the base configuration (lowest priority)
        $currentConfig = $ConfigurationHierarchy[0].Clone()
        $result.InheritanceAnalysis.InheritanceChain += @{
            Level = 0
            Description = "Base Configuration"
            Keys = @($currentConfig.Keys)
            KeyCount = $currentConfig.Keys.Count
        }
        
        # Track key origins
        foreach ($key in $currentConfig.Keys) {
            $result.InheritanceAnalysis.KeyOrigins[$key] = @{
                OriginLevel = 0
                OriginDescription = "Base Configuration"
                OverrideHistory = @()
            }
        }
        
        # Apply each subsequent configuration level
        for ($i = 1; $i -lt $ConfigurationHierarchy.Count; $i++) {
            $overrideConfig = $ConfigurationHierarchy[$i]
            $levelDescription = "Level $i Configuration"
            
            Write-Verbose "Applying $levelDescription with $($overrideConfig.Keys.Count) keys..."
            
            # Track what keys will be overridden
            $overriddenKeys = @()
            $addedKeys = @()
            
            foreach ($key in $overrideConfig.Keys) {
                if ($currentConfig.ContainsKey($key)) {
                    $overriddenKeys += $key
                    
                    # Update override history
                    if (-not $result.InheritanceAnalysis.KeyOrigins.ContainsKey($key)) {
                        $result.InheritanceAnalysis.KeyOrigins[$key] = @{
                            OriginLevel = $i
                            OriginDescription = $levelDescription
                            OverrideHistory = @()
                        }
                    }
                    
                    $result.InheritanceAnalysis.KeyOrigins[$key].OverrideHistory += @{
                        Level = $i
                        Description = $levelDescription
                        OldValue = $currentConfig[$key]
                        NewValue = $overrideConfig[$key]
                    }
                } else {
                    $addedKeys += $key
                    $result.InheritanceAnalysis.KeyOrigins[$key] = @{
                        OriginLevel = $i
                        OriginDescription = $levelDescription
                        OverrideHistory = @()
                    }
                }
            }
            
            # Apply inheritance rules if specified
            $processedOverrideConfig = $overrideConfig.Clone()
            
            foreach ($ruleName in $InheritanceRules.Keys) {
                $rule = $InheritanceRules[$ruleName]
                
                try {
                    Write-Verbose "Applying inheritance rule: $ruleName at level $i"
                    $ruleResult = & $rule -CurrentConfig $currentConfig -OverrideConfig $processedOverrideConfig -Level $i
                    
                    if ($ruleResult.ModifiedConfig) {
                        $processedOverrideConfig = $ruleResult.ModifiedConfig
                    }
                    
                    if (-not $ruleResult.Success) {
                        $result.Errors += "Inheritance rule '$ruleName' failed at level $i`: $($ruleResult.Message)"
                        $result.Success = $false
                    }
                }
                catch {
                    $result.Errors += "Inheritance rule '$ruleName' threw an exception at level $i`: $($_.Exception.Message)"
                    $result.Success = $false
                }
            }
            
            # Perform the merge
            $currentConfig = Merge-Configurations -Base $currentConfig -Override $processedOverrideConfig
            
            # Record inheritance chain information
            $result.InheritanceAnalysis.InheritanceChain += @{
                Level = $i
                Description = $levelDescription
                Keys = @($overrideConfig.Keys)
                KeyCount = $overrideConfig.Keys.Count
                OverriddenKeys = $overriddenKeys
                AddedKeys = $addedKeys
            }
            
            $result.InheritanceAnalysis.OverrideHistory += @{
                Level = $i
                Description = $levelDescription
                OverriddenKeys = $overriddenKeys
                AddedKeys = $addedKeys
                TotalKeysAfterMerge = $currentConfig.Keys.Count
            }
        }
        
        $result.FinalConfiguration = $currentConfig
        
        # Validate against schema if provided
        if ($ValidationSchema.Count -gt 0) {
            Write-Verbose "Validating final configuration against schema..."
            
            foreach ($schemaKey in $ValidationSchema.Keys) {
                $schemaRule = $ValidationSchema[$schemaKey]
                
                $validationResult = @{
                    Key = $schemaKey
                    Required = $schemaRule.Required -eq $true
                    Present = $currentConfig.ContainsKey($schemaKey)
                    TypeValid = $false
                    ValueValid = $false
                }
                
                if ($validationResult.Required -and -not $validationResult.Present) {
                    $result.Errors += "Required key '$schemaKey' is missing from final configuration"
                    $result.Success = $false
                }
                
                if ($validationResult.Present) {
                    $value = $currentConfig[$schemaKey]
                    
                    # Type validation
                    if ($schemaRule.Type) {
                        $validationResult.TypeValid = $value.GetType().Name -eq $schemaRule.Type
                        if (-not $validationResult.TypeValid) {
                            $result.Errors += "Key '$schemaKey' has invalid type. Expected: $($schemaRule.Type), Actual: $($value.GetType().Name)"
                            $result.Success = $false
                        }
                    }
                    
                    # Value validation
                    if ($schemaRule.Validator) {
                        try {
                            $validationResult.ValueValid = & $schemaRule.Validator -Value $value
                            if (-not $validationResult.ValueValid) {
                                $result.Errors += "Key '$schemaKey' failed value validation"
                                $result.Success = $false
                            }
                        }
                        catch {
                            $result.Errors += "Value validation for key '$schemaKey' threw an exception: $($_.Exception.Message)"
                            $result.Success = $false
                        }
                    }
                }
                
                $result.InheritanceAnalysis.SchemaValidation += $validationResult
            }
        }
        
        # Generate summary warnings
        $totalOverrides = 0
        foreach ($override in $result.InheritanceAnalysis.OverrideHistory) {
            if ($override.OverriddenKeys) {
                if ($override.OverriddenKeys -is [array]) {
                    $totalOverrides += $override.OverriddenKeys.Count
                } else {
                    $totalOverrides += 1
                }
            }
        }
        
        if ($totalOverrides -gt 0) {
            $result.Warnings += "Total of $totalOverrides key overrides occurred during inheritance"
        }
        
        $finalKeyCount = $currentConfig.Keys.Count
        $result.Warnings += "Final configuration contains $finalKeyCount keys after inheritance"
        
    }
    catch {
        $result.Errors += "Configuration inheritance failed: $($_.Exception.Message)"
        $result.Success = $false
    }
    
    Write-Verbose "Configuration inheritance validation completed. Success: $($result.Success)"
    return $result
}

<#
.SYNOPSIS
    Validates configuration file paths and accessibility.

.DESCRIPTION
    Ensures that configuration files exist, are accessible, and contain valid data.

.PARAMETER ConfigurationPaths
    Array of configuration file paths to validate.

.PARAMETER AccessibilityChecks
    Whether to perform file accessibility checks.

.PARAMETER ContentValidation
    Whether to validate configuration file contents.

.EXAMPLE
    $result = Test-ConfigurationFilePaths -ConfigurationPaths @($machineConfigPath, $sharedConfigPath) -AccessibilityChecks $true -ContentValidation $true
    
.OUTPUTS
    Returns a validation result with file path analysis and accessibility status.
#>
function Test-ConfigurationFilePaths {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$ConfigurationPaths,
        
        [Parameter(Mandatory = $false)]
        [bool]$AccessibilityChecks = $true,
        
        [Parameter(Mandatory = $false)]
        [bool]$ContentValidation = $true
    )
    
    $result = @{
        Success = $true
        Errors = @()
        Warnings = @()
        PathAnalysis = @()
    }
    
    Write-Verbose "Starting configuration file path validation for $($ConfigurationPaths.Count) paths..."
    
    foreach ($path in $ConfigurationPaths) {
        $pathResult = @{
            Path = $path
            Exists = $false
            Accessible = $false
            ValidContent = $false
            Size = 0
            LastModified = $null
            Extension = $null
            Issues = @()
        }
        
        try {
            # Check if path exists
            $pathResult.Exists = Test-Path -Path $path
            $pathResult.Extension = [System.IO.Path]::GetExtension($path)
            
            if (-not $pathResult.Exists) {
                $pathResult.Issues += "File does not exist"
                $result.Warnings += "Configuration file does not exist: $path"
            } else {
                $fileInfo = Get-Item -Path $path
                $pathResult.Size = $fileInfo.Length
                $pathResult.LastModified = $fileInfo.LastWriteTime
                
                # Accessibility checks
                if ($AccessibilityChecks) {
                    try {
                        $content = Get-Content -Path $path -Raw -ErrorAction Stop
                        $pathResult.Accessible = $true
                        
                        # Content validation
                        if ($ContentValidation) {
                            switch ($pathResult.Extension.ToLower()) {
                                '.json' {
                                    try {
                                        $jsonContent = $content | ConvertFrom-Json
                                        $pathResult.ValidContent = $true
                                    }
                                    catch {
                                        $pathResult.Issues += "Invalid JSON content: $($_.Exception.Message)"
                                        $result.Errors += "Invalid JSON in configuration file $path`: $($_.Exception.Message)"
                                        $result.Success = $false
                                    }
                                }
                                { $_ -in @('.yaml', '.yml') } {
                                    # Basic YAML validation (would need PowerShell-Yaml module for full validation)
                                    if ($content.Trim().Length -gt 0) {
                                        $pathResult.ValidContent = $true
                                    } else {
                                        $pathResult.Issues += "Empty YAML content"
                                        $result.Warnings += "Empty YAML content in configuration file: $path"
                                    }
                                }
                                '.xml' {
                                    try {
                                        $xmlContent = [xml]$content
                                        $pathResult.ValidContent = $true
                                    }
                                    catch {
                                        $pathResult.Issues += "Invalid XML content: $($_.Exception.Message)"
                                        $result.Errors += "Invalid XML in configuration file $path`: $($_.Exception.Message)"
                                        $result.Success = $false
                                    }
                                }
                                default {
                                    $pathResult.ValidContent = $true  # Assume valid for unknown extensions
                                }
                            }
                        }
                    }
                    catch {
                        $pathResult.Issues += "File access error: $($_.Exception.Message)"
                        $result.Errors += "Cannot access configuration file $path`: $($_.Exception.Message)"
                        $result.Success = $false
                    }
                }
                
                # File size warnings
                if ($pathResult.Size -eq 0) {
                    $pathResult.Issues += "File is empty"
                    $result.Warnings += "Configuration file is empty: $path"
                }
                elseif ($pathResult.Size -gt 1MB) {
                    $pathResult.Issues += "File is unusually large (>1MB)"
                    $result.Warnings += "Configuration file is unusually large: $path ($($pathResult.Size) bytes)"
                }
            }
        }
        catch {
            $pathResult.Issues += "Path validation error: $($_.Exception.Message)"
            $result.Errors += "Error validating configuration path $path`: $($_.Exception.Message)"
            $result.Success = $false
        }
        
        $result.PathAnalysis += $pathResult
    }
    
    Write-Verbose "Configuration file path validation completed. Success: $($result.Success)"
    return $result
}

# Export functions for module use
# Functions are available when dot-sourced
