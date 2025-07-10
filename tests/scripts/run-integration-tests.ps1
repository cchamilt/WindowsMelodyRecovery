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
    Write-Host "🐳 Running integration tests in Docker environment..." -ForegroundColor Cyan
    Write-Host "   Windows-only tests will be skipped automatically" -ForegroundColor Yellow
    
    # Use Docker-based execution
    $dockerUtilsPath = Join-Path $PSScriptRoot ".." "utilities" "Docker-Management.ps1"
    if (Test-Path $dockerUtilsPath) {
        . $dockerUtilsPath
        
        # Initialize Docker environment
        $startResult = Initialize-DockerEnvironment
        if (-not $startResult) {
            Write-Host "✗ Failed to initialize Docker environment" -ForegroundColor Red
            exit 1
        }
        
        # Build test command
        $testCommand = "cd /workspace && . tests/utilities/Test-Environment.ps1 && "
        if ($TestName) {
            $testCommand += "Invoke-Pester -Path './tests/integration/$TestName.Tests.ps1'"
        } else {
            $testCommand += "Invoke-Pester -Path './tests/integration/'"
        }
        $testCommand += " -OutputFormat $OutputFormat"
        
        # Execute tests in Docker
        Write-Host "Executing integration tests..." -ForegroundColor Cyan
        docker exec wmr-test-runner pwsh -Command $testCommand
        $exitCode = $LASTEXITCODE
        
        if (-not $SkipCleanup) {
            Stop-DockerEnvironment
        }
        
        exit $exitCode
    } else {
        Write-Host "✗ Docker management utilities not found" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "🪟 Running integration tests in native Windows environment..." -ForegroundColor Cyan
    Write-Host "   All tests including Windows-only will be executed" -ForegroundColor Yellow
    
    # Use native Windows execution
    try {
        # Import test environment
        $testEnvPath = Join-Path $PSScriptRoot ".." "utilities" "Test-Environment.ps1"
        if (Test-Path $testEnvPath) {
            . $testEnvPath
        } else {
            Write-Host "✗ Test environment not found at: $testEnvPath" -ForegroundColor Red
            exit 1
        }
        
        # Initialize test environment
        Initialize-TestEnvironment
        
        # Import the module
        $moduleRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $modulePath = Join-Path $moduleRoot "WindowsMelodyRecovery.psd1"
        Import-Module $modulePath -Force
        
        # Run tests
        Write-Host "Executing integration tests..." -ForegroundColor Cyan
        
        $pesterConfig = @{
            Run = @{
                Path = if ($TestName) {
                    Join-Path $PSScriptRoot ".." "integration" "$TestName.Tests.ps1"
                } else {
                    Join-Path $PSScriptRoot ".." "integration"
                }
            }
            Output = @{
                Verbosity = $OutputFormat
            }
        }
        
        if ($GenerateReport) {
            $pesterConfig.TestResult = @{
                Enabled = $true
                OutputPath = Join-Path $moduleRoot "test-results" "integration-test-results.xml"
            }
        }
        
        $result = Invoke-Pester -Configuration $pesterConfig
        
        # Cleanup
        if (-not $SkipCleanup) {
            Remove-TestEnvironment
        }
        
        # Report results
        Write-Host "" -ForegroundColor White
        Write-Host "=== Integration Test Results ===" -ForegroundColor Cyan
        Write-Host "Tests Passed: $($result.PassedCount)" -ForegroundColor Green
        Write-Host "Tests Failed: $($result.FailedCount)" -ForegroundColor Red
        Write-Host "Tests Skipped: $($result.SkippedCount)" -ForegroundColor Yellow
        Write-Host "Total Tests: $($result.TotalCount)" -ForegroundColor White
        
        if ($result.FailedCount -gt 0) {
            Write-Host "✗ Some integration tests failed" -ForegroundColor Red
            exit 1
        } else {
            Write-Host "✓ All integration tests passed!" -ForegroundColor Green
            exit 0
        }
        
    } catch {
        Write-Host "✗ Error running integration tests: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

# Model: claude-3-5-sonnet-20241022
# Confidence: 85% 
