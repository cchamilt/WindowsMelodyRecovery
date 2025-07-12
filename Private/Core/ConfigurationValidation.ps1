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
        [Parameter(Mandatory=$true)]
        [hashtable]$MachineConfig,

        [Parameter(Mandatory=$true)]
        [hashtable]$SharedConfig,

        [Parameter(Mandatory=$false)]
        [array]$RequiredKeys = @(),

        [Parameter(Mandatory=$false)]
        [hashtable]$ValidationRules = @{}
    )

    $result = [PSCustomObject]@{
        Success = $true
        Errors = @()
        ValidationDetails = @{
            MachineConfigKeys = $MachineConfig.Keys
            SharedConfigKeys = $SharedConfig.Keys
            MissingRequiredKeys = @()
            TypeMismatches = @()
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
                    Key = $key
                    MachineType = $machineType.Name
                    SharedType = $sharedType.Name
                }
            }
        }
    }

    # Apply custom validation rules
    foreach ($ruleName in $ValidationRules.Keys) {
        $ruleResult = & $ValidationRules[$ruleName] $MachineConfig $SharedConfig
        $result.ValidationDetails.ValidationRuleResults += [PSCustomObject]@{
            RuleName = $ruleName
            Success = $ruleResult.Success
            Message = $ruleResult.Message
        }
        if (-not $ruleResult.Success) {
            $result.Success = $false
            $result.Errors += $ruleResult.Message
        }
    }

    return $result
}

function Validate-SharedConfigurationMerging {
    <#
    .SYNOPSIS
        Validates shared configuration merging operations.
    .DESCRIPTION
        Stub implementation for testing purposes.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSObject])]
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$BaseConfig,

        [Parameter(Mandatory=$true)]
        [hashtable]$OverrideConfig,

        [Parameter(Mandatory=$false)]
        [array]$ExpectedKeys = @(),

        [Parameter(Mandatory=$false)]
        [hashtable]$MergingRules = @{}
    )

    $result = [PSCustomObject]@{
        Success = $true
        Errors = @()
        MergedConfig = @{}
        ValidationDetails = @{
            BaseConfigKeys = $BaseConfig.Keys
            OverrideConfigKeys = $OverrideConfig.Keys
            MergedKeys = @()
            MergingRuleResults = @()
        }
    }

    # Simple merge logic
    $result.MergedConfig = $BaseConfig.Clone()
    foreach ($key in $OverrideConfig.Keys) {
        $result.MergedConfig[$key] = $OverrideConfig[$key]
        $result.ValidationDetails.MergedKeys += $key
    }

    # Check expected keys if provided
    foreach ($key in $ExpectedKeys) {
        if (-not $result.MergedConfig.ContainsKey($key)) {
            $result.Success = $false
            $result.Errors += "Expected key '$key' not found in merged configuration"
        }
    }

    return $result
}

function Test-ConfigurationInheritance {
    <#
    .SYNOPSIS
        Tests configuration inheritance hierarchy.
    .DESCRIPTION
        Stub implementation for testing purposes.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSObject])]
    param(
        [Parameter(Mandatory=$true)]
        [array]$ConfigurationHierarchy,

        [Parameter(Mandatory=$false)]
        [hashtable]$InheritanceRules = @(),

        [Parameter(Mandatory=$false)]
        [hashtable]$ValidationSchema = @{}
    )

    $result = [PSCustomObject]@{
        Success = $true
        Errors = @()
        ResolvedConfiguration = @{}
        ValidationDetails = @{
            HierarchyLevels = $ConfigurationHierarchy.Count
            InheritanceRuleResults = @()
            SchemaValidationResults = @()
        }
    }

    # Simple inheritance resolution - last configuration wins
    foreach ($config in $ConfigurationHierarchy) {
        foreach ($key in $config.Keys) {
            $result.ResolvedConfiguration[$key] = $config[$key]
        }
    }

    return $result
}

function Test-ConfigurationFilePaths {
    <#
    .SYNOPSIS
        Tests configuration file paths for accessibility and validity.
    .DESCRIPTION
        Stub implementation for testing purposes.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSObject])]
    param(
        [Parameter(Mandatory=$true)]
        [array]$ConfigurationPaths,

        [Parameter(Mandatory=$false)]
        [bool]$AccessibilityChecks = $true,

        [Parameter(Mandatory=$false)]
        [bool]$ContentValidation = $true
    )

    $result = [PSCustomObject]@{
        Success = $true
        Errors = @()
        ValidationDetails = @{
            TotalPaths = $ConfigurationPaths.Count
            AccessiblePaths = @()
            InaccessiblePaths = @()
            ValidPaths = @()
            InvalidPaths = @()
        }
    }

    foreach ($path in $ConfigurationPaths) {
        if ($AccessibilityChecks) {
            if (Test-Path $path) {
                $result.ValidationDetails.AccessiblePaths += $path
            } else {
                $result.ValidationDetails.InaccessiblePaths += $path
                $result.Success = $false
                $result.Errors += "Path not accessible: $path"
            }
        }

        if ($ContentValidation -and (Test-Path $path)) {
            try {
                # Simple content validation - try to read the file
                $content = Get-Content $path -ErrorAction Stop
                $result.ValidationDetails.ValidPaths += $path
            } catch {
                $result.ValidationDetails.InvalidPaths += $path
                $result.Success = $false
                $result.Errors += "Invalid content in path: $path - $($_.Exception.Message)"
            }
        }
    }

    return $result
}

function Test-WmrResolvedConfiguration {
    <#
    .SYNOPSIS
        Tests resolved configuration for validity and consistency.
    #>
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param(
        [Parameter(Mandatory=$true)]
        [PSObject]$ResolvedConfig,

        [Parameter(Mandatory=$false)]
        [string]$ValidationLevel = "moderate",

        [Parameter(Mandatory=$false)]
        [hashtable]$InheritanceConfig = @{}
    )

    # Handle both parameter styles for backward compatibility
    if ($InheritanceConfig.Count -gt 0 -and $InheritanceConfig.validation_level) {
        $ValidationLevel = $InheritanceConfig.validation_level
    }

    try {
        switch ($ValidationLevel) {
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
        return $true
    } catch {
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
        [Parameter(Mandatory=$true)]
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
                throw "Duplicate names found in $section: $($duplicateNames.Name -join ', ')"
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
        [Parameter(Mandatory=$true)]
        [PSObject]$Item,

        [Parameter(Mandatory=$true)]
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







