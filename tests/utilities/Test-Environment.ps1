#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Unified Test Environment Management for Windows Melody Recovery

.DESCRIPTION
    Centralized script for setting up test environments that works across:
    - Docker containers (Linux/cross-platform)
    - Windows local development
    - CI/CD environments
    
    Auto-detects environment and loads appropriate mocks and utilities.

.NOTES
    This script replaces the fragmented Docker-Test-Bootstrap.ps1 approach
    with a unified environment setup that works everywhere.
#>

# Environment Detection
$script:IsDockerEnvironment = ($env:DOCKER_TEST -eq 'true') -or ($env:CONTAINER -eq 'true') -or (Test-Path '/.dockerenv')
$script:IsWindowsEnvironment = $IsWindows
$script:IsCICDEnvironment = $env:CI -or $env:GITHUB_ACTIONS -or $env:BUILD_BUILDID -or $env:JENKINS_URL

# Get module root directory
$script:ModuleRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

# Define test directories based on environment
if ($script:IsDockerEnvironment) {
    $script:TestDirectories = @{
        TestRestore = '/tmp/wmr-test-restore'
        TestBackup = '/tmp/wmr-test-backup'
        Temp = '/tmp/wmr-temp'
        MockData = Join-Path $script:ModuleRoot "tests/mock-data"
    }
} else {
    $script:TestDirectories = @{
        TestRestore = Join-Path $script:ModuleRoot "test-restore"
        TestBackup = Join-Path $script:ModuleRoot "test-backups" 
        Temp = Join-Path $script:ModuleRoot "Temp"
        MockData = Join-Path $script:ModuleRoot "tests\mock-data"
    }
}

# Load environment-specific mocks and utilities
if ($script:IsDockerEnvironment) {
    Write-Verbose "🐳 Docker environment detected, loading Docker-specific mocks"
    
    # Load Docker-specific mocks
    $dockerMockPath = Join-Path $PSScriptRoot "Docker-Path-Mocks.ps1"
    if (Test-Path $dockerMockPath) {
        . $dockerMockPath
        Write-Verbose "Loaded Docker path mocks from: $dockerMockPath"
    } else {
        Write-Warning "Docker path mocks not found at: $dockerMockPath"
    }
    
    # Set up Docker-specific environment variables
    $env:WMR_DOCKER_TEST = 'true'
    $env:WMR_BACKUP_PATH = $env:WMR_BACKUP_PATH ?? '/tmp/wmr-test-backup'
    $env:WMR_LOG_PATH = $env:WMR_LOG_PATH ?? '/tmp/wmr-test-logs'
    $env:WMR_STATE_PATH = $env:WMR_STATE_PATH ?? '/tmp/wmr-test-state'
    
    # Mock Windows-specific environment variables for cross-platform compatibility
    $env:USERPROFILE = $env:USERPROFILE ?? '/mock-c/Users/TestUser'
    $env:PROGRAMFILES = $env:PROGRAMFILES ?? '/mock-c/Program Files'
    $env:PROGRAMDATA = $env:PROGRAMDATA ?? '/mock-c/ProgramData'
    $env:COMPUTERNAME = $env:COMPUTERNAME ?? 'TEST-MACHINE'
    $env:HOSTNAME = $env:HOSTNAME ?? 'TEST-MACHINE'
    $env:USERNAME = $env:USERNAME ?? 'TestUser'
    $env:PROCESSOR_ARCHITECTURE = $env:PROCESSOR_ARCHITECTURE ?? 'AMD64'
    $env:USERDOMAIN = $env:USERDOMAIN ?? 'WORKGROUP'
    $env:PROCESSOR_IDENTIFIER = $env:PROCESSOR_IDENTIFIER ?? 'Intel64 Family 6 Model 158 Stepping 10, GenuineIntel'
    
} else {
    Write-Verbose "🪟 Windows environment detected, loading Windows-compatible mocks"
    
    # Load Windows-compatible versions of Docker mocks for consistency
    # This ensures unit tests work the same way locally as in Docker
    $dockerMockPath = Join-Path $PSScriptRoot "Docker-Path-Mocks.ps1"
    if (Test-Path $dockerMockPath) {
        . $dockerMockPath
        Write-Verbose "Loaded Docker path mocks for Windows compatibility"
    } else {
        Write-Warning "Docker path mocks not found at: $dockerMockPath"
    }
    
    # Set up Windows-specific environment variables
    $env:WMR_DOCKER_TEST = 'false'
    $env:WMR_BACKUP_PATH = $env:WMR_BACKUP_PATH ?? (Join-Path $script:ModuleRoot "test-backups")
    $env:WMR_LOG_PATH = $env:WMR_LOG_PATH ?? (Join-Path $script:ModuleRoot "logs")
    $env:WMR_STATE_PATH = $env:WMR_STATE_PATH ?? (Join-Path $script:ModuleRoot "test-restore")
}

# Environment information output
Write-Host "🧪 Test environment loaded" -ForegroundColor Green
Write-Host "Available commands: Test-Environment, Start-TestRun, Install-TestModule" -ForegroundColor Gray

if ($script:IsDockerEnvironment) {
    Write-Host "🐳 Docker test environment initialized with comprehensive mocks" -ForegroundColor Cyan
} else {
    Write-Host "🪟 Windows test environment initialized with Docker-compatible mocks" -ForegroundColor Cyan
}

function Initialize-TestEnvironment {
    <#
    .SYNOPSIS
        Initializes clean test directories for unit tests.
    
    .DESCRIPTION
        Creates or cleans test directories based on environment.
        Works in both Docker and Windows environments.
    
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
        IsDocker = $script:IsDockerEnvironment
        IsWindows = $script:IsWindowsEnvironment
        IsCICD = $script:IsCICDEnvironment
    }
}

function Remove-TestEnvironment {
    <#
    .SYNOPSIS
        Safely removes test directories and their contents.
    
    .DESCRIPTION
        Cleans up test directories with appropriate safety checks for each environment.
    
    .EXAMPLE
        Remove-TestEnvironment
    #>
    [CmdletBinding()]
    param()
    
    Write-Host "Cleaning up test environment..." -ForegroundColor Cyan
    
    foreach ($dirName in @('TestRestore', 'TestBackup', 'Temp')) {
        $dirPath = $script:TestDirectories[$dirName]
        
        # Safety checks
        if (-not $dirPath -or $dirPath.Length -lt 5) {
            Write-Warning "Skipping unsafe path: $dirPath"
            continue
        }
        
        # Environment-specific safety checks
        if ($script:IsDockerEnvironment) {
            if (-not ($dirPath.StartsWith('/tmp/') -or $dirPath.Contains('wmr-test'))) {
                Write-Warning "Skipping non-test path in Docker: $dirPath"
                continue
            }
        } else {
            if (-not $dirPath.Contains("WindowsMelodyRecovery")) {
                Write-Warning "Skipping path outside project: $dirPath"
                continue
            }
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

function Get-TestPaths {
    <#
    .SYNOPSIS
        Returns standardized test paths for use in unit tests.
    
    .DESCRIPTION
        Provides consistent path structure for all unit tests across environments.
        
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
        IsDocker = $script:IsDockerEnvironment
        IsWindows = $script:IsWindowsEnvironment
        IsCICD = $script:IsCICDEnvironment
    }
}

function Test-SafeTestPath {
    <#
    .SYNOPSIS
        Validates that a path is safe for test operations.
    
    .DESCRIPTION
        Ensures paths are within appropriate test directories to prevent
        accidental deletion of important files. Works across environments.
    
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
    if ([string]::IsNullOrWhiteSpace($Path) -or $Path.Length -lt 5) {
        return $false
    }
    
    # Environment-specific safety validation
    if ($script:IsDockerEnvironment) {
        # Docker environment: must be in /tmp/ or contain wmr-test
        $dockerSafeDirs = @('/tmp/', 'wmr-test', 'mock-data')
        $isInDockerSafeDir = $false
        
        foreach ($safeDir in $dockerSafeDirs) {
            if ($Path.Contains($safeDir)) {
                $isInDockerSafeDir = $true
                break
            }
        }
        
        return $isInDockerSafeDir
    } else {
        # Windows environment: must be within project and test directories
        if (-not $Path.Contains("WindowsMelodyRecovery")) {
            return $false
        }
        
        $testDirs = @("test-restore", "test-backups", "Temp", "tests\mock-data", "tests/mock-data")
        $isInTestDir = $false
        
        foreach ($testDir in $testDirs) {
            if ($Path.Contains($testDir)) {
                $isInTestDir = $true
                break
            }
        }
        
        return $isInTestDir
    }
}

# Export environment information for scripts that need it
$script:TestEnvironmentInfo = @{
    IsDocker = $script:IsDockerEnvironment
    IsWindows = $script:IsWindowsEnvironment
    IsCICD = $script:IsCICDEnvironment
    ModuleRoot = $script:ModuleRoot
    TestDirectories = $script:TestDirectories
}

# Note: Docker-Path-Mocks.ps1 functions are already loaded above
# This includes: Read-WmrTemplateConfig, Test-WmrTemplateSchema, and all other mock functions

# Functions are available when dot-sourced - no need to export when not a module 