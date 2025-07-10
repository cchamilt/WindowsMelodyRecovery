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

.EXAMPLE
    .\run-unit-tests.ps1
    .\run-unit-tests.ps1 -TestName "ConfigurationValidation"
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

# Import the unified test environment (works for both Docker and Windows)
. (Join-Path $PSScriptRoot "..\utilities\Test-Environment.ps1")

Write-Host "🧪 Running Unit Tests for Windows Melody Recovery" -ForegroundColor Cyan

# Show environment information (auto-detected by Test-Environment.ps1)
Write-Host ""

# Initialize test environment using the unified system
Write-Host "🧹 Initializing test environment..." -ForegroundColor Yellow
$testEnvironment = Initialize-TestEnvironment -Force
Write-Host "✅ Test environment ready" -ForegroundColor Green
Write-Host ""

# Get all available unit tests
$unitTestsPath = Join-Path $PSScriptRoot "..\unit"
$availableTests = Get-ChildItem -Path $unitTestsPath -Filter "*.Tests.ps1" | ForEach-Object { 
    $_.BaseName -replace '\.Tests$', '' 
}

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
$totalSkipped = 0
$totalTime = 0

foreach ($test in $testsToRun) {
    $testFile = Join-Path $unitTestsPath "$test.Tests.ps1"
    
    if (-not (Test-Path $testFile)) {
        Write-Warning "Test file not found: $testFile"
        continue
    }
    
    Write-Host "🔍 Running $test unit tests..." -ForegroundColor Cyan
    
    try {
        $startTime = Get-Date
        
        # Configure Pester for better output (same as Docker tests)
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

# Cleanup
Write-Host "🧹 Cleaning up test environment..." -ForegroundColor Yellow
Remove-TestEnvironment
Write-Host "✅ Cleanup complete" -ForegroundColor Green

# Summary
Write-Host ""
Write-Host "📊 Unit Test Summary:" -ForegroundColor Cyan
Write-Host "  • Total Passed: $totalPassed" -ForegroundColor Green
Write-Host "  • Total Failed: $totalFailed" -ForegroundColor $(if ($totalFailed -eq 0) { "Green" } else { "Red" })
Write-Host "  • Total Skipped: $totalSkipped" -ForegroundColor Yellow
Write-Host "  • Total Time: $([math]::Round($totalTime, 2))s" -ForegroundColor Gray

if ($totalFailed -eq 0) {
    Write-Host ""
    Write-Host "🎉 All unit tests passed!" -ForegroundColor Green
    exit 0
} else {
    Write-Host ""
    Write-Host "⚠️  Some unit tests failed. Check the output above for details." -ForegroundColor Yellow
    exit 1
} 
