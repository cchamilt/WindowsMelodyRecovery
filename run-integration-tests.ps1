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

# Check if Docker is available
function Test-DockerAvailable {
    try {
        $dockerVersion = docker --version 2>$null
        if ($dockerVersion) {
            Write-Host "✓ Docker is available: $dockerVersion" -ForegroundColor Green
            return $true
        }
    } catch {
        Write-Host "✗ Docker is not available or not running" -ForegroundColor Red
        Write-Host "Please install Docker Desktop and ensure it's running" -ForegroundColor Yellow
        return $false
    }
    return $false
}

# Check if Docker Compose is available
function Test-DockerComposeAvailable {
    try {
        $composeVersion = docker compose version 2>$null
        if ($composeVersion) {
            Write-Host "✓ Docker Compose is available: $composeVersion" -ForegroundColor Green
            return $true
        }
    } catch {
        Write-Host "✗ Docker Compose is not available" -ForegroundColor Red
        return $false
    }
    return $false
}

# Clean up existing containers and volumes
function Invoke-Cleanup {
    Write-Host "🧹 Cleaning up existing containers and volumes..." -ForegroundColor Yellow
    
    try {
        # Stop and remove containers
        docker compose -f docker-compose.test.yml down --volumes --remove-orphans 2>$null
        
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
        # Check if containers are already running
        $runningContainers = docker compose -f docker-compose.test.yml ps -q 2>$null
        if ($runningContainers -and -not $ForceRebuild) {
            Write-Host "✓ Containers are already running, skipping build" -ForegroundColor Green
            return
        }
        
        # Handle build options
        if ($NoBuild) {
            Write-Host "⏭ Skipping build due to -NoBuild flag" -ForegroundColor Yellow
        } else {
            # Use Docker Compose parallel building (faster and more reliable)
            Write-Host "Building Docker images with compose (parallel)..." -ForegroundColor Cyan
            
            $buildArgs = @("-f", "docker-compose.test.yml", "build")
            if ($ForceRebuild) {
                $buildArgs += "--no-cache"
            }
            if ($Parallel) {
                $buildArgs += "--parallel"
            }
            
            # Run the build command
            docker compose $buildArgs
            
            if ($LASTEXITCODE -ne 0) {
                Write-Host "✗ Docker compose build failed, trying individual builds..." -ForegroundColor Yellow
                
                # Fallback to individual builds
                $services = @("windows-mock", "wsl-mock", "mock-cloud-server", "test-runner", "gaming-mock", "package-mock")
                $buildResults = @{}
                $failedBuilds = @()
                
                foreach ($service in $services) {
                    Write-Host "Building $service..." -ForegroundColor Cyan
                    $serviceArgs = @("-f", "docker-compose.test.yml", "build")
                    if ($ForceRebuild) {
                        $serviceArgs += "--no-cache"
                    }
                    $serviceArgs += $service
                    
                    docker compose $serviceArgs 2>&1 | Tee-Object -FilePath "build-$service.log"
                    $buildResults[$service] = $LASTEXITCODE
                    
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host "✓ $service built successfully" -ForegroundColor Green
                    } else {
                        Write-Host "✗ $service build failed" -ForegroundColor Red
                        $failedBuilds += $service
                    }
                }
                
                # Report build results
                if ($failedBuilds.Count -gt 0) {
                    Write-Host "`n📋 Build Summary:" -ForegroundColor Yellow
                    Write-Host "Failed builds: $($failedBuilds -join ', ')" -ForegroundColor Red
                    
                    # Show build logs for failed services
                    Write-Host "`n📝 Build logs for failed services:" -ForegroundColor Yellow
                    foreach ($failedService in $failedBuilds) {
                        if (Test-Path "build-$failedService.log") {
                            Write-Host "`n--- $failedService build log ---" -ForegroundColor Cyan
                            Get-Content "build-$failedService.log" | Select-Object -Last 20
                        }
                    }
                    
                    throw "Some Docker images failed to build: $($failedBuilds -join ', ')"
                }
            } else {
                Write-Host "✓ All Docker images built successfully" -ForegroundColor Green
            }
        }
        
        # Start the containers
        Write-Host "`nStarting containers..." -ForegroundColor Cyan
        docker compose -f docker-compose.test.yml up -d
        
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to start containers"
        }
        
        # Wait for containers to be ready
        Write-Host "Waiting for containers to be ready..." -ForegroundColor Cyan
        Start-Sleep -Seconds 30
        
        # Check container health
        $containers = @("wmr-windows-mock", "wmr-wsl-mock", "wmr-cloud-mock", "wmr-test-runner")
        foreach ($container in $containers) {
            $status = docker inspect --format='{{.State.Status}}' $container 2>$null
            if ($status -eq "running") {
                Write-Host "✓ $container is running" -ForegroundColor Green
            } else {
                Write-Host "✗ $container is not running (status: $status)" -ForegroundColor Red
            }
        }
        
        # Test cloud server health
        try {
            Start-Sleep -Seconds 5
            $healthCheck = Invoke-RestMethod -Uri "http://localhost:8080/health" -TimeoutSec 10
            if ($healthCheck.status -eq "healthy") {
                Write-Host "✓ Cloud mock server is healthy" -ForegroundColor Green
            }
        } catch {
            Write-Host "⚠ Cloud mock server health check failed (may still be starting)" -ForegroundColor Yellow
        }
        
        Write-Host "✓ Test environment is ready" -ForegroundColor Green
        
        # Clean up build logs
        Get-ChildItem "build-*.log" -ErrorAction SilentlyContinue | Remove-Item -Force
        
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
        docker exec wmr-test-runner pwsh -Command "/workspace/run-pester-tests.ps1 $pesterArgs"
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

# Show container logs for debugging
function Show-ContainerLogs {
    Write-Host "📝 Container logs:" -ForegroundColor Yellow
    
    $containers = @("wmr-windows-mock", "wmr-wsl-mock", "wmr-cloud-mock", "wmr-test-runner")
    
    foreach ($container in $containers) {
        Write-Host "`n--- $container logs ---" -ForegroundColor Cyan
        docker logs $container --tail 20 2>$null
    }
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
    
    # Prerequisites check
    if (-not (Test-DockerAvailable)) {
        exit 1
    }
    
    if (-not (Test-DockerComposeAvailable)) {
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
        Show-ContainerLogs
    }
    
    # Final cleanup
    Stop-TestEnvironment
    
    # Clean test artifacts
    Clean-TestArtifacts
    
    exit $testResult
    
} catch {
    Write-Host "💥 Integration test runner failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    
    Show-ContainerLogs
    Stop-TestEnvironment
    
    # Clean test artifacts
    Clean-TestArtifacts
    
    exit 1
} 