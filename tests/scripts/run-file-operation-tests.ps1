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

.PARAMETER GenerateReport
    Generate detailed test reports and coverage data. Default is false.

.EXAMPLE
    .\run-file-operation-tests.ps1
    .\run-file-operation-tests.ps1 -TestName "FileState-FileOperations"
    .\run-file-operation-tests.ps1 -Force  # Run destructive tests locally (dangerous!)
    .\run-file-operation-tests.ps1 -GenerateReport
#>

[CmdletBinding()]
param(
    [string]$TestName,
    [ValidateSet('None', 'Normal', 'Detailed', 'Diagnostic')]
    [string]$OutputFormat = 'Detailed',
    [switch]$SkipCleanup,
    [switch]$Force,
    [switch]$GenerateReport
)

# Set execution policy for current process to allow unsigned scripts (Windows only)
if ($IsWindows) {
    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
}

# Import the unified test environment utilities
. (Join-Path $PSScriptRoot "..\utilities\Test-Environment.ps1")

Write-Information -MessageData "📁 Running File Operation Tests for Windows Melody Recovery" -InformationAction Continue

# Environment Detection and Safety Assessment
$script:IsDockerEnvironment = ($env:DOCKER_TEST -eq 'true') -or ($env:CONTAINER -eq 'true') -or (Test-Path '/.dockerenv')
$script:IsCICDEnvironment = $env:CI -or $env:GITHUB_ACTIONS -or $env:BUILD_BUILDID -or $env:JENKINS_URL
$script:IsWindowsLocal = $IsWindows -and -not $script:IsCICDEnvironment -and -not $script:IsDockerEnvironment

# Show environment information
Write-Warning -Message "🔍 Environment Detection:"
Write-Verbose -Message "  • Platform: $($IsWindows ? 'Windows' : 'Non-Windows')"
Write-Verbose -Message "  • Docker: $($script:IsDockerEnvironment ? 'Yes' : 'No')"
Write-Verbose -Message "  • CI/CD: $($script:IsCICDEnvironment ? 'Yes' : 'No')"
Write-Verbose -Message "  • Local Windows: $($script:IsWindowsLocal ? 'Yes' : 'No')"

# Determine test execution mode
if ($script:IsDockerEnvironment) {
    Write-Information -MessageData "🐳 Mode: Docker Cross-Platform (safe operations with mocking)" -InformationAction Continue
    $script:AllowDestructiveTests = $false
} elseif ($script:IsCICDEnvironment -and $IsWindows) {
    Write-Information -MessageData "🏭 Mode: CI/CD Windows (all operations including destructive)" -InformationAction Continue
    $script:AllowDestructiveTests = $true
} elseif ($script:IsWindowsLocal) {
    if ($Force) {
        Write-Error -Message "⚠️  Mode: Local Windows FORCED (destructive tests enabled - USE WITH CAUTION!)"
        Write-Error -Message "   This may modify your system registry and files!"
        $script:AllowDestructiveTests = $true
    } else {
        Write-Warning -Message "🏠 Mode: Local Windows Safe (destructive tests will be skipped)"
        $script:AllowDestructiveTests = $false
    }
} else {
    Write-Warning -Message "🌐 Mode: Non-Windows (Windows-only tests will be skipped)"
    $script:AllowDestructiveTests = $false
}

# Set environment variables for tests to use
$env:WMR_ALLOW_DESTRUCTIVE_TESTS = $script:AllowDestructiveTests.ToString()
$env:WMR_IS_CICD = $script:IsCICDEnvironment.ToString()
$env:WMR_IS_DOCKER = $script:IsDockerEnvironment.ToString()

Write-Information -MessageData "" -InformationAction Continue

# Initialize test environment using the unified system
Write-Warning -Message "🧹 Initializing test environment..."
$testEnvironment = Initialize-TestEnvironment

# Ensure TestState directory exists for registry and other state tests
if (-not $testEnvironment.TestState) {
    $testEnvironment.TestState = Join-Path $testEnvironment.Temp "TestState"
}
if (-not (Test-Path $testEnvironment.TestState)) {
    New-Item -Path $testEnvironment.TestState -ItemType Directory -Force | Out-Null
    Write-Information -MessageData "  ✓ Created TestState directory: $($testEnvironment.TestState)" -InformationAction Continue
}

Write-Information -MessageData "✅ Test environment ready" -InformationAction Continue
Write-Information -MessageData "" -InformationAction Continue

# Get all available file operation tests
$fileOperationsPath = Join-Path $PSScriptRoot "..\file-operations"
$availableTests = Get-ChildItem -Path $fileOperationsPath -Filter "*.Tests.ps1" | ForEach-Object {
    $_.BaseName -replace '\.Tests$', ''
}

Write-Verbose -Message "📋 Available file operation tests: $($availableTests.Count)"
foreach ($test in $availableTests) {
    Write-Verbose -Message "  • $test"
}
Write-Information -MessageData "" -InformationAction Continue

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
Write-Warning -Message "🔒 Enhanced Safety Check - Verifying test directories..."
$safeDirs = @($testEnvironment.TestRestore, $testEnvironment.TestBackup, $testEnvironment.Temp, $testEnvironment.TestState)
$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

Write-Verbose -Message "Debug: Checking directories:"
foreach ($dir in $safeDirs) {
    Write-Verbose -Message "  • $dir"
}

foreach ($dir in $safeDirs) {
    # ENHANCED SAFETY CHECK: Identify safe path types first
    $isProjectPath = $dir.StartsWith($projectRoot)
    $isUserTempPath = $script:IsCICDEnvironment -and (
        ($IsWindows -and $dir.Contains($env:TEMP) -and $dir.Contains("WindowsMelodyRecovery-Tests")) -or
        (-not $IsWindows -and $dir.StartsWith('/tmp/') -and $dir.Contains("WindowsMelodyRecovery-Tests"))
    )
    # Docker-specific safety check for workspace paths
    $isDockerWorkspacePath = $script:IsDockerEnvironment -and $dir.StartsWith('/workspace/') -and $dir.Contains("Temp")

    # ADDITIONAL CI/CD SAFETY: Allow runner temp directories (GitHub Actions)
    $isRunnerTempPath = $script:IsCICDEnvironment -and $IsWindows -and (
        $dir.StartsWith("C:\Users\RUNNER~1\AppData\Local\Temp\WindowsMelodyRecovery-Tests") -or
        $dir.StartsWith("C:\Users\runner\AppData\Local\Temp\WindowsMelodyRecovery-Tests")
    )

    # Check if this is a safe path
    $isSafePath = $isProjectPath -or $isUserTempPath -or $isDockerWorkspacePath -or $isRunnerTempPath

    # CRITICAL: Check for dangerous C:\ root paths ONLY if not already identified as safe
    if (-not $isSafePath -and $dir.StartsWith("C:\")) {
        # Check for specific dangerous paths
        $isDangerousPath = $dir.StartsWith("C:\Windows") -or
                          $dir.StartsWith("C:\Program Files") -or
                          $dir.StartsWith("C:\ProgramData") -or
                          $dir.StartsWith("C:\System") -or
                          $dir -eq "C:\" -or
                          $dir.StartsWith("C:\$")

        if ($isDangerousPath) {
            Write-Error "🚨 SAFETY VIOLATION: Directory '$dir' attempts to write to dangerous C:\ location!"
            Write-Error "🚨 This is NEVER allowed and indicates a serious path resolution bug!"
            Write-Error "🚨 Project root: '$projectRoot'"
            Write-Error "🚨 All test operations must be within project temp directories or user temp in CI/CD!"
            return
        }
    }

    # Final safety check: ensure path is identified as safe
    if (-not $isSafePath) {
        Write-Error "SAFETY VIOLATION: Directory '$dir' is not within safe test paths!"
        Write-Error "  • Project root: '$projectRoot'"
        Write-Error "  • User temp (CI/CD only): $($script:IsCICDEnvironment)"
        Write-Error "  • Docker workspace: $($script:IsDockerEnvironment)"
        Write-Error "  • Runner temp path: $isRunnerTempPath"
        Write-Error "  • Is CI/CD: $($script:IsCICDEnvironment)"
        Write-Error "  • TEMP env var: $($env:TEMP)"
        return
    }

    # Verify directory exists
    if (-not (Test-Path $dir)) {
        Write-Error "SAFETY VIOLATION: Directory '$dir' does not exist after initialization!"
        return
    }
}

# Additional safety for local Windows without CI/CD
if ($script:IsWindowsLocal -and -not $Force) {
    Write-Warning -Message "🛡️  Local Windows Safety: Destructive tests will be automatically skipped"
    Write-Warning -Message "   (Use -Force to override, but this may modify your system!)"
}

Write-Information -MessageData "✅ All test directories are safe" -InformationAction Continue
Write-Information -MessageData "" -InformationAction Continue

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

    Write-Information -MessageData "🔍 Running $test file operation tests..." -InformationAction Continue

    try {
        $startTime = Get-Date

        # Configure Pester for better output with optional reporting
        $projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

        $pesterConfig = @{
            Run = @{
                Path = $testFile
                PassThru = $true
            }
            Output = @{
                Verbosity = $OutputFormat
            }
        }

        # Add test results and coverage only if GenerateReport is specified
        if ($GenerateReport) {
            $testResultsDir = Join-Path $projectRoot "test-results"
            $coverageDir = Join-Path $testResultsDir "coverage"

            # Ensure test result directories exist
            @($testResultsDir, $coverageDir) | ForEach-Object {
                if (-not (Test-Path $_)) {
                    New-Item -Path $_ -ItemType Directory -Force | Out-Null
                }
            }

            $pesterConfig.TestResult = @{
                Enabled = $true
                OutputPath = Join-Path $testResultsDir "file-operations-test-results.xml"
                OutputFormat = 'NUnitXml'
            }

            $pesterConfig.CodeCoverage = @{
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
            Write-Information -MessageData $statusMsg  -InformationAction Continue
        } else {
            Write-Error -Message "❌ $test tests failed ($($result.FailedCount) failed, $($result.PassedCount) passed, $($result.SkippedCount) skipped, $([math]::Round($testTime, 2))s)"

            # Show failed test details
            if ($result.Failed.Count -gt 0) {
                Write-Error -Message "   Failed tests:"
                foreach ($failedTest in $result.Failed) {
                    Write-Error -Message "     • $($failedTest.Name): $($failedTest.ErrorRecord.Exception.Message)"
                }
            }
        }
    } catch {
        Write-Error -Message "💥 $test tests crashed: $_"
        $totalFailed++
    }

    Write-Information -MessageData "" -InformationAction Continue
}

# Cleanup unless skipped
if (-not $SkipCleanup) {
    Write-Warning -Message "🧹 Cleaning up test directories..."
    Remove-TestEnvironment
    Write-Information -MessageData "✅ Cleanup complete" -InformationAction Continue
} else {
    Write-Warning -Message "⚠️  Skipping cleanup - test files remain in:"
    Write-Verbose -Message "  • $($testEnvironment.TestRestore)"
    Write-Verbose -Message "  • $($testEnvironment.TestBackup)"
    Write-Verbose -Message "  • $($testEnvironment.Temp)"
    Write-Verbose -Message "  • $($testEnvironment.TestState)"
}

# Enhanced Summary
Write-Information -MessageData "" -InformationAction Continue
Write-Information -MessageData "📊 File Operation Test Summary:" -InformationAction Continue
Write-Information -MessageData "  • Total Passed: $totalPassed" -InformationAction Continue
Write-Information -MessageData "  • Total Failed: $totalFailed"  -InformationAction Continue
Write-Warning -Message "  • Total Skipped: $totalSkipped"
Write-Verbose -Message "  • Total Time: $([math]::Round($totalTime, 2))s"
Write-Verbose -Message "  • Environment: $($script:IsDockerEnvironment ? 'Docker' : $script:IsCICDEnvironment ? 'CI/CD' : 'Local')"
Write-Verbose -Message "  • Destructive Tests: $($script:AllowDestructiveTests ? 'Enabled' : 'Disabled')"

if ($totalFailed -eq 0) {
    Write-Information -MessageData "" -InformationAction Continue
    Write-Information -MessageData "🎉 All file operation tests passed!" -InformationAction Continue
    exit 0
} else {
    Write-Information -MessageData "" -InformationAction Continue
    Write-Warning -Message "⚠️  Some file operation tests failed. Check the output above for details."
    exit 1
}







