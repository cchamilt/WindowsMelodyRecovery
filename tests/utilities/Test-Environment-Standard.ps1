#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Standardized Test Environment Management for Windows Melody Recovery

.DESCRIPTION
    Comprehensive test environment management providing consistent setup, cleanup,
    safety validation, and reset functionality across all test categories.

    Features:
    - Consistent directory structure across all test types
    - Enhanced safety checks and validation
    - Comprehensive cleanup with recovery mechanisms
    - Environment isolation and contamination detection
    - Resource management and performance monitoring
    - Cross-platform compatibility (Windows/WSL/Docker)

.NOTES
    This replaces inconsistent environment setup across multiple test runners
    and provides a single source of truth for test environment management.
#>

# Module-level variables
$script:ModuleRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$script:StandardPaths = $null
$script:EnvironmentInitialized = $false
$script:SafetyValidated = $false

# Enhanced test directory configuration
$script:TestConfiguration = @{
    Directories = @{
        # Core test directories
        TestRestore = "test-restore"
        TestBackup = "test-backups"
        TestTemp = "Temp"
        TestResults = "test-results"
        TestMockData = "tests\mock-data"
        TestLogs = "logs"

        # Specialized test directories
        UnitTests = "tests\unit"
        IntegrationTests = "tests\integration"
        FileOperations = "tests\file-operations"
        EndToEnd = "tests\end-to-end"

        # Test isolation directories
        IsolatedTemp = "tests\isolated-temp"
        SafeWorkspace = "tests\safe-workspace"
        TestReports = "test-results\reports"
    }

    SafetyPatterns = @{
        RequiredInPath = @("WindowsMelodyRecovery", "tests", "test-", "Temp")
        ForbiddenPaths = @("C:\Windows", "C:\Program Files", "C:\Users\$env:USERNAME\Desktop", "\System32")
        AllowedRoots = @("test-restore", "test-backups", "tests", "Temp", "logs")
    }

    Environment = @{
        Variables = @{
            "WMR_TEST_MODE" = $true
            "WMR_SAFE_MODE" = $true
            "WMR_LOG_LEVEL" = "Debug"
        }
        Isolation = @{
            MaxMemoryMB = 1024
            MaxProcesses = 50
            TimeoutMinutes = 30
        }
    }
}

function Initialize-StandardTestEnvironment {
    <#
    .SYNOPSIS
        Initializes standardized test environment with comprehensive safety checks.

    .DESCRIPTION
        Creates consistent test environment structure with safety validation,
        resource monitoring, and isolation mechanisms. Supports all test types.

    .PARAMETER TestType
        Type of test environment to initialize (Unit, Integration, FileOperations, EndToEnd, All).

    .PARAMETER Force
        Force recreation of directories even if they exist.

    .PARAMETER IsolationLevel
        Level of environment isolation (None, Basic, Enhanced, Complete).

    .PARAMETER ValidateSafety
        Perform comprehensive safety validation before setup.

    .EXAMPLE
        Initialize-StandardTestEnvironment -TestType "Unit" -IsolationLevel "Basic"
        Initialize-StandardTestEnvironment -TestType "All" -Force -ValidateSafety
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('Unit', 'Integration', 'FileOperations', 'EndToEnd', 'All')]
        [string]$TestType = 'All',

        [switch]$Force,

        [ValidateSet('None', 'Basic', 'Enhanced', 'Complete')]
        [string]$IsolationLevel = 'Basic',

        [bool]$ValidateSafety = $true
    )

    Write-Information -MessageData "🔧 Initializing Standardized Test Environment" -InformationAction Continue
    Write-Verbose -Message "   Test Type: $TestType | Isolation: $IsolationLevel | Force: $Force"
    Write-Information -MessageData "" -InformationAction Continue

    # Step 1: Safety validation
    if ($ValidateSafety) {
        $safetyResult = Test-EnvironmentSafety -Strict
        if (-not $safetyResult.IsSafe) {
            throw "Environment safety validation failed: $($safetyResult.Violations -join ', ')"
        }
        Write-Information -MessageData "✅ Environment safety validation passed" -InformationAction Continue
        $script:SafetyValidated = $true
    }

    # Step 2: Clean existing environment if Force
    if ($Force) {
        Write-Warning -Message "🧹 Force cleanup requested - removing existing environment..."
        Remove-StandardTestEnvironment -Confirm:$false
    }

    # Step 3: Create directory structure
    $paths = New-TestDirectoryStructure -TestType $TestType -IsolationLevel $IsolationLevel
    Write-Information -MessageData "✅ Test directory structure created" -InformationAction Continue

    # Step 4: Set environment variables
    Set-TestEnvironmentVariables -IsolationLevel $IsolationLevel
    Write-Information -MessageData "✅ Test environment variables configured" -InformationAction Continue

    # Step 5: Initialize mock data
    if ($TestType -in @('Integration', 'FileOperations', 'EndToEnd', 'All')) {
        Initialize-MockDataEnvironment -TestType $TestType
        Write-Information -MessageData "✅ Mock data environment initialized" -InformationAction Continue
    }

    # Step 6: Setup resource monitoring
    if ($IsolationLevel -in @('Enhanced', 'Complete')) {
        Start-ResourceMonitoring
        Write-Information -MessageData "✅ Resource monitoring started" -InformationAction Continue
    }

    # Step 7: Validate environment integrity
    $validation = Test-EnvironmentIntegrity -Paths $paths
    if (-not $validation.IsValid) {
        throw "Environment integrity validation failed: $($validation.Issues -join ', ')"
    }

    $script:StandardPaths = $paths
    $script:EnvironmentInitialized = $true

    Write-Information -MessageData "" -InformationAction Continue
    Write-Information -MessageData "🎉 Standardized test environment initialized successfully!" -InformationAction Continue
    Write-Verbose -Message "   Root: $($paths.TestRoot)"
    Write-Verbose -Message "   Type: $TestType | Isolation: $IsolationLevel"
    Write-Information -MessageData "" -InformationAction Continue

    return $paths
}

function New-TestDirectoryStructure {
    <#
    .SYNOPSIS
        Creates standardized test directory structure.

    .PARAMETER TestType
        Type of test directories to create.

    .PARAMETER IsolationLevel
        Level of directory isolation to implement.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    [OutputType([hashtable])]
    param(
        [string]$TestType,
        [string]$IsolationLevel
    )

    # Create base paths structure
    $paths = @{
        ModuleRoot = $script:ModuleRoot
        TestRoot = Join-Path $script:ModuleRoot "tests"
    }

    # Add all configured directories
    foreach ($dirName in $script:TestConfiguration.Directories.Keys) {
        $relativePath = $script:TestConfiguration.Directories[$dirName]
        $fullPath = Join-Path $script:ModuleRoot $relativePath
        $paths[$dirName] = $fullPath

        # Create directory if needed
        if (-not (Test-Path $fullPath)) {
            if ($PSCmdlet.ShouldProcess($fullPath, "Create test directory")) {
                New-Item -ItemType Directory -Path $fullPath -Force | Out-Null
                Write-Information -MessageData "  ✓ Created $dirName : $fullPath" -InformationAction Continue
            }
        }
        else {
            Write-Warning -Message "  ✓ Verified $dirName : $fullPath"
        }
    }

    # Create test type specific structures
    switch ($TestType) {
        'Unit' {
            New-UnitTestStructure -BasePaths $paths
        }
        'Integration' {
            New-IntegrationTestStructure -BasePaths $paths
        }
        'FileOperations' {
            New-FileOperationsTestStructure -BasePaths $paths
        }
        'EndToEnd' {
            New-EndToEndTestStructure -BasePaths $paths
        }
        'All' {
            New-UnitTestStructure -BasePaths $paths
            New-IntegrationTestStructure -BasePaths $paths
            New-FileOperationsTestStructure -BasePaths $paths
            New-EndToEndTestStructure -BasePaths $paths
        }
    }

    # Add isolation-specific directories
    if ($IsolationLevel -in @('Enhanced', 'Complete')) {
        New-IsolationDirectories -BasePaths $paths -IsolationLevel $IsolationLevel
    }

    return $paths
}

function New-UnitTestStructure {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param([hashtable]$BasePaths)

    # Unit tests only need minimal structure - no file operations
    $unitPaths = @(
        (Join-Path $BasePaths.TestTemp "unit-mocks"),
        (Join-Path $BasePaths.TestReports "unit")
    )

    foreach ($path in $unitPaths) {
        if (-not (Test-Path $path)) {
            if ($PSCmdlet.ShouldProcess($path, "Create unit test directory")) {
                New-Item -ItemType Directory -Path $path -Force | Out-Null
            }
        }
    }
}

function New-IntegrationTestStructure {
    param([hashtable]$BasePaths)

    # Integration tests need backup/restore structure
    $integrationPaths = @(
        Join-Path $BasePaths.TestRestore "TEST-MACHINE",
        Join-Path $BasePaths.TestRestore "shared",
        Join-Path $BasePaths.TestBackup "TEST-MACHINE",
        Join-Path $BasePaths.TestBackup "shared",
        Join-Path $BasePaths.TestReports "integration"
    )

    # Create component subdirectories
    $components = @('applications', 'system-settings', 'gaming', 'wsl', 'cloud', 'registry', 'files')

    foreach ($basePath in $integrationPaths) {
        foreach ($component in $components) {
            $componentPath = Join-Path $basePath $component
            if (-not (Test-Path $componentPath)) {
                New-Item -ItemType Directory -Path $componentPath -Force | Out-Null
            }
        }
    }
}

function New-FileOperationsTestStructure {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param([hashtable]$BasePaths)

    # File operations need safe test directories with isolation
    $fileOpsPaths = @(
        Join-Path $BasePaths.SafeWorkspace "file-operations",
        Join-Path $BasePaths.IsolatedTemp "file-ops-temp",
        Join-Path $BasePaths.TestReports "file-operations"
    )

    foreach ($path in $fileOpsPaths) {
        if (-not (Test-Path $path)) {
            if ($PSCmdlet.ShouldProcess($path, "Create file operations test directory")) {
                New-Item -ItemType Directory -Path $path -Force | Out-Null
            }
        }
    }
}

function New-EndToEndTestStructure {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param([hashtable]$BasePaths)

    # End-to-end tests need complete environment simulation
    $e2ePaths = @(
        Join-Path $BasePaths.SafeWorkspace "e2e-environments",
        Join-Path $BasePaths.SafeWorkspace "e2e-user-profiles",
        Join-Path $BasePaths.SafeWorkspace "e2e-system-simulation",
        Join-Path $BasePaths.TestReports "end-to-end"
    )

    foreach ($path in $e2ePaths) {
        if (-not (Test-Path $path)) {
            if ($PSCmdlet.ShouldProcess($path, "Create end-to-end test directory")) {
                New-Item -ItemType Directory -Path $path -Force | Out-Null
            }
        }
    }
}

function New-IsolationDirectory {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param([hashtable]$BasePaths, [string]$IsolationLevel)

    $isolationPaths = @(
        Join-Path $BasePaths.IsolatedTemp "process-isolation",
        Join-Path $BasePaths.IsolatedTemp "memory-sandbox",
        Join-Path $BasePaths.IsolatedTemp "resource-limits"
    )

    if ($IsolationLevel -eq 'Complete') {
        $isolationPaths += @(
            Join-Path $BasePaths.IsolatedTemp "network-isolation",
            Join-Path $BasePaths.IsolatedTemp "service-isolation"
        )
    }

    foreach ($path in $isolationPaths) {
        if (-not (Test-Path $path)) {
            if ($PSCmdlet.ShouldProcess($path, "Create isolation directory")) {
                New-Item -ItemType Directory -Path $path -Force | Out-Null
            }
        }
    }
}

function Set-TestEnvironmentVariable {
    <#
    .SYNOPSIS
        Sets standardized test environment variables.

    .PARAMETER IsolationLevel
        Level of environment variable isolation.
    #>
    [CmdletBinding()]
    param([string]$IsolationLevel)

    # Set core test environment variables
    foreach ($var in $script:TestConfiguration.Environment.Variables.Keys) {
        $value = $script:TestConfiguration.Environment.Variables[$var]
        Set-Item -Path "env:$var" -Value $value
    }

    # Set paths to test directories
    if ($script:StandardPaths) {
        $env:WMR_TEST_ROOT = $script:StandardPaths.TestRoot
        $env:WMR_TEST_RESTORE = $script:StandardPaths.TestRestore
        $env:WMR_TEST_BACKUP = $script:StandardPaths.TestBackup
        $env:WMR_TEST_TEMP = $script:StandardPaths.TestTemp
        $env:WMR_TEST_LOGS = $script:StandardPaths.TestLogs
    }

    # Set isolation-specific variables
    if ($IsolationLevel -in @('Enhanced', 'Complete')) {
        $isolation = $script:TestConfiguration.Environment.Isolation
        $env:WMR_MAX_MEMORY_MB = $isolation.MaxMemoryMB
        $env:WMR_MAX_PROCESSES = $isolation.MaxProcesses
        $env:WMR_TIMEOUT_MINUTES = $isolation.TimeoutMinutes
    }
}

function Initialize-MockDataEnvironment {
    <#
    .SYNOPSIS
        Initializes mock data for testing environments.

    .PARAMETER TestType
        Type of test requiring mock data.
    #>
    [CmdletBinding()]
    param([string]$TestType)

    $mockDataPath = Join-Path $script:ModuleRoot "tests\mock-data"

    if (-not (Test-Path $mockDataPath)) {
        Write-Warning "Mock data directory not found: $mockDataPath"
        return
    }

    # Copy relevant mock data based on test type
    switch ($TestType) {
        'Integration' {
            Copy-MockDataForIntegration -SourcePath $mockDataPath
        }
        'FileOperations' {
            Copy-MockDataForFileOps -SourcePath $mockDataPath
        }
        'EndToEnd' {
            Copy-MockDataForEndToEnd -SourcePath $mockDataPath
        }
        'All' {
            Copy-MockDataForIntegration -SourcePath $mockDataPath
            Copy-MockDataForFileOps -SourcePath $mockDataPath
            Copy-MockDataForEndToEnd -SourcePath $mockDataPath
        }
    }
}

function Copy-MockDataForIntegration {
    param([string]$SourcePath)

    $destinations = @(
        Join-Path $script:StandardPaths.TestRestore "TEST-MACHINE",
        Join-Path $script:StandardPaths.TestRestore "shared"
    )

    $components = Get-ChildItem -Path $SourcePath -Directory
    foreach ($component in $components) {
        foreach ($dest in $destinations) {
            $targetPath = Join-Path $dest $component.Name
            if (-not (Test-Path $targetPath)) {
                Copy-Item -Path $component.FullName -Destination $targetPath -Recurse -Force
            }
        }
    }
}

function Copy-MockDataForFileOp {
    param([string]$SourcePath)

    $destination = Join-Path $script:StandardPaths.SafeWorkspace "file-operations\mock-data"
    if (-not (Test-Path (Split-Path $destination -Parent))) {
        New-Item -ItemType Directory -Path (Split-Path $destination -Parent) -Force | Out-Null
    }

    Copy-Item -Path $SourcePath -Destination $destination -Recurse -Force
}

function Copy-MockDataForEndToEnd {
    param([string]$SourcePath)

    $destination = Join-Path $script:StandardPaths.SafeWorkspace "e2e-environments\mock-data"
    if (-not (Test-Path (Split-Path $destination -Parent))) {
        New-Item -ItemType Directory -Path (Split-Path $destination -Parent) -Force | Out-Null
    }

    Copy-Item -Path $SourcePath -Destination $destination -Recurse -Force
}

function Test-EnvironmentSafety {
    <#
    .SYNOPSIS
        Performs comprehensive safety validation of test environment.

    .PARAMETER Strict
        Enable strict safety checking with additional validations.

    .RETURNS
        PSObject with IsSafe boolean and Violations array.
    #>
    [CmdletBinding()]
    param([switch]$Strict)

    $safetyResult = @{
        IsSafe = $true
        Violations = @()
        Warnings = @()
    }

    # Check forbidden paths
    foreach ($forbiddenPath in $script:TestConfiguration.SafetyPatterns.ForbiddenPaths) {
        if ($PWD.Path.Contains($forbiddenPath)) {
            $safetyResult.IsSafe = $false
            $safetyResult.Violations += "Current directory contains forbidden path: $forbiddenPath"
        }
    }

    # Check required path patterns
    $hasRequiredPattern = $false
    foreach ($requiredPattern in $script:TestConfiguration.SafetyPatterns.RequiredInPath) {
        if ($script:ModuleRoot.Contains($requiredPattern)) {
            $hasRequiredPattern = $true
            break
        }
    }

    if (-not $hasRequiredPattern) {
        $safetyResult.IsSafe = $false
        $safetyResult.Violations += "Module root does not contain required path patterns"
    }

    # Check for production indicators (strict mode)
    if ($Strict) {
        $productionIndicators = @(
            { Test-Path "C:\Program Files\WindowsMelodyRecovery" },
            { Test-Path "C:\ProgramData\WindowsMelodyRecovery" },
            { $env:USERPROFILE -eq "C:\Users\$env:USERNAME" -and -not $env:WMR_ALLOW_TEST_ON_PRODUCTION }
        )

        foreach ($check in $productionIndicators) {
            if (& $check) {
                $safetyResult.Warnings += "Production environment detected - ensure WMR_ALLOW_TEST_ON_PRODUCTION is set"
            }
        }
    }

    # Check available disk space
    $testDrive = (Get-Item $script:ModuleRoot).PSDrive
    $freeSpaceGB = (Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$($testDrive.Name):'" | Select-Object -ExpandProperty FreeSpace) / 1GB

    if ($freeSpaceGB -lt 1) {
        $safetyResult.IsSafe = $false
        $safetyResult.Violations += "Insufficient disk space for test environment (< 1GB free)"
    }
    elseif ($freeSpaceGB -lt 5) {
        $safetyResult.Warnings += "Low disk space for test environment ($([math]::Round($freeSpaceGB, 1))GB free)"
    }

    return $safetyResult
}

function Test-EnvironmentIntegrity {
    <#
    .SYNOPSIS
        Validates the integrity of the test environment setup.

    .PARAMETER Paths
        Hashtable of paths to validate.

    .RETURNS
        PSObject with IsValid boolean and Issues array.
    #>
    [CmdletBinding()]
    param([hashtable]$Paths)

    $validation = @{
        IsValid = $true
        Issues = @()
        Verified = @()
    }

    # Validate all paths exist and are accessible
    foreach ($pathName in $Paths.Keys) {
        $path = $Paths[$pathName]

        if (-not (Test-Path $path)) {
            $validation.IsValid = $false
            $validation.Issues += "Missing path: $pathName ($path)"
        }
        else {
            # Test read/write access
            try {
                $testFile = Join-Path $path "test-access-$(Get-Random).tmp"
                "test" | Out-File -FilePath $testFile -ErrorAction Stop
                Remove-Item -Path $testFile -Force -Confirm:$false -ErrorAction Stop
                $validation.Verified += $pathName
            }
            catch {
                $validation.IsValid = $false
                $validation.Issues += "No write access to: $pathName ($path)"
            }
        }
    }

    # Validate environment variables
    $requiredVars = @("WMR_TEST_MODE", "WMR_SAFE_MODE")
    foreach ($var in $requiredVars) {
        if (-not (Get-Item "env:$var" -ErrorAction SilentlyContinue)) {
            $validation.IsValid = $false
            $validation.Issues += "Missing environment variable: $var"
        }
    }

    return $validation
}

function Start-ResourceMonitoring {
    <#
    .SYNOPSIS
        Starts resource monitoring for test environment.
    #>
    [CmdletBinding()]
    param()

    # Start a background job to monitor resource usage
    $script:ResourceMonitorJob = Start-Job -ScriptBlock {
        while ($true) {
            try {
                # Check memory usage
                $process = Get-Process -Id $PID -ErrorAction SilentlyContinue
                if ($process -and $process.WorkingSet64 / 1MB -gt $Using:script:TestConfiguration.Environment.Isolation.MaxMemoryMB) {
                    Write-Warning "Test process exceeding memory limit: $([math]::Round($process.WorkingSet64 / 1MB, 1))MB"
                }

                # Check process count
                $processCount = (Get-Process | Where-Object { $_.ProcessName -like "*test*" -or $_.ProcessName -like "*pester*" }).Count
                if ($processCount -gt $Using:script:TestConfiguration.Environment.Isolation.MaxProcesses) {
                    Write-Warning "Test process count exceeding limit: $processCount"
                }

                Start-Sleep -Seconds 30
            }
            catch {
                # Silently continue on monitoring errors
                Write-Verbose "Resource monitoring error: $($_.Exception.Message)" -Verbose:$false
            }
        }
    }
}

function Stop-ResourceMonitoring {
    <#
    .SYNOPSIS
        Stops resource monitoring for test environment.
    #>
    [CmdletBinding()]
    param()

    if ($script:ResourceMonitorJob) {
        Stop-Job $script:ResourceMonitorJob -ErrorAction SilentlyContinue
        Remove-Job $script:ResourceMonitorJob -Force -ErrorAction SilentlyContinue
        $script:ResourceMonitorJob = $null
    }
}

function Remove-StandardTestEnvironment {
    <#
    .SYNOPSIS
        Safely removes standardized test environment with comprehensive cleanup.

    .PARAMETER Confirm
        Prompt for confirmation before removal.

    .PARAMETER PreserveLogs
        Preserve log files during cleanup.

    .PARAMETER GenerateReport
        Generate cleanup report.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [switch]$PreserveLogs,
        [switch]$GenerateReport
    )

    Write-Warning -Message "🧹 Removing Standardized Test Environment"

    if ($Confirm) {
        $response = Read-Host "Are you sure you want to remove the test environment? (y/N)"
        if ($response -ne 'y' -and $response -ne 'Y') {
            Write-Verbose -Message "Cleanup cancelled"
            return
        }
    }

    $cleanupReport = @{
        StartTime = Get-Date
        RemovedPaths = @()
        FailedPaths = @()
        PreservedPaths = @()
    }

    # Stop resource monitoring
    Stop-ResourceMonitoring
    Write-Information -MessageData "✓ Stopped resource monitoring" -InformationAction Continue

    # Clean environment variables
    $testVars = Get-ChildItem -Path env: | Where-Object { $_.Name -like "WMR_TEST*" }
    foreach ($var in $testVars) {
        if ($PSCmdlet.ShouldProcess("env:$($var.Name)", "Remove test environment variable")) {
            Remove-Item -Path "env:$($var.Name)" -ErrorAction SilentlyContinue
        }
    }
    Write-Information -MessageData "✓ Cleaned test environment variables" -InformationAction Continue

    # Remove ONLY temporary/dynamic test directories (NEVER source code directories)
    if ($script:StandardPaths) {
        # SAFE PATHS TO CLEAN: Only dynamically created temporary directories
        $safeToCleanPaths = @("TestRestore", "TestBackup", "TestTemp", "IsolatedTemp", "SafeWorkspace", "TestReports")

        foreach ($pathName in $script:StandardPaths.Keys) {
            $path = $script:StandardPaths[$pathName]

            # Skip logs if preservation requested
            if ($PreserveLogs -and $pathName -like "*Log*") {
                $cleanupReport.PreservedPaths += $path
                continue
            }

            # CRITICAL SAFETY: Only clean temporary directories, NEVER source code directories
            if ($pathName -in $safeToCleanPaths) {
                # Additional safety validation
                if (Test-SafeTestPath -Path $path) {
                    try {
                        if (Test-Path $path) {
                            if ($PSCmdlet.ShouldProcess($path, "Remove test directory")) {
                                Remove-Item -Path $path -Recurse -Force -Confirm:$false -ErrorAction Stop
                                $cleanupReport.RemovedPaths += $path
                                Write-Information -MessageData "  ✓ Removed $pathName : $path" -InformationAction Continue
                            }
                        }
                    }
                    catch {
                        $cleanupReport.FailedPaths += @{ Path = $path; Error = $_.Exception.Message }
                        Write-Warning "Failed to remove $pathName : $_"
                    }
                }
                else {
                    Write-Warning "Skipped unsafe path: $path"
                }
            }
            else {
                # NEVER delete source code directories
                $cleanupReport.PreservedPaths += $path
                Write-Information -MessageData "  ✅ Preserved source directory: $pathName : $path" -InformationAction Continue
            }
        }
    }

    # Reset script state
    $script:StandardPaths = $null
    $script:EnvironmentInitialized = $false
    $script:SafetyValidated = $false

    $cleanupReport.EndTime = Get-Date
    $cleanupReport.Duration = ($cleanupReport.EndTime - $cleanupReport.StartTime).TotalSeconds

    # Generate cleanup report if requested
    if ($GenerateReport) {
        $reportPath = Join-Path $script:ModuleRoot "test-results\reports\cleanup-report-$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').json"
        $cleanupReport | ConvertTo-Json -Depth 10 | Set-Content -Path $reportPath -Encoding UTF8
        Write-Information -MessageData "📄 Cleanup report saved: $reportPath" -InformationAction Continue
    }

    Write-Information -MessageData "" -InformationAction Continue
    Write-Information -MessageData "🎉 Test environment cleanup completed!" -InformationAction Continue
    Write-Verbose -Message "   Removed: $($cleanupReport.RemovedPaths.Count) paths"
    Write-Verbose -Message "   Failed: $($cleanupReport.FailedPaths.Count) paths"
    Write-Verbose -Message "   Duration: $([math]::Round($cleanupReport.Duration, 2))s"
    Write-Information -MessageData "" -InformationAction Continue
}

function Reset-StandardTestEnvironment {
    <#
    .SYNOPSIS
        Resets test environment to clean state.

    .PARAMETER TestType
        Type of test environment to reset.

    .PARAMETER IsolationLevel
        Isolation level for reset environment.
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('Unit', 'Integration', 'FileOperations', 'EndToEnd', 'All')]
        [string]$TestType = 'All',

        [ValidateSet('None', 'Basic', 'Enhanced', 'Complete')]
        [string]$IsolationLevel = 'Basic'
    )

    Write-Information -MessageData "🔄 Resetting Standardized Test Environment" -InformationAction Continue

    # Clean existing environment
    Remove-StandardTestEnvironment -Confirm:$false

    # Wait for cleanup to complete
    Start-Sleep -Seconds 2

    # Reinitialize with same parameters
    Initialize-StandardTestEnvironment -TestType $TestType -IsolationLevel $IsolationLevel -Force

    Write-Information -MessageData "🎉 Test environment reset completed!" -InformationAction Continue
}

function Test-SafeTestPath {
    <#
    .SYNOPSIS
        Enhanced safety validation for test paths.

    .PARAMETER Path
        Path to validate for safety.

    .RETURNS
        Boolean indicating if path is safe for test operations.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    # Basic validation
    if ([string]::IsNullOrWhiteSpace($Path) -or $Path.Length -lt 10) {
        return $false
    }

    # Check against forbidden patterns
    foreach ($forbidden in $script:TestConfiguration.SafetyPatterns.ForbiddenPaths) {
        if ($Path.Contains($forbidden)) {
            return $false
        }
    }

    # Check for allowed root patterns
    $hasAllowedRoot = $false
    foreach ($allowedRoot in $script:TestConfiguration.SafetyPatterns.AllowedRoots) {
        if ($Path.Contains($allowedRoot)) {
            $hasAllowedRoot = $true
            break
        }
    }

    if (-not $hasAllowedRoot) {
        return $false
    }

    # Check required patterns
    $hasRequiredPattern = $false
    foreach ($required in $script:TestConfiguration.SafetyPatterns.RequiredInPath) {
        if ($Path.Contains($required)) {
            $hasRequiredPattern = $true
            break
        }
    }

    return $hasRequiredPattern
}

function Get-StandardTestPath {
    <#
    .SYNOPSIS
        Returns standardized test paths for use in tests.

    .RETURNS
        Hashtable of standardized test paths.
    #>
    [CmdletBinding()]
    param()

    if (-not $script:EnvironmentInitialized) {
        throw "Test environment not initialized. Call Initialize-StandardTestEnvironment first."
    }

    return $script:StandardPaths.Clone()
}

function Get-TestEnvironmentStatus {
    <#
    .SYNOPSIS
        Gets current status of test environment.

    .RETURNS
        PSObject with environment status details.
    #>
    [CmdletBinding()]
    param()

    return @{
        Initialized = $script:EnvironmentInitialized
        SafetyValidated = $script:SafetyValidated
        ResourceMonitoring = ($null -ne $script:ResourceMonitorJob)
        Paths = if ($script:StandardPaths) { $script:StandardPaths.Count } else { 0 }
        EnvironmentVariables = (Get-ChildItem -Path env: | Where-Object { $_.Name -like "WMR_TEST*" }).Count
    }
}

# Functions are available when dot-sourced - no need to export when not a module







