#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Enhanced Mock Utilities for Windows Melody Recovery Testing

.DESCRIPTION
    Utility functions for working with enhanced mock environments and data.
    Provides backwards compatibility while integrating with enhanced mock infrastructure.

.NOTES
    This file has been enhanced to integrate with the new Enhanced-Mock-Infrastructure.ps1
    while maintaining backwards compatibility with existing tests.
#>

# Import enhanced mock infrastructure and integration layer
. (Join-Path $PSScriptRoot "Enhanced-Mock-Infrastructure.ps1")
. (Join-Path $PSScriptRoot "Mock-Integration.ps1")

# Enhanced mock environment utilities with backwards compatibility
function Test-MockDataExist {
    <#
    .SYNOPSIS
        Tests if mock data exists for the specified data type and path.
        Enhanced version with improved path resolution and validation.
    #>
    param(
        [string]$DataType,
        [string]$Path
    )

    $mockPath = Get-MockDataPath -DataType $DataType
    $fullPath = Join-Path $mockPath $Path

    return Test-Path $fullPath
}

function Get-MockDataPath {
    <#
    .SYNOPSIS
        Gets the path to mock data for the specified data type.
        Enhanced version with standardized test path integration.
    #>
    param(
        [string]$DataType
    )

    # Use standardized test paths from Test-Environment-Standard.ps1
    $testPaths = Get-StandardTestPaths
    $basePath = $testPaths.TestMockData

    switch ($DataType) {
        "registry" { return Join-Path $basePath "registry" }
        "appdata" { return Join-Path $basePath "appdata" }
        "programfiles" { return Join-Path $basePath "programfiles" }
        "cloud" { return Join-Path $basePath "cloud" }
        "wsl" { return Join-Path $basePath "wsl" }
        "applications" { return Join-Path $basePath "applications" }
        "gaming" { return Join-Path $basePath "gaming" }
        "system-settings" { return Join-Path $basePath "system-settings" }
        "unit" { return Join-Path $basePath "unit" }
        "file-operations" { return Join-Path $basePath "file-operations" }
        "end-to-end" { return Join-Path $basePath "end-to-end" }
        default { return $basePath }
    }
}

function Initialize-MockEnvironment {
    <#
    .SYNOPSIS
        Initializes mock environment with enhanced infrastructure.
        Backwards compatible wrapper that uses enhanced mock infrastructure.
    #>
    param(
        [string]$Environment = "Enhanced",
        [string]$TestType = "Integration",
        [string]$Scope = "Standard"
    )

    Write-Information -MessageData "🚀 Initializing enhanced mock environment: $Environment" -InformationAction Continue
    Write-Verbose -Message "   Test Type: $TestType | Scope: $Scope"

    # Use enhanced mock infrastructure
    Initialize-EnhancedMockInfrastructure -TestType $TestType -Scope $Scope

    # Legacy compatibility - create additional directories if needed
    $legacyDirs = @(
        "/mock-registry",
        "/mock-appdata",
        "/mock-programfiles",
        "/mock-cloud"
    )

    foreach ($dir in $legacyDirs) {
        if (-not (Test-Path $dir)) {
            New-Item -Path $dir -ItemType Directory -Force | Out-Null
            Write-Verbose -Message "  ✓ Created legacy compatibility directory: $dir"
        }
    }

    Write-Information -MessageData "✅ Enhanced mock environment initialized successfully!" -InformationAction Continue
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

    Write-Information -MessageData "✓ Set mock registry value: $KeyPath\$ValueName = $Value" -InformationAction Continue
}







