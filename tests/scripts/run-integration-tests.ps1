#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Run Integration Tests for Windows Melody Recovery

.DESCRIPTION
    Runs integration tests using either Docker containers or native Windows environment.
    Automatically detects environment and skips Windows-only tests when running in Docker.
    Uses the same environment setup as the successful unit and file-operations tests.

.PARAMETER TestName
    Specific test file to run (without .Tests.ps1 extension). If not specified, runs all integration tests.

.PARAMETER OutputFormat
    Pester output format. Default is 'Detailed'.

.PARAMETER UseDocker
    Force use of Docker environment. If not specified, auto-detects based on environment.

.PARAMETER SkipCleanup
    Skip cleanup after tests (useful for debugging).

.PARAMETER GenerateReport
    Generate detailed test reports.

.EXAMPLE
    .\run-integration-tests.ps1
    .\run-integration-tests.ps1 -TestName "cloud-provider-detection"
    .\run-integration-tests.ps1 -UseDocker
    .\run-integration-tests.ps1 -OutputFormat "Normal"
#>

[CmdletBinding()]
param(
    [string]$TestName,
    [ValidateSet('None', 'Normal', 'Detailed', 'Diagnostic')]
    [string]$OutputFormat = 'Detailed',
    [switch]$UseDocker,
    [switch]$SkipCleanup,
    [switch]$GenerateReport
)

# Set execution policy for current process
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

# Determine environment
$isDockerAvailable = $UseDocker -or (Get-Command docker -ErrorAction SilentlyContinue)
$runInDocker = $UseDocker -or ($isDockerAvailable -and -not $IsWindows)

if ($runInDocker) {
    Write-Information -MessageData "🐳 Running integration tests in Docker environment..." -InformationAction Continue
    Write-Warning -Message "   Windows-only tests will be skipped automatically"

    # Use Docker-based execution
    $dockerUtilsPath = Join-Path $PSScriptRoot ".." "utilities" "Docker-Management.ps1"
    if (Test-Path $dockerUtilsPath) {
        . $dockerUtilsPath

        # Initialize Docker environment
        $startResult = Initialize-DockerEnvironment
        if (-not $startResult) {
            Write-Error -Message "✗ Failed to initialize Docker environment"
            exit 1
        }

        # Build test command
        $testCommand = "cd /workspace && . tests/utilities/Test-Environment.ps1 && Import-Module ./WindowsMelodyRecovery.psd1 -Force && "
        if ($TestName) {
            $testCommand += "Invoke-Pester -Path './tests/integration/$TestName.Tests.ps1' -Passthru"
        }
        else {
            $testCommand += "Invoke-Pester -Path './tests/integration/' -Passthru"
        }
        # Note: OutputFormat is deprecated in Pester v5, using -Passthru for result object

        # Execute tests in Docker
        Write-Information -MessageData "Executing integration tests..." -InformationAction Continue
        $result = docker exec wmr-test-runner pwsh -Command $testCommand
        $exitCode = $LASTEXITCODE

        # Display the result properly
        Write-Host $result

        # Parse test results if available
        if ($result -match "Tests Passed: (\d+), Failed: (\d+)") {
            $passedCount = $matches[1]
            $failedCount = $matches[2]
            Write-Information -MessageData "`n=== Docker Integration Test Results ===" -InformationAction Continue
            Write-Information -MessageData "Tests Passed: $passedCount" -InformationAction Continue
            Write-Information -MessageData "Tests Failed: $failedCount" -InformationAction Continue
            $exitCode = [int]$failedCount -gt 0 ? 1 : 0
        }

        if (-not $SkipCleanup) {
            Stop-TestContainer
        }

        exit $exitCode
    }
    else {
        Write-Error -Message "✗ Docker management utilities not found"
        exit 1
    }
}
else {
    Write-Information -MessageData "🪟 Running integration tests in native Windows environment..." -InformationAction Continue
    Write-Warning -Message "   All tests including Windows-only will be executed"

    # Use native Windows execution
    try {
        # Import test environment
        $testEnvPath = Join-Path $PSScriptRoot ".." "utilities" "Test-Environment.ps1"
        if (Test-Path $testEnvPath) {
            . $testEnvPath
        }
        else {
            Write-Error -Message "✗ Test environment not found at: $testEnvPath"
            exit 1
        }

        # Initialize test environment
        Initialize-TestEnvironment

        # Import the module
        $moduleRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $modulePath = Join-Path $moduleRoot "WindowsMelodyRecovery.psd1"
        Import-Module $modulePath -Force

        # Run tests
        Write-Information -MessageData "Executing integration tests..." -InformationAction Continue

        $pesterConfig = @{
            Run    = @{
                Path = if ($TestName) {
                    Join-Path $PSScriptRoot ".." "integration" "$TestName.Tests.ps1"
                }
                else {
                    Join-Path $PSScriptRoot ".." "integration"
                }
            }
            Output = @{
                Verbosity = $OutputFormat
            }
        }

        if ($GenerateReport) {
            $pesterConfig.TestResult = @{
                Enabled    = $true
                OutputPath = Join-Path $moduleRoot "test-results" "integration-test-results.xml"
            }
        }

        $result = Invoke-Pester -Configuration $pesterConfig

        # Cleanup
        if (-not $SkipCleanup) {
            Remove-TestEnvironment
        }

        # Report results
        Write-Information -MessageData ""  -InformationAction Continue
        Write-Information -MessageData "=== Integration Test Results ===" -InformationAction Continue
        Write-Information -MessageData "Tests Passed: $($result.PassedCount)" -InformationAction Continue
        Write-Error -Message "Tests Failed: $($result.FailedCount)"
        Write-Warning -Message "Tests Skipped: $($result.SkippedCount)"
        Write-Information -MessageData "Total Tests: $($result.TotalCount)"  -InformationAction Continue

        if ($result.FailedCount -gt 0) {
            Write-Error -Message "✗ Some integration tests failed"
            exit 1
        }
        else {
            Write-Information -MessageData "✓ All integration tests passed!" -InformationAction Continue
            exit 0
        }

    }
    catch {
        Write-Error -Message "✗ Error running integration tests: $($_.Exception.Message)"
        exit 1
    }
}

# Model: claude-3-5-sonnet-20241022
# Confidence: 85%








