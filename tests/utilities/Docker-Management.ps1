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

    }
    catch {
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
                }
                else {
                    $containerStatus[$container] = "not_found"
                }
            }
            catch {
                $containerStatus[$container] = "error"
            }
        }

        return $containerStatus

    }
    catch {
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

function Start-TestContainer {
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

    Write-Warning -Message "🚀 Starting Docker test environment..."

    try {
        # Ensure Docker is available
        if (-not (Test-DockerAvailable)) {
            Write-Error "Docker is not available. Please ensure Docker Desktop is installed and running."
            return $false
        }

        # Clean up if requested
        if ($Clean) {
            Write-Information -MessageData "🧹 Cleaning up existing containers..." -InformationAction Continue
            Stop-TestContainers -Force
            Remove-TestContainers -Force
        }

        # Check if containers are already running
        if ((Test-ContainersRunning) -and -not $ForceRebuild -and -not $Clean) {
            Write-Information -MessageData "✓ All containers are already running" -InformationAction Continue
            return $true
        }

        # Build containers if needed
        if (-not $NoBuild) {
            Write-Information -MessageData "🔨 Building Docker images..." -InformationAction Continue

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
                    Write-Verbose -Message "Building $service..."
                    $serviceArgs = @("-f", $script:DockerComposeFile, "build")
                    if ($ForceRebuild) {
                        $serviceArgs += "--no-cache"
                    }
                    $serviceArgs += $service

                    docker compose $serviceArgs 2>&1 | Out-Null
                    if ($LASTEXITCODE -ne 0) {
                        $failedBuilds += $service
                        Write-Warning "Failed to build $service"
                    }
                    else {
                        Write-Information -MessageData "✓ $service built successfully" -InformationAction Continue
                    }
                }

                if ($failedBuilds.Count -gt 0) {
                    Write-Error "Failed to build services: $($failedBuilds -join ', ')"
                    return $false
                }
            }
            else {
                Write-Information -MessageData "✓ All Docker images built successfully" -InformationAction Continue
            }
        }

        # Start containers
        Write-Information -MessageData "🚀 Starting containers..." -InformationAction Continue
        $startResult = docker compose -f $script:DockerComposeFile up -d 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to start containers: $startResult"
            return $false
        }

        # Wait for containers to be ready
        Write-Information -MessageData "⏳ Waiting for containers to be ready..." -InformationAction Continue
        $maxWaitTime = 60 # seconds
        $waitInterval = 5 # seconds
        $elapsedTime = 0

        while ($elapsedTime -lt $maxWaitTime) {
            Start-Sleep -Seconds $waitInterval
            $elapsedTime += $waitInterval

            if (Test-ContainersRunning) {
                Write-Information -MessageData "✓ All containers are running" -InformationAction Continue
                break
            }

            Write-Warning -Message "⏳ Still waiting for containers... ($elapsedTime/$maxWaitTime seconds)"
        }

        # Final status check
        if (-not (Test-ContainersRunning)) {
            Write-Error "Failed to start all containers. Check logs for details."
            Get-ContainerStatus | Format-Table
            return $false
        }

        # Health checks for critical services
        Write-Information -MessageData "🩺 Performing health checks..." -InformationAction Continue
        if (-not (Test-AllContainersHealthy -TimeoutSeconds 120)) {
            Write-Error "One or more containers failed health checks. Please check container logs."
            return $false
        }

        Write-Information -MessageData "✅ Docker test environment started successfully!" -InformationAction Continue
        return $true

    }
    catch {
        Write-Error "An unexpected error occurred while starting containers: $($_.Exception.Message)"
        return $false
    }
}

function Stop-TestContainers {
    <#
    .SYNOPSIS
        Stops all running test containers
    .DESCRIPTION
        Stops all containers defined in docker-compose.test.yml without removing them
    .PARAMETER Force
        Force stop without confirmation
    .OUTPUTS
        Boolean indicating if containers stopped successfully
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([bool])]
    param(
        [switch]$Force
    )

    Write-Warning -Message "🛑 Stopping Docker test environment..."

    try {
        if ($Force -or $PSCmdlet.ShouldProcess("all test containers", "Stop")) {
            $stopResult = docker compose -f $script:DockerComposeFile stop 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Error "Failed to stop containers: $stopResult"
                return $false
            }
            Write-Information -MessageData "✓ All test containers stopped" -InformationAction Continue
        }
        return $true

    }
    catch {
        Write-Error "An unexpected error occurred while stopping containers: $($_.Exception.Message)"
        return $false
    }
}

function Remove-TestContainers {
    <#
    .SYNOPSIS
        Removes all test containers and associated volumes
    .DESCRIPTION
        Stops and removes all containers, networks, and volumes defined in docker-compose.test.yml
    .PARAMETER Force
        Force removal without confirmation
    .OUTPUTS
        Boolean indicating if cleanup was successful
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([bool])]
    param(
        [switch]$Force
    )

    Write-Warning -Message "🗑️ Removing Docker test environment..."

    try {
        if ($Force -or $PSCmdlet.ShouldProcess("all test containers and volumes", "Remove")) {
            $downResult = docker compose -f $script:DockerComposeFile down --volumes --remove-orphans 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Error "Failed to remove containers: $downResult"
                return $false
            }
            Write-Information -MessageData "✓ Docker test environment removed successfully" -InformationAction Continue
        }
        return $true

    }
    catch {
        Write-Error "An unexpected error occurred while removing containers: $($_.Exception.Message)"
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
        }
        else {
            Write-Warning "Container connectivity test failed: $testResult"
            return $false
        }

    }
    catch {
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
        }
        else {
            Write-Warning "Cloud mock server returned unhealthy status: $($healthResponse.status)"
            return $false
        }

    }
    catch {
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

    Write-Information -MessageData "`n📊 Container Status:" -InformationAction Continue

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

    Write-Information -MessageData "" -InformationAction Continue
}

function Show-ContainerLog {
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

    Write-Information -MessageData "📝 Container Logs:" -InformationAction Continue

    foreach ($container in $script:ExpectedContainers) {
        Write-Warning -Message "`n--- $container logs (last $Lines lines) ---"
        docker logs $container --tail $Lines 2>&1 | ForEach-Object {
            Write-Verbose -Message "  $_"
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

    Write-Information -MessageData "🏗️ Initializing Docker test environment..." -InformationAction Continue

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

    Write-Information -MessageData "✅ Docker test environment initialized successfully!" -InformationAction Continue
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

    Write-Information -MessageData "🔄 Resetting Docker test environment..." -InformationAction Continue

    # Stop containers
    Stop-TestContainers -Force

    # Remove containers and volumes
    Remove-TestContainers -Force

    # Start fresh
    return Initialize-DockerEnvironment -Clean
}

function Get-ContainerLog {
    <#
    .SYNOPSIS
        Gets the logs for a specific container
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [string]$ContainerName,
        [int]$TailLines = 100
    )

    if ($ContainerName -notin $script:ExpectedContainers) {
        Write-Warning "Container '$ContainerName' is not part of the expected test environment."
        return $null
    }

    try {
        $logs = docker logs $ContainerName --tail $TailLines 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Could not retrieve logs for container: $ContainerName"
            return $null
        }
        return $logs
    }
    catch {
        Write-Warning "Unable to retrieve logs for container: $ContainerName. Error: $($_.Exception.Message)"
        return $null
    }
}

function Test-ContainerHealth {
    <#
    .SYNOPSIS
        Checks the health of a single container by inspecting its state.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [string]$ContainerName,
        [int]$TimeoutSeconds = 30
    )

    $startTime = Get-Date
    $healthy = $false

    while ((Get-Date) -lt ($startTime.AddSeconds($TimeoutSeconds))) {
        try {
            $status = docker inspect --format='{{.State.Status}}' $ContainerName 2>$null
            if ($LASTEXITCODE -eq 0 -and $status -eq "running") {
                # For more specific health, check .State.Health.Status if available
                $healthStatus = docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{end}}' $ContainerName 2>$null
                if ($healthStatus -eq "healthy") {
                    $healthy = $true
                    break
                }
                elseif ($healthStatus -eq "") { # No health check defined
                    $healthy = $true
                    break
                }
            }
        }
        catch {
            # Container not found or other error
        }
        Start-Sleep -Seconds 2
    }

    return $healthy
}

function Test-AllContainersHealthy {
    <#
    .SYNOPSIS
        Checks if all expected containers are healthy.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [int]$TimeoutSeconds = 60
    )

    Write-Information -MessageData "🩺 Checking health of all test containers..." -InformationAction Continue
    $healthyCount = 0
    $unhealthyList = @()

    foreach ($container in $script:ExpectedContainers) {
        if (Test-ContainerHealth -ContainerName $container -TimeoutSeconds $TimeoutSeconds) {
            $healthyCount++
            Write-Verbose "✓ $container is healthy"
        }
        else {
            $unhealthyList += $container
            Write-Warning "✗ $container is not healthy"
        }
    }

    if ($unhealthyList.Count -gt 0) {
        Write-Warning "The following containers are not healthy: $($unhealthyList -join ', ')"
    }

    return $healthyCount -eq $script:ExpectedContainers.Count
}

# Add plural function aliases for compatibility
Set-Alias -Name "Start-TestContainers" -Value "Start-TestContainer"
Set-Alias -Name "Stop-TestContainers" -Value "Stop-TestContainer"
Set-Alias -Name "Remove-TestContainers" -Value "Remove-TestContainer"

# Export functions (only when loaded as a module)
if ($MyInvocation.MyCommand.CommandType -eq 'ExternalScript') {
    # Functions are automatically available when dot-sourced
}
else {
    Export-ModuleMember -Function @(
        'Test-DockerAvailable',
        'Get-ContainerStatus',
        'Test-ContainersRunning',
        'Start-TestContainer',
        'Start-TestContainers',
        'Stop-TestContainer',
        'Stop-TestContainers',
        'Remove-TestContainer',
        'Remove-TestContainers',
        'Test-ContainerConnectivity',
        'Test-CloudMockHealth',
        'Show-ContainerStatus',
        'Show-ContainerLogs',
        'Initialize-DockerEnvironment',
        'Reset-DockerEnvironment',
        'Get-ContainerLog',
        'Test-AllContainersHealthy',
        'Test-ContainerHealth'
    )
}







