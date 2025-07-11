# Docker Test Bootstrap for Windows Melody Recovery
# This script sets up the test environment for Docker-based testing

# Detect if running in Docker environment
$script:IsDockerEnvironment = ($env:DOCKER_TEST -eq 'true') -or ($env:CONTAINER -eq 'true') -or (Test-Path '/.dockerenv')

# Always load Docker-specific mocks for cross-platform compatibility
# Unit tests depend on these mocks regardless of environment
$mockPath = Join-Path $PSScriptRoot "Docker-Path-Mocks.ps1"
if (Test-Path $mockPath) {
    . $mockPath
    Write-Verbose "Loaded Docker path mocks from: $mockPath"
} else {
    Write-Warning "Docker path mocks not found at: $mockPath"
}

if ($script:IsDockerEnvironment) {
    Write-Verbose "Docker environment detected, loading additional Docker setup"

    # Set up Docker-specific environment variables
    $env:WMR_DOCKER_TEST = 'true'
    $env:WMR_BACKUP_PATH = $env:WMR_BACKUP_PATH ?? '/tmp/wmr-test-backup'
    $env:WMR_LOG_PATH = $env:WMR_LOG_PATH ?? '/tmp/wmr-test-logs'
    $env:WMR_STATE_PATH = $env:WMR_STATE_PATH ?? '/tmp/wmr-test-state'

    # Create test directories
    @($env:WMR_BACKUP_PATH, $env:WMR_LOG_PATH, $env:WMR_STATE_PATH) | ForEach-Object {
        if (-not (Test-Path $_)) {
            New-Item -Path $_ -ItemType Directory -Force | Out-Null
            Write-Verbose "Created test directory: $_"
        }
    }

    # Mock Windows-specific environment variables
    $env:USERPROFILE = $env:USERPROFILE ?? '/mock-c/Users/TestUser'
    $env:PROGRAMFILES = $env:PROGRAMFILES ?? '/mock-c/Program Files'
    $env:PROGRAMDATA = $env:PROGRAMDATA ?? '/mock-c/ProgramData'
    $env:COMPUTERNAME = $env:COMPUTERNAME ?? 'TEST-MACHINE'
    $env:HOSTNAME = $env:HOSTNAME ?? 'TEST-MACHINE'
    $env:USERNAME = $env:USERNAME ?? 'TestUser'
    $env:PROCESSOR_ARCHITECTURE = $env:PROCESSOR_ARCHITECTURE ?? 'AMD64'
    $env:USERDOMAIN = $env:USERDOMAIN ?? 'WORKGROUP'
    $env:PROCESSOR_IDENTIFIER = $env:PROCESSOR_IDENTIFIER ?? 'Intel64 Family 6 Model 158 Stepping 10, GenuineIntel'

    # Mock Get-CimInstance for hardware information
    if (-not (Get-Command Get-CimInstance -ErrorAction SilentlyContinue)) {
        function Get-CimInstance {
            [CmdletBinding()]
            param(
                [string]$ClassName
            )

            switch ($ClassName) {
                'Win32_Processor' {
                    return @(
                        [PSCustomObject]@{
                            Name = 'Intel(R) Core(TM) i7-8700K CPU @ 3.70GHz'
                            NumberOfCores = 6
                            NumberOfLogicalProcessors = 12
                        }
                    )
                }
                'Win32_PhysicalMemory' {
                    return @(
                        [PSCustomObject]@{
                            Capacity = 17179869184  # 16GB
                        }
                    )
                }
                'Win32_VideoController' {
                    return @(
                        [PSCustomObject]@{
                            Name = 'NVIDIA GeForce GTX 1080'
                            AdapterRAM = 8589934592  # 8GB
                        }
                    )
                }
                default {
                    return @()
                }
            }
        }
    }

    # Mock Windows Features functions
    if (-not (Get-Command Get-WindowsOptionalFeature -ErrorAction SilentlyContinue)) {
        function Get-WindowsOptionalFeature {
            [CmdletBinding()]
            param(
                [switch]$Online,
                [string]$FeatureName
            )

            if ($FeatureName) {
                return [PSCustomObject]@{
                    FeatureName = $FeatureName
                    State = 'Enabled'
                    RestartRequired = $false
                }
            } else {
                return @(
                    [PSCustomObject]@{ FeatureName = 'MockFeature1'; State = 'Enabled'; RestartRequired = $false },
                    [PSCustomObject]@{ FeatureName = 'MockFeature2'; State = 'Disabled'; RestartRequired = $false },
                    [PSCustomObject]@{ FeatureName = 'MockFeature3'; State = 'Enabled'; RestartRequired = $false }
                )
            }
        }
    }

    if (-not (Get-Command Enable-WindowsOptionalFeature -ErrorAction SilentlyContinue)) {
        function Enable-WindowsOptionalFeature {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory)]
                [string]$FeatureName,
                [switch]$Online,
                [switch]$All
            )

            return [PSCustomObject]@{
                FeatureName = $FeatureName
                RestartNeeded = $false
                LogPath = '/tmp/mock-feature-log.txt'
            }
        }
    }

    if (-not (Get-Command Disable-WindowsOptionalFeature -ErrorAction SilentlyContinue)) {
        function Disable-WindowsOptionalFeature {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory)]
                [string]$FeatureName,
                [switch]$Online
            )

            return [PSCustomObject]@{
                FeatureName = $FeatureName
                RestartNeeded = $false
                LogPath = '/tmp/mock-feature-log.txt'
            }
        }
    }

    # Mock Windows Capabilities functions
    if (-not (Get-Command Get-WindowsCapability -ErrorAction SilentlyContinue)) {
        function Get-WindowsCapability {
            [CmdletBinding()]
            param(
                [switch]$Online,
                [string]$Name
            )

            if ($Name) {
                return [PSCustomObject]@{
                    Name = $Name
                    State = 'Installed'
                    DisplayName = "Mock Capability: $Name"
                }
            } else {
                return @(
                    [PSCustomObject]@{ Name = 'MockCapability1'; State = 'Installed'; DisplayName = 'Mock Capability 1' },
                    [PSCustomObject]@{ Name = 'MockCapability2'; State = 'NotPresent'; DisplayName = 'Mock Capability 2' },
                    [PSCustomObject]@{ Name = 'MockCapability3'; State = 'Installed'; DisplayName = 'Mock Capability 3' }
                )
            }
        }
    }

    if (-not (Get-Command Add-WindowsCapability -ErrorAction SilentlyContinue)) {
        function Add-WindowsCapability {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory)]
                [string]$Name,
                [switch]$Online
            )

            return [PSCustomObject]@{
                Name = $Name
                RestartNeeded = $false
                LogPath = '/tmp/mock-capability-log.txt'
            }
        }
    }

    if (-not (Get-Command Remove-WindowsCapability -ErrorAction SilentlyContinue)) {
        function Remove-WindowsCapability {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory)]
                [string]$Name,
                [switch]$Online
            )

            return [PSCustomObject]@{
                Name = $Name
                RestartNeeded = $false
                LogPath = '/tmp/mock-capability-log.txt'
            }
        }
    }

    # Mock Scheduled Task functions
    if (-not (Get-Command Register-ScheduledTask -ErrorAction SilentlyContinue)) {
        function Register-ScheduledTask {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory)]
                [string]$TaskName,
                [Parameter(Mandatory)]
                $Action,
                [Parameter(Mandatory)]
                $Trigger,
                $Principal,
                [string]$Description
            )

            return [PSCustomObject]@{
                TaskName = $TaskName
                State = 'Ready'
                LastRunTime = Get-Date
                NextRunTime = (Get-Date).AddDays(1)
                Actions = @($Action)
                Triggers = @($Trigger)
                Principal = $Principal
            }
        }
    }

    if (-not (Get-Command Unregister-ScheduledTask -ErrorAction SilentlyContinue)) {
        function Unregister-ScheduledTask {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory)]
                [string]$TaskName,
                [switch]$Confirm
            )

            return $true
        }
    }

    if (-not (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue)) {
        function Get-ScheduledTask {
            [CmdletBinding()]
            param(
                [string]$TaskName
            )

            if ($TaskName) {
                return [PSCustomObject]@{
                    TaskName = $TaskName
                    State = 'Ready'
                    LastRunTime = Get-Date
                    NextRunTime = (Get-Date).AddDays(1)
                }
            } else {
                return @(
                    [PSCustomObject]@{ TaskName = 'MockTask1'; State = 'Ready' },
                    [PSCustomObject]@{ TaskName = 'MockTask2'; State = 'Running' },
                    [PSCustomObject]@{ TaskName = 'MockTask3'; State = 'Disabled' }
                )
            }
        }
    }

    # Mock Service functions
    if (-not (Get-Command Set-Service -ErrorAction SilentlyContinue)) {
        function Set-Service {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory)]
                [string]$Name,
                [string]$StartupType,
                [string]$Status
            )

            return $true
        }
    }

    if (-not (Get-Command Start-Service -ErrorAction SilentlyContinue)) {
        function Start-Service {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory)]
                [string]$Name
            )

            return $true
        }
    }

    if (-not (Get-Command Stop-Service -ErrorAction SilentlyContinue)) {
        function Stop-Service {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory)]
                [string]$Name
            )

            return $true
        }
    }

    if (-not (Get-Command Get-Service -ErrorAction SilentlyContinue)) {
        function Get-Service {
            [CmdletBinding()]
            param(
                [string]$Name
            )

            if ($Name) {
                return [PSCustomObject]@{
                    Name = $Name
                    Status = 'Running'
                    StartType = 'Automatic'
                    DisplayName = "Mock Service: $Name"
                }
            } else {
                return @(
                    [PSCustomObject]@{ Name = 'MockService1'; Status = 'Running'; StartType = 'Automatic' },
                    [PSCustomObject]@{ Name = 'MockService2'; Status = 'Stopped'; StartType = 'Manual' },
                    [PSCustomObject]@{ Name = 'MockService3'; Status = 'Running'; StartType = 'Automatic' }
                )
            }
        }
    }

    # Mock Windows Principal functions
    if (-not (Get-Command New-ScheduledTaskPrincipal -ErrorAction SilentlyContinue)) {
        function New-ScheduledTaskPrincipal {
            [CmdletBinding()]
            param(
                [string]$UserId,
                [string]$RunLevel,
                [string]$LogonType
            )

            return [PSCustomObject]@{
                UserId = $UserId ?? 'SYSTEM'
                RunLevel = $RunLevel ?? 'Limited'
                LogonType = $LogonType ?? 'ServiceAccount'
            }
        }
    }

    if (-not (Get-Command New-ScheduledTaskAction -ErrorAction SilentlyContinue)) {
        function New-ScheduledTaskAction {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory)]
                [string]$Execute,
                [string]$Argument,
                [string]$WorkingDirectory
            )

            return [PSCustomObject]@{
                Execute = $Execute
                Arguments = $Argument
                WorkingDirectory = $WorkingDirectory
            }
        }
    }

    if (-not (Get-Command New-ScheduledTaskTrigger -ErrorAction SilentlyContinue)) {
        function New-ScheduledTaskTrigger {
            [CmdletBinding()]
            param(
                [switch]$Daily,
                [switch]$Weekly,
                [switch]$AtStartup,
                [switch]$AtLogOn,
                [DateTime]$At
            )

            return [PSCustomObject]@{
                TriggerType = if ($Daily) { 'Daily' } elseif ($Weekly) { 'Weekly' } elseif ($AtStartup) { 'AtStartup' } elseif ($AtLogOn) { 'AtLogOn' } else { 'Unknown' }
                StartBoundary = $At ?? (Get-Date)
                Enabled = $true
            }
        }
    }

    # Mock prerequisite functions that tests expect
    if (-not (Get-Command Test-WmrPrerequisites -ErrorAction SilentlyContinue)) {
        function Test-WmrPrerequisites {
            [CmdletBinding()]
            param(
                $TemplateConfig,
                [string]$Operation
            )

            return $true
        }
    }

    if (-not (Get-Command Backup-WindowsFeatures -ErrorAction SilentlyContinue)) {
        function Backup-WindowsFeatures {
            [CmdletBinding()]
            param(
                [string]$BackupPath
            )

            return @{
                Success = $true
                RequiresElevation = $false
                BackupPath = $BackupPath ?? '/tmp/mock-features-backup.json'
                Features = @(
                    @{ Name = 'MockFeature1'; State = 'Enabled' },
                    @{ Name = 'MockFeature2'; State = 'Disabled' }
                )
            }
        }
    }

    # Mock administrative operations functions
    if (-not (Get-Command Get-WindowsOptionalFeaturesState -ErrorAction SilentlyContinue)) {
        function Get-WindowsOptionalFeaturesState {
            [CmdletBinding()]
            param()

            return @{
                Success = $true
                RequiresElevation = $false
                Features = @(
                    @{ FeatureName = 'MockFeature1'; State = 'Enabled' },
                    @{ FeatureName = 'MockFeature2'; State = 'Disabled' }
                )
            }
        }
    }

    if (-not (Get-Command Get-WindowsCapabilitiesState -ErrorAction SilentlyContinue)) {
        function Get-WindowsCapabilitiesState {
            [CmdletBinding()]
            param()

            return @{
                Success = $true
                RequiresElevation = $false
                Capabilities = @(
                    @{ Name = 'MockCapability1'; State = 'Installed' },
                    @{ Name = 'MockCapability2'; State = 'NotPresent' }
                )
            }
        }
    }

    if (-not (Get-Command Set-WindowsService -ErrorAction SilentlyContinue)) {
        function Set-WindowsService {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory)]
                [string]$ServiceName,
                [Parameter(Mandatory)]
                [string]$Action
            )

            return @{
                Success = $true
                RequiresElevation = $false
                ServiceName = $ServiceName
                Action = $Action
            }
        }
    }

    if (-not (Get-Command Set-RegistryValue -ErrorAction SilentlyContinue)) {
        function Set-RegistryValue {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory)]
                [string]$Path,
                [Parameter(Mandatory)]
                [string]$Name,
                [Parameter(Mandatory)]
                $Value
            )

            return @{
                Success = $true
                RequiresElevation = $Path -like "HKLM:*"
                Path = $Path
                Name = $Name
                Value = $Value
            }
        }
    }

    if (-not (Get-Command Set-ScheduledTask -ErrorAction SilentlyContinue)) {
        function Set-ScheduledTask {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory)]
                [string]$TaskName,
                [Parameter(Mandatory)]
                [string]$Action,
                [bool]$RequireElevation = $false
            )

            return @{
                Success = $true
                RequiresElevation = $RequireElevation
                TaskName = $TaskName
                Action = $Action
            }
        }
    }

    if (-not (Get-Command Test-ElevationCapability -ErrorAction SilentlyContinue)) {
        function Test-ElevationCapability {
            [CmdletBinding()]
            param()

            return $true
        }
    }

    # Set up mock Windows drives
    if (-not (Test-Path '/mock-c')) {
        New-Item -Path '/mock-c' -ItemType Directory -Force | Out-Null
        New-Item -Path '/mock-c/Users' -ItemType Directory -Force | Out-Null
        New-Item -Path '/mock-c/Users/TestUser' -ItemType Directory -Force | Out-Null
        New-Item -Path '/mock-c/Program Files' -ItemType Directory -Force | Out-Null
        New-Item -Path '/mock-c/ProgramData' -ItemType Directory -Force | Out-Null
        New-Item -Path '/mock-c/Windows' -ItemType Directory -Force | Out-Null
        Write-Verbose "Created mock Windows directory structure"
    }

    # Mock Windows security objects
    if (-not ([System.Management.Automation.PSTypeName]'Security.Principal.WindowsIdentity').Type) {
        Add-Type -TypeDefinition @"
            namespace Security.Principal {
                public class WindowsIdentity {
                    public string Name { get; set; }
                    public System.Collections.Generic.List<object> Groups { get; set; }

                    public WindowsIdentity() {
                        Name = "TestUser";
                        Groups = new System.Collections.Generic.List<object>();
                    }

                    public static WindowsIdentity GetCurrent() {
                        return new WindowsIdentity();
                    }
                }

                public class WindowsPrincipal {
                    public WindowsIdentity Identity { get; set; }

                    public WindowsPrincipal(WindowsIdentity identity) {
                        Identity = identity;
                    }

                    public bool IsInRole(WindowsBuiltInRole role) {
                        return false; // Mock as non-admin by default
                    }
                }

                public enum WindowsBuiltInRole {
                    Administrator
                }

                public class SecurityIdentifier {
                    public SecurityIdentifier(WellKnownSidType sidType, SecurityIdentifier domainSid) {
                    }

                    public bool Equals(SecurityIdentifier other) {
                        return false;
                    }
                }

                public enum WellKnownSidType {
                    BuiltinAdministratorsSid
                }
            }
"@
    }

    # Mock id command for Unix-like systems
    if (-not (Get-Command id -ErrorAction SilentlyContinue)) {
        function id {
            param([string]$u)
            return "1000"  # Non-root user ID
        }
    }

    # Mock Read-WmrTemplateConfig for template operations
    if (-not (Get-Command Read-WmrTemplateConfig -ErrorAction SilentlyContinue)) {
        function Read-WmrTemplateConfig {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory=$true)]
                [string]$TemplatePath
            )

            if (-not (Test-Path $TemplatePath)) {
                throw "Template file not found: $TemplatePath"
            }

            try {
                $content = Get-Content $TemplatePath -Raw -Encoding UTF8
                if ($TemplatePath -like "*.yaml" -or $TemplatePath -like "*.yml") {
                    # Simple YAML parsing for test purposes
                    $yamlContent = @{
                        metadata = @{}
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
                                $yamlContent.metadata.name = $matches[1] -replace '"', ''
                            } elseif ($currentItem) {
                                $currentItem.name = $matches[1] -replace '"', ''
                            }
                        } elseif ($line -match "^\s*version:\s*(.+)") {
                            if ($currentSection -eq "metadata") {
                                $yamlContent.metadata.version = $matches[1] -replace '"', ''
                            }
                        } elseif ($line -match "^\s*description:\s*(.+)") {
                            if ($currentSection -eq "metadata") {
                                $yamlContent.metadata.description = $matches[1] -replace '"', ''
                            }
                        } elseif ($line -match "^\s*-\s*type:\s*(.+)") {
                            $currentItem = @{ type = $matches[1] -replace '"', '' }
                            if ($currentSection -eq "prerequisites") {
                                $yamlContent.prerequisites += $currentItem
                            }
                        } elseif ($line -match "^\s*-\s*name:\s*(.+)") {
                            $currentItem = @{ name = $matches[1] -replace '"', '' }
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
    }

    # Mock Get-WmrModulePath for module operations
    if (-not (Get-Command Get-WmrModulePath -ErrorAction SilentlyContinue)) {
        function Get-WmrModulePath {
            [CmdletBinding()]
            param()

            # Return the actual module file path, not the directory
            return "/workspace/WindowsMelodyRecovery.psm1"
        }
    }

    # Mock additional path utilities - removed duplicate function definition

    Write-Information -MessageData "🐳 Docker test environment initialized with comprehensive mocks" -InformationAction Continue
} else {
    Write-Verbose "Native Windows environment detected, using standard functionality"
}

# Helper function to check if running in Docker
function Test-DockerEnvironment {
    return $script:IsDockerEnvironment
}

# Helper function to get appropriate path for current environment
function Get-WmrTestPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$WindowsPath
    )

    if ($script:IsDockerEnvironment) {
        # Convert Windows paths to Linux paths for Docker (avoid recursion)
        $linuxPath = $WindowsPath -replace '\\', '/'
        $linuxPath = $linuxPath -replace '^C:', '/workspace'
        return $linuxPath
    } else {
        return $WindowsPath
    }
}

# Helper function to normalize line endings for cross-platform tests
function ConvertTo-UnixLineEndings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]$Text
    )

    process {
        return $Text.Replace("`r`n", "`n").Replace("`r", "`n")
    }
}

# Helper function to create test directories safely
function New-WmrTestDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $testPath = Get-WmrTestPath -WindowsPath $Path
    if (-not (Test-Path $testPath)) {
        New-Item -Path $testPath -ItemType Directory -Force | Out-Null
        Write-Verbose "Created test directory: $testPath"
    }
    return $testPath
}

# Helper function to clean up test directories
function Remove-WmrTestDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $testPath = Get-WmrTestPath -WindowsPath $Path
    if (Test-Path $testPath) {
        Remove-Item -Path $testPath -Recurse -Force -ErrorAction SilentlyContinue
        Write-Verbose "Cleaned up test directory: $testPath"
    }
}

# Functions are available when dot-sourced, no need to export when not in module context







