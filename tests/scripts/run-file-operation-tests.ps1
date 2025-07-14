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

# Import the unified test environment library
. (Join-Path $PSScriptRoot "..\utilities\Test-Environment.ps1")

Write-Information -MessageData "📁 Running File Operation Tests for Windows Melody Recovery" -InformationAction Continue

# Initialize a dedicated, isolated environment for this file operations test run
Write-Warning -Message "🧹 Initializing isolated file operations test environment..."
$testEnvironment = Initialize-TestEnvironment -SuiteName 'FileOps'
Write-Information -MessageData "✅ Test environment ready in: $($testEnvironment.TestRoot)" -InformationAction Continue
Write-Information -MessageData "" -InformationAction Continue

# Environment Detection and Safety Assessment for this specific suite
$envType = Get-EnvironmentType
$allowDestructiveTests = $false
if ($envType.IsDocker) {
    Write-Information -MessageData "🐳 Mode: Docker Cross-Platform (safe operations with mocking)" -InformationAction Continue
}
elseif ($envType.IsCI -and $envType.IsWindows) {
    Write-Information -MessageData "🏭 Mode: CI/CD Windows (all operations including destructive)" -InformationAction Continue
    $allowDestructiveTests = $true
}
elseif ($envType.IsWindows) {
    if ($Force) {
        Write-Error -Message "⚠️  Mode: Local Windows FORCED (destructive tests enabled - USE WITH CAUTION!)"
        $allowDestructiveTests = $true
    }
    else {
        Write-Warning -Message "🏠 Mode: Local Windows Safe (destructive tests will be skipped)"
    }
}
else {
    Write-Warning -Message "🌐 Mode: Non-Windows (Windows-only tests will be skipped)"
}

# Set environment variables for tests to use
$env:WMR_ALLOW_DESTRUCTIVE_TESTS = $allowDestructiveTests.ToString()
$env:WMR_IS_CICD = $envType.IsCI.ToString()
$env:WMR_IS_DOCKER = $envType.IsDocker.ToString()

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
    }
    else {
        Write-Warning "Test '$TestName' not found. Available tests: $($availableTests -join ', ')"
        return
    }
}
else {
    $availableTests
}

# Enhanced Safety check - ensure we're only operating in safe directories
Write-Warning -Message "🔒 Enhanced Safety Check - Verifying test directories..."
$safeDirs = @($testEnvironment.TestRestore, $testEnvironment.TestBackup, $testEnvironment.Temp, $testEnvironment.TestState)
$moduleRoot = Find-ModuleRoot

Write-Verbose -Message "Debug: Checking directories:"
foreach ($dir in $safeDirs) {
    Write-Verbose -Message "  • $dir"
}

foreach ($dir in $safeDirs) {
    # ENHANCED SAFETY CHECK: Identify safe path types first
    $isProjectPath = $dir.StartsWith($moduleRoot)
    $isUserTempPath = $envType.IsCI -and (
        ($IsWindows -and $dir.Contains($env:TEMP) -and ($dir.Contains("WMR-Tests-") -or $dir.Contains("WindowsMelodyRecovery-Tests"))) -or
        (-not $IsWindows -and $dir.StartsWith('/tmp/') -and ($dir.Contains("WMR-Tests-") -or $dir.Contains("WindowsMelodyRecovery-Tests")))
    )
    # Docker-specific safety check for workspace paths
    $isDockerWorkspacePath = $envType.IsDocker -and $dir.StartsWith('/workspace/') -and $dir.Contains("Temp")

    # ADDITIONAL CI/CD SAFETY: Allow runner temp directories (GitHub Actions)
    $isRunnerTempPath = $envType.IsCI -and $IsWindows -and (
        $dir.StartsWith("C:\Users\RUNNER~1\AppData\Local\Temp\WMR-Tests-") -or
        $dir.StartsWith("C:\Users\runner\AppData\Local\Temp\WMR-Tests-") -or
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
            Write-Error "🚨 Project root: '$moduleRoot'"
            Write-Error "🚨 All test operations must be within project temp directories or user temp in CI/CD!"
            return
        }
    }

    # Final safety check: ensure path is identified as safe
    if (-not $isSafePath) {
        Write-Error "SAFETY VIOLATION: Directory '$dir' is not within safe test paths!"
        Write-Error "  • Project root: '$moduleRoot'"
        Write-Error "  • User temp (CI/CD only): $($envType.IsCI)"
        Write-Error "  • Docker workspace: $($envType.IsDocker)"
        Write-Error "  • Runner temp path: $isRunnerTempPath"
        Write-Error "  • Is CI/CD: $($envType.IsCI)"
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
if ($envType.IsWindows -and -not $Force) {
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
        $moduleRoot = Find-ModuleRoot

        $pesterConfig = @{
            Run    = @{
                Path     = $testFile
                PassThru = $true
            }
            Output = @{
                Verbosity = $OutputFormat
            }
        }

        # Add test results and coverage only if GenerateReport is specified
        if ($GenerateReport) {
            $testResultsDir = Join-Path $moduleRoot "test-results"
            $coverageDir = Join-Path $testResultsDir "coverage"
            $logsDir = Join-Path $testResultsDir "logs"

            # Ensure test result directories exist (including logs for CI/CD compatibility)
            @($testResultsDir, $coverageDir, $logsDir) | ForEach-Object {
                if (-not (Test-Path $_)) {
                    New-Item -Path $_ -ItemType Directory -Force | Out-Null
                    Write-Verbose "Created directory: $_"
                }
            }

            # Create a placeholder log file to ensure the logs directory is not empty
            $logPlaceholder = Join-Path $logsDir "file-operations-test-placeholder.log"
            if (-not (Test-Path $logPlaceholder)) {
                "File operations test run at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Out-File -FilePath $logPlaceholder -Encoding UTF8
            }

            $pesterConfig.TestResult = @{
                Enabled      = $true
                OutputPath   = Join-Path $testResultsDir "file-operations-test-results.xml"
                OutputFormat = 'JUnitXml'
            }

            $pesterConfig.CodeCoverage = @{
                Enabled               = $true
                Path                  = @(
                    (Join-Path $moduleRoot "Public/*.ps1"),
                    (Join-Path $moduleRoot "Private/Core/*.ps1"),
                    (Join-Path $moduleRoot "WindowsMelodyRecovery.psm1")
                )
                ExcludePath           = @(
                    (Join-Path $moduleRoot "tests/**/*"),
                    (Join-Path $moduleRoot "Templates/**/*"),
                    (Join-Path $moduleRoot "Private/scripts/**/*"),
                    (Join-Path $moduleRoot "Private/tasks/**/*"),
                    (Join-Path $moduleRoot "Private/setup/**/*"),
                    (Join-Path $moduleRoot "Private/backup/**/*"),
                    (Join-Path $moduleRoot "Private/restore/**/*"),
                    (Join-Path $moduleRoot "TUI/**/*"),
                    (Join-Path $moduleRoot "**/mock-*"),
                    (Join-Path $moduleRoot "**/test-*"),
                    (Join-Path $moduleRoot "example-*"),
                    (Join-Path $moduleRoot "Temp/**/*"),
                    (Join-Path $moduleRoot "logs/**/*")
                )
                OutputPath            = Join-Path $coverageDir "file-operations-coverage.xml"
                OutputFormat          = 'JaCoCo'
                CoveragePercentTarget = 75
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
        }
        else {
            Write-Error -Message "❌ $test tests failed ($($result.FailedCount) failed, $($result.PassedCount) passed, $($result.SkippedCount) skipped, $([math]::Round($testTime, 2))s)"

            # Show failed test details
            if ($result.Failed.Count -gt 0) {
                Write-Error -Message "   Failed tests:"
                foreach ($failedTest in $result.Failed) {
                    Write-Error -Message "     • $($failedTest.Name): $($failedTest.ErrorRecord.Exception.Message)"
                }
            }
        }
    }
    catch {
        Write-Error -Message "💥 $test tests crashed: $_"
        $totalFailed++
    }

    Write-Information -MessageData "" -InformationAction Continue
}

# Cleanup
if (-not $SkipCleanup) {
    Write-Warning -Message "🧹 Cleaning up test environment..."
    Remove-TestEnvironment
    Write-Information -MessageData "✅ Cleanup complete." -InformationAction Continue
}
else {
    Write-Warning -Message "⚠️ Cleanup skipped due to -SkipCleanup flag."
}

# Enhanced Summary
Write-Information -MessageData "" -InformationAction Continue
Write-Information -MessageData "📊 File Operation Test Summary:" -InformationAction Continue
Write-Information -MessageData "  • Total Passed: $totalPassed" -InformationAction Continue
Write-Information -MessageData "  • Total Failed: $totalFailed"  -InformationAction Continue
Write-Warning -Message "  • Total Skipped: $totalSkipped"
Write-Verbose -Message "  • Total Time: $([math]::Round($totalTime, 2))s"
Write-Verbose -Message "  • Environment: $($envType.IsDocker ? 'Docker' : $envType.IsCI ? 'CI/CD' : 'Local')"
Write-Verbose -Message "  • Destructive Tests: $($allowDestructiveTests ? 'Enabled' : 'Disabled')"

if ($totalFailed -eq 0) {
    Write-Information -MessageData "" -InformationAction Continue
    Write-Information -MessageData "🎉 All file operation tests passed!" -InformationAction Continue
    exit 0
}
else {
    Write-Information -MessageData "" -InformationAction Continue
    Write-Warning -Message "⚠️  Some file operation tests failed. Check the output above for details."
    exit 1
}








