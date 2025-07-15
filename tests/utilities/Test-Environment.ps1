#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Unified and Standardized Test Environment Management for Windows Melody Recovery.

.DESCRIPTION
    This script provides a single, comprehensive system for managing test environments.
    It combines the safety features and structured configuration of the previous
    "Standard" environment with the dynamic, isolated directory creation of the
    simpler environment script.

    It provides a single function, 'Initialize-WmrTestEnvironment', to be used by
    all test runners and Pester test files.

    Features:
    - Consistent, isolated test environment for each test run.
    - Strong safety checks to prevent operations outside the test directory.
    - Unified configuration for easy maintenance.
    - Explicit environment detection (Docker, CI, Windows, etc.).
    - Suite-specific setup for Unit, Integration, FileOps, E2E, and Windows tests.
#>

#region Enhanced Mocking Integration
# Dot-source the core mocking infrastructure. This makes the powerful data generation
# and simulation functions available to the test environment lifecycle.
# These scripts are sourced once and their functions are used by the setup helpers below.
. (Join-Path $PSScriptRoot "Enhanced-Mock-Infrastructure.ps1")
. (Join-Path $PSScriptRoot "Mock-Integration.ps1")
#endregion

#region Core Configuration and State
# Script-level variables for state and configuration management.

$script:ModuleRoot = $null
$script:TestRunInitialized = $false
$script:CurrentTestEnvironment = $null

# Central configuration for all test-related paths, variables, and safety checks.
$script:TestConfiguration = @{
    Directories    = @{
        # Core directories to be created inside the isolated test root
        TestRestore = "test-restore"
        TestBackup  = "test-backups"
        Temp        = "temp"
        TestState   = "test-state"
        Logs        = "logs"
        MockData    = "mock-data"
        Reports     = "reports"
    }

    SafetyPatterns = @{
        # The root path MUST contain one of these patterns
        RequiredInPath = @("WMR-Tests", "Temp", "tmp")
        # The root path MUST NOT contain any of these patterns
        ForbiddenPaths = @("C:\Windows", "C:\Program Files", "$env:SystemRoot")
        # Safety check will fail if the current path is one of these
        ForbiddenRoots = @("C:\", "D:\", "/")
    }

    Environment    = @{
        Variables = @{
            "WMR_TEST_MODE"                 = "true"
            "WMR_SAFE_MODE"                 = "true" # Enables additional safety checks in module code
            "WMR_LOG_LEVEL"                 = "Debug"
            "POWERSHELL_TELEMETRY_OPTOUT"   = "1"
            "POWERSHELL_UPDATECHECK_OPTOUT" = "1"
        }
    }
}
#endregion

#region Core Functions
# --- Main Public Functions ---

function Initialize-WmrTestEnvironment {
    <#
    .SYNOPSIS
        Initializes a unified, isolated, and safe test environment for a specific test suite.
    .DESCRIPTION
        This is the primary function for all test setup. It performs the following steps:
        1. Detects the current environment (OS, CI, Docker).
        2. Finds the module root.
        3. Performs strict safety checks to ensure it's not running in a production directory.
        4. Creates a unique, isolated root directory for the test run.
        5. Sets up a standard structure of subdirectories within the isolated root.
        6. Sets all required environment variables for testing.
        7. Loads suite-specific mocks or utilities based on the -SuiteName parameter.
        8. Returns a hashtable containing all relevant paths for the test run.
    .PARAMETER SuiteName
        The name of the test suite to initialize. This determines which, if any,
        additional mock utilities are loaded.
    .PARAMETER SessionId
        An optional unique ID for the test run. If not provided, a random one is generated.
        This is used to create the isolated test directory.
    .PARAMETER Force
        Force re-creation of the test directory if it already exists.
    .EXAMPLE
        $testEnv = Initialize-WmrTestEnvironment -SuiteName 'Unit'
    .EXAMPLE
        $testEnv = Initialize-WmrTestEnvironment -SuiteName 'Integration' -Force
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Unit', 'FileOps', 'Integration', 'E2E', 'Windows')]
        [string]$SuiteName,

        [Parameter(Mandatory = $false)]
        [string]$SessionId = (New-Guid).Guid.Substring(0, 8),

        [switch]$Force
    )

    Write-Information -MessageData "🔧 Initializing Unified Test Environment for Suite: $SuiteName" -InformationAction Continue

    # --- Step 1: Environment Detection and Path Finding ---
    $envDetails = Get-WmrEnvironmentType
    $script:ModuleRoot = Find-WmrModuleRoot
    if (-not $script:ModuleRoot) {
        throw "Could not find the module root. Cannot initialize test environment."
    }

    # --- Step 2: Create Isolated Root Path ---
    $baseTempPath = if ($envDetails.IsCI) {
        if ($envDetails.IsWindows) { $env:TEMP } else { '/tmp' }
    }
    else {
        Join-Path $script:ModuleRoot "Temp"
    }

    $testRoot = Join-Path $baseTempPath "WMR-Tests-$SuiteName-$SessionId"
    Write-Verbose "Isolated Test Root: $testRoot"

    # --- Step 3: Safety Validation ---
    Test-WmrEnvironmentSafety -TestRoot $testRoot -Strict
    Write-Verbose "✅ Environment safety validation passed."

    # --- Step 4: Create Directory Structure ---
    if ($Force -and (Test-Path $testRoot)) {
        Write-Warning "Force cleanup requested - removing existing test directory..."
        Remove-Item -Path $testRoot -Recurse -Force
    }
    $testPaths = New-WmrTestDirectoryStructure -TestRoot $testRoot
    Write-Verbose "✅ Test directory structure created."

    # --- Step 5: Set Environment Variables ---
    Set-WmrTestEnvironmentVariables -TestPaths $testPaths -EnvironmentDetails $envDetails
    Write-Verbose "✅ Test environment variables configured."

    # --- Step 6: Suite-Specific Setup ---
    Invoke-WmrSuiteSpecificSetup -SuiteName $SuiteName -ModuleRoot $script:ModuleRoot -EnvironmentDetails $envDetails
    Write-Verbose "✅ Suite-specific setup for '$SuiteName' complete."


    # --- Step 7: Finalize and Return ---
    $script:TestRunInitialized = $true
    $script:CurrentTestEnvironment = $testPaths
    $global:TestEnvironment = $script:CurrentTestEnvironment # For backward compatibility with some tests

    Write-Information -MessageData "🎉 Unified test environment initialized successfully!" -InformationAction Continue
    return $script:CurrentTestEnvironment
}

function Remove-WmrTestEnvironment {
    <#
    .SYNOPSIS
        Safely removes the currently active test environment directory.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param()

    if (-not $script:TestRunInitialized -or -not $script:CurrentTestEnvironment) {
        Write-Verbose "No active test environment to remove."
        return
    }

    $testRoot = $script:CurrentTestEnvironment.TestRoot
    Write-Warning "🧹 Cleaning up isolated test environment at: $testRoot"

    # Final safety check before removing
    Test-WmrEnvironmentSafety -TestRoot $testRoot -Strict

    if ($PSCmdlet.ShouldProcess($testRoot, "Remove Test Environment Directory")) {
        Remove-Item -Path $testRoot -Recurse -Force
        Write-Verbose "✅ Test environment cleanup successful."
    }

    $script:TestRunInitialized = $false
    $script:CurrentTestEnvironment = $null
    $global:TestEnvironment = $null
}


# --- Internal Helper Functions ---

function Get-WmrEnvironmentType {
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param()

    Write-Verbose "🔍 Detecting test environment type..."
    $isDocker = ($env:DOCKER_TEST -eq 'true') -or ($env:CONTAINER -eq 'true') -or (Test-Path '/.dockerenv')
    $isWindows = $IsWindows
    $isCI = $env:CI -or $env:GITHUB_ACTIONS -or $env:BUILD_BUILDID -or $env:JENKINS_URL

    $envType = [PSCustomObject]@{
        IsDocker  = $isDocker
        IsWindows = $isWindows
        IsLinux   = $IsLinux
        IsMacOs   = $IsMacOS
        IsCI      = $isCI
        Platform  = if ($isWindows) { 'Windows' } elseif ($isLinux) { 'Linux' } else { 'MacOS' }
    }

    Write-Verbose "Environment: $($envType | ConvertTo-Json -Compress)"
    return $envType
}

function Find-WmrModuleRoot {
    [OutputType('string')]
    [CmdletBinding()]
    param()

    Write-Verbose "🔍 Finding module root..."
    $currentPath = $PSScriptRoot
    if (-not $currentPath) { $currentPath = Get-Location }

    $searchDepth = 0
    while ($currentPath -and $searchDepth -lt 10) {
        if (Test-Path (Join-Path $currentPath "WindowsMelodyRecovery.psd1")) {
            Write-Verbose "Found module root at: $currentPath"
            return $currentPath.ToString()
        }
        $parentPath = Split-Path -Parent $currentPath
        if ($parentPath -eq $currentPath) { break }
        $currentPath = $parentPath
        $searchDepth++
    }

    Write-Error "Could not find module root directory."
    return $null
}

function Test-WmrEnvironmentSafety {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TestRoot,
        [switch]$Strict
    )

    Write-Verbose "🛡️  Performing environment safety validation for path: $TestRoot"

    # Check 1: Forbidden Roots
    foreach ($root in $script:TestConfiguration.SafetyPatterns.ForbiddenRoots) {
        if ($TestRoot -eq $root) {
            throw "Safety Error: Test root cannot be a filesystem root ('$root')."
        }
    }

    # Check 2: Required Patterns
    $foundRequired = $false
    foreach ($pattern in $script:TestConfiguration.SafetyPatterns.RequiredInPath) {
        if ($TestRoot -like "*$pattern*") {
            $foundRequired = $true
            break
        }
    }
    if (-not $foundRequired) {
        throw "Safety Error: Test root path '$TestRoot' must contain one of the required safety patterns: $($script:TestConfiguration.SafetyPatterns.RequiredInPath -join ', ')."
    }

    # Check 3: Forbidden Paths
    foreach ($pattern in $script:TestConfiguration.SafetyPatterns.ForbiddenPaths) {
        if ($TestRoot -like "*$pattern*") {
            throw "Safety Error: Test root path '$TestRoot' contains a forbidden pattern: '$pattern'."
        }
    }

    Write-Verbose "Safety validation passed."
}

function New-WmrTestDirectoryStructure {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TestRoot
    )

    $paths = @{
        TestRoot   = $TestRoot
        ModuleRoot = $script:ModuleRoot
    }

    foreach ($dirEntry in $script:TestConfiguration.Directories.GetEnumerator()) {
        $fullPath = Join-Path $TestRoot $dirEntry.Value
        New-Item -Path $fullPath -ItemType Directory -Force | Out-Null
        $paths[$dirEntry.Name] = $fullPath
    }

    return $paths
}

function Set-WmrTestEnvironmentVariables {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$TestPaths,
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$EnvironmentDetails
    )

    # Set standard variables
    foreach ($var in $script:TestConfiguration.Environment.Variables.GetEnumerator()) {
        $env:${var.Name} = $var.Value
    }

    # Set dynamic path variables
    $env:WMR_STATE_PATH = $TestPaths.TestState
    $env:WMR_BACKUP_PATH = $TestPaths.TestBackup
    $env:WMR_LOG_PATH = $TestPaths.Logs
    $env:WMR_TEMP_PATH = $TestPaths.Temp

    # Set environment indicator variables
    $env:WMR_IS_DOCKER = $EnvironmentDetails.IsDocker.ToString()
    $env:WMR_IS_CI = $EnvironmentDetails.IsCI.ToString()

    # If in Docker, mock essential Windows environment variables for compatibility
    if ($EnvironmentDetails.IsDocker) {
        Write-Verbose "🐧 Docker environment detected. Mocking Windows-specific environment variables."
        if (-not $env:USERPROFILE) { $env:USERPROFILE = '/mock-c/Users/TestUser' }
        if (-not $env:PROGRAMFILES) { $env:PROGRAMFILES = '/mock-c/Program Files' }
        if (-not $env:PROGRAMFILESX86) { $env:PROGRAMFILESX86 = '/mock-c/Program Files (x86)' }
        if (-not $env:PROGRAMDATA) { $env:PROGRAMDATA = '/mock-c/ProgramData' }
        if (-not $env:COMPUTERNAME) { $env:COMPUTERNAME = 'TEST-MACHINE' }
        if (-not $env:HOSTNAME) { $env:HOSTNAME = 'TEST-MACHINE' }
        if (-not $env:USERNAME) { $env:USERNAME = 'TestUser' }
        if (-not $env:PROCESSOR_ARCHITECTURE) { $env:PROCESSOR_ARCHITECTURE = 'AMD64' }
        if (-not $env:USERDOMAIN) { $env:USERDOMAIN = 'WORKGROUP' }
        if (-not $env:PROCESSOR_IDENTIFIER) { $env:PROCESSOR_IDENTIFIER = 'Intel64 Family 6 Model 158 Stepping 10, GenuineIntel' }
        if (-not $env:SystemDrive) { $env:SystemDrive = 'C:' }
    }
}

function Invoke-WmrSuiteSpecificSetup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SuiteName,
        [Parameter(Mandatory)]
        [string]$ModuleRoot,
        [Parameter(Mandatory)]
        [PSCustomObject]$EnvironmentDetails
    )

    $utilitiesPath = Join-Path $ModuleRoot "tests/utilities"

    # If running in Docker, the foundational Windows cmdlets must be mocked for any
    # test suite to function correctly. This is the first thing we do.
    if ($EnvironmentDetails.IsDocker) {
        Write-Verbose "🐧 Docker environment detected. Applying foundational Windows cmdlet mocks."
        Initialize-WmrDockerMocks
        Initialize-WmrDockerPathMocks
    }

    # A helper function to safely dot-source a utility if it exists.
    function Import-TestUtility {
        param([string]$UtilityName)
        $utilityFile = Join-Path $utilitiesPath "$UtilityName.ps1"
        if (Test-Path $utilityFile) {
            . $utilityFile
            Write-Verbose "Loaded test utility: $UtilityName"
        }
        else {
            Write-Warning "Could not find test utility: $UtilityName"
        }
    }

    Write-Verbose "🔧 Performing setup for '$SuiteName' suite..."
    switch ($SuiteName) {
        'Unit' {
            # Unit tests should be pure logic and require minimal setup.
            # Mocks should be defined within the test files themselves.
        }
        'FileOps' {
            # FileOps tests need the standard paths, but no complex application mocks.
        }
        'Integration' {
            # Load mocks for external services, applications, etc.
            Initialize-MockForTestType -TestType "Integration" -Scope "Standard"
        }
        'E2E' {
            # E2E tests get the full mock infrastructure.
            Initialize-MockForTestType -TestType "EndToEnd" -Scope "Comprehensive"
        }
        'Windows' {
            # Windows tests run against the real system, so minimal mocking is needed.
            # Safety checks are paramount and handled by the core initializer.
        }
    }
}

function Initialize-WmrDockerMocks {
    <#
    .SYNOPSIS
        Defines mock functions for essential Windows cmdlets.
    .DESCRIPTION
        This function creates simple, in-memory mocks for a wide range of
        Windows-specific cmdlets that are not available in the Linux Docker
        containers. This allows integration tests that call these cmdlets to run
        without crashing. These mocks are not intended to be sophisticated, but
        to provide baseline compatibility.
    #>
    [CmdletBinding()]
    param()

    Write-Verbose "Mocking essential Windows cmdlets for Docker environment."

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
                            Name                      = 'Intel(R) Core(TM) i7-8700K CPU @ 3.70GHz'
                            NumberOfCores             = 6
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
                            Name       = 'NVIDIA GeForce GTX 1080'
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
                    FeatureName     = $FeatureName
                    State           = 'Enabled'
                    RestartRequired = $false
                }
            }
            else {
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
                FeatureName   = $FeatureName
                RestartNeeded = $false
                LogPath       = '/tmp/mock-feature-log.txt'
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
                FeatureName   = $FeatureName
                RestartNeeded = $false
                LogPath       = '/tmp/mock-feature-log.txt'
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
                    Name        = $Name
                    State       = 'Installed'
                    DisplayName = "Mock Capability: $Name"
                }
            }
            else {
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
                Name          = $Name
                RestartNeeded = $false
                LogPath       = '/tmp/mock-capability-log.txt'
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
                Name          = $Name
                RestartNeeded = $false
                LogPath       = '/tmp/mock-capability-log.txt'
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

            # Store mock task data in a script-level variable to allow other mocks to see it
            $script:MockScheduledTasks = $script:MockScheduledTasks | Where-Object { $_.TaskName -ne $TaskName }
            $task = [PSCustomObject]@{
                TaskName    = $TaskName
                State       = 'Ready'
                LastRunTime = (Get-Date).AddHours(-1)
                NextRunTime = (Get-Date).AddDays(1)
                Actions     = @($Action)
                Triggers    = @($Trigger)
                Principal   = $Principal
            }
            $script:MockScheduledTasks += $task
            return $task
        }
    }

    if (-not (Get-Command Unregister-ScheduledTask -ErrorAction SilentlyContinue)) {
        function Unregister-ScheduledTask {
            [CmdletBinding(SupportsShouldProcess)]
            param(
                [Parameter(Mandatory)]
                [string]$TaskName,
                [switch]$Confirm
            )
            if ($PSCmdlet.ShouldProcess($TaskName, "Unregister Scheduled Task")) {
                $script:MockScheduledTasks = $script:MockScheduledTasks | Where-Object { $_.TaskName -ne $TaskName }
            }
        }
    }

    if (-not (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue)) {
        function Get-ScheduledTask {
            [CmdletBinding()]
            param(
                [string]$TaskName
            )
            if ($TaskName) {
                return $script:MockScheduledTasks | Where-Object { $_.TaskName -eq $TaskName }
            }
            return $script:MockScheduledTasks
        }
    }

    # Mock other system cmdlets
    if (-not (Get-Command Get-ComputerInfo -ErrorAction SilentlyContinue)) {
        function Get-ComputerInfo {
            return [PSCustomObject]@{
                WindowsProductName = 'Windows 10 Pro'
                WindowsVersion     = '2004'
                OsArchitecture     = '64-bit'
            }
        }
    }

    if (-not (Get-Command Test-NetConnection -ErrorAction SilentlyContinue)) {
        function Test-NetConnection {
            [CmdletBinding()]
            param(
                [string]$ComputerName,
                [int]$Port
            )
            # Assume success for mocked tests
            return [PSCustomObject]@{
                ComputerName     = $ComputerName
                TcpTestSucceeded = $true
                RemotePort       = $Port
            }
        }
    }

    # Add more mocks as needed...
}

function Initialize-WmrDockerPathMocks {
    <#
    .SYNOPSIS
        Defines mock functions for path and privilege management in Docker.
    .DESCRIPTION
        This function creates mocks for path translations (e.g., C:\ to /mock-c/),
        registry access, and administrative privilege checks to allow tests
        that depend on Windows-like structures to run in a Linux container.
    #>
    [CmdletBinding()]
    param()

    Write-Verbose "Mocking Windows paths and privileges for Docker environment."

    # Global path mappings for Docker testing
    $script:DockerPathMappings = @{
        'C:\'              = '/mock-c/'
        'D:\'              = '/mock-d/'
        'E:\'              = '/mock-e/'
        'C:\Users'         = '/mock-c/Users'
        'C:\Program Files' = '/mock-c/Program Files'
        'C:\ProgramData'   = '/mock-c/ProgramData'
        'C:\Windows'       = '/mock-c/Windows'
        'C:\Temp'          = '/tmp'
        'C:\tmp'           = '/tmp'
    }

    # Mock Windows Principal functionality for Docker tests
    if (-not (Get-Command Test-WmrAdminPrivilege -ErrorAction SilentlyContinue)) {
        function Test-WmrAdminPrivilege {
            [CmdletBinding()]
            [OutputType([System.Boolean])]
            param()

            # In Docker tests, simulate non-admin user unless overridden
            if ($env:DOCKER_TEST_ADMIN -eq 'true') {
                return $true
            }
            return $false
        }
    }

    if (-not (Get-Command Test-WmrAdministrativePrivilege -ErrorAction SilentlyContinue)) {
        function Test-WmrAdministrativePrivilege {
            [CmdletBinding()]
            [OutputType([System.Boolean])]
            param()

            # Mock administrative privileges check
            return Test-WmrAdminPrivilege
        }
    }


    # Convert Windows paths to Docker-compatible paths
    if (-not (Get-Command Convert-WmrPathForDocker -ErrorAction SilentlyContinue)) {
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
    }

    # Mock Join-Path that works cross-platform
    if (-not (Get-Command Join-WmrPath -ErrorAction SilentlyContinue)) {
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
    }

    # Mock Windows registry functionality
    if (-not (Get-Command Test-WmrRegistryPath -ErrorAction SilentlyContinue)) {
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
    }
}
#endregion







