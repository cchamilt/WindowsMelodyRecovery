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
    
    Test File Management:
    - Local Dev & Docker: Uses project root Temp directory for isolation
    - CI/CD: Uses user temp directory in AppData for better cleanup

.NOTES
    This script replaces the fragmented Docker-Test-Bootstrap.ps1 approach
    with a unified environment setup that works everywhere.
#>

# Environment Detection - Cache results to prevent repeated calls
if (-not $script:EnvironmentDetectionCached) {
    Write-Verbose "🔍 Detecting test environment (one-time detection)..."
    
    # Cache environment detection results
    $script:IsDockerEnvironment = ($env:DOCKER_TEST -eq 'true') -or ($env:CONTAINER -eq 'true') -or (Test-Path '/.dockerenv')
    $script:IsWindowsEnvironment = $IsWindows
    $script:IsCICDEnvironment = $env:CI -or $env:GITHUB_ACTIONS -or $env:BUILD_BUILDID -or $env:JENKINS_URL
    
    # Mark as cached
    $script:EnvironmentDetectionCached = $true
    
    Write-Verbose "Environment Detection Results:"
    Write-Verbose "  • Docker: $script:IsDockerEnvironment"
    Write-Verbose "  • Windows: $script:IsWindowsEnvironment"
    Write-Verbose "  • CI/CD: $script:IsCICDEnvironment"
}

# Robust module root detection
function Find-ModuleRoot {
    <#
    .SYNOPSIS
        Finds the module root directory using multiple detection methods.
    
    .DESCRIPTION
        Searches for the module root by looking for the module manifest file,
        working upward from the current script location or working directory.
    #>
    [CmdletBinding()]
    param()
    
    $moduleManifestName = "WindowsMelodyRecovery.psd1"
    $searchPaths = @()
    
    # Method 1: Try from script location (if available)
    if ($PSScriptRoot) {
        $searchPaths += $PSScriptRoot
        $searchPaths += Split-Path -Parent $PSScriptRoot  # tests/
        $searchPaths += Split-Path -Parent (Split-Path -Parent $PSScriptRoot)  # module root
    }
    
    # Method 2: Try from current working directory
    $searchPaths += Get-Location
    $searchPaths += Split-Path -Parent (Get-Location)
    
    # Method 3: Try common relative paths
    $searchPaths += Join-Path (Get-Location) ".."
    $searchPaths += Join-Path (Get-Location) "../.."
    
    # Search each path and work upward
    foreach ($startPath in $searchPaths) {
        if (-not $startPath -or -not (Test-Path $startPath)) {
            continue
        }
        
        $currentPath = Resolve-Path $startPath -ErrorAction SilentlyContinue
        if (-not $currentPath) {
            continue
        }
        
        # Search upward from current path
        $searchDepth = 0
        while ($currentPath -and $searchDepth -lt 10) {
            $manifestPath = Join-Path $currentPath $moduleManifestName
            
            if (Test-Path $manifestPath) {
                Write-Verbose "Found module root via manifest: $currentPath"
                return $currentPath.ToString()
            }
            
            # Also check for other identifying files/directories
            $identifyingPaths = @(
                Join-Path $currentPath "Public"
                Join-Path $currentPath "Private" 
                Join-Path $currentPath "tests"
                Join-Path $currentPath "Templates"
            )
            
            $identifyingPathsFound = 0
            foreach ($identifyingPath in $identifyingPaths) {
                if (Test-Path $identifyingPath) {
                    $identifyingPathsFound++
                }
            }
            
            # If we found 3 or more identifying paths, this is likely the module root
            if ($identifyingPathsFound -ge 3) {
                Write-Verbose "Found module root via structure: $currentPath"
                return $currentPath.ToString()
            }
            
            $parentPath = Split-Path -Parent $currentPath
            if ($parentPath -eq $currentPath) {
                break  # Reached filesystem root
            }
            $currentPath = $parentPath
            $searchDepth++
        }
    }
    
    # Final fallback: use current directory
    $fallbackPath = Get-Location
    Write-Warning "Could not find module root, using current directory: $fallbackPath"
    return $fallbackPath.ToString()
}

# Get module root directory with robust detection
$script:ModuleRoot = Find-ModuleRoot
Write-Verbose "Module root detected: $script:ModuleRoot"

# Set up test directories based on environment
if ($script:IsCICDEnvironment) {
    # CI/CD: Use user temp directory for better cleanup
    $tempBase = if ($IsWindows) { $env:TEMP } else { '/tmp' }
    $script:TestEnvironment = @{
        TestRestore = Join-Path $tempBase "WindowsMelodyRecovery-Tests" "test-restore"
        TestBackup = Join-Path $tempBase "WindowsMelodyRecovery-Tests" "test-backup"
        Temp = Join-Path $tempBase "WindowsMelodyRecovery-Tests" "temp"
        TestState = Join-Path $tempBase "WindowsMelodyRecovery-Tests" "test-state"
    }
    Write-Verbose "🚀 CI/CD environment detected, using temp directory: $tempBase"
} else {
    # Docker & Local Dev: Use project root Temp directory
    $tempBase = Join-Path $script:ModuleRoot "Temp"
    
    # Ensure the root Temp directory exists
    if (-not (Test-Path $tempBase)) {
        Write-Verbose "Creating root Temp directory: $tempBase"
        New-Item -Path $tempBase -ItemType Directory -Force | Out-Null
    }
    
    $script:TestEnvironment = @{
        TestRestore = Join-Path $tempBase "test-restore"
        TestBackup = Join-Path $tempBase "test-backup"
        Temp = Join-Path $tempBase "temp"
        TestState = Join-Path $tempBase "temp" "TestState"
    }
    
    if ($script:IsDockerEnvironment) {
        Write-Verbose "🐳 Docker environment detected, using project temp directory: $tempBase"
    } else {
        Write-Verbose "🪟 Local development environment detected, using project temp directory: $tempBase"
    }
}

# Load general test utilities for all environments
$testUtilitiesPath = Join-Path $PSScriptRoot "Test-Utilities.ps1"
if (Test-Path $testUtilitiesPath) {
    . $testUtilitiesPath
    Write-Verbose "Loaded general test utilities from: $testUtilitiesPath"
} else {
    Write-Warning "Test utilities not found at: $testUtilitiesPath"
}

# Load environment-specific mocks and utilities
if ($script:IsDockerEnvironment) {
    Write-Verbose "🐳 Loading Docker-specific mocks"
    
    # Load Docker-specific mocks ONLY in Docker environments
    $dockerMockPath = Join-Path $PSScriptRoot "Docker-Path-Mocks.ps1"
    if (Test-Path $dockerMockPath) {
        . $dockerMockPath
        Write-Verbose "Loaded Docker path mocks from: $dockerMockPath"
    } else {
        Write-Warning "Docker path mocks not found at: $dockerMockPath"
    }
    
    # Set up Docker-specific environment variables
    $env:WMR_DOCKER_TEST = 'true'
    $env:WMR_BACKUP_PATH = $env:WMR_BACKUP_PATH ?? $script:TestEnvironment.TestBackup
    $env:WMR_LOG_PATH = $env:WMR_LOG_PATH ?? (Join-Path $script:TestEnvironment.Temp "logs")
    $env:WMR_STATE_PATH = $env:WMR_STATE_PATH ?? $script:TestEnvironment.TestRestore
    
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
    Write-Verbose "🪟 Loading Windows native environment (no mocks)"
    
    # Set up Windows-specific environment variables
    $env:WMR_DOCKER_TEST = 'false'
    $env:WMR_BACKUP_PATH = $env:WMR_BACKUP_PATH ?? $script:TestEnvironment.TestBackup
    $env:WMR_LOG_PATH = $env:WMR_LOG_PATH ?? (Join-Path $script:ModuleRoot "logs")
    $env:WMR_STATE_PATH = $env:WMR_STATE_PATH ?? $script:TestEnvironment.TestRestore
}

# Environment information output
Write-Host "🧪 Test environment loaded" -ForegroundColor Green
Write-Host "Available commands: Test-Environment, Start-TestRun, Install-TestModule" -ForegroundColor Gray

if ($script:IsCICDEnvironment) {
    Write-Host "🏗️ CI/CD test environment initialized with user temp directory" -ForegroundColor Yellow
} elseif ($script:IsDockerEnvironment) {
    Write-Host "🐳 Docker test environment initialized with project temp directory" -ForegroundColor Cyan
} else {
    Write-Host "🪟 Local development test environment initialized with project temp directory" -ForegroundColor Cyan
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
    
    # Create standard test directories if they don't exist
    foreach ($dirName in @('TestRestore', 'TestBackup', 'Temp', 'TestState')) {
        $dirPath = $script:TestEnvironment[$dirName]
        
        # Safety checks
        if (-not (Test-SafeTestPath -Path $dirPath)) {
            throw "SAFETY VIOLATION: TestState directory path '$dirPath' is not safe for testing!"
        }
        
        if (-not (Test-Path $dirPath)) {
            Write-Host "  ✓ Created $dirName directory: $dirPath" -ForegroundColor Green
            New-Item -Path $dirPath -ItemType Directory -Force | Out-Null
        } else {
            Write-Host "  ✓ $dirName directory exists: $dirPath" -ForegroundColor Gray
        }
    }
    
    # Create standard backup structure
    $machineBackup = Join-Path $script:TestEnvironment.TestRestore "TEST-MACHINE"
    $sharedBackup = Join-Path $script:TestEnvironment.TestRestore "shared"
    
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
        TestRestore = $script:TestEnvironment.TestRestore
        TestBackup = $script:TestEnvironment.TestBackup
        Temp = $script:TestEnvironment.Temp
        TestState = $script:TestEnvironment.TestState
        MockData = Join-Path $script:ModuleRoot "tests/mock-data"
        MachineBackup = $machineBackup
        SharedBackup = $sharedBackup
        MachineTestBackup = Join-Path $script:TestEnvironment.TestBackup "TEST-MACHINE"
        SharedTestBackup = Join-Path $script:TestEnvironment.TestBackup "shared"
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
        Handles different temp directory locations based on environment type.
    
    .EXAMPLE
        Remove-TestEnvironment
    #>
    [CmdletBinding()]
    param()
    
    Write-Host "Cleaning up test environment..." -ForegroundColor Cyan
    
    foreach ($dirName in @('TestRestore', 'TestBackup', 'Temp')) {
        $dirPath = $script:TestEnvironment[$dirName]
        
        # Safety checks
        if (-not $dirPath -or $dirPath.Length -lt 5) {
            Write-Warning "Skipping unsafe path: $dirPath"
            continue
        }
        
        # Environment-specific safety checks
        if ($script:IsCICDEnvironment) {
            # CI/CD: Allow user temp directory paths
            $isUserTempPath = $false
            if ($script:IsWindowsEnvironment) {
                $isUserTempPath = $dirPath.Contains($env:TEMP) -and $dirPath.Contains("WindowsMelodyRecovery-Tests")
            } else {
                $isUserTempPath = $dirPath.StartsWith('/tmp/') -and $dirPath.Contains("WindowsMelodyRecovery-Tests")
            }
            
            if (-not $isUserTempPath) {
                Write-Warning "Skipping non-user-temp path in CI/CD: $dirPath"
                continue
            }
        } elseif ($script:IsDockerEnvironment) {
            # Docker: Allow project temp paths or workspace temp paths
            $isProjectTemp = $dirPath.Contains("WindowsMelodyRecovery") -and $dirPath.Contains("Temp")
            $isWorkspaceTemp = $dirPath.StartsWith("/workspace/") -and $dirPath.Contains("Temp")
            if (-not ($isProjectTemp -or $isWorkspaceTemp)) {
                Write-Warning "Skipping non-project/workspace-temp path in Docker: $dirPath"
                continue
            }
        } else {
            # Local dev: Allow project temp paths only
            if (-not ($dirPath.Contains("WindowsMelodyRecovery") -and $dirPath.Contains("Temp"))) {
                Write-Warning "Skipping non-project-temp path in local dev: $dirPath"
                continue
            }
        }
        
        if ($dirPath -and (Test-Path $dirPath)) {
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
        TestRestore = $script:TestEnvironment.TestRestore
        TestBackup = $script:TestEnvironment.TestBackup
        Temp = $script:TestEnvironment.Temp
        TestState = $script:TestEnvironment.TestState
        MockData = Join-Path $script:ModuleRoot "tests/mock-data"
        MachineBackup = Join-Path $script:TestEnvironment.TestRestore "TEST-MACHINE"
        SharedBackup = Join-Path $script:TestEnvironment.TestRestore "shared"
        MachineTestBackup = Join-Path $script:TestEnvironment.TestBackup "TEST-MACHINE"
        SharedTestBackup = Join-Path $script:TestEnvironment.TestBackup "shared"
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
        accidental deletion of important files. Works across all environments
        with different temp directory strategies.
        
        CRITICAL: This function prevents any writes to C:\ root directories!
    
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
        Write-Warning "Test-SafeTestPath: Path is null, empty, or too short: '$Path'"
        return $false
    }
    
    # CRITICAL: Prevent ANY C:\ root writes outside of project
    if ($Path.StartsWith("C:\") -and -not ($Path.StartsWith($script:ModuleRoot))) {
        Write-Error "🚨 CRITICAL SAFETY VIOLATION: Attempted C:\ root write blocked!"
        Write-Error "🚨 Path: '$Path'"
        Write-Error "🚨 Module Root: '$script:ModuleRoot'"
        Write-Error "🚨 This indicates a serious path resolution bug!"
        return $false
    }
    
    # CRITICAL: Block any obvious dangerous patterns
    $dangerousPaths = @(
        "C:\Windows",
        "C:\Program Files", 
        "C:\Program Files (x86)",
        "C:\Users\$env:USERNAME\Desktop",
        "C:\Users\$env:USERNAME\Documents",
        "C:\ProgramData"
    )
    
    foreach ($dangerousPath in $dangerousPaths) {
        if ($Path.StartsWith($dangerousPath, [System.StringComparison]::OrdinalIgnoreCase)) {
            Write-Error "🚨 CRITICAL SAFETY VIOLATION: Attempted write to dangerous system path blocked!"
            Write-Error "🚨 Path: '$Path'"
            Write-Error "🚨 Dangerous pattern: '$dangerousPath'"
            return $false
        }
    }
    
    # Environment-specific safety validation
    if ($script:IsCICDEnvironment) {
        # CI/CD environment: must be in user temp directory
        if ($script:IsWindowsEnvironment) {
            # Windows CI/CD: must be in user temp and contain our test identifier
            $isValid = $Path.Contains($env:TEMP) -and $Path.Contains("WindowsMelodyRecovery-Tests")
            if (-not $isValid) {
                Write-Verbose "Test-SafeTestPath: CI/CD Windows path not in user temp: '$Path'"
            }
            return $isValid
        } else {
            # Linux CI/CD: must be in /tmp/ and contain our test identifier
            $isValid = $Path.StartsWith('/tmp/') -and $Path.Contains("WindowsMelodyRecovery-Tests")
            if (-not $isValid) {
                Write-Verbose "Test-SafeTestPath: CI/CD Linux path not in /tmp: '$Path'"
            }
            return $isValid
        }
    } elseif ($script:IsDockerEnvironment) {
        # Docker environment: must be in project temp directory or workspace temp directory
        $isProjectTemp = $Path.Contains("WindowsMelodyRecovery") -and $Path.Contains("Temp")
        $isWorkspaceTemp = $Path.StartsWith("/workspace/") -and $Path.Contains("Temp")
        $isValid = $isProjectTemp -or $isWorkspaceTemp
        if (-not $isValid) {
            Write-Verbose "Test-SafeTestPath: Docker path not in project/workspace temp: '$Path'"
        }
        return $isValid
    } else {
        # Local development: must be in project temp directory
        $isValid = $Path.Contains("WindowsMelodyRecovery") -and $Path.Contains("Temp")
        if (-not $isValid) {
            Write-Verbose "Test-SafeTestPath: Local dev path not in project temp: '$Path'"
        }
        return $isValid
    }
}

# Export environment information for scripts that need it
$script:TestEnvironmentInfo = @{
    IsDocker = $script:IsDockerEnvironment
    IsWindows = $script:IsWindowsEnvironment
    IsCICD = $script:IsCICDEnvironment
    ModuleRoot = $script:ModuleRoot
    TestDirectories = $script:TestEnvironment
    TempStrategy = if ($script:IsCICDEnvironment) { "UserTemp" } else { "ProjectTemp" }
}

# Note: Docker-Path-Mocks.ps1 functions are already loaded above
# This includes: Read-WmrTemplateConfig, Test-WmrTemplateSchema, and all other mock functions

# Functions are available when dot-sourced - no need to export when not a module 