#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Test Helper Functions

.DESCRIPTION
    Common utility functions for Windows Missing Recovery tests.
#>

# Test helper functions
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

function Get-MockDataPath {
    param(
        [string]$DataType
    )
    
    $basePath = "/mock-data"
    
    switch ($DataType) {
        "registry" { return Join-Path $basePath "registry" }
        "appdata" { return Join-Path $basePath "appdata" }
        "programfiles" { return Join-Path $basePath "programfiles" }
        "cloud" { return Join-Path $basePath "cloud" }
        "wsl" { return Join-Path $basePath "wsl" }
        default { return $basePath }
    }
}

function Test-MockDataExists {
    param(
        [string]$DataType,
        [string]$Path
    )
    
    $mockPath = Get-MockDataPath -DataType $DataType
    $fullPath = Join-Path $mockPath $Path
    
    return Test-Path $fullPath
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

Export-ModuleMember -Function Test-ContainerHealth, Test-ServiceEndpoint, Get-MockDataPath, Test-MockDataExists, Get-TestEnvironment 