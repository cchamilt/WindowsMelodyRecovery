#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Docker Utilities for Windows Melody Recovery Integration Tests

.DESCRIPTION
    Utility functions for Docker container management and health checks.
#>

# Docker container utilities
function Test-ContainerHealth {
    param(
        [string]$ContainerName,
        [int]$TimeoutSeconds = 30
    )

    $startTime = Get-Date
    $healthy = $false

    while ((Get-Date) -lt ($startTime.AddSeconds($TimeoutSeconds))) {
        try {
            $status = docker inspect --format='{{.State.Status}}' $ContainerName 2>$null
            if ($status -eq "running") {
                $healthy = $true
                break
            }
        } catch {
            # Container not found or other error
        }
        Start-Sleep -Seconds 2
    }

    return $healthy
}

function Test-ServiceEndpoint {
    param(
        [string]$Url,
        [int]$TimeoutSeconds = 10
    )

    try {
        $response = Invoke-RestMethod -Uri $Url -TimeoutSec $TimeoutSeconds
        return $true
    } catch {
        return $false
    }
}

function Get-ContainerLogs {
    param(
        [string]$ContainerName,
        [int]$TailLines = 50
    )

    try {
        $logs = docker logs $ContainerName --tail $TailLines 2>$null
        return $logs
    } catch {
        return "Unable to retrieve logs for container: $ContainerName"
    }
}

function Wait-ForContainerReady {
    param(
        [string]$ContainerName,
        [int]$TimeoutSeconds = 60,
        [string]$HealthCheckCommand = "echo 'ready'"
    )

    Write-Host "Waiting for container $ContainerName to be ready..." -ForegroundColor Yellow

    $startTime = Get-Date
    $ready = $false

    while ((Get-Date) -lt ($startTime.AddSeconds($TimeoutSeconds))) {
        try {
            $result = docker exec $ContainerName $HealthCheckCommand 2>$null
            if ($result -eq "ready") {
                $ready = $true
                break
            }
        } catch {
            # Container not ready yet
        }
        Start-Sleep -Seconds 2
    }

    if ($ready) {
        Write-Host "✓ Container $ContainerName is ready" -ForegroundColor Green
    } else {
        Write-Host "✗ Container $ContainerName failed to become ready within $TimeoutSeconds seconds" -ForegroundColor Red
    }

    return $ready
}

function Get-TestEnvironment {
    return @{
        Docker = $true
        WindowsMock = "wmr-windows-mock"
        WSLMock = "wmr-wsl-mock"
        CloudMock = "wmr-cloud-mock"
        TestRunner = "wmr-test-runner"
    }
}

function Test-AllContainersHealthy {
    $env = Get-TestEnvironment
    $containers = @($env.WindowsMock, $env.WSLMock, $env.CloudMock, $env.TestRunner)
    $healthyCount = 0

    foreach ($container in $containers) {
        if (Test-ContainerHealth -ContainerName $container -TimeoutSeconds 10) {
            $healthyCount++
            Write-Host "✓ $container is healthy" -ForegroundColor Green
        } else {
            Write-Host "✗ $container is not healthy" -ForegroundColor Red
        }
    }

    return $healthyCount -eq $containers.Count
}