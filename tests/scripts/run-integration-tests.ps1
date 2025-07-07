#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Run Windows Melody Recovery Integration Tests in Docker

.DESCRIPTION
    This script sets up and runs comprehensive integration tests for the Windows Melody Recovery module
    using Docker containers that simulate Windows, WSL, and cloud storage environments.

.PARAMETER TestSuite
    Which test suite to run (All, Installation, Initialization, Pester, Backup, Restore, WSL, Gaming, Cloud, Chezmoi, Setup)

.PARAMETER Clean
    Clean up existing containers and volumes before starting

.PARAMETER KeepContainers
    Keep containers running after tests complete for debugging

.PARAMETER GenerateReport
    Generate detailed HTML and JSON test reports

.PARAMETER Parallel
    Run tests in parallel where possible

.PARAMETER ForceRebuild
    Force rebuild of Docker images

.PARAMETER NoBuild
    Skip building Docker images (assumes they already exist)

.PARAMETER NoCleanup
    Skip cleanup of test artifacts and containers

.EXAMPLE
    ./run-integration-tests.ps1 -TestSuite All -GenerateReport

.EXAMPLE
    ./run-integration-tests.ps1 -TestSuite WSL -Clean -KeepContainers

.EXAMPLE
    ./run-integration-tests.ps1 -ForceRebuild -TestSuite All

.EXAMPLE
    ./run-integration-tests.ps1 -NoBuild -TestSuite Installation -KeepContainers
#>

param(
    [ValidateSet("All", "Installation", "Initialization", "Pester", "Backup", "Restore", "WSL", "Gaming", "Cloud", "Chezmoi", "Setup")]
    [string]$TestSuite = "All",
    
    [switch]$Clean,
    
    [switch]$KeepContainers,
    
    [switch]$GenerateReport,
    
    [switch]$Parallel,
    
    [switch]$ForceRebuild,
    
    [switch]$NoBuild,
    
    [string]$LogLevel = "Info",
    
    [switch]$NoCleanup
)

# Import Docker management utilities
. "$PSScriptRoot/../utilities/Docker-Management.ps1"

# Clean up existing containers and volumes
function Invoke-Cleanup {
    Write-Host "🧹 Cleaning up existing containers and volumes..." -ForegroundColor Yellow
    
    try {
        # Use centralized Docker management
        Stop-TestContainers -Force
        Remove-TestContainers -Force
        
        # Remove any dangling images
        $danglingImages = docker images -f "dangling=true" -q 2>$null
        if ($danglingImages) {
            docker rmi $danglingImages 2>$null
        }
        
        Write-Host "✓ Cleanup completed" -ForegroundColor Green
    } catch {
        Write-Host "⚠ Cleanup encountered some issues (this is usually normal)" -ForegroundColor Yellow
    }
}

# Build and start the test environment
function Start-TestEnvironment {
    Write-Host "🚀 Building and starting test environment..." -ForegroundColor Yellow
    
    try {
        # Use centralized Docker management to start containers
        $startResult = Start-TestContainers -ForceRebuild:$ForceRebuild -NoBuild:$NoBuild -Clean:$Clean
        if (-not $startResult) {
            throw "Failed to start test containers"
        }
        
        Write-Host "✓ Test environment started successfully" -ForegroundColor Green
        return
        
    } catch {
        Write-Host "✗ Failed to start test environment: $($_.Exception.Message)" -ForegroundColor Red
        throw
    }
}

# Run the integration tests
function Invoke-IntegrationTests {
    Write-Host "🧪 Running integration tests..." -ForegroundColor Yellow
    
    try {
        # Prepare test arguments
        $testArgs = @(
            "-TestSuite", $TestSuite,
            "-Environment", "Docker"
        )
        
        if ($GenerateReport) {
            $testArgs += "-GenerateReport"
        }
        
        if ($Parallel) {
            $testArgs += "-Parallel"
        }
        
        # Initialize test directories in container
        Write-Host "Initializing test environment..." -ForegroundColor Cyan
        docker exec wmr-test-runner pwsh -Command "
            New-Item -Path '/test-results/logs' -ItemType Directory -Force | Out-Null
            New-Item -Path '/test-results/reports' -ItemType Directory -Force | Out-Null
            New-Item -Path '/test-results/coverage' -ItemType Directory -Force | Out-Null
            New-Item -Path '/test-results/junit' -ItemType Directory -Force | Out-Null
            Write-Host '✓ Test directories created'
        "
        
        # Run tests in the test-runner container with proper Pester configuration
        Write-Host "Executing test suite: $TestSuite" -ForegroundColor Cyan
        
        # Use dedicated Pester test script for reliable execution
        Write-Host "Running dedicated Pester test script..." -ForegroundColor Cyan
        
        # Build arguments for the Pester script
        $pesterArgs = "-TestSuite $TestSuite"
        if ($GenerateReport) {
            $pesterArgs += " -GenerateReport"
        }
        
        # Execute the dedicated Pester script in container
        docker exec wmr-test-runner pwsh -Command "/workspace/tests/scripts/run-pester-tests.ps1 $pesterArgs"
        $testExitCode = $LASTEXITCODE
        
        # Generate additional reports if requested
        if ($GenerateReport) {
            Write-Host "📋 Generating additional reports..." -ForegroundColor Cyan
            docker exec wmr-test-runner pwsh /tests/generate-reports.ps1
        }
        
        if ($testExitCode -eq 0) {
            Write-Host "✓ All tests passed!" -ForegroundColor Green
        } else {
            Write-Host "✗ Some tests failed (exit code: $testExitCode)" -ForegroundColor Red
        }
        
        return $testExitCode
        
    } catch {
        Write-Host "✗ Test execution failed: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Copy test results from container
function Copy-TestResults {
    Write-Host "📋 Copying test results..." -ForegroundColor Yellow
    
    try {
        # Create local results directory
        $resultsDir = "./test-results"
        if (-not (Test-Path $resultsDir)) {
            New-Item -Path $resultsDir -ItemType Directory -Force | Out-Null
        }
        
        # Copy results from test-runner container
        docker cp wmr-test-runner:/test-results/. $resultsDir/
        
        Write-Host "✓ Test results copied to: $resultsDir" -ForegroundColor Green
        
        # List available reports
        $reports = Get-ChildItem -Path "$resultsDir/reports" -ErrorAction SilentlyContinue
        if ($reports) {
            Write-Host "📊 Available reports:" -ForegroundColor Cyan
            foreach ($report in $reports) {
                Write-Host "  - $($report.FullName)" -ForegroundColor White
            }
        }
        
    } catch {
        Write-Host "⚠ Failed to copy test results: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# Show container logs for debugging (use centralized utility)
function Show-TestContainerLogs {
    Show-ContainerLogs -Lines 20
}

# Cleanup function
function Stop-TestEnvironment {
    if (-not $KeepContainers) {
        Write-Host "🛑 Stopping test environment..." -ForegroundColor Yellow
        docker compose -f docker-compose.test.yml down --volumes 2>$null
        Write-Host "✓ Test environment stopped" -ForegroundColor Green
    } else {
        Write-Host "🔄 Keeping containers running for debugging" -ForegroundColor Yellow
        Write-Host "To stop manually: docker compose -f docker-compose.test.yml down --volumes" -ForegroundColor Cyan
        Write-Host "To view logs: docker compose -f docker-compose.test.yml logs -f" -ForegroundColor Cyan
    }
}

# Cleanup test artifacts function
function Clean-TestArtifacts {
    if ($NoCleanup) {
        Write-Host "🧹 Skipping cleanup due to -NoCleanup flag" -ForegroundColor Yellow
        return
    }
    
    Write-Host "🧹 Cleaning up test artifacts..." -ForegroundColor Yellow
    
    # Clean up test directories
    $testDirs = @("test-backups", "test-restore")
    foreach ($testDir in $testDirs) {
        if (Test-Path $testDir) {
            try {
                Remove-Item -Path $testDir -Recurse -Force
                Write-Host "✓ Removed test directory: $testDir" -ForegroundColor Green
            } catch {
                Write-Host "⚠ Failed to remove ${testDir}: $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }
    }
    
    # Note: Docker container cleanup is handled by Stop-TestEnvironment
    Write-Host "✓ Cleanup completed" -ForegroundColor Green
}

# Main execution
try {
    Write-Host "🧪 Windows Melody Recovery - Integration Test Runner" -ForegroundColor Magenta
    Write-Host "=" * 60 -ForegroundColor Magenta
    Write-Host ""
    
    # Prerequisites check - centralized Docker management handles both Docker and Compose
    if (-not (Test-DockerAvailable)) {
        exit 1
    }
    
    # Check if docker-compose.test.yml exists
    if (-not (Test-Path "docker-compose.test.yml")) {
        Write-Host "✗ docker-compose.test.yml not found in current directory" -ForegroundColor Red
        Write-Host "Please run this script from the root of the Windows Melody Recovery repository" -ForegroundColor Yellow
        exit 1
    }
    
    # Cleanup if requested
    if ($Clean) {
        Invoke-Cleanup
    }
    
    # Start test environment
    Start-TestEnvironment
    
    # Run tests
    $testResult = Invoke-IntegrationTests
    
    # Copy results
    Copy-TestResults
    
    # Show summary
    Write-Host "`n" + "=" * 60 -ForegroundColor Magenta
    if ($testResult -eq 0) {
        Write-Host "🎉 Integration tests completed successfully!" -ForegroundColor Green
    } else {
        Write-Host "❌ Integration tests failed" -ForegroundColor Red
        Show-TestContainerLogs
    }
    
    # Final cleanup
    Stop-TestEnvironment
    
    # Clean test artifacts
    Clean-TestArtifacts
    
    exit $testResult
    
} catch {
    Write-Host "💥 Integration test runner failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    
    Show-TestContainerLogs
    Stop-TestEnvironment
    
    # Clean test artifacts
    Clean-TestArtifacts
    
    exit 1
} 