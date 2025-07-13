#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Run Integration Tests for Windows Melody Recovery

.DESCRIPTION
    Runs integration tests using either Docker containers or native Windows environment.
    Automatically detects environment and skips Windows-only tests when running in Docker.
    Uses the same environment setup as the successful unit and file-operations tests.

.PARAMETER TestName
    Specific test file to run (without .Tests.ps1 extension). If not specified, runs all integration tests.

.PARAMETER OutputFormat
    Pester output format. Default is 'Detailed'.

.PARAMETER UseDocker
    Force use of Docker environment. If not specified, auto-detects based on environment.

.PARAMETER SkipCleanup
    Skip cleanup after tests (useful for debugging).

.PARAMETER GenerateReport
    Generate detailed test reports.

.EXAMPLE
    .\run-integration-tests.ps1
    .\run-integration-tests.ps1 -TestName "cloud-provider-detection"
    .\run-integration-tests.ps1 -UseDocker
    .\run-integration-tests.ps1 -OutputFormat "Normal"
#>

[CmdletBinding()]
param(
    [string]$TestName,
    [ValidateSet('None', 'Normal', 'Detailed', 'Diagnostic')]
    [string]$OutputFormat = 'Detailed',
    [switch]$SkipCleanup,
    [switch]$GenerateReport
)

# Set execution policy for current process
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

# Import the unified test environment library
. (Join-Path $PSScriptRoot "..\utilities\Test-Environment.ps1")

Write-Information -MessageData "⚙️ Running Integration Tests for Windows Melody Recovery" -InformationAction Continue

# Initialize a dedicated, isolated environment for this integration test run
Write-Warning -Message "🧹 Initializing isolated integration test environment..."
$testEnvironment = Initialize-TestEnvironment -SuiteName 'Integration'
Write-Information -MessageData "✅ Test environment ready in: $($testEnvironment.TestRoot)" -InformationAction Continue
Write-Information -MessageData "" -InformationAction Continue

# Get all available integration tests
$integrationTestsPath = Join-Path $PSScriptRoot "..\integration"
$availableTests = Get-ChildItem -Path $integrationTestsPath -Filter "*.Tests.ps1" | ForEach-Object {
    $_.BaseName -replace '\.Tests$', ''
}

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

foreach ($test in $testsToRun) {
    $testFile = Join-Path $integrationTestsPath "$test.Tests.ps1"

    if (-not (Test-Path $testFile)) {
        Write-Warning "Test file not found: $testFile"
        continue
    }

    Write-Information -MessageData "🔍 Running $test integration tests..." -InformationAction Continue

    try {
        $pesterConfig = @{
            Run    = @{ Path = $testFile }
            Output = @{ Verbosity = $OutputFormat }
        }

        if ($GenerateReport) {
            $pesterConfig.TestResult = @{
                Enabled    = $true
                OutputPath = Join-Path $testEnvironment.Logs "integration-test-results.xml"
            }
        }

        $result = Invoke-Pester -Configuration $pesterConfig -PassThru

        $totalPassed += $result.PassedCount
        $totalFailed += $result.FailedCount
        $totalSkipped += $result.SkippedCount

        if ($result.FailedCount -eq 0) {
            Write-Information -MessageData "✅ $test tests passed." -InformationAction Continue
        }
        else {
            Write-Error -Message "❌ $test tests failed."
        }
    }
    catch {
        Write-Error -Message "💥 $test tests crashed: $_"
        $totalFailed++
    }
}

# Cleanup
if (-not $SkipCleanup) {
    Write-Warning -Message "🧹 Cleaning up test environment..."
    Remove-TestEnvironment
    Write-Information -MessageData "✅ Cleanup complete." -InformationAction Continue
}

# Summary
Write-Information -MessageData "📊 Integration Test Summary:" -InformationAction Continue
Write-Information -MessageData "  • Total Passed: $totalPassed" -InformationAction Continue
Write-Information -MessageData "  • Total Failed: $totalFailed" -InformationAction Continue
Write-Warning -Message "  • Total Skipped: $totalSkipped"

if ($totalFailed -gt 0) {
    exit 1
}
else {
    exit 0
}








