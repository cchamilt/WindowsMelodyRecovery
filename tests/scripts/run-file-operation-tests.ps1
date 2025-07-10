#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Run File Operation Tests for Windows Melody Recovery

.DESCRIPTION
    Runs tests that perform actual file operations in safe test directories.
    These tests operate ONLY in test-restore, test-backup, and Temp directories.
    Uses the same environment setup as the successful Docker tests.

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

# Import the working test environment utilities (same as Docker tests)
. (Join-Path $PSScriptRoot "..\utilities\Test-Environment.ps1")

Write-Host "📁 Running File Operation Tests for Windows Melody Recovery" -ForegroundColor Cyan

# Show environment information
if ($IsWindows) {
    Write-Host "Environment: Windows (all tests will run)" -ForegroundColor Green
} else {
    Write-Host "Environment: Non-Windows (Windows-only tests will be skipped)" -ForegroundColor Yellow
}
Write-Host ""

# Initialize test environment using the working system
Write-Host "🧹 Initializing test environment..." -ForegroundColor Yellow
$testEnvironment = Initialize-TestEnvironment -Force
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

# Safety check - ensure we're only operating in safe directories
Write-Host "🔒 Safety Check - Verifying test directories..." -ForegroundColor Yellow
$safeDirs = @($testEnvironment.TestRestore, $testEnvironment.TestBackup, $testEnvironment.Temp)
foreach ($dir in $safeDirs) {
    if (-not $dir.Contains("WindowsMelodyRecovery")) {
        Write-Error "SAFETY VIOLATION: Directory '$dir' is not in the WindowsMelodyRecovery project!"
        return
    }
    if (-not (Test-Path $dir)) {
        Write-Error "SAFETY VIOLATION: Directory '$dir' does not exist!"
        return
    }
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
}

# Summary
Write-Host ""
Write-Host "📊 File Operation Test Summary:" -ForegroundColor Cyan
Write-Host "  • Total Passed: $totalPassed" -ForegroundColor Green
Write-Host "  • Total Failed: $totalFailed" -ForegroundColor $(if ($totalFailed -eq 0) { "Green" } else { "Red" })
Write-Host "  • Total Skipped: $totalSkipped" -ForegroundColor Yellow
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
