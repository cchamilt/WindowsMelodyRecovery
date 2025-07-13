#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Run Unit Tests for Windows Melody Recovery

.DESCRIPTION
    Runs unit tests using the unified Test-Environment.ps1 that works across:
    - Docker containers (Linux/cross-platform)
    - Windows local development
    - CI/CD environments

.PARAMETER TestName
    Specific test file to run (without .Tests.ps1 extension). If not specified, runs all unit tests.

.PARAMETER OutputFormat
    Pester output format. Default is 'Detailed'.

.PARAMETER GenerateReport
    Generate detailed test reports and coverage data. Default is false.

.EXAMPLE
    .\run-unit-tests.ps1
    .\run-unit-tests.ps1 -TestName "ConfigurationValidation"
    .\run-unit-tests.ps1 -OutputFormat "Normal"
    .\run-unit-tests.ps1 -GenerateReport
#>

[CmdletBinding()]
param(
    [string]$TestName,
    [ValidateSet('None', 'Normal', 'Detailed', 'Diagnostic')]
    [string]$OutputFormat = 'Detailed',
    [switch]$GenerateReport
)

# Set execution policy for current process to allow unsigned scripts
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

# Import the unified test environment library
. (Join-Path $PSScriptRoot "..\utilities\Test-Environment.ps1")

Write-Information -MessageData "🧪 Running Unit Tests for Windows Melody Recovery" -InformationAction Continue

# Initialize a dedicated, isolated environment for this unit test run
Write-Warning -Message "🧹 Initializing isolated unit test environment..."
$testEnvironment = Initialize-TestEnvironment -SuiteName 'Unit'
Write-Information -MessageData "✅ Test environment ready in: $($testEnvironment.TestRoot)" -InformationAction Continue
Write-Information -MessageData "" -InformationAction Continue

# Get all available unit tests
$unitTestsPath = Join-Path $PSScriptRoot "..\unit"
$availableTests = Get-ChildItem -Path $unitTestsPath -Filter "*.Tests.ps1" | ForEach-Object {
    $_.BaseName -replace '\.Tests$', ''
}

Write-Verbose -Message "📋 Available unit tests: $($availableTests.Count)"
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

# Run the tests
$totalPassed = 0
$totalFailed = 0
$totalSkipped = 0
$totalTime = 0

foreach ($test in $testsToRun) {
    $testFile = Join-Path $unitTestsPath "$test.Tests.ps1"

    if (-not (Test-Path $testFile)) {
        Write-Warning "Test file not found: $testFile"
        continue
    }

    Write-Information -MessageData "🔍 Running $test unit tests..." -InformationAction Continue

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
                OutputPath = Join-Path $testResultsDir "unit-test-results.xml"
                OutputFormat = 'NUnitXml'
            }

            $pesterConfig.CodeCoverage = @{
                Enabled = $true
                Path = @(
                    (Join-Path $projectRoot "Public/*.ps1"),
                    (Join-Path $projectRoot "Private/**/*.ps1"),
                    (Join-Path $projectRoot "WindowsMelodyRecovery.psm1")
                )
                OutputPath = Join-Path $coverageDir "unit-coverage.xml"
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
Write-Warning -Message "🧹 Cleaning up test environment..."
Remove-TestEnvironment
Write-Information -MessageData "✅ Cleanup complete." -InformationAction Continue

# Summary
Write-Information -MessageData "" -InformationAction Continue
Write-Information -MessageData "📊 Unit Test Summary:" -InformationAction Continue
Write-Information -MessageData "  • Total Passed: $totalPassed" -InformationAction Continue
Write-Information -MessageData "  • Total Failed: $totalFailed"  -InformationAction Continue
Write-Warning -Message "  • Total Skipped: $totalSkipped"
Write-Verbose -Message "  • Total Time: $([math]::Round($totalTime, 2))s"

if ($totalFailed -eq 0) {
    Write-Information -MessageData "" -InformationAction Continue
    Write-Information -MessageData "🎉 All unit tests passed!" -InformationAction Continue
    exit 0
}
 else {
    Write-Information -MessageData "" -InformationAction Continue
    Write-Warning -Message "⚠️  Some unit tests failed. Check the output above for details."
    exit 1
}








