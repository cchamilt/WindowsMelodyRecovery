#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Unified Test Environment Management for Windows Melody Recovery

.DESCRIPTION
    Centralized script for setting up test environments. This script provides a library
    of functions that can be called by specific test runners to set up the
    appropriate, isolated environment for each test suite.

    This script itself does not perform any setup; it only provides the functions.

.NOTES
    This script replaces the previous monolithic approach with a modular, function-based
    library to enforce strict test environment isolation.
#>

# --- Core Environment Detection Functions ---

<#
.SYNOPSIS
Short description

.DESCRIPTION
Long description

.EXAMPLE
An example

.NOTES
General notes
#>
function Get-EnvironmentType {
    [OutputType('PSCustomObject')]
    [CmdletBinding()]
    param()

    Write-Verbose "🔍 Detecting test environment..."

    $envType = [PSCustomObject]@{
        IsDocker  = ($env:DOCKER_TEST -eq 'true') -or ($env:CONTAINER -eq 'true') -or (Test-Path '/.dockerenv')
        IsWindows = $IsWindows
        IsCI      = $env:CI -or $env:GITHUB_ACTIONS -or $env:BUILD_BUILDID -or $env:JENKINS_URL
    }

    Write-Verbose "Environment Detection Results: Docker=$($envType.IsDocker), Windows=$($envType.IsWindows), CI=$($envType.IsCI)"
    return $envType
}

<#
.SYNOPSIS
Short description

.DESCRIPTION
Long description

.EXAMPLE
An example

.NOTES
General notes
#>
function Find-ModuleRoot {
    [OutputType('string')]
    [CmdletBinding()]
    param()

    <#
    .SYNOPSIS
        Finds the module root directory using multiple detection methods.

    .DESCRIPTION
        Searches for the module root by looking for the module manifest file,
        working upward from the current script location or working directory.
    #>
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

# --- Test Suite Specific Initializers ---

<#
.SYNOPSIS
Short description

.DESCRIPTION
Long description

.PARAMETER SuiteName
Parameter description

.PARAMETER SessionId
Parameter description

.EXAMPLE
An example

.NOTES
General notes
#>
function Initialize-TestEnvironment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Unit', 'FileOps', 'Integration', 'E2E', 'Windows')]
        [string]$SuiteName,

        [Parameter(Mandatory = $false)]
        [string]$SessionId = (New-Guid).Guid.Substring(0, 8)
    )

    $envType = Get-EnvironmentType
    $moduleRoot = Find-ModuleRoot

    # Create a unique, isolated root path for this test run
    $baseTempPath = if ($envType.IsCI) {
        if ($envType.IsWindows) { $env:TEMP } else { '/tmp' }
    }
    else {
        Join-Path $moduleRoot "Temp"
    }
    $testRoot = Join-Path $baseTempPath "WMR-Tests-$SuiteName-$SessionId"
    New-Item -Path $testRoot -ItemType Directory -Force | Out-Null
    Write-Verbose "✅ Initialized isolated test root: $testRoot"

    # Define standard paths within the isolated root
    $testPaths = @{
        TestRoot    = $testRoot
        TestRestore = Join-Path $testRoot "test-restore"
        TestBackup  = Join-Path $testRoot "test-backup"
        Temp        = Join-Path $testRoot "temp"
        TestState   = Join-Path $testRoot "test-state"
        Logs        = Join-Path $testRoot "logs"
    }

    # Create all standard directories
    $testPaths.Values | ForEach-Object {
        if (-not (Test-Path $_)) {
            New-Item -Path $_ -ItemType Directory -Force | Out-Null
        }
    }

    # Load general test utilities for all environments
    $utilityPath = Join-Path $moduleRoot "tests/utilities/Test-Utilities.ps1"
    if (Test-Path $utilityPath) {
        . $utilityPath
        Write-Verbose "Loaded general test utilities from: $utilityPath"
    }

    # --- Suite-specific setup ---
    switch ($SuiteName) {
        'Unit' {
            # Unit tests should have NO file system or registry mocks.
            # They should be pure logic tests.
            Write-Verbose "🔧 Initializing Unit Test environment. (Minimal setup)"
        }
        'FileOps' {
            Write-Verbose "🔧 Initializing File Operations Test environment."
            # FileOps tests get the standard paths, but no complex mocks.
        }
        'Integration' {
            Write-Verbose "🔧 Initializing Integration Test environment."
            # Load mocks for external services, but not a full virtual file system.
            . (Join-Path $moduleRoot "tests/utilities/Mock-Utilities.ps1")
        }
        'E2E' {
            Write-Verbose "🔧 Initializing End-to-End Test environment."
            # E2E tests get the full mock infrastructure.
            . (Join-Path $moduleRoot "tests/utilities/Enhanced-Mock-Infrastructure.ps1")
            if ($envType.IsDocker) {
                . (Join-Path $moduleRoot "tests/utilities/Docker-Path-Mocks.ps1")
            }
        }
        'Windows' {
            Write-Verbose "🔧 Initializing Windows-Only Test environment."
            # Windows tests run against the real system, so minimal mocking is needed.
            # Safety checks should be handled by the test runner itself.
        }
    }

    # Make paths available to the script scope
    $global:TestEnvironment = $testPaths
    Write-Verbose "✅ Test environment '$SuiteName' initialized successfully."
    return $global:TestEnvironment
}

# --- Deprecated Global Variables and Functions ---
# The following are kept for brief backward compatibility but will be removed.

# $script:ModuleRoot = Find-ModuleRoot
# if ($script:IsCICDEnvironment) {
# ... existing logic ...
# } else {
# ... existing logic ...
# }

# function Ensure-TestModules { ... }
# Ensure-TestModules

# Import Test-Utilities for cleanup and helper functions
. (Join-Path $PSScriptRoot "Test-Utilities.ps1")

# Functions are automatically available when dot-sourced
# Export-ModuleMember is not needed since this script is dot-sourced, not imported as a module

<#
.SYNOPSIS
Imports core WindowsMelodyRecovery functions for testing with code coverage support.

.DESCRIPTION
This function loads core WindowsMelodyRecovery functions through the module system
to enable proper code coverage tracking while avoiding TUI dependencies.

.PARAMETER Functions
Array of function names to import. If not specified, imports all core functions.

.PARAMETER SkipTUI
Skip TUI module loading to avoid dependencies. Default is $true.

.EXAMPLE
Import-WmrCoreForTesting -Functions @('Get-WmrFileState', 'Set-WmrFileState')
#>
function Import-WmrCoreForTesting {
    [CmdletBinding()]
    param(
        [string[]]$Functions = @(),
        [bool]$SkipTUI = $true
    )

    # Find the module root
    $moduleRoot = $PSScriptRoot
    while (-not (Test-Path (Join-Path $moduleRoot "WindowsMelodyRecovery.psd1"))) {
        $moduleRoot = Split-Path -Parent $moduleRoot
        if ([string]::IsNullOrEmpty($moduleRoot)) {
            throw "Could not find WindowsMelodyRecovery module root"
        }
    }

    # Ensure TUI dependency is available for module import
    if (-not (Get-Module -Name Microsoft.PowerShell.ConsoleGuiTools -ListAvailable)) {
        Write-Verbose "Installing Microsoft.PowerShell.ConsoleGuiTools for code coverage testing..."
        try {
            Install-Module -Name Microsoft.PowerShell.ConsoleGuiTools -RequiredVersion 0.7.7 -Force -SkipPublisherCheck -Scope CurrentUser -ErrorAction Stop
            Write-Verbose "Successfully installed Microsoft.PowerShell.ConsoleGuiTools"
        }
        catch {
            Write-Warning "Failed to install Microsoft.PowerShell.ConsoleGuiTools: $($_.Exception.Message)"
            throw "Cannot import module without TUI dependency. Please install Microsoft.PowerShell.ConsoleGuiTools manually."
        }
    }

    # Import the full module for code coverage
    try {
        $modulePath = Join-Path $moduleRoot "WindowsMelodyRecovery.psd1"
        Import-Module $modulePath -Force -Global -ErrorAction Stop
        Write-Verbose "Successfully imported WindowsMelodyRecovery module for code coverage"

        # Explicitly load Core functions that may not be exported by the module
        $coreFiles = @(
            "Private\Core\ApplicationState.ps1",
            "Private\Core\FileState.ps1",
            "Private\Core\RegistryState.ps1",
            "Private\Core\EncryptionUtilities.ps1",
            "Private\Core\PathUtilities.ps1",
            "Private\Core\Prerequisites.ps1",
            "Private\Core\AdministrativePrivileges.ps1",
            "Private\Core\Test-WmrAdminPrivilege.ps1"
        )

        foreach ($coreFile in $coreFiles) {
            $coreFilePath = Join-Path $moduleRoot $coreFile
            if (Test-Path $coreFilePath) {
                try {
                    # Load in global scope to ensure functions are available to tests
                    Invoke-Expression ". '$coreFilePath'"
                    Write-Verbose "Successfully loaded core file: $coreFile"
                }
                catch {
                    Write-Warning "Failed to load core file $coreFile`: $($_.Exception.Message)"
                }
            }
        }

        # Verify that the requested functions are available
        if ($Functions.Count -gt 0) {
            foreach ($func in $Functions) {
                if (-not (Get-Command $func -ErrorAction SilentlyContinue)) {
                    Write-Warning "Function $func not found after module import"
                }
            }
        }
    }
    catch {
        throw "Failed to import WindowsMelodyRecovery module: $($_.Exception.Message)"
    }
}







