#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Run Clean Unit Tests for Windows Melody Recovery

.DESCRIPTION
    Runs unit tests that have been cleaned up to use the centralized test environment.
    These tests use standardized test directories and mock data.

.PARAMETER TestName
    Specific test file to run (without .Tests.ps1 extension). If not specified, runs all clean tests.

.PARAMETER OutputFormat
    Pester output format. Default is 'Detailed'.

.EXAMPLE
    .\run-unit-tests.ps1
    .\run-unit-tests.ps1 -TestName "SharedConfiguration"
    .\run-unit-tests.ps1 -OutputFormat "Normal"
#>

[CmdletBinding()]
param(
    [string]$TestName,
    [ValidateSet('None', 'Normal', 'Detailed', 'Diagnostic')]
    [string]$OutputFormat = 'Detailed'
)

# Set execution policy for current process to allow unsigned scripts
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

# Import the test environment utilities
. (Join-Path $PSScriptRoot "..\utilities\Test-Environment-Standard.ps1")

Write-Host "🧪 Running Clean Unit Tests for Windows Melody Recovery" -ForegroundColor Cyan
Write-Host ""

# Reset test environment first
Write-Host "🧹 Resetting test environment..." -ForegroundColor Yellow
$testPaths = Initialize-StandardTestEnvironment -TestType "Unit" -Force
Write-Host "✅ Test environment ready" -ForegroundColor Green
Write-Host ""

# Discover actual unit test files
$unitTestsPath = Join-Path $PSScriptRoot "..\unit"
$allTestFiles = Get-ChildItem -Path $unitTestsPath -Filter "*.Tests.ps1" | Select-Object -ExpandProperty BaseName

# Remove .Tests from the names for easier matching
$availableTests = $allTestFiles | ForEach-Object { $_ -replace '\.Tests$', '' }

Write-Host "📋 Available unit tests: $($availableTests.Count)" -ForegroundColor Gray
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

# Run the tests
$totalPassed = 0
$totalFailed = 0
$totalTime = 0

foreach ($test in $testsToRun) {
    $testFile = Join-Path $unitTestsPath "$test.Tests.ps1"
    
    if (-not (Test-Path $testFile)) {
        Write-Warning "Test file not found: $testFile"
        continue
    }
    
    Write-Host "🔍 Running $test tests..." -ForegroundColor Cyan
    
    try {
        $startTime = Get-Date
        
        # Configure Pester for better output
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
            }
        }
        
        $result = Invoke-Pester -Configuration $pesterConfig
        $endTime = Get-Date
        $testTime = ($endTime - $startTime).TotalSeconds
        
        $totalPassed += $result.PassedCount
        $totalFailed += $result.FailedCount
        $totalTime += $testTime
        
        if ($result.FailedCount -eq 0) {
            Write-Host "✅ $test tests passed ($($result.PassedCount) tests, $([math]::Round($testTime, 2))s)" -ForegroundColor Green
        } else {
            Write-Host "❌ $test tests failed ($($result.FailedCount) failed, $($result.PassedCount) passed, $([math]::Round($testTime, 2))s)" -ForegroundColor Red
            
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

# Summary
Write-Host "📊 Test Summary:" -ForegroundColor Cyan
Write-Host "  • Total Passed: $totalPassed" -ForegroundColor Green
Write-Host "  • Total Failed: $totalFailed" -ForegroundColor $(if ($totalFailed -eq 0) { "Green" } else { "Red" })
Write-Host "  • Total Time: $([math]::Round($totalTime, 2))s" -ForegroundColor Gray

if ($totalFailed -eq 0) {
    Write-Host ""
    Write-Host "🎉 All clean unit tests passed!" -ForegroundColor Green
    exit 0
} else {
    Write-Host ""
    Write-Host "⚠️  Some tests failed. Check the output above for details." -ForegroundColor Yellow
    exit 1
} 
