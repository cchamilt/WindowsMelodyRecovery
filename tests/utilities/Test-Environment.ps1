#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Test Environment Management for Windows Melody Recovery Unit Tests

.DESCRIPTION
    Centralized script for setting up and cleaning up test environments.
    Manages test-restore, test-backup, and Temp directories.
    Uses existing mock data from tests/mock-data for consistent testing.

.NOTES
    This script ensures all unit tests have a clean, consistent environment
    without dangerous file operations scattered across individual test files.
#>

# Get module root directory
$script:ModuleRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

# Define test directories
$script:TestDirectories = @{
    TestRestore = Join-Path $script:ModuleRoot "test-restore"
    TestBackup = Join-Path $script:ModuleRoot "test-backups" 
    Temp = Join-Path $script:ModuleRoot "Temp"
    MockData = Join-Path $script:ModuleRoot "tests\mock-data"
}

function Initialize-TestEnvironment {
    <#
    .SYNOPSIS
        Initializes clean test directories for unit tests.
    
    .DESCRIPTION
        Creates or cleans test-restore, test-backup, and Temp directories.
        Sets up basic directory structure using mock data patterns.
    
    .PARAMETER Force
        Force recreation of directories even if they exist.
    
    .EXAMPLE
        Initialize-TestEnvironment
        Initialize-TestEnvironment -Force
    #>
    [CmdletBinding()]
    param(
        [switch]$Force
    )
    
    Write-Host "Initializing test environment..." -ForegroundColor Cyan
    
    # Clean up existing directories if Force is specified
    if ($Force) {
        Remove-TestEnvironment
    }
    
    # Create base test directories
    foreach ($dirName in @('TestRestore', 'TestBackup', 'Temp')) {
        $dirPath = $script:TestDirectories[$dirName]
        
        if (-not (Test-Path $dirPath)) {
            New-Item -ItemType Directory -Path $dirPath -Force | Out-Null
            Write-Host "  ✓ Created $dirName directory: $dirPath" -ForegroundColor Green
        } else {
            Write-Host "  ✓ $dirName directory exists: $dirPath" -ForegroundColor Yellow
        }
    }
    
    # Create standard backup structure
    $machineBackup = Join-Path $script:TestDirectories.TestRestore "TEST-MACHINE"
    $sharedBackup = Join-Path $script:TestDirectories.TestRestore "shared"
    
    foreach ($dir in @($machineBackup, $sharedBackup)) {
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            Write-Host "  ✓ Created backup directory: $dir" -ForegroundColor Green
        }
    }
    
    # Create component subdirectories based on mock data structure
    $components = @('appdata', 'registry', 'programfiles', 'cloud', 'wsl', 'ssh', 'steam', 'epic', 'ea', 'gog')
    
    foreach ($component in $components) {
        $machineComponentDir = Join-Path $machineBackup $component
        $sharedComponentDir = Join-Path $sharedBackup $component
        
        foreach ($dir in @($machineComponentDir, $sharedComponentDir)) {
            if (-not (Test-Path $dir)) {
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
            }
        }
    }
    
    Write-Host "✓ Test environment initialized successfully" -ForegroundColor Green
    
    return @{
        ModuleRoot = $script:ModuleRoot
        TestRestore = $script:TestDirectories.TestRestore
        TestBackup = $script:TestDirectories.TestBackup
        Temp = $script:TestDirectories.Temp
        MockData = $script:TestDirectories.MockData
        MachineBackup = $machineBackup
        SharedBackup = $sharedBackup
    }
}

function Remove-TestEnvironment {
    <#
    .SYNOPSIS
        Safely removes test directories and their contents.
    
    .DESCRIPTION
        Cleans up test-restore, test-backup, and Temp directories.
        Includes safety checks to prevent accidental deletion of important files.
    
    .EXAMPLE
        Remove-TestEnvironment
    #>
    [CmdletBinding()]
    param()
    
    Write-Host "Cleaning up test environment..." -ForegroundColor Cyan
    
    foreach ($dirName in @('TestRestore', 'TestBackup', 'Temp')) {
        $dirPath = $script:TestDirectories[$dirName]
        
        # Safety checks
        if (-not $dirPath -or $dirPath.Length -lt 10) {
            Write-Warning "Skipping unsafe path: $dirPath"
            continue
        }
        
        if (-not $dirPath.Contains("WindowsMelodyRecovery")) {
            Write-Warning "Skipping path outside project: $dirPath"
            continue
        }
        
        if (Test-Path $dirPath) {
            try {
                Remove-Item -Path $dirPath -Recurse -Force -ErrorAction Stop
                Write-Host "  ✓ Removed $dirName directory: $dirPath" -ForegroundColor Green
            } catch {
                Write-Warning "Failed to remove $dirName directory: $_"
            }
        } else {
            Write-Host "  ✓ $dirName directory already clean: $dirPath" -ForegroundColor Yellow
        }
    }
    
    Write-Host "✓ Test environment cleaned successfully" -ForegroundColor Green
}

function Copy-MockDataToTest {
    <#
    .SYNOPSIS
        Copies mock data to test directories for unit testing.
    
    .DESCRIPTION
        Copies specific mock data files from tests/mock-data to test directories
        for use in unit tests. Allows selective copying of components.
    
    .PARAMETER Component
        Specific component to copy (appdata, registry, etc.). If not specified, copies all.
    
    .PARAMETER Destination
        Destination type: 'restore', 'backup', or 'both'. Default is 'restore'.
    
    .EXAMPLE
        Copy-MockDataToTest -Component "registry"
        Copy-MockDataToTest -Component "appdata" -Destination "both"
    #>
    [CmdletBinding()]
    param(
        [string]$Component,
        [ValidateSet('restore', 'backup', 'both')]
        [string]$Destination = 'restore'
    )
    
    $mockDataPath = $script:TestDirectories.MockData
    
    if (-not (Test-Path $mockDataPath)) {
        Write-Warning "Mock data directory not found: $mockDataPath"
        return
    }
    
    # Determine which components to copy
    $componentsToProcess = if ($Component) {
        @($Component)
    } else {
        Get-ChildItem -Path $mockDataPath -Directory | Select-Object -ExpandProperty Name
    }
    
    # Determine destination directories
    $destinations = switch ($Destination) {
        'restore' { @($script:TestDirectories.TestRestore) }
        'backup' { @($script:TestDirectories.TestBackup) }
        'both' { @($script:TestDirectories.TestRestore, $script:TestDirectories.TestBackup) }
    }
    
    foreach ($comp in $componentsToProcess) {
        $sourcePath = Join-Path $mockDataPath $comp
        
        if (-not (Test-Path $sourcePath)) {
            Write-Warning "Mock data component not found: $sourcePath"
            continue
        }
        
        foreach ($destRoot in $destinations) {
            $destPath = Join-Path $destRoot $comp
            
            try {
                if (Test-Path $destPath) {
                    Remove-Item -Path $destPath -Recurse -Force
                }
                
                Copy-Item -Path $sourcePath -Destination $destPath -Recurse -Force
                Write-Host "  ✓ Copied $comp mock data to: $destPath" -ForegroundColor Green
            } catch {
                Write-Warning "Failed to copy $comp mock data: $_"
            }
        }
    }
}

# Add missing functions that are available in Docker environment
function Get-WmrModulePath {
    <#
    .SYNOPSIS
        Gets the path to the Windows Melody Recovery module file.
    
    .DESCRIPTION
        Returns the path to the main module file (WindowsMelodyRecovery.psm1).
        This function provides compatibility with Docker test environment.
    
    .EXAMPLE
        Get-WmrModulePath
    #>
    [CmdletBinding()]
    param()
    
    $moduleFile = Join-Path $script:ModuleRoot "WindowsMelodyRecovery.psm1"
    
    if (Test-Path $moduleFile) {
        return $moduleFile
    } else {
        Write-Warning "Module file not found: $moduleFile"
        return $null
    }
}

function Read-WmrTemplateConfig {
    <#
    .SYNOPSIS
        Reads and parses a YAML template configuration file.
    
    .DESCRIPTION
        Reads a YAML template file and returns the parsed configuration.
        This function provides compatibility with Docker test environment.
    
    .PARAMETER TemplatePath
        Path to the template file to read.
    
    .EXAMPLE
        Read-WmrTemplateConfig -TemplatePath "Templates/System/display.yaml"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TemplatePath
    )
    
    # Handle relative paths
    if (-not [System.IO.Path]::IsPathRooted($TemplatePath)) {
        $TemplatePath = Join-Path $script:ModuleRoot $TemplatePath
    }
    
    if (-not (Test-Path $TemplatePath)) {
        throw "Template file not found: $TemplatePath"
    }
    
    try {
        $yamlContent = Get-Content -Path $TemplatePath -Raw -Encoding UTF8
        
        # Simple YAML parsing for basic structures
        # This is a simplified parser for testing purposes
        $config = @{}
        
        $lines = $yamlContent -split "`n"
        $currentSection = $null
        
        foreach ($line in $lines) {
            $line = $line.Trim()
            
            if ($line -match '^#' -or [string]::IsNullOrWhiteSpace($line)) {
                continue
            }
            
            if ($line -match '^(\w+):$') {
                $currentSection = $matches[1]
                $config[$currentSection] = @{}
            } elseif ($line -match '^(\w+):\s*(.+)$') {
                $key = $matches[1]
                $value = $matches[2].Trim()
                
                # Remove quotes if present - fixed regex
                if ($value -match '^["''](.+)["'']$') {
                    $value = $matches[1]
                }
                
                if ($currentSection) {
                    $config[$currentSection][$key] = $value
                } else {
                    $config[$key] = $value
                }
            }
        }
        
        return $config
    } catch {
        throw "Failed to parse template file '$TemplatePath': $_"
    }
}

function Get-TestPaths {
    <#
    .SYNOPSIS
        Returns standardized test paths for use in unit tests.
    
    .DESCRIPTION
        Provides consistent path structure for all unit tests.
        
    .EXAMPLE
        $paths = Get-TestPaths
        $machineBackup = $paths.MachineBackup
    #>
    [CmdletBinding()]
    param()
    
    return @{
        ModuleRoot = $script:ModuleRoot
        TestRestore = $script:TestDirectories.TestRestore
        TestBackup = $script:TestDirectories.TestBackup
        Temp = $script:TestDirectories.Temp
        MockData = $script:TestDirectories.MockData
        MachineBackup = Join-Path $script:TestDirectories.TestRestore "TEST-MACHINE"
        SharedBackup = Join-Path $script:TestDirectories.TestRestore "shared"
        MachineTestBackup = Join-Path $script:TestDirectories.TestBackup "TEST-MACHINE"
        SharedTestBackup = Join-Path $script:TestDirectories.TestBackup "shared"
    }
}

function Test-SafeTestPath {
    <#
    .SYNOPSIS
        Validates that a path is safe for test operations.
    
    .DESCRIPTION
        Ensures paths are within the project and test directories to prevent
        accidental deletion of important files.
    
    .PARAMETER Path
        Path to validate.
    
    .EXAMPLE
        if (Test-SafeTestPath $somePath) { Remove-Item $somePath }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path
    )
    
    # Basic safety checks
    if ([string]::IsNullOrWhiteSpace($Path) -or $Path.Length -lt 10) {
        return $false
    }
    
    # Must be within the project
    if (-not $Path.Contains("WindowsMelodyRecovery")) {
        return $false
    }
    
    # Must be within test directories
    $testDirs = @("test-restore", "test-backups", "Temp", "tests\mock-data")
    $isInTestDir = $false
    
    foreach ($testDir in $testDirs) {
        if ($Path.Contains($testDir)) {
            $isInTestDir = $true
            break
        }
    }
    
    return $isInTestDir
}

function Test-WmrTemplateSchema {
    <#
    .SYNOPSIS
        Validates a template configuration against the expected schema.
    
    .DESCRIPTION
        Validates that a template configuration has the required metadata
        and structure. This function provides compatibility with Docker test environment.
    
    .PARAMETER TemplateConfig
        Template configuration to validate.
    
    .EXAMPLE
        Test-WmrTemplateSchema -TemplateConfig $config
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$TemplateConfig
    )
    
    # Convert PSCustomObject to hashtable if needed
    if ($TemplateConfig -is [PSCustomObject]) {
        $configHash = @{}
        foreach ($prop in $TemplateConfig.PSObject.Properties) {
            $configHash[$prop.Name] = $prop.Value
        }
        $TemplateConfig = $configHash
    }
    
    # Mock template schema validation
    if (-not $TemplateConfig.metadata) {
        throw "Template schema validation failed: 'metadata' is missing."
    }
    
    if ($TemplateConfig.metadata -is [PSCustomObject]) {
        if (-not $TemplateConfig.metadata.name) {
            throw "Template schema validation failed: 'metadata.name' is missing."
        }
    } elseif ($TemplateConfig.metadata -is [hashtable]) {
        if (-not $TemplateConfig.metadata.name) {
            throw "Template schema validation failed: 'metadata.name' is missing."
        }
    }
    
    return $true
}

# Functions are available when dot-sourced - no need to export when not a module 