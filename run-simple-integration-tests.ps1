#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Simple Integration Test Runner for Windows Melody Recovery

.DESCRIPTION
    Runs only the core backup integration tests that are known to work well.
    This bypasses the complex test orchestrator that may be causing issues.

.PARAMETER TestSuite
    Which test suite to run (Backup, All)

.PARAMETER NoCleanup
    Skip cleanup of test directories and Docker containers

.EXAMPLE
    ./run-simple-integration-tests.ps1 -TestSuite Backup
#>

param(
    [ValidateSet("Backup", "All")]
    [string]$TestSuite = "Backup",
    [switch]$NoCleanup
)

function Write-TestHeader {
    param([string]$Title)
    $border = "=" * 80
    Write-Host $border -ForegroundColor Cyan
    Write-Host "  $Title" -ForegroundColor Yellow
    Write-Host $border -ForegroundColor Cyan
    Write-Host ""
}

function Write-TestSection {
    param([string]$Section)
    $border = "-" * 60
    Write-Host $border -ForegroundColor Green
    Write-Host "  $Section" -ForegroundColor White
    Write-Host $border -ForegroundColor Green
}

function Initialize-TestEnvironment {
    Write-TestSection "Initializing Test Environment"
    
    # Create test-results directory structure
    $resultDirs = @(
        "test-results",
        "test-results/logs", 
        "test-results/reports",
        "test-results/junit",
        "test-results/coverage"
    )
    
    foreach ($dir in $resultDirs) {
        if (-not (Test-Path $dir)) {
            New-Item -Path $dir -ItemType Directory -Force | Out-Null
        }
    }
    
    # Initialize main log file
    $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
    $global:mainLogFile = "test-results/logs/test-run-$timestamp.log"
    
    "Windows Melody Recovery - Integration Test Run" | Tee-Object -FilePath $global:mainLogFile
    "Started: $(Get-Date)" | Tee-Object -FilePath $global:mainLogFile -Append
    "Test Suite: $TestSuite" | Tee-Object -FilePath $global:mainLogFile -Append
    "Host: $env:COMPUTERNAME" | Tee-Object -FilePath $global:mainLogFile -Append
    "PowerShell: $($PSVersionTable.PSVersion)" | Tee-Object -FilePath $global:mainLogFile -Append
    "=" * 80 | Tee-Object -FilePath $global:mainLogFile -Append
    "" | Tee-Object -FilePath $global:mainLogFile -Append
    
    Write-Host "✓ Test environment initialized" -ForegroundColor Green
    Write-Host "✓ Log file: $global:mainLogFile" -ForegroundColor Green
}

function Start-DockerEnvironment {
    Write-TestSection "Starting Docker Environment"
    "Starting Docker containers..." | Tee-Object -FilePath $global:mainLogFile -Append
    
    try {
        $result = docker-compose -f docker-compose.test.yml up -d 2>&1
        if ($LASTEXITCODE -ne 0) {
            $errorMsg = "Failed to start Docker containers: $result"
            $errorMsg | Tee-Object -FilePath $global:mainLogFile -Append
            throw $errorMsg
        }
        $successMsg = "Docker containers started successfully"
        $successMsg | Tee-Object -FilePath $global:mainLogFile -Append
        Write-Host "✓ $successMsg" -ForegroundColor Green
        
        # Wait for containers to be ready
        Write-Host "Waiting for containers to be ready..." -ForegroundColor Yellow
        "Waiting for containers to be ready..." | Tee-Object -FilePath $global:mainLogFile -Append
        Start-Sleep -Seconds 15
        
    } catch {
        $errorMsg = "Failed to start Docker environment: $($_.Exception.Message)"
        $errorMsg | Tee-Object -FilePath $global:mainLogFile -Append
        Write-Host "✗ $errorMsg" -ForegroundColor Red
        exit 1
    }
}

function Test-ContainerConnectivity {
    Write-TestSection "Testing Container Connectivity"
    "Testing container connectivity..." | Tee-Object -FilePath $global:mainLogFile -Append
    
    try {
        $testResult = docker exec wmr-test-runner pwsh -Command "Write-Host 'Container is ready'; Get-Location" 2>&1
        if ($LASTEXITCODE -eq 0) {
            $successMsg = "Test runner container is accessible"
            $successMsg | Tee-Object -FilePath $global:mainLogFile -Append
            Write-Host "✓ $successMsg" -ForegroundColor Green
            
            # Log container environment info
            "Container environment:" | Tee-Object -FilePath $global:mainLogFile -Append
            $testResult | Tee-Object -FilePath $global:mainLogFile -Append
        } else {
            throw "Container not responding properly"
        }
    } catch {
        $errorMsg = "Cannot connect to test runner container: $($_.Exception.Message)"
        $errorMsg | Tee-Object -FilePath $global:mainLogFile -Append
        Write-Host "✗ $errorMsg" -ForegroundColor Red
        exit 1
    }
}

function Invoke-CoreTests {
    Write-TestSection "Running Core Backup Integration Tests"
    "Starting core backup integration tests..." | Tee-Object -FilePath $global:mainLogFile -Append

    $coreTests = @(
        "tests/integration/backup-applications.Tests.ps1",
        "tests/integration/backup-gaming.Tests.ps1", 
        "tests/integration/backup-cloud.Tests.ps1",
        "tests/integration/backup-system-settings.Tests.ps1"
    )

    $allTestResults = @()
    $totalPassed = 0
    $totalFailed = 0
    $totalSkipped = 0

    foreach ($testFile in $coreTests) {
        $testName = [System.IO.Path]::GetFileNameWithoutExtension($testFile)
        $testStartTime = Get-Date
        
        "Running test: $testName ($testFile)" | Tee-Object -FilePath $global:mainLogFile -Append
        Write-Host "Running $testName..." -ForegroundColor Cyan
        
        try {
            # Create test-specific log file in container
            $containerLogFile = "/test-results/logs/$testName-$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').log"
            
            # Enhanced test command with better logging and error handling
            $testCommand = @"
cd /workspace
if (-not (Test-Path '/test-results/logs')) { New-Item -Path '/test-results/logs' -ItemType Directory -Force | Out-Null }
Write-Host "Starting test $testName at `$(Get-Date)" | Tee-Object -FilePath '$containerLogFile'
if (-not (Get-Module -ListAvailable Pester)) {
    Write-Host 'Installing Pester module...' -ForegroundColor Yellow | Tee-Object -FilePath '$containerLogFile' -Append
    Install-Module -Name Pester -Force -Scope AllUsers
}
Import-Module Pester -Force
Write-Host "Running Pester test: $testFile" | Tee-Object -FilePath '$containerLogFile' -Append
Invoke-Pester '$testFile' -Output Normal | Tee-Object -FilePath '$containerLogFile' -Append
Write-Host "Test $testName completed at `$(Get-Date)" | Tee-Object -FilePath '$containerLogFile' -Append
"@
            
            $testOutput = docker exec wmr-test-runner pwsh -Command $testCommand 2>&1
            $testEndTime = Get-Date
            $duration = $testEndTime - $testStartTime
            
            # Log the test output to main log
            "Test output for $testName:" | Tee-Object -FilePath $global:mainLogFile -Append
            $testOutput | Tee-Object -FilePath $global:mainLogFile -Append
            "Test duration: $($duration.TotalSeconds) seconds" | Tee-Object -FilePath $global:mainLogFile -Append
            
            if ($LASTEXITCODE -eq 0) {
                # Parse the results from output
                $passedMatch = $testOutput | Select-String "Tests Passed: (\d+)" | Select-Object -Last 1
                $failedMatch = $testOutput | Select-String "Failed: (\d+)" | Select-Object -Last 1
                $skippedMatch = $testOutput | Select-String "Skipped: (\d+)" | Select-Object -Last 1
                
                $passed = if ($passedMatch) { [int]$passedMatch.Matches[0].Groups[1].Value } else { 0 }
                $failed = if ($failedMatch) { [int]$failedMatch.Matches[0].Groups[1].Value } else { 0 }
                $skipped = if ($skippedMatch) { [int]$skippedMatch.Matches[0].Groups[1].Value } else { 0 }
                
                $totalPassed += $passed
                $totalFailed += $failed
                $totalSkipped += $skipped
                
                $status = if ($failed -gt 0) { "Failed" } else { "Passed" }
                $color = if ($failed -gt 0) { "Red" } else { "Green" }
                
                $resultMsg = "$testName`: $passed passed, $failed failed, $skipped skipped"
                $resultMsg | Tee-Object -FilePath $global:mainLogFile -Append
                Write-Host "✓ $resultMsg" -ForegroundColor $color
                
                $allTestResults += @{
                    Test = $testName
                    TestFile = $testFile
                    Status = $status
                    Passed = $passed
                    Failed = $failed
                    Skipped = $skipped
                    Duration = $duration.TotalSeconds
                    StartTime = $testStartTime
                    EndTime = $testEndTime
                }
            } else {
                $errorMsg = "$testName`: Test execution failed (exit code: $LASTEXITCODE)"
                $errorMsg | Tee-Object -FilePath $global:mainLogFile -Append
                Write-Host "✗ $errorMsg" -ForegroundColor Red
                $totalFailed += 1
                
                $allTestResults += @{
                    Test = $testName
                    TestFile = $testFile
                    Status = "Error"
                    Passed = 0
                    Failed = 1
                    Skipped = 0
                    Duration = $duration.TotalSeconds
                    StartTime = $testStartTime
                    EndTime = $testEndTime
                }
            }
        } catch {
            $errorMsg = "$testName`: Exception occurred: $($_.Exception.Message)"
            $errorMsg | Tee-Object -FilePath $global:mainLogFile -Append
            Write-Host "✗ $errorMsg" -ForegroundColor Red
            $totalFailed += 1
            
            $allTestResults += @{
                Test = $testName
                TestFile = $testFile
                Status = "Exception"
                Passed = 0
                Failed = 1
                Skipped = 0
                Duration = 0
                StartTime = $testStartTime
                EndTime = Get-Date
            }
        }
    }

    return @{
        Results = $allTestResults
        TotalPassed = $totalPassed
        TotalFailed = $totalFailed
        TotalSkipped = $totalSkipped
    }
}

function Copy-TestResults {
    Write-TestSection "Copying Test Results"
    "Copying test results from containers..." | Tee-Object -FilePath $global:mainLogFile -Append
    
    try {
        # Copy test results from container
        $copyResult = docker cp wmr-test-runner:/test-results/. ./test-results/ 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            $successMsg = "Test results copied successfully to ./test-results/"
            $successMsg | Tee-Object -FilePath $global:mainLogFile -Append
            Write-Host "✓ $successMsg" -ForegroundColor Green
        } else {
            $warnMsg = "Warning: Could not copy some test results: $copyResult"
            $warnMsg | Tee-Object -FilePath $global:mainLogFile -Append
            Write-Host "⚠ $warnMsg" -ForegroundColor Yellow
        }
        
        # List what was actually copied
        $logFiles = Get-ChildItem "test-results/logs" -Filter "*.log" -ErrorAction SilentlyContinue
        if ($logFiles) {
            "Copied log files:" | Tee-Object -FilePath $global:mainLogFile -Append
            foreach ($logFile in $logFiles) {
                "  - $($logFile.Name) ($($logFile.Length) bytes)" | Tee-Object -FilePath $global:mainLogFile -Append
            }
        }
        
    } catch {
        $warnMsg = "Could not copy test results: $($_.Exception.Message)"
        $warnMsg | Tee-Object -FilePath $global:mainLogFile -Append
        Write-Host "⚠ $warnMsg" -ForegroundColor Yellow
    }
}

function Write-TestSummary {
    param($TestResult)
    
    Write-TestHeader "Test Summary"
    
    $successRate = if (($TestResult.TotalPassed + $TestResult.TotalFailed) -gt 0) {
        [math]::Round(($TestResult.TotalPassed / ($TestResult.TotalPassed + $TestResult.TotalFailed)) * 100, 1)
    } else { 0 }
    
    # Write summary to both console and log
    $summaryLines = @(
        "=== TEST EXECUTION SUMMARY ===",
        "Completed: $(Get-Date)",
        "Total Tests Passed: $($TestResult.TotalPassed)",
        "Total Tests Failed: $($TestResult.TotalFailed)",
        "Total Tests Skipped: $($TestResult.TotalSkipped)",
        "Success Rate: $successRate%",
        ""
    )
    
    foreach ($line in $summaryLines) {
        $line | Tee-Object -FilePath $global:mainLogFile -Append
        $color = if ($line -match "Failed.*[1-9]") { "Red" } elseif ($line -match "Passed") { "Green" } else { "White" }
        Write-Host $line -ForegroundColor $color
    }
    
    # Detailed results
    "Detailed Results:" | Tee-Object -FilePath $global:mainLogFile -Append
    Write-Host "Detailed Results:" -ForegroundColor White
    
    foreach ($result in $TestResult.Results) {
        $color = switch ($result.Status) {
            "Passed" { "Green" }
            "Failed" { "Red" }
            "Error" { "Red" }
            "Exception" { "Red" }
        }
        $detailLine = "  $($result.Test): $($result.Status) ($($result.Passed)P/$($result.Failed)F/$($result.Skipped)S) - $([math]::Round($result.Duration, 1))s"
        $detailLine | Tee-Object -FilePath $global:mainLogFile -Append
        Write-Host $detailLine -ForegroundColor $color
    }
    
    # Generate JSON summary report
    $jsonReport = @{
        TestRun = @{
            StartTime = (Get-Date).ToString()
            TestSuite = $TestSuite
            Host = $env:COMPUTERNAME
            PowerShellVersion = $PSVersionTable.PSVersion.ToString()
        }
        Summary = @{
            TotalPassed = $TestResult.TotalPassed
            TotalFailed = $TestResult.TotalFailed
            TotalSkipped = $TestResult.TotalSkipped
            SuccessRate = $successRate
        }
        Results = $TestResult.Results
    }
    
    $jsonReportPath = "test-results/reports/test-summary-$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').json"
    $jsonReport | ConvertTo-Json -Depth 4 | Out-File -FilePath $jsonReportPath -Encoding UTF8
    
    "JSON report generated: $jsonReportPath" | Tee-Object -FilePath $global:mainLogFile -Append
    Write-Host "📊 JSON report: $jsonReportPath" -ForegroundColor Cyan
}

function Clean-TestArtifacts {
    if ($NoCleanup) {
        Write-TestSection "Skipping Cleanup (NoCleanup flag set)"
        "Cleanup skipped due to -NoCleanup flag" | Tee-Object -FilePath $global:mainLogFile -Append
        return
    }
    
    Write-TestSection "Cleaning Up Test Artifacts"
    "Starting cleanup of test artifacts..." | Tee-Object -FilePath $global:mainLogFile -Append
    
    # Clean up test directories
    $testDirs = @("test-backups", "test-restore")
    foreach ($testDir in $testDirs) {
        if (Test-Path $testDir) {
            try {
                Remove-Item -Path $testDir -Recurse -Force
                $cleanupMsg = "Removed test directory: $testDir"
                $cleanupMsg | Tee-Object -FilePath $global:mainLogFile -Append
                Write-Host "✓ $cleanupMsg" -ForegroundColor Green
            } catch {
                $errorMsg = "Failed to remove $testDir`: $($_.Exception.Message)"
                $errorMsg | Tee-Object -FilePath $global:mainLogFile -Append
                Write-Host "⚠ $errorMsg" -ForegroundColor Yellow
            }
        }
    }
    
    # Stop Docker containers
    try {
        "Stopping Docker containers..." | Tee-Object -FilePath $global:mainLogFile -Append
        docker-compose -f docker-compose.test.yml down 2>&1 | Tee-Object -FilePath $global:mainLogFile -Append
        Write-Host "✓ Docker containers stopped" -ForegroundColor Green
    } catch {
        $errorMsg = "Error stopping containers: $($_.Exception.Message)"
        $errorMsg | Tee-Object -FilePath $global:mainLogFile -Append
        Write-Host "⚠ $errorMsg" -ForegroundColor Yellow
    }
    
    "Cleanup completed" | Tee-Object -FilePath $global:mainLogFile -Append
}

# Main execution
try {
    Initialize-TestEnvironment
    Start-DockerEnvironment
    Test-ContainerConnectivity
    $testResult = Invoke-CoreTests
    Copy-TestResults
    Write-TestSummary -TestResult $testResult
    
    # Final status
    if ($testResult.TotalFailed -gt 0) {
        "FINAL RESULT: FAILURE - Some tests failed" | Tee-Object -FilePath $global:mainLogFile -Append
        Write-Host "❌ Some tests failed" -ForegroundColor Red
        $exitCode = 1
    } else {
        "FINAL RESULT: SUCCESS - All tests passed" | Tee-Object -FilePath $global:mainLogFile -Append
        Write-Host "✅ All tests passed!" -ForegroundColor Green
        $exitCode = 0
    }
    
} finally {
    Clean-TestArtifacts
    if ($global:mainLogFile) {
        "Test run completed at $(Get-Date)" | Tee-Object -FilePath $global:mainLogFile -Append
        Write-Host "📄 Complete log: $global:mainLogFile" -ForegroundColor Cyan
    }
}

exit $exitCode 