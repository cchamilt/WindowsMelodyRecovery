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

#region Core Configuration and State
# Script-level variables for state and configuration management.

$script:ModuleRoot = $null
$script:TestRunInitialized = $false
$script:CurrentTestEnvironment = $null

# Central configuration for all test-related paths, variables, and safety checks.
$script:TestConfiguration = @{
    Directories = @{
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

    Environment = @{
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
    Invoke-WmrSuiteSpecificSetup -SuiteName $SuiteName -ModuleRoot $script:ModuleRoot
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
        $env:($var.Name) = $var.Value
    }

    # Set dynamic path variables
    $env:WMR_STATE_PATH = $TestPaths.TestState
    $env:WMR_BACKUP_PATH = $TestPaths.TestBackup
    $env:WMR_LOG_PATH = $TestPaths.Logs
    $env:WMR_TEMP_PATH = $TestPaths.Temp

    # Set environment indicator variables
    $env:WMR_IS_DOCKER = $EnvironmentDetails.IsDocker.ToString()
    $env:WMR_IS_CI = $EnvironmentDetails.IsCI.ToString()
}

function Invoke-WmrSuiteSpecificSetup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SuiteName,
        [Parameter(Mandatory)]
        [string]$ModuleRoot
    )

    $utilitiesPath = Join-Path $ModuleRoot "tests/utilities"

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
            Import-TestUtility "Mock-Utilities"
            Import-TestUtility "Mock-Integration"
        }
        'E2E' {
            # E2E tests get the full mock infrastructure.
            Import-TestUtility "Mock-Utilities"
            Import-TestUtility "Enhanced-Mock-Infrastructure"
            if ((Get-WmrEnvironmentType).IsDocker) {
                Import-TestUtility "Docker-Path-Mocks"
            }
        }
        'Windows' {
            # Windows tests run against the real system, so minimal mocking is needed.
            # Safety checks are paramount and handled by the core initializer.
        }
    }
}
#endregion







