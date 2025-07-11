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

        [Parameter(Mandatory=$true)]
        [hashtable]$InheritanceConfig
    )

    $validationLevel = if ($InheritanceConfig.validation_level) { $InheritanceConfig.validation_level } else { "moderate" }

    try {
        switch ($validationLevel) {
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
                Write-Warning "Unknown validation level: $validationLevel. Using moderate validation."
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

    # Check for required properties
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
                if (-not $item.action) {
                    throw "Missing required 'action' property in $section item '$($item.name)'"
                }
                if (-not $item.dynamic_state_path) {
                    throw "Missing required 'dynamic_state_path' property in $section item '$($item.name)'"
                }
            }
        }
    }

    # Check for conflicts
    if ($ResolvedConfig.files) {
        $paths = $ResolvedConfig.files | ForEach-Object { $_.path }
        $duplicatePaths = $paths | Group-Object | Where-Object { $_.Count -gt 1 }
        if ($duplicatePaths) {
            throw "Duplicate file paths found: $($duplicatePaths.Name -join ', ')"
        }
    }

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
                if ($item.inheritance_source -and $item.inheritance_source -notin @("shared", "machine_specific")) {
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

# Functions are available when dot-sourced, no need to export when not in module context






