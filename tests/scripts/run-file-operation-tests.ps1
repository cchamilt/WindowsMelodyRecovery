#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Run File Operation Tests for Windows Melody Recovery

.DESCRIPTION
    Runs tests that perform actual file operations in safe test directories.
    These tests operate ONLY in test-restore, test-backup, and Temp directories.
    Uses unified environment setup that works for both Docker and local Windows.
    
    CI/CD Detection:
    - Local Windows: Safe operations only (no destructive registry/system changes)
    - CI/CD Windows: All operations including destructive tests
    - Docker: Cross-platform safe operations with mocking

.PARAMETER TestName
    Specific test file to run (without .Tests.ps1 extension). If not specified, runs all file operation tests.

.PARAMETER OutputFormat
    Pester output format. Default is 'Detailed'.

.PARAMETER SkipCleanup
    Skip cleanup after tests (useful for debugging).

.PARAMETER Force
    Force run destructive tests in local Windows environment (use with caution).

.EXAMPLE
    .\run-file-operation-tests.ps1
    .\run-file-operation-tests.ps1 -TestName "FileState-FileOperations"
    .\run-file-operation-tests.ps1 -Force  # Run destructive tests locally (dangerous!)
#>

[CmdletBinding()]
param(
    [string]$TestName,
    [ValidateSet('None', 'Normal', 'Detailed', 'Diagnostic')]
    [string]$OutputFormat = 'Detailed',
    [switch]$SkipCleanup,
    [switch]$Force
)

# Set execution policy for current process to allow unsigned scripts (Windows only)
if ($IsWindows) {
    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
}

# Import the unified test environment utilities
. (Join-Path $PSScriptRoot "..\utilities\Test-Environment.ps1")

Write-Host "📁 Running File Operation Tests for Windows Melody Recovery" -ForegroundColor Cyan

# Environment Detection and Safety Assessment
$script:IsDockerEnvironment = ($env:DOCKER_TEST -eq 'true') -or ($env:CONTAINER -eq 'true') -or (Test-Path '/.dockerenv')
$script:IsCICDEnvironment = $env:CI -or $env:GITHUB_ACTIONS -or $env:BUILD_BUILDID -or $env:JENKINS_URL
$script:IsWindowsLocal = $IsWindows -and -not $script:IsCICDEnvironment -and -not $script:IsDockerEnvironment

# Show environment information
Write-Host "🔍 Environment Detection:" -ForegroundColor Yellow
Write-Host "  • Platform: $($IsWindows ? 'Windows' : 'Non-Windows')" -ForegroundColor Gray
Write-Host "  • Docker: $($script:IsDockerEnvironment ? 'Yes' : 'No')" -ForegroundColor Gray
Write-Host "  • CI/CD: $($script:IsCICDEnvironment ? 'Yes' : 'No')" -ForegroundColor Gray
Write-Host "  • Local Windows: $($script:IsWindowsLocal ? 'Yes' : 'No')" -ForegroundColor Gray

# Determine test execution mode
if ($script:IsDockerEnvironment) {
    Write-Host "🐳 Mode: Docker Cross-Platform (safe operations with mocking)" -ForegroundColor Cyan
    $script:AllowDestructiveTests = $false
} elseif ($script:IsCICDEnvironment -and $IsWindows) {
    Write-Host "🏭 Mode: CI/CD Windows (all operations including destructive)" -ForegroundColor Green
    $script:AllowDestructiveTests = $true
} elseif ($script:IsWindowsLocal) {
    if ($Force) {
        Write-Host "⚠️  Mode: Local Windows FORCED (destructive tests enabled - USE WITH CAUTION!)" -ForegroundColor Red
        Write-Host "   This may modify your system registry and files!" -ForegroundColor Red
        $script:AllowDestructiveTests = $true
    } else {
        Write-Host "🏠 Mode: Local Windows Safe (destructive tests will be skipped)" -ForegroundColor Yellow
        $script:AllowDestructiveTests = $false
    }
} else {
    Write-Host "🌐 Mode: Non-Windows (Windows-only tests will be skipped)" -ForegroundColor Yellow
    $script:AllowDestructiveTests = $false
}

# Set environment variables for tests to use
$env:WMR_ALLOW_DESTRUCTIVE_TESTS = $script:AllowDestructiveTests.ToString()
$env:WMR_IS_CICD = $script:IsCICDEnvironment.ToString()
$env:WMR_IS_DOCKER = $script:IsDockerEnvironment.ToString()

Write-Host ""

# Initialize test environment using the unified system
Write-Host "🧹 Initializing test environment..." -ForegroundColor Yellow
$testEnvironment = Initialize-TestEnvironment

# Ensure TestState directory exists for registry and other state tests
if (-not $testEnvironment.TestState) {
    $testEnvironment.TestState = Join-Path $testEnvironment.Temp "TestState"
}
if (-not (Test-Path $testEnvironment.TestState)) {
    New-Item -Path $testEnvironment.TestState -ItemType Directory -Force | Out-Null
    Write-Host "  ✓ Created TestState directory: $($testEnvironment.TestState)" -ForegroundColor Green
}

Write-Host "✅ Test environment ready" -ForegroundColor Green
Write-Host ""

# Get all available file operation tests
$fileOperationsPath = Join-Path $PSScriptRoot "..\file-operations"
$availableTests = Get-ChildItem -Path $fileOperationsPath -Filter "*.Tests.ps1" | ForEach-Object { 
    $_.BaseName -replace '\.Tests$', '' 
}

Write-Host "📋 Available file operation tests: $($availableTests.Count)" -ForegroundColor Gray
foreach ($test in $availableTests) {
    Write-Host "  • $test" -ForegroundColor Gray
}
Write-Host ""

# Determine which tests to run
$testsToRun = if ($TestName) {
    if ($TestName -in $availableTests) {
        @($TestName)
    } else {
        Write-Warning "Test '$TestName' not found. Available tests: $($availableTests -join ', ')"
        return
    }
} else {
    $availableTests
}

# Enhanced Safety check - ensure we're only operating in safe directories
Write-Host "🔒 Enhanced Safety Check - Verifying test directories..." -ForegroundColor Yellow
$safeDirs = @($testEnvironment.TestRestore, $testEnvironment.TestBackup, $testEnvironment.Temp, $testEnvironment.TestState)
$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

Write-Host "Debug: Checking directories:" -ForegroundColor Magenta
foreach ($dir in $safeDirs) {
    Write-Host "  • $dir" -ForegroundColor Gray
}

foreach ($dir in $safeDirs) {
    # STRICT SAFETY CHECK: Only allow project paths or temp paths - NEVER C:\ root paths
    $isProjectPath = $dir.StartsWith($projectRoot)
    $isUserTempPath = $script:IsCICDEnvironment -and (
        ($IsWindows -and $dir.Contains($env:TEMP) -and $dir.Contains("WindowsMelodyRecovery-Tests")) -or
        (-not $IsWindows -and $dir.StartsWith('/tmp/') -and $dir.Contains("WindowsMelodyRecovery-Tests"))
    )
    # Docker-specific safety check for workspace paths
    $isDockerWorkspacePath = $script:IsDockerEnvironment -and $dir.StartsWith('/workspace/') -and $dir.Contains("Temp")
    
    # CRITICAL: Check for dangerous C:\ root paths
    if ($dir.StartsWith("C:\") -and -not ($dir.StartsWith($projectRoot))) {
        Write-Error "🚨 SAFETY VIOLATION: Directory '$dir' attempts to write to C:\ root!"
        Write-Error "🚨 This is NEVER allowed and indicates a serious path resolution bug!"
        Write-Error "🚨 Project root: '$projectRoot'"
        Write-Error "🚨 All test operations must be within project temp directories or user temp in CI/CD!"
        return
    }
    
    if (-not ($isProjectPath -or $isUserTempPath -or $isDockerWorkspacePath)) {
        Write-Error "SAFETY VIOLATION: Directory '$dir' is not within safe test paths!"
        Write-Error "  • Project root: '$projectRoot'"
        Write-Error "  • User temp (CI/CD only): $($script:IsCICDEnvironment)"
        Write-Error "  • Docker workspace: $($script:IsDockerEnvironment)"
        return
    }
    
    if (-not (Test-Path $dir)) {
        Write-Error "SAFETY VIOLATION: Directory '$dir' does not exist after initialization!"
        return
    }
}

# Additional safety for local Windows without CI/CD
if ($script:IsWindowsLocal -and -not $Force) {
    Write-Host "🛡️  Local Windows Safety: Destructive tests will be automatically skipped" -ForegroundColor Yellow
    Write-Host "   (Use -Force to override, but this may modify your system!)" -ForegroundColor Yellow
}

Write-Host "✅ All test directories are safe" -ForegroundColor Green
Write-Host ""

# Run the tests
$totalPassed = 0
$totalFailed = 0
$totalSkipped = 0
$totalTime = 0

foreach ($test in $testsToRun) {
    $testFile = Join-Path $fileOperationsPath "$test.Tests.ps1"
    
    if (-not (Test-Path $testFile)) {
        Write-Warning "Test file not found: $testFile"
        continue
    }
    
    Write-Host "🔍 Running $test file operation tests..." -ForegroundColor Cyan
    
    try {
        $startTime = Get-Date
        
        # Configure Pester for better output with proper reporting
        $projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $testResultsDir = Join-Path $projectRoot "test-results"
        $coverageDir = Join-Path $testResultsDir "coverage"
        
        # Ensure test result directories exist
        @($testResultsDir, $coverageDir) | ForEach-Object {
            if (-not (Test-Path $_)) {
                New-Item -Path $_ -ItemType Directory -Force | Out-Null
            }
        }
        
        $pesterConfig = @{
            Run = @{
                Path = $testFile
                PassThru = $true
            }
            Output = @{
                Verbosity = $OutputFormat
            }
            TestResult = @{
                Enabled = $true
                OutputPath = Join-Path $testResultsDir "file-operations-test-results.xml"
                OutputFormat = 'NUnitXml'
            }
            CodeCoverage = @{
                Enabled = $true
                Path = @(
                    (Join-Path $projectRoot "Public/*.ps1"),
                    (Join-Path $projectRoot "Private/**/*.ps1"),
                    (Join-Path $projectRoot "WindowsMelodyRecovery.psm1")
                )
                OutputPath = Join-Path $coverageDir "file-operations-coverage.xml"
                OutputFormat = 'JaCoCo'
                CoveragePercentTarget = 80
            }
        }
        
        $result = Invoke-Pester -Configuration $pesterConfig
        $endTime = Get-Date
        $testTime = ($endTime - $startTime).TotalSeconds
        
        $totalPassed += $result.PassedCount
        $totalFailed += $result.FailedCount
        $totalSkipped += $result.SkippedCount
        $totalTime += $testTime
        
        if ($result.FailedCount -eq 0) {
            $statusMsg = "✅ $test tests passed ($($result.PassedCount) passed"
            if ($result.SkippedCount -gt 0) {
                $statusMsg += ", $($result.SkippedCount) skipped"
            }
            $statusMsg += ", $([math]::Round($testTime, 2))s)"
            Write-Host $statusMsg -ForegroundColor Green
        } else {
            Write-Host "❌ $test tests failed ($($result.FailedCount) failed, $($result.PassedCount) passed, $($result.SkippedCount) skipped, $([math]::Round($testTime, 2))s)" -ForegroundColor Red
            
            # Show failed test details
            if ($result.Failed.Count -gt 0) {
                Write-Host "   Failed tests:" -ForegroundColor Red
                foreach ($failedTest in $result.Failed) {
                    Write-Host "     • $($failedTest.Name): $($failedTest.ErrorRecord.Exception.Message)" -ForegroundColor Red
                }
            }
        }
    } catch {
        Write-Host "💥 $test tests crashed: $_" -ForegroundColor Red
        $totalFailed++
    }
    
    Write-Host ""
}

# Cleanup unless skipped
if (-not $SkipCleanup) {
    Write-Host "🧹 Cleaning up test directories..." -ForegroundColor Yellow
    Remove-TestEnvironment
    Write-Host "✅ Cleanup complete" -ForegroundColor Green
} else {
    Write-Host "⚠️  Skipping cleanup - test files remain in:" -ForegroundColor Yellow
    Write-Host "  • $($testEnvironment.TestRestore)" -ForegroundColor Gray
    Write-Host "  • $($testEnvironment.TestBackup)" -ForegroundColor Gray
    Write-Host "  • $($testEnvironment.Temp)" -ForegroundColor Gray
    Write-Host "  • $($testEnvironment.TestState)" -ForegroundColor Gray
}

# Enhanced Summary
Write-Host ""
Write-Host "📊 File Operation Test Summary:" -ForegroundColor Cyan
Write-Host "  • Total Passed: $totalPassed" -ForegroundColor Green
Write-Host "  • Total Failed: $totalFailed" -ForegroundColor $(if ($totalFailed -eq 0) { "Green" } else { "Red" })
Write-Host "  • Total Skipped: $totalSkipped" -ForegroundColor Yellow
Write-Host "  • Total Time: $([math]::Round($totalTime, 2))s" -ForegroundColor Gray
Write-Host "  • Environment: $($script:IsDockerEnvironment ? 'Docker' : $script:IsCICDEnvironment ? 'CI/CD' : 'Local')" -ForegroundColor Gray
Write-Host "  • Destructive Tests: $($script:AllowDestructiveTests ? 'Enabled' : 'Disabled')" -ForegroundColor Gray

if ($totalFailed -eq 0) {
    Write-Host ""
    Write-Host "🎉 All file operation tests passed!" -ForegroundColor Green
    exit 0
} else {
    Write-Host ""
    Write-Host "⚠️  Some file operation tests failed. Check the output above for details." -ForegroundColor Yellow
    exit 1
} 
