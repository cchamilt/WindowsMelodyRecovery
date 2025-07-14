#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Run End-to-End Tests for Windows Melody Recovery

.DESCRIPTION
    Runs end-to-end tests using either Docker containers or native Windows environment.
    Automatically detects environment and skips Windows-only tests when running in Docker.
    Uses the same environment setup as the successful unit and file-operations tests.

.PARAMETER TestName
    Specific test file to run (without .Tests.ps1 extension). If not specified, runs all end-to-end tests.

.PARAMETER OutputFormat
    Pester output format. Default is 'Detailed'.

.PARAMETER UseDocker
    Force use of Docker environment. If not specified, auto-detects based on environment.

.PARAMETER SkipCleanup
    Skip cleanup after tests (useful for debugging).

.PARAMETER Timeout
    Timeout in minutes for end-to-end tests. Default is 15 minutes.

.PARAMETER GenerateReport
    Generate detailed test reports.

.EXAMPLE
    .\run-end-to-end-tests.ps1
    .\run-end-to-end-tests.ps1 -TestName "User-Journey-Tests"
    .\run-end-to-end-tests.ps1 -UseDocker
    .\run-end-to-end-tests.ps1 -Timeout 30
#>

[CmdletBinding()]
param(
    [string]$TestName,
    [ValidateSet('None', 'Normal', 'Detailed', 'Diagnostic')]
    [string]$OutputFormat = 'Detailed',
    [switch]$SkipCleanup,
    [int]$Timeout = 15,
    [switch]$GenerateReport
)

# Set execution policy for current process (Windows only)
if ($IsWindows) {
    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
}

# Import the unified test environment library
. (Join-Path $PSScriptRoot "..\utilities\Test-Environment.ps1")

Write-Information -MessageData "🏁 Running End-to-End Tests for Windows Melody Recovery" -InformationAction Continue

# Initialize a dedicated, isolated environment for this end-to-end test run
Write-Warning -Message "🧹 Initializing isolated end-to-end test environment..."
$testEnvironment = Initialize-TestEnvironment -SuiteName 'E2E'
Write-Information -MessageData "✅ Test environment ready in: $($testEnvironment.TestRoot)" -InformationAction Continue
Write-Information -MessageData "" -InformationAction Continue

# Get all available end-to-end tests
$e2eTestsPath = Join-Path $PSScriptRoot "..\end-to-end"
$availableTests = Get-ChildItem -Path $e2eTestsPath -Filter "*.Tests.ps1" | ForEach-Object {
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

# Run tests with timeout
Write-Information -MessageData "Executing end-to-end tests... (Timeout: $Timeout minutes)" -InformationAction Continue

$pesterConfig = @{
    Run = @{
        Path = $testsToRun | ForEach-Object { Join-Path $e2eTestsPath "$_.Tests.ps1" }
    }
    Output = @{
        Verbosity = $OutputFormat
    }
}

if ($GenerateReport) {
    $pesterConfig.TestResult = @{
        Enabled = $true
        OutputPath = Join-Path $testEnvironment.Logs "e2e-test-results.xml"
        OutputFormat = 'JUnitXml'
    }
}

$job = Start-Job -ScriptBlock {
    param($using:Config)
    Invoke-Pester -Configuration $using:Config
} -ArgumentList $pesterConfig

$timeoutSeconds = $Timeout * 60
$completed = Wait-Job -Job $job -Timeout $timeoutSeconds

$result = $null
if ($completed) {
    $result = Receive-Job -Job $job
    $exitCode = $result.FailedCount -gt 0 ? 1 : 0
}
else {
    Write-Error -Message "✗ End-to-end tests timed out after $Timeout minutes"
    Stop-Job -Job $job
    $exitCode = 1
}

Remove-Job -Job $job -Force

# Cleanup
if (-not $SkipCleanup) {
    Write-Warning -Message "🧹 Cleaning up test environment..."
    Remove-TestEnvironment
    Write-Information -MessageData "✅ Cleanup complete." -InformationAction Continue
}
else {
    Write-Warning "⚠️ Cleanup skipped due to -SkipCleanup flag. Environment is at: $($testEnvironment.TestRoot)"
}

# Summary
if ($result) {
    Write-Information -MessageData "📊 End-to-End Test Summary:" -InformationAction Continue
    Write-Information -MessageData "  • Total Passed: $($result.PassedCount)" -InformationAction Continue
    Write-Information -MessageData "  • Total Failed: $($result.FailedCount)" -InformationAction Continue
    Write-Warning -Message "  • Total Skipped: $($result.SkippedCount)"
}

if ($exitCode -ne 0) {
    Write-Error "End-to-end test run failed or timed out."
}
else {
    Write-Information "🎉 All end-to-end tests passed!" -InformationAction Continue
}

exit $exitCode








