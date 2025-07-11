#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Test Utilities for Windows Melody Recovery Integration Tests

.DESCRIPTION
    Common utility functions for test execution, reporting, and environment management.
#>

# Test execution utilities
function Invoke-TestWithRetry {
    param(
        [scriptblock]$TestScript,
        [int]$MaxRetries = 3,
        [int]$RetryDelaySeconds = 5
    )

    for ($i = 1; $i -le $MaxRetries; $i++) {
        try {
            $result = & $TestScript
            return $result
        } catch {
            if ($i -eq $MaxRetries) {
                throw "Test failed after $MaxRetries attempts: $($_.Exception.Message)"
            }
            Write-Warning -Message "Test attempt $i failed, retrying in $RetryDelaySeconds seconds..."
            Start-Sleep -Seconds $RetryDelaySeconds
        }
    }
}

function Write-TestResult {
    param(
        [string]$TestName,
        [bool]$Passed,
        [string]$Message = "",
        [object]$Details = $null
    )

    $status = if ($Passed) { "✓ PASS" } else { "✗ FAIL" }
    $color = if ($Passed) { "Green" } else { "Red" }

    Write-Information -MessageData "$status $TestName"  -InformationAction Continue-ForegroundColor $color
    if ($Message) {
        Write-Verbose -Message "  $Message"
    }
    if ($Details) {
        Write-Verbose -Message "  Details: $($Details | ConvertTo-Json -Compress)"
    }
}

function Get-TestSummary {
    param(
        [array]$TestResults
    )

    $summary = @{
        Total = $TestResults.Count
        Passed = ($TestResults | Where-Object { $_.Result -eq "Passed" }).Count
        Failed = ($TestResults | Where-Object { $_.Result -eq "Failed" }).Count
        Duration = ($TestResults | Measure-Object -Property Duration -Sum).Sum
    }

    return $summary
}

# Test utilities module
$script:ModuleRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

# Only export functions if we're in a module context
if ($MyInvocation.MyCommand.Path) {  # Check if we're in a script file
    # Create module scope for functions
    New-Module -Name TestUtilities -ScriptBlock {
        function Start-TestWithTimeout {
            <#
            .SYNOPSIS
                Executes a test block with timeout protection.

            .DESCRIPTION
                Runs a test block with configurable timeout protection. If the test exceeds
                the specified timeout, it will be terminated and marked as failed.

            .PARAMETER ScriptBlock
                The test script block to execute.

            .PARAMETER TimeoutSeconds
                The maximum time in seconds to allow the test to run.

            .PARAMETER TestName
                The name of the test for logging purposes.

            .PARAMETER Type
                The type of timeout (Test, Describe, Context, Block, or Global).

            .EXAMPLE
                Start-TestWithTimeout -ScriptBlock { Test-Something } -TimeoutSeconds 300 -TestName "My Test" -Type "Test"
            #>
            [CmdletBinding()]
            param(
                [Parameter(Mandatory = $true)]
                [scriptblock]$ScriptBlock,

                [Parameter(Mandatory = $true)]
                [int]$TimeoutSeconds,

                [Parameter(Mandatory = $true)]
                [string]$TestName,

                [Parameter(Mandatory = $true)]
                [ValidateSet('Test', 'Describe', 'Context', 'Block', 'Global')]
                [string]$Type
            )

            try {
                $job = Start-Job -ScriptBlock $ScriptBlock

                $completed = Wait-Job -Job $job -Timeout $TimeoutSeconds

                if ($completed -eq $null) {
                    Stop-Job -Job $job
                    Remove-Job -Job $job -Force
                    throw "Test '$TestName' exceeded timeout of $TimeoutSeconds seconds"
                }

                $result = Receive-Job -Job $job
                Remove-Job -Job $job

                return $result
            }
            catch {
                Write-Warning "$Type '$TestName' failed: $_"
                throw
            }
        }

        function Get-TestTimeout {
            <#
            .SYNOPSIS
                Gets the configured timeout value for a test type.

            .DESCRIPTION
                Retrieves the timeout value from PesterConfig.psd1 for the specified test type.
                Falls back to default values if not configured.

            .PARAMETER Type
                The type of timeout to retrieve (Test, Describe, Context, Block, or Global).

            .EXAMPLE
                Get-TestTimeout -Type "Test"
            #>
            [CmdletBinding()]
            param(
                [Parameter(Mandatory = $true)]
                [ValidateSet('Test', 'Describe', 'Context', 'Block', 'Global')]
                [string]$Type
            )

            # Default timeout values (in seconds)
            $defaultTimeouts = @{
                Test = 300       # 5 minutes
                Describe = 1800  # 30 minutes
                Context = 900    # 15 minutes
                Block = 3600     # 1 hour
                Global = 7200    # 2 hours
            }

            try {
                # Try to get configuration from PesterConfig.psd1
                $configPath = Join-Path $script:ModuleRoot "PesterConfig.psd1"
                if ($configPath -and (Test-Path $configPath)) {
                    $config = Import-PowerShellDataFile $configPath
                    if ($config.Run.Timeout."${Type}Timeout") {
                        return $config.Run.Timeout."${Type}Timeout"
                    }
                }
            }
            catch {
                Write-Warning "Failed to load timeout configuration: $_"
            }

            # Fall back to default timeout
            return $defaultTimeouts[$Type]
        }

        # Export the functions
        Export-ModuleMember -Function Start-TestWithTimeout, Get-TestTimeout
    } | Import-Module
}

# Test Utilities for Windows Melody Recovery Testing
# General utility functions used across all test environments

function Get-WmrModulePath {
    <#
    .SYNOPSIS
        Gets the appropriate module path for the current environment.

    .DESCRIPTION
        Returns the correct module path based on the current environment:
        - Docker: Returns workspace path
        - Local: Returns actual module path
        - CI/CD: Returns appropriate path based on platform
    #>
    [CmdletBinding()]
    param()

    # Cache the result to avoid repeated environment detection
    if (-not $script:CachedModulePath) {
        # Check if we're in a Docker environment
        $isDockerEnvironment = ($env:DOCKER_TEST -eq 'true') -or ($env:CONTAINER -eq 'true') -or
                              (Test-Path '/.dockerenv' -ErrorAction SilentlyContinue)

        if ($isDockerEnvironment) {
            # Return current workspace path in Docker
            $script:CachedModulePath = "/workspace"
        } else {
            # Return Windows project root path
            $moduleRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
            $script:CachedModulePath = Join-Path $moduleRoot "WindowsMelodyRecovery.psm1"
        }
    }

    return $script:CachedModulePath
}

function Get-WmrTestPath {
    <#
    .SYNOPSIS
        Converts a Windows path to an appropriate test path for the current environment.

    .DESCRIPTION
        Converts Windows paths to test-safe paths based on the current environment:
        - Docker: Converts to Docker-compatible mock paths
        - Local: Converts to project temp directory paths
        - CI/CD: Converts to appropriate temp directory paths
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$WindowsPath
    )

    # Check if we're in a Docker environment
    $isDockerEnvironment = ($env:DOCKER_TEST -eq 'true') -or ($env:CONTAINER -eq 'true') -or
                          (Test-Path '/.dockerenv' -ErrorAction SilentlyContinue)

    if ($isDockerEnvironment) {
        # Use Docker path conversion (function available in Docker-Path-Mocks.ps1)
        if (Get-Command Convert-WmrPathForDocker -ErrorAction SilentlyContinue) {
            return Convert-WmrPathForDocker -Path $WindowsPath
        } else {
            Write-Warning "Convert-WmrPathForDocker not available in Docker environment"
            return $WindowsPath
        }
    } else {
        # For local/CI environments, use the ConvertTo-TestEnvironmentPath from PathUtilities
        # This function should be available from the main module
        if (Get-Command ConvertTo-TestEnvironmentPath -ErrorAction SilentlyContinue) {
            return ConvertTo-TestEnvironmentPath -Path $WindowsPath
        } else {
            # Fallback: return the original path if the function doesn't exist
            Write-Warning "ConvertTo-TestEnvironmentPath not available, using original path: $WindowsPath"
            return $WindowsPath
        }
    }
}

function Test-WmrTestEnvironment {
    <#
    .SYNOPSIS
        Checks if we're currently in a test environment.

    .DESCRIPTION
        Determines if the current execution context is a test environment
        based on various environment indicators.
    #>
    [CmdletBinding()]
    param()

    # Check for test environment indicators
    return ($env:WMR_TEST_MODE -eq 'true') -or
           ($env:DOCKER_TEST -eq 'true') -or
           ($env:PESTER_TEST -eq 'true') -or
           ((Test-Path variable:PSCommandPath -ErrorAction SilentlyContinue) -and
            ($PSCommandPath -like "*test*"))
}

function Get-WmrTestEnvironmentInfo {
    <#
    .SYNOPSIS
        Gets information about the current test environment.

    .DESCRIPTION
        Returns a hashtable with information about the current test environment
        including platform, environment type, and available features.
    #>
    [CmdletBinding()]
    param()

    $isDockerEnvironment = ($env:DOCKER_TEST -eq 'true') -or ($env:CONTAINER -eq 'true') -or
                          (Test-Path '/.dockerenv' -ErrorAction SilentlyContinue)
    $isCICDEnvironment = $env:CI -or $env:GITHUB_ACTIONS -or $env:BUILD_BUILDID -or $env:JENKINS_URL
    $isWindowsEnvironment = $IsWindows

    return @{
        IsDocker = $isDockerEnvironment
        IsWindows = $isWindowsEnvironment
        IsCICD = $isCICDEnvironment
        IsLocalDev = -not $isDockerEnvironment -and -not $isCICDEnvironment
        Platform = if ($isWindowsEnvironment) { 'Windows' } else { 'Linux' }
        EnvironmentType = if ($isDockerEnvironment) { 'Docker' } elseif ($isCICDEnvironment) { 'CI/CD' } else { 'Local' }
        TestMode = Test-WmrTestEnvironment
        ModulePath = Get-WmrModulePath
    }
}

# Functions are available via dot-sourcing - no Export-ModuleMember needed
