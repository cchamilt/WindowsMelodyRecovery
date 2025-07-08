#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Run End-to-End Tests for Windows Melody Recovery

.DESCRIPTION
    Runs comprehensive end-to-end tests that validate complete user workflows.
    These tests simulate real user scenarios from installation to daily usage.

.PARAMETER TestName
    Specific test file to run (without .Tests.ps1 extension). If not specified, runs all end-to-end tests.

.PARAMETER OutputFormat
    Pester output format. Default is 'Detailed'.

.PARAMETER SkipCleanup
    Skip cleanup after tests (useful for debugging).

.PARAMETER Timeout
    Timeout in minutes for end-to-end tests. Default is 15 minutes.

.EXAMPLE
    .\run-end-to-end-tests.ps1
    .\run-end-to-end-tests.ps1 -TestName "User-Journey-Tests"
    .\run-end-to-end-tests.ps1 -Timeout 30 -SkipCleanup
#>

[CmdletBinding()]
param(
    [string]$TestName,
    [ValidateSet('None', 'Normal', 'Detailed', 'Diagnostic')]
    [string]$OutputFormat = 'Detailed',
    [switch]$SkipCleanup,
    [int]$Timeout = 15
)

# Set execution policy for current process to allow unsigned scripts
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

# Import the test environment utilities
. (Join-Path $PSScriptRoot "..\utilities\Test-Environment.ps1")

Write-Host "🎯 Running End-to-End Tests for Windows Melody Recovery" -ForegroundColor Cyan
Write-Host ""

# Safety check - ensure we're not running on a production system
Write-Host "🔒 Performing safety checks..." -ForegroundColor Yellow

# Check for production indicators
$productionIndicators = @(
    { Test-Path "C:\Program Files\WindowsMelodyRecovery" },
    { Test-Path "C:\ProgramData\WindowsMelodyRecovery" },
    { (Get-Process -Name "explorer" -ErrorAction SilentlyContinue) -and $env:USERPROFILE -eq "C:\Users\$env:USERNAME" }
)

$isProduction = $false
foreach ($check in $productionIndicators) {
    if (& $check) {
        $isProduction = $true
        break
    }
}

if ($isProduction -and -not $env:WMR_ALLOW_E2E_ON_PRODUCTION) {
    Write-Error @"
🚨 SAFETY VIOLATION: End-to-end tests detected production environment!

End-to-end tests should only run in isolated test environments because they:
- Create and modify large numbers of files and directories
- Simulate system configurations and user environments
- Perform extensive backup and restore operations

To override this safety check, set environment variable:
`$env:WMR_ALLOW_E2E_ON_PRODUCTION = `$true

Recommended: Run these tests in Docker, CI/CD, or dedicated test VMs.
"@
    exit 1
}

Write-Host "✅ Safety checks passed" -ForegroundColor Green
Write-Host ""

# Reset test environment
Write-Host "🧹 Preparing end-to-end test environment..." -ForegroundColor Yellow
$testPaths = Initialize-TestEnvironment -Force
Write-Host "✅ Test environment ready" -ForegroundColor Green
Write-Host ""

# Discover available end-to-end tests
$endToEndDir = Join-Path $PSScriptRoot "..\end-to-end"
$availableTests = Get-ChildItem -Path $endToEndDir -Filter "*.Tests.ps1" -ErrorAction SilentlyContinue | ForEach-Object { 
    $_.BaseName -replace '\.Tests$', '' 
}

if (-not $availableTests) {
    Write-Warning "No end-to-end tests found in $endToEndDir"
    return
}

Write-Host "📋 Available end-to-end tests:" -ForegroundColor Cyan
foreach ($test in $availableTests) {
    Write-Host "  • $test" -ForegroundColor Gray
}
Write-Host ""

# Determine which tests to run
$testsToRun = if ($TestName) {
    if ($TestName -in $availableTests) {
        @($TestName)
    } else {
        Write-Warning "Test '$TestName' is not in the available tests list. Available: $($availableTests -join ', ')"
        return
    }
} else {
    $availableTests
}

# Create timeout job for safety
$timeoutJob = Start-Job -ScriptBlock {
    param($TimeoutMinutes)
    Start-Sleep -Seconds ($TimeoutMinutes * 60)
    Write-Host "⏰ End-to-end test timeout reached ($TimeoutMinutes minutes)" -ForegroundColor Red
} -ArgumentList $Timeout

Write-Host "⏱️  End-to-end tests will timeout after $Timeout minutes" -ForegroundColor Yellow
Write-Host ""

# Run the tests
$totalPassed = 0
$totalFailed = 0
$totalTime = 0
$testResults = @()

try {
    foreach ($test in $testsToRun) {
        $testFile = Join-Path $endToEndDir "$test.Tests.ps1"
        
        if (-not (Test-Path $testFile)) {
            Write-Warning "Test file not found: $testFile"
            continue
        }
        
        Write-Host "🎯 Running $test end-to-end tests..." -ForegroundColor Cyan
        Write-Host "  Test file: $testFile" -ForegroundColor Gray
        
        # Check if timeout job is still running
        if ($timeoutJob.State -ne "Running") {
            Write-Host "⏰ Test execution stopped due to timeout" -ForegroundColor Red
            break
        }
        
        try {
            $startTime = Get-Date
            
            # Run with timeout protection
            $result = Invoke-Pester -Path $testFile -Output $OutputFormat -PassThru
            
            $endTime = Get-Date
            $testTime = ($endTime - $startTime).TotalSeconds
            
            $testResult = @{
                TestName = $test
                PassedCount = $result.PassedCount
                FailedCount = $result.FailedCount
                Duration = $testTime
                Status = if ($result.FailedCount -eq 0) { "Passed" } else { "Failed" }
            }
            $testResults += $testResult
            
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
            
            $testResult = @{
                TestName = $test
                PassedCount = 0
                FailedCount = 1
                Duration = 0
                Status = "Crashed"
                Error = $_.Exception.Message
            }
            $testResults += $testResult
        }
        
        Write-Host ""
        
        # Memory cleanup between tests
        [System.GC]::Collect()
        [System.GC]::WaitForPendingFinalizers()
    }
} finally {
    # Stop timeout job
    Stop-Job $timeoutJob -ErrorAction SilentlyContinue
    Remove-Job $timeoutJob -ErrorAction SilentlyContinue
}

# Generate detailed test report in project root test-results directory
$projectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$reportsDir = Join-Path $projectRoot "test-results\reports"
if (-not (Test-Path $reportsDir)) {
    New-Item -Path $reportsDir -ItemType Directory -Force | Out-Null
}
$reportPath = Join-Path $reportsDir "EndToEndTestReport.json"
$report = @{
    Timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"
    Environment = @{
        PowerShellVersion = $PSVersionTable.PSVersion.ToString()
        OS = $PSVersionTable.OS
        IsProduction = $isProduction
        TestRoot = $testPaths.TestRoot
    }
    Summary = @{
        TotalTests = $testsToRun.Count
        TotalPassed = $totalPassed
        TotalFailed = $totalFailed
        TotalDuration = $totalTime
        SuccessRate = if ($totalPassed + $totalFailed -gt 0) { 
            [math]::Round(($totalPassed / ($totalPassed + $totalFailed)) * 100, 2) 
        } else { 0 }
    }
    Results = $testResults
}

$report | ConvertTo-Json -Depth 10 | Set-Content -Path $reportPath -Encoding UTF8

# Cleanup unless skipped
if (-not $SkipCleanup) {
    Write-Host "🧹 Cleaning up test environment..." -ForegroundColor Yellow
    Remove-TestEnvironment
    Write-Host "✅ Cleanup complete" -ForegroundColor Green
} else {
    Write-Host "⚠️  Skipping cleanup - test files remain in:" -ForegroundColor Yellow
    Write-Host "  • $($testPaths.TestRoot)" -ForegroundColor Gray
}

# Final summary
Write-Host ""
Write-Host "📊 End-to-End Test Summary:" -ForegroundColor Cyan
Write-Host "  • Tests Run: $($testsToRun.Count)" -ForegroundColor Gray
Write-Host "  • Total Passed: $totalPassed" -ForegroundColor Green
Write-Host "  • Total Failed: $totalFailed" -ForegroundColor $(if ($totalFailed -eq 0) { "Green" } else { "Red" })
Write-Host "  • Total Duration: $([math]::Round($totalTime, 2))s" -ForegroundColor Gray
Write-Host "  • Success Rate: $($report.Summary.SuccessRate)%" -ForegroundColor $(if ($report.Summary.SuccessRate -ge 90) { "Green" } elseif ($report.Summary.SuccessRate -ge 70) { "Yellow" } else { "Red" })
Write-Host "  • Report: $reportPath" -ForegroundColor Cyan

# Individual test breakdown
if ($testResults.Count -gt 1) {
    Write-Host ""
    Write-Host "📋 Individual Test Results:" -ForegroundColor Cyan
    foreach ($result in $testResults) {
        $statusColor = switch ($result.Status) {
            "Passed" { "Green" }
            "Failed" { "Red" }
            "Crashed" { "Magenta" }
            default { "Gray" }
        }
        Write-Host "  • $($result.TestName): $($result.Status) ($($result.PassedCount)P/$($result.FailedCount)F, $([math]::Round($result.Duration, 1))s)" -ForegroundColor $statusColor
    }
}

# Performance analysis
$averageTestTime = if ($testResults.Count -gt 0) { $totalTime / $testResults.Count } else { 0 }
if ($averageTestTime -gt 60) {
    Write-Host ""
    Write-Host "⚠️  Performance Notice: Average test time is $([math]::Round($averageTestTime, 1))s" -ForegroundColor Yellow
    Write-Host "   Consider optimizing slower tests or increasing timeout for complex scenarios." -ForegroundColor Gray
}

# Final result
Write-Host ""
if ($totalFailed -eq 0) {
    Write-Host "🎉 All end-to-end tests passed! User workflows are working correctly." -ForegroundColor Green
    exit 0
} else {
    Write-Host "⚠️  Some end-to-end tests failed. Check the output above for details." -ForegroundColor Yellow
    Write-Host "   This may indicate issues with user workflows or test environment setup." -ForegroundColor Gray
    exit 1
} 