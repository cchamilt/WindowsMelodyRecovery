#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Run File Operation Tests for Windows Melody Recovery

.DESCRIPTION
    Runs tests that perform actual file operations in safe test directories.
    These tests operate ONLY in test-restore, test-backup, and Temp directories.
    Automatically cleans up before and after tests.

.PARAMETER TestName
    Specific test file to run (without .Tests.ps1 extension). If not specified, runs all file operation tests.

.PARAMETER OutputFormat
    Pester output format. Default is 'Detailed'.

.PARAMETER SkipCleanup
    Skip cleanup after tests (useful for debugging).

.EXAMPLE
    .\run-file-operation-tests.ps1
    .\run-file-operation-tests.ps1 -TestName "FileState-FileOperations"
    .\run-file-operation-tests.ps1 -SkipCleanup
#>

[CmdletBinding()]
param(
    [string]$TestName,
    [ValidateSet('None', 'Normal', 'Detailed', 'Diagnostic')]
    [string]$OutputFormat = 'Detailed',
    [switch]$SkipCleanup
)

# Set execution policy for current process to allow unsigned scripts
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

# Import the test environment utilities
. (Join-Path $PSScriptRoot "..\utilities\Test-Environment.ps1")

Write-Host "🗂️  Running File Operation Tests for Windows Melody Recovery" -ForegroundColor Cyan
Write-Host ""

# Reset test environment first
Write-Host "🧹 Resetting test environment..." -ForegroundColor Yellow
$testPaths = Initialize-TestEnvironment -Force
Write-Host "✅ Test environment ready" -ForegroundColor Green
Write-Host ""

# Define the file operation tests
$fileOpTests = @(
    "FileState-FileOperations"
)

# Add any other file operation tests here as they're created
$availableTests = Get-ChildItem -Path "tests/file-operations" -Filter "*.Tests.ps1" | ForEach-Object { 
    $_.BaseName -replace '\.Tests$', '' 
}

if ($availableTests) {
    $fileOpTests = $availableTests
}

# Determine which tests to run
$testsToRun = if ($TestName) {
    if ($TestName -in $fileOpTests) {
        @($TestName)
    } else {
        Write-Warning "Test '$TestName' is not in the file operation tests list. Available: $($fileOpTests -join ', ')"
        return
    }
} else {
    $fileOpTests
}

# Safety check - ensure we're only operating in safe directories
Write-Host "🔒 Safety Check - Verifying test directories..." -ForegroundColor Yellow
$safeDirs = @($testPaths.TestRestore, $testPaths.TestBackup, $testPaths.Temp)
foreach ($dir in $safeDirs) {
    if (-not (Test-SafeTestPath $dir)) {
        Write-Error "SAFETY VIOLATION: Directory '$dir' is not safe for file operations!"
        return
    }
}
Write-Host "✅ All test directories are safe" -ForegroundColor Green
Write-Host ""

# Run the tests
$totalPassed = 0
$totalFailed = 0
$totalTime = 0

foreach ($test in $testsToRun) {
    $testFile = "tests/file-operations/$test.Tests.ps1"
    
    if (-not (Test-Path $testFile)) {
        Write-Warning "Test file not found: $testFile"
        continue
    }
    
    Write-Host "🔍 Running $test file operation tests..." -ForegroundColor Cyan
    
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

# Cleanup unless skipped
if (-not $SkipCleanup) {
    Write-Host "🧹 Cleaning up test directories..." -ForegroundColor Yellow
    Remove-TestEnvironment
    Write-Host "✅ Cleanup complete" -ForegroundColor Green
} else {
    Write-Host "⚠️  Skipping cleanup - test files remain in:" -ForegroundColor Yellow
    Write-Host "  • $($testPaths.TestRestore)" -ForegroundColor Gray
    Write-Host "  • $($testPaths.TestBackup)" -ForegroundColor Gray
    Write-Host "  • $($testPaths.Temp)" -ForegroundColor Gray
}

# Summary
Write-Host ""
Write-Host "📊 File Operation Test Summary:" -ForegroundColor Cyan
Write-Host "  • Total Passed: $totalPassed" -ForegroundColor Green
Write-Host "  • Total Failed: $totalFailed" -ForegroundColor $(if ($totalFailed -eq 0) { "Green" } else { "Red" })
Write-Host "  • Total Time: $([math]::Round($totalTime, 2))s" -ForegroundColor Gray

if ($totalFailed -eq 0) {
    Write-Host ""
    Write-Host "🎉 All file operation tests passed!" -ForegroundColor Green
    exit 0
} else {
    Write-Host ""
    Write-Host "⚠️  Some file operation tests failed. Check the output above for details." -ForegroundColor Yellow
    exit 1
} 