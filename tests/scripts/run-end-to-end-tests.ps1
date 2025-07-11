#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Run End-to-End Tests for Windows Melody Recovery

.DESCRIPTION
    Runs end-to-end tests using either Docker containers or native Windows environment.
    Automatically detects environment and skips Windows-only tests when running in Docker.
    Uses the same environment setup as the successful unit and file-operations tests.

.PARAMETER TestName
    Specific test file to run (without .Tests.ps1 extension). If not specified, runs all end-to-end tests.

.PARAMETER OutputFormat
    Pester output format. Default is 'Detailed'.

.PARAMETER UseDocker
    Force use of Docker environment. If not specified, auto-detects based on environment.

.PARAMETER SkipCleanup
    Skip cleanup after tests (useful for debugging).

.PARAMETER Timeout
    Timeout in minutes for end-to-end tests. Default is 15 minutes.

.PARAMETER GenerateReport
    Generate detailed test reports.

.EXAMPLE
    .\run-end-to-end-tests.ps1
    .\run-end-to-end-tests.ps1 -TestName "User-Journey-Tests"
    .\run-end-to-end-tests.ps1 -UseDocker
    .\run-end-to-end-tests.ps1 -Timeout 30
#>

[CmdletBinding()]
param(
    [string]$TestName,
    [ValidateSet('None', 'Normal', 'Detailed', 'Diagnostic')]
    [string]$OutputFormat = 'Detailed',
    [switch]$UseDocker,
    [switch]$SkipCleanup,
    [int]$Timeout = 15,
    [switch]$GenerateReport
)

# Set execution policy for current process
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

# Determine environment
$isDockerAvailable = $UseDocker -or (Get-Command docker -ErrorAction SilentlyContinue)
$runInDocker = $UseDocker -or ($isDockerAvailable -and -not $IsWindows)

if ($runInDocker) {
    Write-Information -MessageData "🐳 Running end-to-end tests in Docker environment..." -InformationAction Continue
    Write-Warning -Message "   Windows-only tests will be skipped automatically"
    Write-Verbose -Message "   Timeout: $Timeout minutes"

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

        # Build test command with timeout
        $testCommand = "cd /workspace && . tests/utilities/Test-Environment.ps1 && "
        if ($TestName) {
            $testCommand += "Invoke-Pester -Path './tests/end-to-end/$TestName.Tests.ps1'"
        } else {
            $testCommand += "Invoke-Pester -Path './tests/end-to-end/'"
        }
        $testCommand += " -OutputFormat $OutputFormat"

        # Execute tests in Docker with timeout
        Write-Information -MessageData "Executing end-to-end tests..." -InformationAction Continue
        $timeoutSeconds = $Timeout * 60

        # Use PowerShell job for timeout control
        $job = Start-Job -ScriptBlock {
            param($Command)
            docker exec wmr-test-runner pwsh -Command $Command
        } -ArgumentList $testCommand

        $completed = Wait-Job -Job $job -Timeout $timeoutSeconds

        if ($completed) {
            $result = Receive-Job -Job $job
            $exitCode = $job.State -eq 'Completed' ? 0 : 1
            Write-Information -MessageData $result -InformationAction Continue
        } else {
            Write-Error -Message "✗ End-to-end tests timed out after $Timeout minutes"
            Stop-Job -Job $job
            $exitCode = 1
        }

        Remove-Job -Job $job -Force

        if (-not $SkipCleanup) {
            Stop-DockerEnvironment
        }

        exit $exitCode
    } else {
        Write-Error -Message "✗ Docker management utilities not found"
        exit 1
    }
} else {
    Write-Information -MessageData "🪟 Running end-to-end tests in native Windows environment..." -InformationAction Continue
    Write-Warning -Message "   All tests including Windows-only will be executed"
    Write-Verbose -Message "   Timeout: $Timeout minutes"

    # Use native Windows execution
    try {
        # Import test environment
        $testEnvPath = Join-Path $PSScriptRoot ".." "utilities" "Test-Environment.ps1"
        if (Test-Path $testEnvPath) {
            . $testEnvPath
        } else {
            Write-Error -Message "✗ Test environment not found at: $testEnvPath"
            exit 1
        }

        # Initialize test environment
        Initialize-TestEnvironment

        # Import the module
        $moduleRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $modulePath = Join-Path $moduleRoot "WindowsMelodyRecovery.psd1"
        Import-Module $modulePath -Force

        # Run tests with timeout
        Write-Information -MessageData "Executing end-to-end tests..." -InformationAction Continue

        $pesterConfig = @{
            Run = @{
                Path = if ($TestName) {
                    Join-Path $PSScriptRoot ".." "end-to-end" "$TestName.Tests.ps1"
                } else {
                    Join-Path $PSScriptRoot ".." "end-to-end"
                }
            }
            Output = @{
                Verbosity = $OutputFormat
            }
        }

        if ($GenerateReport) {
            $pesterConfig.TestResult = @{
                Enabled = $true
                OutputPath = Join-Path $moduleRoot "test-results" "end-to-end-test-results.xml"
            }
        }

        # Execute with timeout using PowerShell job
        $job = Start-Job -ScriptBlock {
            param($Config)
            Invoke-Pester -Configuration $Config
        } -ArgumentList $pesterConfig

        $timeoutSeconds = $Timeout * 60
        $completed = Wait-Job -Job $job -Timeout $timeoutSeconds

        if ($completed) {
            $result = Receive-Job -Job $job
            $exitCode = $result.FailedCount -gt 0 ? 1 : 0

            # Report results
            Write-Information -MessageData ""  -InformationAction Continue
            Write-Information -MessageData "=== End-to-End Test Results ===" -InformationAction Continue
            Write-Information -MessageData "Tests Passed: $($result.PassedCount)" -InformationAction Continue
            Write-Error -Message "Tests Failed: $($result.FailedCount)"
            Write-Warning -Message "Tests Skipped: $($result.SkippedCount)"
            Write-Information -MessageData "Total Tests: $($result.TotalCount)"  -InformationAction Continue

            if ($result.FailedCount -gt 0) {
                Write-Error -Message "✗ Some end-to-end tests failed"
            } else {
                Write-Information -MessageData "✓ All end-to-end tests passed!" -InformationAction Continue
            }
        } else {
            Write-Error -Message "✗ End-to-end tests timed out after $Timeout minutes"
            Stop-Job -Job $job
            $exitCode = 1
        }

        Remove-Job -Job $job -Force

        # Cleanup
        if (-not $SkipCleanup) {
            Remove-TestEnvironment
        }

        exit $exitCode

    } catch {
        Write-Error -Message "✗ Error running end-to-end tests: $($_.Exception.Message)"
        exit 1
    }
}

# Model: claude-3-5-sonnet-20241022
# Confidence: 85%

