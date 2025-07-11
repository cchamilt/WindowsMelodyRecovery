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
    [OutputType([System.Boolean])]
    param()

    # In Docker tests, simulate non-admin user
    if ($env:DOCKER_TEST_ADMIN -eq 'true') {
        return $true
    }
    return $false
}

function Get-WmrPrivilegeRequirements {
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
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
    [OutputType([System.Boolean])]
    param()

    # Mock administrative privileges check
    return Test-WmrAdminPrivilege
}

function Invoke-WmrSafeAdminOperation {
    [CmdletBinding()]
    [OutputType([System.Object])]
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
    [OutputType([System.Object])]
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
        Write-Information -MessageData "What if: Would execute elevated operation" -InformationAction Continue
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
    [OutputType([System.String])]
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
    [OutputType([System.String])]
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
    [OutputType([System.Boolean])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    # Mock registry path validation
    return $Path -match '^HK[CLMU][MU]?:'
}

function Get-WmrRegistryState {
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
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

# Mock functions for AdministrativePrivileges-Logic tests
function Backup-WindowsFeatures {
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param(
        [Parameter()]
        [string]$BackupPath
    )

    Write-Verbose "Mock: Backing up Windows Features to $BackupPath"
    return @{
        Success = $true
        Features = @("IIS-WebServerRole", "Microsoft-Windows-Subsystem-Linux")
        BackupPath = $BackupPath
    }
}

function Test-WmrPrerequisites {
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param(
        [Parameter(Mandatory)]
        [object]$TemplateConfig,

        [Parameter()]
        [string]$Operation = "Backup"
    )

    Write-Verbose "Mock: Testing prerequisites for template '$($TemplateConfig.metadata.name)' with operation '$Operation'"
    return @{
        Success = $true
        Results = @()
        FailedPrerequisites = @()
        Operation = $Operation
        TemplateConfig = $TemplateConfig
    }
}

function Get-WindowsOptionalFeaturesState {
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param(
        [Parameter()]
        [string]$StateFilePath
    )

    Write-Verbose "Mock: Getting Windows Optional Features state"
    return @{
        Features = @(
            @{ Name = "IIS-WebServerRole"; State = "Enabled" }
            @{ Name = "Microsoft-Windows-Subsystem-Linux"; State = "Enabled" }
        )
        StateFilePath = $StateFilePath
    }
}

function Get-WindowsCapabilitiesState {
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param(
        [Parameter()]
        [string]$StateFilePath
    )

    Write-Verbose "Mock: Getting Windows Capabilities state"
    return @{
        Capabilities = @(
            @{ Name = "OpenSSH.Client"; State = "Installed" }
            @{ Name = "OpenSSH.Server"; State = "NotPresent" }
        )
        StateFilePath = $StateFilePath
    }
}

function Manage-WindowsService {
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$ServiceName,

        [Parameter(Mandatory)]
        [ValidateSet("Start", "Stop", "Restart", "Enable", "Disable")]
        [string]$Action
    )

    Write-Verbose "Mock: Managing Windows Service '$ServiceName' with action '$Action'"
    return @{
        Success = $true
        ServiceName = $ServiceName
        Action = $Action
        PreviousState = "Running"
        CurrentState = "Running"
    }
}

function Set-RegistryValue {
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [object]$Value,

        [Parameter()]
        [string]$Type = "String"
    )

    Write-Verbose "Mock: Setting registry value '$Name' at '$Path' to '$Value'"
    return @{
        Success = $true
        Path = $Path
        Name = $Name
        Value = $Value
        Type = $Type
    }
}

function Manage-ScheduledTask {
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$TaskName,

        [Parameter(Mandatory)]
        [ValidateSet("Create", "Delete", "Enable", "Disable", "Run", "Remove")]
        [string]$Action,

        [Parameter()]
        [hashtable]$TaskDefinition,

        [Parameter()]
        [bool]$RequireElevation = $false
    )

    Write-Verbose "Mock: Managing Scheduled Task '$TaskName' with action '$Action' (RequireElevation: $RequireElevation)"
    return @{
        Success = $true
        TaskName = $TaskName
        Action = $Action
        State = "Ready"
        RequireElevation = $RequireElevation
    }
}

function Test-ElevationCapability {
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param()

    Write-Verbose "Mock: Testing elevation capability"
    # In Docker tests, simulate that elevation is not available
    return $false
}

# Enhanced registry mocking for file-operations tests
function New-ItemProperty {
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [object]$Value,

        [Parameter()]
        [ValidateSet("String", "ExpandString", "Binary", "DWord", "MultiString", "QWord")]
        [string]$PropertyType = "String",

        [Parameter()]
        [switch]$Force
    )

    Write-Verbose "Mock: Creating registry property '$Name' at '$Path' with value '$Value' (Type: $PropertyType)"

    # Return a mock property object
    return @{
        PSPath = $Path
        PSParentPath = Split-Path $Path -Parent
        PSChildName = $Name
        PSDrive = ($Path -split ':')[0]
        PSProvider = "Microsoft.PowerShell.Core\Registry"
        $Name = $Value
    }
}

function Set-ItemProperty {
    [CmdletBinding()]
    [OutputType([System.Void])]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [object]$Value,

        [Parameter()]
        [ValidateSet("String", "ExpandString", "Binary", "DWord", "MultiString", "QWord")]
        [string]$PropertyType = "String"
    )

    Write-Verbose "Mock: Setting registry property '$Name' at '$Path' to '$Value' (Type: $PropertyType)"

    # Simulate successful registry write
    return $null
}

function Get-ItemProperty {
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter()]
        [string]$Name = "*"
    )

    Write-Verbose "Mock: Getting registry property '$Name' from '$Path'"

    # Return mock registry values based on the path and name
    $mockValues = @{
        PSPath = $Path
        PSParentPath = Split-Path $Path -Parent
        PSChildName = Split-Path $Path -Leaf
        PSDrive = ($Path -split ':')[0]
        PSProvider = "Microsoft.PowerShell.Core\Registry"
    }

    # Add specific test values based on common test patterns
    if ($Name -eq "TestValue" -or $Name -eq "*") {
        $mockValues.TestValue = "TestData"
    }
    if ($Name -eq "StringValue" -or $Name -eq "*") {
        $mockValues.StringValue = "Test String"
    }
    if ($Name -eq "DWordValue" -or $Name -eq "*") {
        $mockValues.DWordValue = 12345
    }
    if ($Name -eq "BinaryValue" -or $Name -eq "*") {
        $mockValues.BinaryValue = @(1, 2, 3)
    }
    if ($Name -eq "Level1Value" -or $Name -eq "*") {
        $mockValues.Level1Value = "L1"
    }
    if ($Name -eq "Level2Value" -or $Name -eq "*") {
        $mockValues.Level2Value = "L2"
    }
    if ($Name -eq "Level3Value" -or $Name -eq "*") {
        $mockValues.Level3Value = "L3"
    }

    return [PSCustomObject]$mockValues
}

function New-Item {
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable], [System.IO.FileSystemInfo])]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter()]
        [string]$ItemType,

        [Parameter()]
        [switch]$Force
    )

    # Check if we're in a Docker environment
    $isDockerEnvironment = ($env:DOCKER_TEST -eq 'true') -or ($env:CONTAINER -eq 'true') -or
                          (Microsoft.PowerShell.Management\Test-Path '/.dockerenv' -ErrorAction SilentlyContinue)

    if ($isDockerEnvironment) {
        Write-Verbose "Mock: Creating new item at '$Path' (Type: $ItemType)"

        # For registry paths, simulate registry key creation
        if ($Path.StartsWith("HKLM:") -or $Path.StartsWith("HKCU:") -or $Path.StartsWith("HKEY_")) {
            return @{
                PSPath = $Path
                PSParentPath = Split-Path $Path -Parent
                PSChildName = Split-Path $Path -Leaf
                PSDrive = ($Path -split ':')[0]
                PSProvider = "Microsoft.PowerShell.Core\Registry"
                Name = Split-Path $Path -Leaf
            }
        }

        # For file system paths in safe test directories, actually create them
        if ($Path.StartsWith("/workspace/Temp") -or $Path.StartsWith("/workspace/temp")) {
            if ($ItemType -eq "Directory") {
                Write-Verbose "Actually creating directory in Docker: '$Path'"
                return Microsoft.PowerShell.Management\New-Item -Path $Path -ItemType $ItemType -Force:$Force -ErrorAction Stop
            } elseif ($ItemType -eq "File") {
                Write-Verbose "Actually creating file in Docker: '$Path'"
                return Microsoft.PowerShell.Management\New-Item -Path $Path -ItemType $ItemType -Force:$Force -ErrorAction Stop
            }
        }

        # For other file system paths, simulate file/directory creation
        return @{
            FullName = $Path
            Name = Split-Path $Path -Leaf
            Exists = $true
        }
    } else {
        # In local environments, use the real New-Item to actually create directories
        Write-Verbose "Creating actual directory: '$Path' (Type: $ItemType)"
        return Microsoft.PowerShell.Management\New-Item -Path $Path -ItemType $ItemType -Force:$Force -ErrorAction Stop
    }
}

function Remove-Item {
    [CmdletBinding()]
    [OutputType([System.Void])]
    param(
        [Parameter()]
        [string]$Path,

        [Parameter()]
        [switch]$Recurse,

        [Parameter()]
        [switch]$Force,

        [Parameter()]
        [switch]$Confirm
    )

    # Handle null or empty paths gracefully
    if ([string]::IsNullOrWhiteSpace($Path)) {
        Write-Verbose "Mock Remove-Item: Ignoring null/empty path"
        return $null
    }

    # Check if we're in a Docker environment
    $isDockerEnvironment = ($env:DOCKER_TEST -eq 'true') -or ($env:CONTAINER -eq 'true') -or
                          (Microsoft.PowerShell.Management\Test-Path '/.dockerenv' -ErrorAction SilentlyContinue)

    if ($isDockerEnvironment) {
        # For files in safe test directories, actually remove them
        if ($Path.StartsWith("/workspace/Temp/") -or $Path.StartsWith("/workspace/temp/")) {
            Write-Verbose "Actually removing test file in Docker: '$Path'"
            return Microsoft.PowerShell.Management\Remove-Item -Path $Path -Recurse:$Recurse -Force:$Force -Confirm:$Confirm -ErrorAction $ErrorActionPreference
        }

        # For other paths, simulate removal
        Write-Verbose "Mock: Removing item at '$Path' (Recurse: $Recurse, Force: $Force, Confirm: $Confirm)"
        return $null
    } else {
        # In local environments, use the real Remove-Item for cleanup
        Write-Verbose "Removing actual item: '$Path' (Recurse: $Recurse, Force: $Force, Confirm: $Confirm)"
        return Microsoft.PowerShell.Management\Remove-Item -Path $Path -Recurse:$Recurse -Force:$Force -Confirm:$Confirm -ErrorAction $ErrorActionPreference
    }
}

function Test-Path {
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter()]
        [string]$PathType
    )

    # Handle Docker environment detection without verbose spam
    if ($Path -eq '/.dockerenv') {
        # In Docker tests, simulate Docker environment detection
        return ($env:DOCKER_TEST -eq 'true' -or $env:CONTAINER -eq 'true')
    }

    # Mock registry paths as existing for test scenarios
    if ($Path.StartsWith("HKLM:") -or $Path.StartsWith("HKCU:") -or $Path.StartsWith("HKEY_")) {
        # Simulate registry key existence based on test patterns
        return $true
    }

    # For file system paths, use original Test-Path with Microsoft.PowerShell.Management module
    if ($PathType) {
        return Microsoft.PowerShell.Management\Test-Path -Path $Path -PathType $PathType -ErrorAction SilentlyContinue
    } else {
        return Microsoft.PowerShell.Management\Test-Path -Path $Path -ErrorAction SilentlyContinue
    }
}

# Mock Windows-specific path utilities
# Note: Convert-WmrPath is now handled by the real implementation in PathUtilities.ps1
# which properly handles Docker environments

# Mock template inheritance functions
function Get-WmrInheritanceConfiguration {
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
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
    [OutputType([System.Collections.Hashtable])]
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
    [OutputType([System.Boolean])]
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
    [OutputType([System.Boolean])]
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
    [OutputType([System.Array])]
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
    [OutputType([System.Collections.Hashtable])]
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
    [OutputType([System.Collections.Hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$ResolvedConfig,

        [Parameter(Mandatory)]
        [hashtable]$MachineConfig
    )

    # Mock machine-specific configuration merging
    return $ResolvedConfig
}

function Invoke-WmrInheritanceRules {
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
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
    [OutputType([System.Boolean])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Rule,

        [Parameter(Mandatory)]
        [hashtable]$Context
    )

    # Mock inheritance rule condition testing
    return $true
}

function Invoke-WmrConditionalSections {
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
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
    [OutputType([System.Boolean])]
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
    [OutputType([System.Boolean])]
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
    [OutputType([System.Boolean])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$ResolvedConfig
    )

    # Mock strict configuration validation
    return $true
}

function Resolve-WmrTemplateInheritance {
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
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
    [OutputType([System.Management.Automation.PSCustomObject], [System.Collections.Hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$TemplatePath
    )

    # Actually check if the file exists
    if (-not (Test-Path $TemplatePath)) {
        throw "Template file not found: $TemplatePath"
    }

    try {
        $content = Get-Content $TemplatePath -Raw -Encoding UTF8
        if ($TemplatePath -like "*.yaml" -or $TemplatePath -like "*.yml") {
            # Check for obviously invalid YAML patterns - be more strict
            if ($content -match "unclosed_array:\s*true" -or
                $content -match "\[\s*-\s*item1\s*-\s*item2\s*unclosed_array" -or
                $content -match "corrupted:\s*\[unclosed" -or
                $content -match "invalid_structure:\s*\[" -and $content -notmatch "\]" -or
                $content -match "corrupted_template" -or
                $content -match "invalid.*yaml.*structure" -or
                $content -match "\{[^}]*$" -or  # Unclosed braces
                $content -match "\[[^]]*$" -or  # Unclosed brackets
                ($content -match ":\s*\[" -and $content -notmatch "\]")) {  # Unclosed arrays
                throw "Invalid YAML content: malformed structure detected"
            }

            # Simple YAML parsing for test purposes
            $yamlContent = [PSCustomObject]@{
                metadata = [PSCustomObject]@{}
                prerequisites = @()
                files = @()
                registry = @()
                applications = @()
            }

            # Parse basic YAML structure
            $lines = $content -split "`n"
            $currentSection = $null
            $currentItem = $null

            foreach ($line in $lines) {
                $line = $line.Trim()
                if ($line -match "^metadata:") {
                    $currentSection = "metadata"
                } elseif ($line -match "^prerequisites:") {
                    $currentSection = "prerequisites"
                } elseif ($line -match "^files:") {
                    $currentSection = "files"
                } elseif ($line -match "^registry:") {
                    $currentSection = "registry"
                } elseif ($line -match "^applications:") {
                    $currentSection = "applications"
                } elseif ($line -match "^\s*name:\s*(.+)") {
                    if ($currentSection -eq "metadata") {
                        $yamlContent.metadata | Add-Member -Name "name" -Value ($matches[1] -replace '"', '') -MemberType NoteProperty -Force
                    } elseif ($currentItem) {
                        $currentItem | Add-Member -Name "name" -Value ($matches[1] -replace '"', '') -MemberType NoteProperty -Force
                    }
                } elseif ($line -match "^\s*version:\s*(.+)") {
                    if ($currentSection -eq "metadata") {
                        $yamlContent.metadata | Add-Member -Name "version" -Value ($matches[1] -replace '"', '') -MemberType NoteProperty -Force
                    }
                } elseif ($line -match "^\s*description:\s*(.+)") {
                    if ($currentSection -eq "metadata") {
                        $yamlContent.metadata | Add-Member -Name "description" -Value ($matches[1] -replace '"', '') -MemberType NoteProperty -Force
                    }
                } elseif ($line -match "^\s*-\s*type:\s*(.+)") {
                    $currentItem = [PSCustomObject]@{ type = $matches[1] -replace '"', '' }
                    if ($currentSection -eq "prerequisites") {
                        $yamlContent.prerequisites += $currentItem
                    }
                } elseif ($line -match "^\s*-\s*name:\s*(.+)") {
                    $currentItem = [PSCustomObject]@{ name = $matches[1] -replace '"', '' }
                    if ($currentSection -eq "files") {
                        $yamlContent.files += $currentItem
                    }
                }
            }

            return $yamlContent
        } else {
            return ($content | ConvertFrom-Json)
        }
    } catch {
        throw "Failed to parse template file: $($_.Exception.Message)"
    }
}

function Test-WmrTemplateSchema {
    [CmdletBinding()]
    [OutputType([System.Boolean])]
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






