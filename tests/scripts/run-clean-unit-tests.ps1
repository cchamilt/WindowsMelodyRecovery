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
    .\run-clean-unit-tests.ps1
    .\run-clean-unit-tests.ps1 -TestName "SharedConfiguration"
    .\run-clean-unit-tests.ps1 -OutputFormat "Normal"
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
. (Join-Path $PSScriptRoot "..\utilities\Test-Environment.ps1")

Write-Host "🧪 Running Clean Unit Tests for Windows Melody Recovery" -ForegroundColor Cyan
Write-Host ""

# Reset test environment first
Write-Host "🧹 Resetting test environment..." -ForegroundColor Yellow
$testPaths = Initialize-TestEnvironment -Force
Write-Host "✅ Test environment ready" -ForegroundColor Green
Write-Host ""

# Define the cleaned-up unit tests (logic only, no file operations)
$cleanTests = @(
    "ApplicationState-Logic",
    "FileState-Logic", 
    "module-tests-Logic",
    "Prerequisites-Logic",
    "RegistryState-Logic",
    "SharedConfiguration-Logic",
    "TemplateModule-Logic",
    "WSL-Logic",
    "EncryptionUtilities",
    "PathUtilities",
    "Windows-Only",
    "Timeout"
)

# Determine which tests to run
$testsToRun = if ($TestName) {
    if ($TestName -in $cleanTests) {
        @($TestName)
    } else {
        Write-Warning "Test '$TestName' is not in the clean tests list. Available: $($cleanTests -join ', ')"
        return
    }
} else {
    $cleanTests
}

# Run the tests
$totalPassed = 0
$totalFailed = 0
$totalTime = 0

foreach ($test in $testsToRun) {
    $testFile = "tests/unit/$test.Tests.ps1"
    
    if (-not (Test-Path $testFile)) {
        Write-Warning "Test file not found: $testFile"
        continue
    }
    
    Write-Host "🔍 Running $test tests..." -ForegroundColor Cyan
    
    try {
        $startTime = Get-Date
        $result = Invoke-Pester -Path $testFile -Output $OutputFormat -PassThru
        $endTime = Get-Date
        $testTime = ($endTime - $startTime).TotalSeconds
        
        $totalPassed += $result.PassedCount
        $totalFailed += $result.FailedCount
        $totalTime += $testTime
        
        if ($result.FailedCount -eq 0) {
            Write-Host "✅ $test tests passed ($($result.PassedCount) tests, $([math]::Round($testTime, 2))s)" -ForegroundColor Green
        } else {
            Write-Host "❌ $test tests failed ($($result.FailedCount) failed, $($result.PassedCount) passed, $([math]::Round($testTime, 2))s)" -ForegroundColor Red
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