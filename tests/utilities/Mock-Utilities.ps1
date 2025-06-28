#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Mock Utilities for Windows Missing Recovery Integration Tests

.DESCRIPTION
    Utility functions for working with mock environments and data.
#>

# Mock environment utilities
function Test-MockDataExists {
    param(
        [string]$DataType,
        [string]$Path
    )
    
    $mockPath = Get-MockDataPath -DataType $DataType
    $fullPath = Join-Path $mockPath $Path
    
    return Test-Path $fullPath
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

function Initialize-MockEnvironment {
    param(
        [string]$Environment = "Docker"
    )
    
    Write-Host "Initializing mock environment: $Environment" -ForegroundColor Cyan
    
    # Create mock directories if they don't exist
    $mockDirs = @(
        "/mock-registry",
        "/mock-appdata", 
        "/mock-programfiles",
        "/mock-cloud"
    )
    
    foreach ($dir in $mockDirs) {
        if (-not (Test-Path $dir)) {
            New-Item -Path $dir -ItemType Directory -Force | Out-Null
            Write-Host "✓ Created mock directory: $dir" -ForegroundColor Green
        }
    }
    
    Write-Host "✓ Mock environment initialized" -ForegroundColor Green
}

function Get-MockRegistryValue {
    param(
        [string]$KeyPath,
        [string]$ValueName
    )
    
    $mockRegistryPath = "/mock-registry"
    $fullPath = Join-Path $mockRegistryPath $KeyPath
    
    if (Test-Path $fullPath) {
        $valueFile = Join-Path $fullPath "$ValueName.txt"
        if (Test-Path $valueFile) {
            return Get-Content $valueFile -Raw
        }
    }
    
    return $null
}

function Set-MockRegistryValue {
    param(
        [string]$KeyPath,
        [string]$ValueName,
        [string]$Value
    )
    
    $mockRegistryPath = "/mock-registry"
    $fullPath = Join-Path $mockRegistryPath $KeyPath
    
    if (-not (Test-Path $fullPath)) {
        New-Item -Path $fullPath -ItemType Directory -Force | Out-Null
    }
    
    $valueFile = Join-Path $fullPath "$ValueName.txt"
    $Value | Out-File -FilePath $valueFile -Encoding UTF8
    
    Write-Host "✓ Set mock registry value: $KeyPath\$ValueName = $Value" -ForegroundColor Green
} 