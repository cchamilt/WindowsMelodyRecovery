#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Docker Container Management Utilities for Windows Melody Recovery Tests

.DESCRIPTION
    Provides centralized Docker container management functions for all test scripts.
    Handles container lifecycle including checking status, starting, stopping, and cleanup.

.NOTES
    This utility ensures consistent Docker container management across all test scripts.
    It provides safety checks and proper error handling for container operations.
#>

# Global variables for container management
$script:DockerComposeFile = "docker-compose.test.yml"
$script:ExpectedContainers = @(
    "wmr-windows-mock",
    "wmr-wsl-mock",
    "wmr-cloud-mock",
    "wmr-test-runner",
    "wmr-gaming-mock",
    "wmr-package-mock"
)

function Test-DockerAvailable {
    <#
    .SYNOPSIS
        Tests if Docker is available and running
    .DESCRIPTION
        Checks if Docker daemon is running and Docker Compose is available
    .OUTPUTS
        Boolean indicating if Docker is ready for use
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    try {
        # Test Docker daemon
        $dockerVersion = docker --version 2>$null
        if (-not $dockerVersion) {
            Write-Warning "Docker is not available or not running"
            return $false
        }

        # Test Docker Compose
        $composeVersion = docker compose version 2>$null
        if (-not $composeVersion) {
            Write-Warning "Docker Compose is not available"
            return $false
        }

        Write-Verbose "Docker is available: $dockerVersion"
        Write-Verbose "Docker Compose is available: $composeVersion"
        return $true

    } catch {
        Write-Warning "Failed to check Docker availability: $($_.Exception.Message)"
        return $false
    }
}

function Get-ContainerStatus {
    <#
    .SYNOPSIS
        Gets the status of all expected test containers
    .DESCRIPTION
        Checks the current status of all containers defined in docker-compose.test.yml
    .OUTPUTS
        Hashtable with container names as keys and status as values
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    $containerStatus = @{}

    try {
        foreach ($container in $script:ExpectedContainers) {
            try {
                $status = docker inspect --format='{{.State.Status}}' $container 2>$null
                if ($LASTEXITCODE -eq 0) {
                    $containerStatus[$container] = $status
                } else {
                    $containerStatus[$container] = "not_found"
                }
            } catch {
                $containerStatus[$container] = "error"
            }
        }

        return $containerStatus

    } catch {
        Write-Warning "Failed to get container status: $($_.Exception.Message)"
        return @{}
    }
}

function Test-ContainersRunning {
    <#
    .SYNOPSIS
        Tests if all expected containers are running
    .DESCRIPTION
        Checks if all containers required for testing are in 'running' state
    .OUTPUTS
        Boolean indicating if all containers are running
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    $containerStatus = Get-ContainerStatus

    foreach ($container in $script:ExpectedContainers) {
        if ($containerStatus[$container] -ne "running") {
            Write-Verbose "Container $container is not running (status: $($containerStatus[$container]))"
            return $false
        }
    }

    Write-Verbose "All expected containers are running"
    return $true
}

function Start-TestContainers {
    <#
    .SYNOPSIS
        Starts all test containers using Docker Compose
    .DESCRIPTION
        Builds and starts all containers defined in docker-compose.test.yml
        Includes health checks and startup validation
    .PARAMETER ForceRebuild
        Force rebuild of Docker images
    .PARAMETER NoBuild
        Skip building Docker images (assumes they already exist)
    .PARAMETER Clean
        Clean up existing containers and volumes before starting
    .OUTPUTS
        Boolean indicating if containers started successfully
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [switch]$ForceRebuild,
        [switch]$NoBuild,
        [switch]$Clean
    )

    Write-Host "🚀 Starting Docker test environment..." -ForegroundColor Yellow

    try {
        # Ensure Docker is available
        if (-not (Test-DockerAvailable)) {
            Write-Error "Docker is not available. Please ensure Docker Desktop is installed and running."
            return $false
        }

        # Clean up if requested
        if ($Clean) {
            Write-Host "🧹 Cleaning up existing containers..." -ForegroundColor Cyan
            Stop-TestContainers -Force
            Remove-TestContainers -Force
        }

        # Check if containers are already running
        if ((Test-ContainersRunning) -and -not $ForceRebuild -and -not $Clean) {
            Write-Host "✓ All containers are already running" -ForegroundColor Green
            return $true
        }

        # Build containers if needed
        if (-not $NoBuild) {
            Write-Host "🔨 Building Docker images..." -ForegroundColor Cyan

            $buildArgs = @("-f", $script:DockerComposeFile, "build")
            if ($ForceRebuild) {
                $buildArgs += "--no-cache"
            }
            $buildArgs += "--parallel"

            $buildResult = docker compose $buildArgs 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Warning "Docker compose build failed, trying individual service builds..."

                # Try building individual services
                $services = @("windows-mock", "wsl-mock", "cloud-mock", "test-runner", "gaming-mock", "package-mock")
                $failedBuilds = @()

                foreach ($service in $services) {
                    Write-Host "Building $service..." -ForegroundColor Gray
                    $serviceArgs = @("-f", $script:DockerComposeFile, "build")
                    if ($ForceRebuild) {
                        $serviceArgs += "--no-cache"
                    }
                    $serviceArgs += $service

                    docker compose $serviceArgs 2>&1 | Out-Null
                    if ($LASTEXITCODE -ne 0) {
                        $failedBuilds += $service
                        Write-Warning "Failed to build $service"
                    } else {
                        Write-Host "✓ $service built successfully" -ForegroundColor Green
                    }
                }

                if ($failedBuilds.Count -gt 0) {
                    Write-Error "Failed to build services: $($failedBuilds -join ', ')"
                    return $false
                }
            } else {
                Write-Host "✓ All Docker images built successfully" -ForegroundColor Green
            }
        }

        # Start containers
        Write-Host "🚀 Starting containers..." -ForegroundColor Cyan
        $startResult = docker compose -f $script:DockerComposeFile up -d 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to start containers: $startResult"
            return $false
        }

        # Wait for containers to be ready
        Write-Host "⏳ Waiting for containers to be ready..." -ForegroundColor Cyan
        $maxWaitTime = 60 # seconds
        $waitInterval = 5 # seconds
        $elapsedTime = 0

        while ($elapsedTime -lt $maxWaitTime) {
            Start-Sleep -Seconds $waitInterval
            $elapsedTime += $waitInterval

            if (Test-ContainersRunning) {
                Write-Host "✓ All containers are running" -ForegroundColor Green
                break
            }

            Write-Host "⏳ Still waiting for containers... ($elapsedTime/$maxWaitTime seconds)" -ForegroundColor Yellow
        }

        # Final status check
        if (-not (Test-ContainersRunning)) {
            Write-Warning "Some containers failed to start properly"
            Show-ContainerStatus
            return $false
        }

        # Test container connectivity
        Write-Host "🔍 Testing container connectivity..." -ForegroundColor Cyan
        if (Test-ContainerConnectivity) {
            Write-Host "✓ Container connectivity verified" -ForegroundColor Green
        } else {
            Write-Warning "Container connectivity test failed"
            return $false
        }

        # Test cloud mock health (optional)
        if (Test-CloudMockHealth) {
            Write-Host "✓ Cloud mock server is healthy" -ForegroundColor Green
        } else {
            Write-Host "⚠ Cloud mock server health check failed (continuing anyway)" -ForegroundColor Yellow
        }

        Write-Host "🎉 Docker test environment is ready!" -ForegroundColor Green
        return $true

    } catch {
        Write-Error "Failed to start test containers: $($_.Exception.Message)"
        return $false
    }
}

function Stop-TestContainers {
    <#
    .SYNOPSIS
        Stops all test containers
    .DESCRIPTION
        Gracefully stops all containers using Docker Compose
    .PARAMETER Force
        Force stop containers without graceful shutdown
    .OUTPUTS
        Boolean indicating if containers stopped successfully
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [switch]$Force
    )

    Write-Host "🛑 Stopping test containers..." -ForegroundColor Yellow

    try {
        if ($Force) {
            docker compose -f $script:DockerComposeFile kill 2>&1 | Out-Null
        } else {
            docker compose -f $script:DockerComposeFile stop 2>&1 | Out-Null
        }

        if ($LASTEXITCODE -eq 0) {
            Write-Host "✓ Containers stopped successfully" -ForegroundColor Green
            return $true
        } else {
            Write-Warning "Failed to stop some containers"
            return $false
        }

    } catch {
        Write-Error "Failed to stop containers: $($_.Exception.Message)"
        return $false
    }
}

function Remove-TestContainers {
    <#
    .SYNOPSIS
        Removes all test containers and volumes
    .DESCRIPTION
        Removes containers, networks, and volumes created by Docker Compose
    .PARAMETER Force
        Force removal without confirmation
    .OUTPUTS
        Boolean indicating if cleanup was successful
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [switch]$Force
    )

    Write-Host "🗑️ Removing test containers and volumes..." -ForegroundColor Yellow

    try {
        $removeArgs = @("-f", $script:DockerComposeFile, "down", "--volumes", "--remove-orphans")
        if ($Force) {
            $removeArgs += "--rmi", "local"
        }

        docker compose $removeArgs 2>&1 | Out-Null

        if ($LASTEXITCODE -eq 0) {
            Write-Host "✓ Containers and volumes removed successfully" -ForegroundColor Green
            return $true
        } else {
            Write-Warning "Failed to remove some containers or volumes"
            return $false
        }

    } catch {
        Write-Error "Failed to remove containers: $($_.Exception.Message)"
        return $false
    }
}

function Test-ContainerConnectivity {
    <#
    .SYNOPSIS
        Tests connectivity to the test runner container
    .DESCRIPTION
        Verifies that the test runner container is accessible and responsive
    .OUTPUTS
        Boolean indicating if connectivity test passed
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    try {
        $testResult = docker exec wmr-test-runner pwsh -Command "Write-Host 'Container connectivity test passed'; exit 0" 2>&1
        if ($LASTEXITCODE -eq 0) {
            return $true
        } else {
            Write-Warning "Container connectivity test failed: $testResult"
            return $false
        }

    } catch {
        Write-Warning "Container connectivity test failed: $($_.Exception.Message)"
        return $false
    }
}

function Test-CloudMockHealth {
    <#
    .SYNOPSIS
        Tests the health of the cloud mock server
    .DESCRIPTION
        Checks if the cloud mock server is responding to health checks
    .OUTPUTS
        Boolean indicating if cloud mock is healthy
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    try {
        $healthResponse = Invoke-RestMethod -Uri "http://localhost:3000/health" -TimeoutSec 10 -ErrorAction Stop
        if ($healthResponse.status -eq "healthy") {
            return $true
        } else {
            Write-Warning "Cloud mock server returned unhealthy status: $($healthResponse.status)"
            return $false
        }

    } catch {
        Write-Warning "Cloud mock server health check failed: $($_.Exception.Message)"
        return $false
    }
}

function Show-ContainerStatus {
    <#
    .SYNOPSIS
        Displays the current status of all test containers
    .DESCRIPTION
        Shows a formatted table of container statuses for debugging
    #>
    [CmdletBinding()]
    param()

    Write-Host "`n📊 Container Status:" -ForegroundColor Cyan

    $containerStatus = Get-ContainerStatus

    foreach ($container in $script:ExpectedContainers) {
        $status = $containerStatus[$container]
        $color = switch ($status) {
            "running" { "Green" }
            "exited" { "Yellow" }
            "not_found" { "Red" }
            "error" { "Red" }
            default { "Gray" }
        }

        Write-Host "  $container : $status" -ForegroundColor $color
    }

    Write-Host ""
}

function Show-ContainerLogs {
    <#
    .SYNOPSIS
        Shows recent logs from all test containers
    .DESCRIPTION
        Displays the last 20 lines of logs from each container for debugging
    .PARAMETER Lines
        Number of log lines to show (default: 20)
    #>
    [CmdletBinding()]
    param(
        [int]$Lines = 20
    )

    Write-Host "📝 Container Logs:" -ForegroundColor Cyan

    foreach ($container in $script:ExpectedContainers) {
        Write-Host "`n--- $container logs (last $Lines lines) ---" -ForegroundColor Yellow
        docker logs $container --tail $Lines 2>&1 | ForEach-Object {
            Write-Host "  $_" -ForegroundColor Gray
        }
    }
}

function Initialize-DockerEnvironment {
    <#
    .SYNOPSIS
        Initializes the Docker environment for testing
    .DESCRIPTION
        Comprehensive initialization that ensures Docker is ready and containers are started
    .PARAMETER ForceRebuild
        Force rebuild of Docker images
    .PARAMETER Clean
        Clean up existing containers before starting
    .OUTPUTS
        Boolean indicating if initialization was successful
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [switch]$ForceRebuild,
        [switch]$Clean
    )

    Write-Host "🏗️ Initializing Docker test environment..." -ForegroundColor Cyan

    # Check Docker availability
    if (-not (Test-DockerAvailable)) {
        Write-Error "Docker is not available. Please install Docker Desktop and ensure it's running."
        return $false
    }

    # Start containers
    $startResult = Start-TestContainers -ForceRebuild:$ForceRebuild -Clean:$Clean
    if (-not $startResult) {
        Write-Error "Failed to start Docker containers"
        Show-ContainerStatus
        return $false
    }

    # Show final status
    Show-ContainerStatus

    Write-Host "✅ Docker test environment initialized successfully!" -ForegroundColor Green
    return $true
}

function Reset-DockerEnvironment {
    <#
    .SYNOPSIS
        Resets the Docker environment by stopping and restarting all containers
    .DESCRIPTION
        Performs a complete reset of the Docker test environment
    .OUTPUTS
        Boolean indicating if reset was successful
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    Write-Host "🔄 Resetting Docker test environment..." -ForegroundColor Cyan

    # Stop containers
    Stop-TestContainers -Force

    # Remove containers and volumes
    Remove-TestContainers -Force

    # Start fresh
    return Initialize-DockerEnvironment -Clean
}

# Export functions (only when loaded as a module)
if ($MyInvocation.MyCommand.CommandType -eq 'ExternalScript') {
    # Functions are automatically available when dot-sourced
} else {
    Export-ModuleMember -Function @(
        'Test-DockerAvailable',
        'Get-ContainerStatus',
        'Test-ContainersRunning',
        'Start-TestContainers',
        'Stop-TestContainers',
        'Remove-TestContainers',
        'Test-ContainerConnectivity',
        'Test-CloudMockHealth',
        'Show-ContainerStatus',
        'Show-ContainerLogs',
        'Initialize-DockerEnvironment',
        'Reset-DockerEnvironment'
    )
}