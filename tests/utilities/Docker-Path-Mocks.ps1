# Docker Path Mocks for Windows Melody Recovery Testing
# This utility provides cross-platform path handling for tests running in Docker

# Global path mappings for Docker testing
$script:DockerPathMappings = @{
    'C:\' = '/mock-c/'
    'D:\' = '/mock-d/'
    'E:\' = '/mock-e/'
    'C:\Users' = '/mock-c/Users'
    'C:\Program Files' = '/mock-c/Program Files'
    'C:\ProgramData' = '/mock-c/ProgramData'
    'C:\Windows' = '/mock-c/Windows'
    'C:\Temp' = '/tmp'
    'C:\tmp' = '/tmp'
}

# Mock Windows Principal functionality for Docker tests
function Test-WmrAdminPrivilege {
    [CmdletBinding()]
    param()
    
    # In Docker tests, simulate non-admin user
    if ($env:DOCKER_TEST_ADMIN -eq 'true') {
        return $true
    }
    return $false
}

function Get-WmrPrivilegeRequirements {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Template
    )
    
    # Mock privilege requirements analysis
    $requirements = @{
        RequiresAdmin = $false
        RequiresElevation = $false
        WindowsFeatures = @()
        RegistryAccess = @()
        ServiceAccess = @()
    }
    
    # Simulate analysis of template requirements
    if ($Template.metadata.name -match 'bitlocker|windows-features|services') {
        $requirements.RequiresAdmin = $true
        $requirements.RequiresElevation = $true
    }
    
    return $requirements
}

function Test-WmrAdministrativePrivileges {
    [CmdletBinding()]
    param()
    
    # Mock administrative privileges check
    return Test-WmrAdminPrivilege
}

function Invoke-WmrSafeAdminOperation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ScriptBlock]$MainOperation,
        
        [Parameter()]
        [ScriptBlock]$FallbackOperation,
        
        [Parameter()]
        [string]$OperationType = "User"
    )
    
    # Mock safe admin operation execution
    if ($OperationType -eq "Admin" -and -not (Test-WmrAdminPrivilege)) {
        if ($FallbackOperation) {
            Write-Verbose "Executing fallback operation (no admin privileges)"
            return & $FallbackOperation
        } else {
            throw "Administrative privileges required and no fallback available"
        }
    }
    
    Write-Verbose "Executing main operation"
    return & $MainOperation
}

function Invoke-WmrWithElevation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ScriptBlock]$ScriptBlock,
        
        [Parameter()]
        [switch]$WhatIf,
        
        [Parameter()]
        [switch]$NoPrompt
    )
    
    # Mock elevation functionality
    if ($WhatIf) {
        Write-Host "What if: Would execute elevated operation"
        return
    }
    
    if ((Test-WmrAdminPrivilege)) {
        Write-Verbose "Already elevated, executing directly"
        return & $ScriptBlock
    } else {
        if ($NoPrompt) {
            throw "Elevation required but NoPrompt specified"
        }
        Write-Verbose "Mock elevation: Executing script block"
        return & $ScriptBlock
    }
}

# Convert Windows paths to Docker-compatible paths
function Convert-WmrPathForDocker {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]$Path
    )
    
    process {
        if ([string]::IsNullOrEmpty($Path)) {
            return $Path
        }
        
        # Handle Windows drive letters
        foreach ($mapping in $script:DockerPathMappings.GetEnumerator()) {
            if ($Path.StartsWith($mapping.Key, [System.StringComparison]::OrdinalIgnoreCase)) {
                $convertedPath = $Path.Replace($mapping.Key, $mapping.Value)
                # Convert backslashes to forward slashes
                $convertedPath = $convertedPath.Replace('\', '/')
                return $convertedPath
            }
        }
        
        # Handle relative paths and convert backslashes
        return $Path.Replace('\', '/')
    }
}

# Mock Join-Path that works cross-platform
function Join-WmrPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        
        [Parameter(Mandatory)]
        [string]$ChildPath
    )
    
    if ([string]::IsNullOrEmpty($Path) -or [string]::IsNullOrEmpty($ChildPath)) {
        throw "Path parameters cannot be null or empty"
    }
    
    # Convert Windows paths for Docker
    $convertedPath = Convert-WmrPathForDocker -Path $Path
    $convertedChild = Convert-WmrPathForDocker -Path $ChildPath
    
    # Use native Join-Path with converted paths
    return Join-Path -Path $convertedPath -ChildPath $convertedChild
}

# Mock Windows registry functionality
function Test-WmrRegistryPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )
    
    # Mock registry path validation
    return $Path -match '^HK[CLMU][MU]?:'
}

function Get-WmrRegistryState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$RegistryConfig,
        
        [Parameter(Mandatory)]
        [string]$StateFilesDirectory
    )
    
    # Mock registry state retrieval
    return @{
        Path = $RegistryConfig.path
        Values = @{}
        StateFilePath = Join-WmrPath -Path $StateFilesDirectory -ChildPath "registry_mock.json"
    }
}

# Mock Windows module path functionality
function Get-WmrModulePath {
    [CmdletBinding()]
    param()
    
    # Return current workspace path in Docker
    return "/workspace"
}

# Mock Windows-specific path utilities
# Note: Convert-WmrPath is now handled by the real implementation in PathUtilities.ps1
# which properly handles Docker environments

# Mock template inheritance functions
function Get-WmrInheritanceConfiguration {
    [CmdletBinding()]
    param(
        [Parameter()]
        [hashtable]$TemplateConfig = @{}
    )
    
    return @{
        enabled = $true
        validation_level = 'moderate'
        shared_configuration = @{}
        machine_configurations = @()
        inheritance_rules = @()
        conditional_sections = @()
    }
}

function Get-WmrMachineContext {
    [CmdletBinding()]
    param()
    
    return @{
        machine_name = $env:COMPUTERNAME ?? 'docker-test'
        hostname = $env:HOSTNAME ?? 'docker-test'
        environment = @{
            DOCKER_TEST = 'true'
            CI = $env:CI ?? 'false'
        }
        hardware = @{
            manufacturer = 'Docker'
            model = 'Container'
        }
        software = @{
            os = 'Linux'
            version = '1.0'
        }
    }
}

function Test-WmrMachineSelectors {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Selectors,
        
        [Parameter(Mandatory)]
        [hashtable]$Context
    )
    
    # Mock machine selector testing
    return $true
}

function Test-WmrStringComparison {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Value1,
        
        [Parameter(Mandatory)]
        [string]$Value2,
        
        [Parameter(Mandatory)]
        [string]$ComparisonType
    )
    
    switch ($ComparisonType) {
        'equals' { return $Value1 -eq $Value2 }
        'equals_ci' { return $Value1 -ieq $Value2 }
        'contains' { return $Value1 -like "*$Value2*" }
        'matches' { return $Value1 -match $Value2 }
        default { return $false }
    }
}

function Get-WmrApplicableMachineConfigurations {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$MachineConfigurations,
        
        [Parameter(Mandatory)]
        [hashtable]$Context
    )
    
    # Mock applicable machine configurations
    return $MachineConfigurations
}

function Merge-WmrSharedConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$ResolvedConfig,
        
        [Parameter(Mandatory)]
        [hashtable]$SharedConfig
    )
    
    # Mock configuration merging
    return $ResolvedConfig
}

function Merge-WmrMachineSpecificConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$ResolvedConfig,
        
        [Parameter(Mandatory)]
        [hashtable]$MachineConfig
    )
    
    # Mock machine-specific configuration merging
    return $ResolvedConfig
}

function Apply-WmrInheritanceRules {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$ResolvedConfig,
        
        [Parameter(Mandatory)]
        [array]$InheritanceRules
    )
    
    # Mock inheritance rules application
    return $ResolvedConfig
}

function Test-WmrInheritanceRuleCondition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Rule,
        
        [Parameter(Mandatory)]
        [hashtable]$Context
    )
    
    # Mock inheritance rule condition testing
    return $true
}

function Apply-WmrConditionalSections {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$ResolvedConfig,
        
        [Parameter(Mandatory)]
        [array]$ConditionalSections
    )
    
    # Mock conditional sections application
    return $ResolvedConfig
}

function Test-WmrConditionalSectionConditions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Condition,
        
        [Parameter(Mandatory)]
        [hashtable]$Context
    )
    
    # Mock conditional section condition testing
    return $true
}

function Test-WmrResolvedConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$ResolvedConfig,
        
        [Parameter(Mandatory)]
        [hashtable]$InheritanceConfig
    )
    
    # Mock resolved configuration testing
    return $true
}

function Test-WmrStrictConfigurationValidation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$ResolvedConfig
    )
    
    # Mock strict configuration validation
    return $true
}

function Resolve-WmrTemplateInheritance {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$TemplateConfig,
        
        [Parameter()]
        [hashtable]$Context = @{}
    )
    
    # Mock template inheritance resolution
    return $TemplateConfig
}

function Read-WmrTemplateConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$TemplatePath
    )
    
    # Mock template configuration reading with predefined responses
    switch ($TemplatePath) {
        "valid_template.yaml" {
            return [PSCustomObject]@{
                metadata = [PSCustomObject]@{
                    name = "Test Template"
                    version = "1.0"
                    description = "A test template"
                }
                prerequisites = @(
                    [PSCustomObject]@{
                        name = "Dummy Prereq"
                        type = "script"
                        inline_script = "Write-Output 'test'"
                        expected_output = "test"
                        on_missing = "warn"
                    }
                )
            }
        }
        "invalid_template.yaml" {
            throw "Invalid YAML content in template file"
        }
        default {
            throw "Template file not found: $TemplatePath"
        }
    }
}

function Test-WmrTemplateSchema {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$TemplateConfig
    )
    
    # Convert PSCustomObject to hashtable if needed
    if ($TemplateConfig -is [PSCustomObject]) {
        $configHash = @{}
        foreach ($prop in $TemplateConfig.PSObject.Properties) {
            $configHash[$prop.Name] = $prop.Value
        }
        $TemplateConfig = $configHash
    }
    
    # Mock template schema validation
    if (-not $TemplateConfig.metadata) {
        throw "Template schema validation failed: 'metadata' is missing."
    }
    
    if ($TemplateConfig.metadata -is [PSCustomObject]) {
        if (-not $TemplateConfig.metadata.name) {
            throw "Template schema validation failed: 'metadata.name' is missing."
        }
    } elseif ($TemplateConfig.metadata -is [hashtable]) {
        if (-not $TemplateConfig.metadata.name) {
            throw "Template schema validation failed: 'metadata.name' is missing."
        }
    }
    
    return $true
}

# Functions are available when dot-sourced, no need to export when not in module context 