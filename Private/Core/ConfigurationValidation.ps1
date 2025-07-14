# Private/Core/ConfigurationValidation.ps1

<#
.SYNOPSIS
    Configuration validation functionality for Windows Melody Recovery template inheritance.

.DESCRIPTION
    Provides functions to validate resolved configurations at different levels (strict, moderate, relaxed)
    and ensure configuration items meet requirements and constraints.

.NOTES
    Author: Windows Melody Recovery
    Version: 2.0
    Requires: PowerShell 5.1 or later
#>

function Test-ConfigurationConsistency {
    <#
    .SYNOPSIS
        Tests consistency between machine and shared configurations.
    .DESCRIPTION
        Stub implementation for testing purposes.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSObject])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$MachineConfig,

        [Parameter(Mandatory = $true)]
        [hashtable]$SharedConfig,

        [Parameter(Mandatory = $false)]
        [array]$RequiredKeys = @(),

        [Parameter(Mandatory = $false)]
        [hashtable]$ValidationRules = @{}
    )

    $result = [PSCustomObject]@{
        Success           = $true
        Errors            = @()
        ValidationDetails = @{
            MachineConfigKeys     = $MachineConfig.Keys
            SharedConfigKeys      = $SharedConfig.Keys
            MissingRequiredKeys   = @()
            TypeMismatches        = @()
            ValidationRuleResults = @()
        }
    }

    # Check required keys
    foreach ($key in $RequiredKeys) {
        if (-not $MachineConfig.ContainsKey($key) -and -not $SharedConfig.ContainsKey($key)) {
            $result.Success = $false
            $result.Errors += "Required key '$key' is missing from both machine and shared configurations"
            $result.ValidationDetails.MissingRequiredKeys += $key
        }
    }

    # Check type consistency
    foreach ($key in $MachineConfig.Keys) {
        if ($SharedConfig.ContainsKey($key)) {
            $machineType = $MachineConfig[$key].GetType()
            $sharedType = $SharedConfig[$key].GetType()
            if ($machineType -ne $sharedType) {
                $result.Success = $false
                $result.Errors += "Type mismatch for key '$key': Machine ($($machineType.Name)) vs Shared ($($sharedType.Name))"
                $result.ValidationDetails.TypeMismatches += @{
                    Key         = $key
                    MachineType = $machineType.Name
                    SharedType  = $sharedType.Name
                }
            }
        }
    }

    # Apply custom validation rules
    foreach ($ruleName in $ValidationRules.Keys) {
        $ruleResult = & $ValidationRules[$ruleName] $MachineConfig $SharedConfig
        $result.ValidationDetails.ValidationRuleResults += [PSCustomObject]@{
            RuleName = $ruleName
            Success  = $ruleResult.Success
            Message  = $ruleResult.Message
        }
        if (-not $ruleResult.Success) {
            $result.Success = $false
            $result.Errors += $ruleResult.Message
        }
    }

    return $result
}

function Test-SharedConfigurationMerging {
    <#
    .SYNOPSIS
        Tests shared configuration merging operations.
    #>
    [CmdletBinding()]
    [OutputType([PSObject])]
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

    # Helper function for deep cloning hashtables
    function Copy-Hashtable {
        param([hashtable]$Source)
        $clone = @{}
        foreach ($key in $Source.Keys) {
            if ($Source[$key] -is [hashtable]) {
                $clone[$key] = Copy-Hashtable $Source[$key]
            }
            else {
                $clone[$key] = $Source[$key]
            }
        }
        return $clone
    }

    # Helper function for deep merging hashtables
    function Merge-Hashtable {
        param(
            [hashtable]$Base,
            [hashtable]$Override,
            [ref]$OverriddenKeys,
            [ref]$AddedKeys
        )

        $merged = Copy-Hashtable $Base

        foreach ($key in $Override.Keys) {
            if ($merged.ContainsKey($key)) {
                # Key exists in base, check if it's a hashtable for deep merge
                if ($merged[$key] -is [hashtable] -and $Override[$key] -is [hashtable]) {
                    # Deep merge nested hashtables
                    $nestedOverridden = @()
                    $nestedAdded = @()
                    $merged[$key] = Merge-Hashtable $merged[$key] $Override[$key] ([ref]$nestedOverridden) ([ref]$nestedAdded)

                    # Only mark as overridden if something actually changed
                    if ($nestedOverridden.Count -gt 0 -or $nestedAdded.Count -gt 0) {
                        $OverriddenKeys.Value += $key
                    }
                }
                else {
                    # Simple override
                    $merged[$key] = $Override[$key]
                    $OverriddenKeys.Value += $key
                }
            }
            else {
                # New key
                $merged[$key] = $Override[$key]
                $AddedKeys.Value += $key
            }
        }

        return $merged
    }

    try {
        # Perform deep merge
        $overriddenKeys = @()
        $addedKeys = @()
        $merged = Merge-Hashtable $BaseConfig $OverrideConfig ([ref]$overriddenKeys) ([ref]$addedKeys)

        # Find preserved keys
        $preservedKeys = @()
        foreach ($key in $BaseConfig.Keys) {
            if (-not ($key -in $overriddenKeys)) {
                $preservedKeys += $key
            }
        }

        # Apply custom merging rules
        foreach ($ruleName in $MergingRules.Keys) {
            $rule = $MergingRules[$ruleName]
            $ruleResult = & $rule $BaseConfig $OverrideConfig $merged
            if (-not $ruleResult.Success) {
                return @{
                    Success         = $false
                    Errors          = @($ruleResult.Message)
                    MergedConfig    = $merged
                    MergingAnalysis = @{
                        OverriddenKeys      = $overriddenKeys
                        PreservedKeys       = $preservedKeys
                        AddedKeys           = $addedKeys
                        MissingExpectedKeys = @()
                    }
                }
            }
        }

        # Check for missing expected keys
        $missingKeys = @()
        foreach ($expectedKey in $ExpectedKeys) {
            if (-not $merged.ContainsKey($expectedKey)) {
                $missingKeys += $expectedKey
            }
        }

        $errors = @()
        if ($missingKeys.Count -gt 0) {
            $errors += $missingKeys | ForEach-Object { "Expected key '$_' is missing from merged configuration" }
        }

        return @{
            Success         = $errors.Count -eq 0
            Errors          = $errors
            MergedConfig    = $merged
            MergingAnalysis = @{
                OverriddenKeys      = $overriddenKeys
                PreservedKeys       = $preservedKeys
                AddedKeys           = $addedKeys
                MissingExpectedKeys = $missingKeys
            }
        }
    }
    catch {
        return @{
            Success         = $false
            Errors          = @("Configuration merging failed: $($_.Exception.Message)")
            MergedConfig    = @{}
            MergingAnalysis = @{
                OverriddenKeys      = @()
                PreservedKeys       = @()
                AddedKeys           = @()
                MissingExpectedKeys = @()
            }
        }
    }
}

function Test-ConfigurationInheritance {
    <#
    .SYNOPSIS
        Tests configuration inheritance hierarchy.
    #>
    [CmdletBinding()]
    [OutputType([PSObject])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Hashtable[]]$ConfigurationHierarchy,

        [Parameter(Mandatory = $false)]
        [hashtable]$InheritanceRules = @{},

        [Parameter(Mandatory = $false)]
        [hashtable]$ValidationSchema = @{}
    )

    try {
        if ($ConfigurationHierarchy.Count -eq 0) {
            return @{
                Success             = $false
                Errors              = @("Configuration hierarchy is empty")
                FinalConfiguration  = @{}
                InheritanceAnalysis = @{
                    LevelCount       = 0
                    InheritanceChain = @()
                    KeyOrigins       = @{}
                    SchemaValidation = @()
                }
            }
        }

        # Track inheritance
        $finalConfig = @{}
        $keyOrigins = @{}
        $inheritanceChain = @()

        # Process each level in the hierarchy
        for ($level = 0; $level -lt $ConfigurationHierarchy.Count; $level++) {
            $currentLevel = $ConfigurationHierarchy[$level]
            $inheritanceChain += @{
                Level         = $level
                Configuration = $currentLevel
            }

            # Apply inheritance rules if provided
            if ($InheritanceRules.Count -gt 0) {
                foreach ($ruleName in $InheritanceRules.Keys) {
                    $rule = $InheritanceRules[$ruleName]
                    $ruleResult = & $rule $finalConfig $currentLevel $level
                    if ($ruleResult.Success) {
                        $currentLevel = $ruleResult.ModifiedConfig
                    }
                }
            }

            # Merge current level into final config
            foreach ($key in $currentLevel.Keys) {
                $oldValue = $finalConfig[$key]
                $newValue = $currentLevel[$key]

                # Track key origins and override history
                if (-not $keyOrigins.ContainsKey($key)) {
                    $keyOrigins[$key] = @{
                        OriginLevel     = $level
                        OriginalValue   = $newValue
                        OverrideHistory = @()
                    }
                }
                else {
                    $keyOrigins[$key].OverrideHistory += @{
                        Level    = $level
                        OldValue = $oldValue
                        NewValue = $newValue
                    }
                }

                $finalConfig[$key] = $newValue
            }
        }

        # Validate against schema if provided
        $schemaValidation = @()
        $schemaErrors = @()
        if ($ValidationSchema.Count -gt 0) {
            foreach ($schemaKey in $ValidationSchema.Keys) {
                $schemaRule = $ValidationSchema[$schemaKey]
                $present = $finalConfig.ContainsKey($schemaKey)
                $value = $finalConfig[$schemaKey]

                $typeValid = $true
                if ($present -and $schemaRule.Type) {
                    $typeValid = $value -is [type]$schemaRule.Type
                }

                $validatorResult = $true
                if ($present -and $schemaRule.Validator) {
                    $validatorResult = & $schemaRule.Validator $value
                }

                $schemaValidation += @{
                    Key             = $schemaKey
                    Present         = $present
                    TypeValid       = $typeValid
                    ValidatorResult = $validatorResult
                    Required        = $schemaRule.Required -eq $true
                }

                if ($schemaRule.Required -eq $true -and -not $present) {
                    $schemaErrors += "Required key '$schemaKey' is missing from final configuration"
                }
            }
        }

        return @{
            Success             = $schemaErrors.Count -eq 0
            Errors              = $schemaErrors
            FinalConfiguration  = $finalConfig
            InheritanceAnalysis = @{
                LevelCount       = $ConfigurationHierarchy.Count
                InheritanceChain = $inheritanceChain
                KeyOrigins       = $keyOrigins
                SchemaValidation = $schemaValidation
            }
        }
    }
    catch {
        return @{
            Success             = $false
            Errors              = @("Configuration inheritance test failed: $($_.Exception.Message)")
            FinalConfiguration  = @{}
            InheritanceAnalysis = @{
                LevelCount       = 0
                InheritanceChain = @()
                KeyOrigins       = @{}
                SchemaValidation = @()
            }
        }
    }
}

function Test-ConfigurationFilePath {
    <#
    .SYNOPSIS
        Tests configuration file path accessibility and validity.
    #>
    [CmdletBinding()]
    [OutputType([PSObject])]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$ConfigurationPaths,

        [Parameter(Mandatory = $false)]
        [bool]$AccessibilityChecks = $true,

        [Parameter(Mandatory = $false)]
        [bool]$ContentValidation = $true
    )

    try {
        $pathAnalysis = @()
        $errors = @()
        $warnings = @()

        foreach ($path in $ConfigurationPaths) {
            $pathInfo = @{
                Path         = $path
                Exists       = $false
                Accessible   = $false
                ValidContent = $false
                Extension    = ""
                Size         = 0
            }

            # Check if file exists
            if (Test-Path $path -PathType Leaf) {
                $pathInfo.Exists = $true
                $fileInfo = Get-Item $path
                $pathInfo.Extension = $fileInfo.Extension
                $pathInfo.Size = $fileInfo.Length

                # Check accessibility
                if ($AccessibilityChecks) {
                    try {
                        $content = Get-Content $path -Raw -ErrorAction Stop
                        $pathInfo.Accessible = $true

                        # Content validation
                        if ($ContentValidation) {
                            if ($pathInfo.Size -eq 0) {
                                $warnings += "Configuration file '$path' is empty"
                                $pathInfo.ValidContent = $false
                            }
                            elseif ($pathInfo.Extension -eq ".json") {
                                try {
                                    $null = $content | ConvertFrom-Json
                                    $pathInfo.ValidContent = $true
                                }
                                catch {
                                    $errors += "Invalid JSON content in file '$path': $($_.Exception.Message)"
                                    $pathInfo.ValidContent = $false
                                }
                            }
                            else {
                                $pathInfo.ValidContent = $true
                            }
                        }
                    }
                    catch {
                        $pathInfo.Accessible = $false
                        $errors += "Cannot access file '$path': $($_.Exception.Message)"
                    }
                }
            }
            else {
                $pathInfo.Exists = $false
                $pathInfo.Accessible = $false
                $warnings += "Configuration file '$path' does not exist"
            }

            $pathAnalysis += $pathInfo
        }

        return @{
            Success      = $errors.Count -eq 0
            Errors       = $errors
            Warnings     = $warnings
            PathAnalysis = $pathAnalysis
        }
    }
    catch {
        return @{
            Success      = $false
            Errors       = @("Configuration file path test failed: $($_.Exception.Message)")
            Warnings     = @()
            PathAnalysis = @()
        }
    }
}

function Test-WmrResolvedConfiguration {
    <#
    .SYNOPSIS
        Tests resolved configuration for validity and consistency.
    #>
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param(
        [Parameter(Mandatory = $true)]
        [PSObject]$ResolvedConfig,

        [Parameter(Mandatory = $false)]
        [string]$ValidationLevel = "moderate",

        [Parameter(Mandatory = $false)]
        [hashtable]$InheritanceConfig = @{}
    )

    # Handle both parameter styles for backward compatibility
    if ($InheritanceConfig.Count -gt 0 -and $InheritanceConfig.validation_level) {
        $ValidationLevel = $InheritanceConfig.validation_level
    }

    try {
        $validationResult = switch ($ValidationLevel) {
            "strict" {
                Test-WmrStrictConfigurationValidation -ResolvedConfig $ResolvedConfig
            }
            "moderate" {
                Test-WmrModerateConfigurationValidation -ResolvedConfig $ResolvedConfig
            }
            "relaxed" {
                Test-WmrRelaxedConfigurationValidation -ResolvedConfig $ResolvedConfig
            }
            default {
                Write-Warning "Unknown validation level: $ValidationLevel. Using moderate validation."
                Test-WmrModerateConfigurationValidation -ResolvedConfig $ResolvedConfig
            }
        }
        return $validationResult
    }
    catch {
        Write-Error "Configuration validation failed: $($_.Exception.Message)"
        return $false
    }
}

function Test-WmrStrictConfigurationValidation {
    <#
    .SYNOPSIS
        Performs strict validation of resolved configuration.
    #>
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param(
        [Parameter(Mandatory = $true)]
        [PSObject]$ResolvedConfig
    )

    # Check for required metadata
    if (-not $ResolvedConfig.metadata) {
        throw "Missing required 'metadata' section"
    }
    if (-not $ResolvedConfig.metadata.name) {
        throw "Missing required 'name' property in metadata"
    }

    # Check for required properties in configuration items
    $configSections = @("files", "registry", "applications")
    foreach ($section in $configSections) {
        if ($ResolvedConfig.$section) {
            foreach ($item in $ResolvedConfig.$section) {
                if (-not $item.name) {
                    throw "Missing required 'name' property in $section item"
                }
                if (-not $item.path) {
                    throw "Missing required 'path' property in $section item '$($item.name)'"
                }
            }
        }
    }

    # Check for duplicate names
    foreach ($section in $configSections) {
        if ($ResolvedConfig.$section) {
            $names = $ResolvedConfig.$section | ForEach-Object { $_.name }
            $duplicateNames = $names | Group-Object | Where-Object { $_.Count -gt 1 }
            if ($duplicateNames) {
                throw "Duplicate names found in ${section}: $($duplicateNames.Name -join ', ')"
            }
        }
    }

    # Check for conflicts in file paths
    if ($ResolvedConfig.files) {
        $paths = $ResolvedConfig.files | ForEach-Object { $_.path }
        $duplicatePaths = $paths | Group-Object | Where-Object { $_.Count -gt 1 }
        if ($duplicatePaths) {
            throw "Duplicate file paths found: $($duplicatePaths.Name -join ', ')"
        }
    }

    # Check for conflicts in registry paths
    if ($ResolvedConfig.registry) {
        $paths = $ResolvedConfig.registry | ForEach-Object { $_.path }
        $duplicatePaths = $paths | Group-Object | Where-Object { $_.Count -gt 1 }
        if ($duplicatePaths) {
            throw "Duplicate registry paths found: $($duplicatePaths.Name -join ', ')"
        }
    }

    # Check inheritance consistency
    $configSections = @("files", "registry", "applications")
    foreach ($section in $configSections) {
        if ($ResolvedConfig.$section) {
            foreach ($item in $ResolvedConfig.$section) {
                if ($item.inheritance_source -and $item.inheritance_source -notin @("shared", "machine_specific", "conditional")) {
                    throw "Invalid inheritance_source '$($item.inheritance_source)' in $section item '$($item.name)'"
                }
                if ($item.inheritance_priority -and ($item.inheritance_priority -lt 1 -or $item.inheritance_priority -gt 100)) {
                    throw "Invalid inheritance_priority '$($item.inheritance_priority)' in $section item '$($item.name)'. Must be between 1 and 100."
                }
            }
        }
    }

    return $true
}

function Test-WmrModerateConfigurationValidation {
    <#
    .SYNOPSIS
        Performs moderate validation of resolved configuration.
    #>
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param(
        [Parameter(Mandatory = $true)]
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

    return $true
}

function Test-WmrRelaxedConfigurationValidation {
    <#
    .SYNOPSIS
        Performs relaxed validation of resolved configuration.
    #>
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param(
        [Parameter(Mandatory = $true)]
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

    return $true
}

function Test-WmrConfigurationItemValidity {
    <#
    .SYNOPSIS
        Tests if a configuration item is valid according to a rule.
    #>
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param(
        [Parameter(Mandatory = $true)]
        [PSObject]$Item,

        [Parameter(Mandatory = $true)]
        [PSObject]$Rule
    )

    # Basic item validity checks
    if (-not $Item.name) {
        return $false
    }

    if (-not $Item.path) {
        return $false
    }

    # Rule-specific validation can be added here
    return $true
}

# Functions are available when dot-sourced, no need to export when not in module context







