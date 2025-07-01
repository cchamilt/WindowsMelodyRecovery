#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Simplified Test Orchestrator for Windows Melody Recovery Integration Tests

.DESCRIPTION
    A simplified version of the test orchestrator that focuses on core functionality
    without the verbose debugging and complex health checks that can cause hangs.

.PARAMETER TestSuite
    Specific test suite to run (All, Backup, Pester)

.PARAMETER Environment
    Test environment (Docker, Local)

.PARAMETER GenerateReport
    Generate comprehensive test report

.EXAMPLE
    ./test-orchestrator-simple.ps1 -TestSuite Pester -GenerateReport
#>

param(
    [ValidateSet("All", "Pester", "Backup", "WSL", "Cloud")]
    [string]$TestSuite = "Pester",
    
    [ValidateSet("Docker", "Local")]
    [string]$Environment = "Docker",
    
    [switch]$GenerateReport,
    
    [string]$OutputPath = "/test-results"
)

# Import utilities
. /tests/utilities/Test-Utilities.ps1

# Global configuration
$Global:TestConfig = @{
    OutputPath = $OutputPath
    StartTime = Get-Date
    TestResults = @()
    FailedTests = @()
    PassedTests = @()
}

# Logging functions
function Write-TestLog {
    param(
        [string]$Message,
        [string]$Level = "INFO",
        [string]$Component = "TEST"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] [$Component] $Message"
    
    # Write to console
    $color = switch ($Level) {
        "ERROR" { "Red" }
        "WARN" { "Yellow" }
        "SUCCESS" { "Green" }
        "INFO" { "White" }
        default { "Gray" }
    }
    Write-Host $logEntry -ForegroundColor $color
    
    # Write to log file
    $logFile = "$($Global:TestConfig.OutputPath)/logs/test-orchestrator.log"
    $logEntry | Out-File -FilePath $logFile -Append -Encoding UTF8
}

function Write-TestHeader {
    param([string]$Title)
    $border = "=" * 80
    Write-TestLog $border "INFO" "HEADER"
    Write-TestLog "  $Title" "INFO" "HEADER"
    Write-TestLog $border "INFO" "HEADER"
}

function Write-TestSection {
    param([string]$Section)
    $border = "-" * 60
    Write-TestLog $border "INFO" "SECTION"
    Write-TestLog "  $Section" "INFO" "SECTION"
    Write-TestLog $border "INFO" "SECTION"
}

# Initialize test environment with proper logging
function Initialize-TestEnvironment {
    Write-TestSection "Initializing Test Environment"
    
    try {
        # Create required directories
        $testDirs = @(
            "$($Global:TestConfig.OutputPath)/logs",
            "$($Global:TestConfig.OutputPath)/reports",
            "$($Global:TestConfig.OutputPath)/pester"
        )
        
        foreach ($dir in $testDirs) {
            if (-not (Test-Path $dir)) {
                New-Item -Path $dir -ItemType Directory -Force | Out-Null
                Write-TestLog "Created directory: $dir" "SUCCESS" "INIT"
            }
        }
        
        # Initialize log file
        $logFile = "$($Global:TestConfig.OutputPath)/logs/test-orchestrator.log"
        "Test Orchestrator Log - Started at $(Get-Date)" | Out-File -FilePath $logFile -Encoding UTF8
        
        Write-TestLog "Test environment initialized successfully" "SUCCESS" "INIT"
        return $true
        
    } catch {
        Write-TestLog "Failed to initialize test environment: $($_.Exception.Message)" "ERROR" "INIT"
        return $false
    }
}

# Simple container health check without verbose debugging
function Test-BasicContainerHealth {
    Write-TestSection "Basic Container Health Check"
    
    try {
        # Just check if we can execute basic commands in the test runner
        $testCommand = "Get-Location"
        $null = docker exec wmr-test-runner pwsh -Command $testCommand 2>$null
        
        if ($LASTEXITCODE -eq 0) {
            Write-TestLog "Container connectivity verified" "SUCCESS" "HEALTH"
            return $true
        } else {
            Write-TestLog "Container not responding to basic commands" "ERROR" "HEALTH"
            return $false
        }
    } catch {
        Write-TestLog "Container health check failed: $($_.Exception.Message)" "ERROR" "HEALTH"
        return $false
    }
}

# Core Pester test execution
function Invoke-CorePesterTests {
    Write-TestSection "Running Core Pester Tests"
    
    try {
        Set-Location /workspace
        
        # Simple Pester availability check
        $pesterCheck = docker exec wmr-test-runner pwsh -Command "Get-Module -ListAvailable Pester" 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-TestLog "Pester not available in container" "ERROR" "PESTER"
            return $false
        }
        
        Write-TestLog "Pester module available" "SUCCESS" "PESTER"
        
        # Core integration tests that we know work
        $coreTests = @(
            "tests/integration/backup-applications.Tests.ps1",
            "tests/integration/backup-gaming.Tests.ps1",
            "tests/integration/backup-cloud.Tests.ps1",
            "tests/integration/backup-system-settings.Tests.ps1"
        )
        
        $totalPassed = 0
        $totalFailed = 0
        
        foreach ($testFile in $coreTests) {
            $testName = [System.IO.Path]::GetFileNameWithoutExtension($testFile)
            Write-TestLog "Running $testName..." "INFO" "PESTER"
            
            # Create individual log file for this test
            $testLogFile = "$($Global:TestConfig.OutputPath)/logs/$testName.log"
            
            try {
                # Run the test and capture output
                $testOutput = docker exec wmr-test-runner pwsh -Command "cd /workspace && Import-Module Pester -Force && Invoke-Pester $testFile -Output Normal" 2>&1
                
                # Write test output to log file
                $testOutput | Out-File -FilePath $testLogFile -Encoding UTF8
                
                if ($LASTEXITCODE -eq 0) {
                    # Parse results from output
                    $passedMatch = $testOutput | Select-String "Tests Passed: (\d+)" | Select-Object -First 1
                    $failedMatch = $testOutput | Select-String "Failed: (\d+)" | Select-Object -First 1
                    
                    $passed = if ($passedMatch) { [int]$passedMatch.Matches[0].Groups[1].Value } else { 0 }
                    $failed = if ($failedMatch) { [int]$failedMatch.Matches[0].Groups[1].Value } else { 0 }
                    
                    $totalPassed += $passed
                    $totalFailed += $failed
                    
                    if ($failed -gt 0) {
                        Write-TestLog "$testName: $passed passed, $failed failed" "WARN" "PESTER"
                        $Global:TestConfig.FailedTests += $testName
                    } else {
                        Write-TestLog "$testName: $passed passed" "SUCCESS" "PESTER"
                        $Global:TestConfig.PassedTests += $testName
                    }
                    
                    # Add to test results
                    $Global:TestConfig.TestResults += @{
                        Suite = "Pester"
                        Test = $testName
                        Result = if ($failed -gt 0) { "Failed" } else { "Passed" }
                        PassedCount = $passed
                        FailedCount = $failed
                        LogFile = $testLogFile
                    }
                } else {
                    Write-TestLog "$testName: Test execution failed" "ERROR" "PESTER"
                    $totalFailed += 1
                    $Global:TestConfig.FailedTests += $testName
                    
                    $Global:TestConfig.TestResults += @{
                        Suite = "Pester"
                        Test = $testName
                        Result = "Error"
                        PassedCount = 0
                        FailedCount = 1
                        LogFile = $testLogFile
                    }
                }
            } catch {
                Write-TestLog "$testName: Exception occurred: $($_.Exception.Message)" "ERROR" "PESTER"
                $totalFailed += 1
                $Global:TestConfig.FailedTests += $testName
            }
        }
        
        Write-TestLog "Pester tests completed: $totalPassed passed, $totalFailed failed" "INFO" "PESTER"
        return $totalFailed -eq 0
        
    } catch {
        Write-TestLog "Pester test execution failed: $($_.Exception.Message)" "ERROR" "PESTER"
        return $false
    }
}

# Generate simple test report with proper logging paths
function Generate-SimpleTestReport {
    if (-not $GenerateReport) { return }
    
    Write-TestSection "Generating Test Report"
    
    $endTime = Get-Date
    $duration = $endTime - $Global:TestConfig.StartTime
    
    $report = @{
        TestRun = @{
            StartTime = $Global:TestConfig.StartTime
            EndTime = $endTime
            Duration = $duration.ToString()
            Environment = $Environment
            TestSuite = $TestSuite
        }
        Summary = @{
            TotalTests = $Global:TestConfig.TestResults.Count
            PassedTests = $Global:TestConfig.PassedTests.Count
            FailedTests = $Global:TestConfig.FailedTests.Count
            SuccessRate = if ($Global:TestConfig.TestResults.Count -gt 0) { 
                [math]::Round(($Global:TestConfig.PassedTests.Count / $Global:TestConfig.TestResults.Count) * 100, 2) 
            } else { 0 }
        }
        Results = $Global:TestConfig.TestResults
        FailedTests = $Global:TestConfig.FailedTests
        PassedTests = $Global:TestConfig.PassedTests
        LogFiles = @{
            MainLog = "$($Global:TestConfig.OutputPath)/logs/test-orchestrator.log"
            TestLogs = $Global:TestConfig.TestResults | ForEach-Object { $_.LogFile } | Where-Object { $_ }
        }
    }
    
    # Save JSON report
    try {
        $jsonReport = $report | ConvertTo-Json -Depth 10
        $jsonPath = "$($Global:TestConfig.OutputPath)/reports/integration-test-report.json"
        $jsonReport | Out-File -FilePath $jsonPath -Encoding UTF8
        Write-TestLog "JSON report saved: $jsonPath" "SUCCESS" "REPORT"
    } catch {
        Write-TestLog "Failed to save JSON report: $($_.Exception.Message)" "ERROR" "REPORT"
    }
    
    # Generate simple HTML report
    try {
        $htmlContent = @"
<!DOCTYPE html>
<html>
<head>
    <title>Windows Melody Recovery - Test Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background-color: #f0f0f0; padding: 20px; border-radius: 5px; }
        .summary { background-color: #e8f5e8; padding: 15px; margin: 20px 0; border-radius: 5px; }
        .failed { background-color: #ffe8e8; padding: 15px; margin: 20px 0; border-radius: 5px; }
        .passed { color: green; }
        .failed-text { color: red; }
        table { border-collapse: collapse; width: 100%; margin: 20px 0; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #f2f2f2; }
    </style>
</head>
<body>
    <div class="header">
        <h1>Windows Melody Recovery - Test Report</h1>
        <p><strong>Test Suite:</strong> $($report.TestRun.TestSuite)</p>
        <p><strong>Environment:</strong> $($report.TestRun.Environment)</p>
        <p><strong>Duration:</strong> $($report.TestRun.Duration)</p>
        <p><strong>Generated:</strong> $($report.TestRun.EndTime)</p>
    </div>
    
    <div class="summary">
        <h2>Summary</h2>
        <p><strong>Total Tests:</strong> $($report.Summary.TotalTests)</p>
        <p><strong>Passed:</strong> <span class="passed">$($report.Summary.PassedTests)</span></p>
        <p><strong>Failed:</strong> <span class="failed-text">$($report.Summary.FailedTests)</span></p>
        <p><strong>Success Rate:</strong> $($report.Summary.SuccessRate)%</p>
    </div>
    
    <h2>Test Results</h2>
    <table>
        <tr><th>Test</th><th>Result</th><th>Passed</th><th>Failed</th><th>Log File</th></tr>
"@
        
        foreach ($result in $Global:TestConfig.TestResults) {
            $resultClass = if ($result.Result -eq "Passed") { "passed" } else { "failed-text" }
            $logFileName = if ($result.LogFile) { [System.IO.Path]::GetFileName($result.LogFile) } else { "N/A" }
            $htmlContent += @"
        <tr>
            <td>$($result.Test)</td>
            <td class="$resultClass">$($result.Result)</td>
            <td>$($result.PassedCount)</td>
            <td>$($result.FailedCount)</td>
            <td>$logFileName</td>
        </tr>
"@
        }
        
        $htmlContent += @"
    </table>
</body>
</html>
"@
        
        $htmlPath = "$($Global:TestConfig.OutputPath)/reports/integration-test-report.html"
        $htmlContent | Out-File -FilePath $htmlPath -Encoding UTF8
        Write-TestLog "HTML report saved: $htmlPath" "SUCCESS" "REPORT"
        
    } catch {
        Write-TestLog "Failed to save HTML report: $($_.Exception.Message)" "ERROR" "REPORT"
    }
}

# Show summary with log file references
function Show-TestSummary {
    Write-TestHeader "Test Summary"
    
    $endTime = Get-Date
    $duration = $endTime - $Global:TestConfig.StartTime
    
    Write-TestLog "Test Suite: $TestSuite" "INFO" "SUMMARY"
    Write-TestLog "Environment: $Environment" "INFO" "SUMMARY" 
    Write-TestLog "Duration: $duration" "INFO" "SUMMARY"
    Write-TestLog "Total Tests: $($Global:TestConfig.TestResults.Count)" "INFO" "SUMMARY"
    Write-TestLog "Passed: $($Global:TestConfig.PassedTests.Count)" "SUCCESS" "SUMMARY"
    Write-TestLog "Failed: $($Global:TestConfig.FailedTests.Count)" $(if ($Global:TestConfig.FailedTests.Count -gt 0) { "ERROR" } else { "SUCCESS" }) "SUMMARY"
    
    if ($Global:TestConfig.TestResults.Count -gt 0) {
        $successRate = [math]::Round(($Global:TestConfig.PassedTests.Count / $Global:TestConfig.TestResults.Count) * 100, 2)
        Write-TestLog "Success Rate: $successRate%" $(if ($successRate -ge 90) { "SUCCESS" } else { "WARN" }) "SUMMARY"
    }
    
    # List log files
    Write-TestLog "Log files generated:" "INFO" "SUMMARY"
    Write-TestLog "  Main log: $($Global:TestConfig.OutputPath)/logs/test-orchestrator.log" "INFO" "SUMMARY"
    foreach ($result in $Global:TestConfig.TestResults) {
        if ($result.LogFile) {
            Write-TestLog "  $($result.Test): $($result.LogFile)" "INFO" "SUMMARY"
        }
    }
}

# Main execution
try {
    Write-TestHeader "Windows Melody Recovery - Simplified Test Orchestrator"
    
    # Initialize environment first
    if (-not (Initialize-TestEnvironment)) {
        Write-TestLog "Failed to initialize test environment" "ERROR" "MAIN"
        exit 1
    }
    
    # Basic health check for Docker environment
    if ($Environment -eq "Docker") {
        if (-not (Test-BasicContainerHealth)) {
            Write-TestLog "Container health check failed" "ERROR" "MAIN"
            exit 1
        }
    }
    
    # Execute the requested test suite
    $success = $false
    switch ($TestSuite) {
        "Pester" { 
            $success = Invoke-CorePesterTests 
        }
        "All" { 
            $success = Invoke-CorePesterTests 
        }
        default {
            Write-TestLog "Test suite '$TestSuite' not implemented in simplified orchestrator" "WARN" "MAIN"
            $success = $false
        }
    }
    
    # Generate report
    Generate-SimpleTestReport
    
    # Show summary
    Show-TestSummary
    
    # Exit with appropriate code
    if ($success -and $Global:TestConfig.FailedTests.Count -eq 0) {
        Write-TestLog "All tests passed! 🎉" "SUCCESS" "MAIN"
        exit 0
    } else {
        Write-TestLog "Some tests failed. Check the reports and logs for details." "ERROR" "MAIN"
        exit 1
    }
    
} catch {
    Write-TestLog "Test orchestrator failed: $($_.Exception.Message)" "ERROR" "MAIN"
    Write-TestLog $_.ScriptStackTrace "ERROR" "MAIN"
    exit 1
} 