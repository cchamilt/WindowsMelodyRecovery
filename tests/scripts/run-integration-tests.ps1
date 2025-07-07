#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Integration Test Runner for Windows Melody Recovery

.DESCRIPTION
    Runs comprehensive integration tests for Windows Melody Recovery using Docker containers.
    Provides detailed logging, result collection, and proper exit code handling.

.PARAMETER TestSuite
    Which test suite to run (default: All)

.PARAMETER GenerateReport
    Generate detailed test reports

.PARAMETER Parallel
    Run tests in parallel (if supported)

.PARAMETER KeepContainers
    Keep Docker containers running after tests

.PARAMETER NoCleanup
    Skip cleanup of test directories and artifacts

.PARAMETER Clean
    Clean up containers and artifacts before running tests

.EXAMPLE
    ./run-integration-tests.ps1 -TestSuite All
    ./run-integration-tests.ps1 -TestSuite Installation -KeepContainers
#>

param(
    [string]$TestSuite = "All",
    [switch]$GenerateReport,
    [switch]$Parallel,
    [switch]$KeepContainers,
    [switch]$NoCleanup,
    [switch]$Clean
)

# Import centralized Docker management
$dockerUtilsPath = Join-Path $PSScriptRoot ".." "utilities" "Docker-Management.ps1"
if (Test-Path $dockerUtilsPath) {
    . $dockerUtilsPath
} else {
    Write-Host "✗ Docker management utilities not found at: $dockerUtilsPath" -ForegroundColor Red
    exit 1
}

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
    
    # Calculate project root (two levels up from this script)
    $script:projectRoot = (Get-Item $PSScriptRoot).Parent.Parent.FullName
    
    # Create test-results directory structure relative to project root
    $resultDirs = @(
        (Join-Path $script:projectRoot "test-results"),
        (Join-Path $script:projectRoot "test-results/logs"), 
        (Join-Path $script:projectRoot "test-results/reports"),
        (Join-Path $script:projectRoot "test-results/junit"),
        (Join-Path $script:projectRoot "test-results/coverage")
    )
    
    foreach ($dir in $resultDirs) {
        if (-not (Test-Path $dir)) {
            New-Item -Path $dir -ItemType Directory -Force | Out-Null
        }
    }
    
    # Initialize main log file
    $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
    $global:mainLogFile = Join-Path $script:projectRoot "test-results/logs/integration-test-run-$timestamp.log"
    
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

function Start-TestEnvironment {
    Write-TestSection "Starting Test Environment"
    "Starting Docker test environment..." | Tee-Object -FilePath $global:mainLogFile -Append
    
    try {
        # Use centralized Docker management
        $startResult = Initialize-DockerEnvironment
        if (-not $startResult) {
            $errorMsg = "Failed to initialize Docker environment"
            $errorMsg | Tee-Object -FilePath $global:mainLogFile -Append
            throw $errorMsg
        }
        
        $successMsg = "Test environment started successfully"
        $successMsg | Tee-Object -FilePath $global:mainLogFile -Append
        Write-Host "✓ $successMsg" -ForegroundColor Green
        
    } catch {
        $errorMsg = "Failed to start test environment: $($_.Exception.Message)"
        $errorMsg | Tee-Object -FilePath $global:mainLogFile -Append
        Write-Host "✗ $errorMsg" -ForegroundColor Red
        exit 1
    }
}

# Run the integration tests
function Invoke-IntegrationTests {
    Write-TestSection "Running Integration Tests"
    "Running integration tests..." | Tee-Object -FilePath $global:mainLogFile -Append
    
    try {
        # Initialize test directories in container
        Write-Host "Initializing test environment..." -ForegroundColor Cyan
        "Initializing test directories in container..." | Tee-Object -FilePath $global:mainLogFile -Append
        
        docker exec wmr-test-runner pwsh -Command "
            New-Item -Path '/test-results/logs' -ItemType Directory -Force | Out-Null
            New-Item -Path '/test-results/reports' -ItemType Directory -Force | Out-Null
            New-Item -Path '/test-results/coverage' -ItemType Directory -Force | Out-Null
            New-Item -Path '/test-results/junit' -ItemType Directory -Force | Out-Null
            Write-Host '✓ Test directories created'
        " | Tee-Object -FilePath $global:mainLogFile -Append
        
        # Build arguments for the Pester script
        $pesterArgs = "-TestSuite $TestSuite"
        if ($GenerateReport) {
            $pesterArgs += " -GenerateReport"
        }
        
        Write-Host "Executing test suite: $TestSuite" -ForegroundColor Cyan
        "Executing test suite: $TestSuite with args: $pesterArgs" | Tee-Object -FilePath $global:mainLogFile -Append
        
        # Execute the dedicated Pester script in container and capture all output
        $testOutput = docker exec wmr-test-runner pwsh -Command "/workspace/tests/scripts/run-pester-tests.ps1 $pesterArgs" 2>&1
        $testExitCode = $LASTEXITCODE
        
        # Log the complete test output
        "=== TEST OUTPUT ===" | Tee-Object -FilePath $global:mainLogFile -Append
        $testOutput | Tee-Object -FilePath $global:mainLogFile -Append
        "=== END TEST OUTPUT ===" | Tee-Object -FilePath $global:mainLogFile -Append
        "Test exit code: $testExitCode" | Tee-Object -FilePath $global:mainLogFile -Append
        
        # Parse test results from output for summary reporting
        $passedMatch = $testOutput | Select-String "Tests Passed: (\d+)" | Select-Object -Last 1
        $failedMatch = $testOutput | Select-String "Failed: (\d+)" | Select-Object -Last 1
        $skippedMatch = $testOutput | Select-String "Skipped: (\d+)" | Select-Object -Last 1
        
        $passed = if ($passedMatch) { [int]$passedMatch.Matches[0].Groups[1].Value } else { 0 }
        $failed = if ($failedMatch) { [int]$failedMatch.Matches[0].Groups[1].Value } else { 0 }
        $skipped = if ($skippedMatch) { [int]$skippedMatch.Matches[0].Groups[1].Value } else { 0 }
        
        # If parsing failed, check for different output formats
        if ($passed -eq 0 -and $failed -eq 0) {
            # Try alternative parsing patterns
            $altPassedMatch = $testOutput | Select-String "(\d+) passed" | Select-Object -Last 1
            $altFailedMatch = $testOutput | Select-String "(\d+) failed" | Select-Object -Last 1
            
            if ($altPassedMatch) { $passed = [int]$altPassedMatch.Matches[0].Groups[1].Value }
            if ($altFailedMatch) { $failed = [int]$altFailedMatch.Matches[0].Groups[1].Value }
        }
        
        # Generate additional reports if requested
        if ($GenerateReport) {
            Write-Host "📋 Generating additional reports..." -ForegroundColor Cyan
            "Generating additional reports..." | Tee-Object -FilePath $global:mainLogFile -Append
            docker exec wmr-test-runner pwsh /tests/generate-reports.ps1 | Tee-Object -FilePath $global:mainLogFile -Append
        }
        
        # Determine success based on exit code AND parsed results
        $success = $testExitCode -eq 0 -and $failed -eq 0
        
        if ($success) {
            $resultMsg = "✓ All tests passed! ($passed passed, $failed failed, $skipped skipped)"
            $resultMsg | Tee-Object -FilePath $global:mainLogFile -Append
            Write-Host $resultMsg -ForegroundColor Green
        } else {
            $resultMsg = "✗ Some tests failed (exit code: $testExitCode, $passed passed, $failed failed, $skipped skipped)"
            $resultMsg | Tee-Object -FilePath $global:mainLogFile -Append
            Write-Host $resultMsg -ForegroundColor Red
        }
        
        # Return structured result data
        return @{
            ExitCode = $testExitCode
            Success = $success
            Passed = $passed
            Failed = $failed
            Skipped = $skipped
            Output = $testOutput
        }
        
    } catch {
        $errorMsg = "✗ Test execution failed: $($_.Exception.Message)"
        $errorMsg | Tee-Object -FilePath $global:mainLogFile -Append
        Write-Host $errorMsg -ForegroundColor Red
        return @{
            ExitCode = 1
            Success = $false
            Passed = 0
            Failed = 1
            Skipped = 0
            Output = $_.Exception.Message
        }
    }
}

# Copy test results from container
function Copy-TestResults {
    Write-TestSection "Copying Test Results"
    "Copying test results from containers..." | Tee-Object -FilePath $global:mainLogFile -Append
    
    try {
        # Copy results from test-runner container to project root test-results
        $copyResult = docker cp wmr-test-runner:/test-results/. (Join-Path $script:projectRoot "test-results/") 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            $successMsg = "Test results copied successfully to $(Join-Path $script:projectRoot "test-results/")"
            $successMsg | Tee-Object -FilePath $global:mainLogFile -Append
            Write-Host "✓ $successMsg" -ForegroundColor Green
        } else {
            $warnMsg = "Warning: Could not copy some test results: $copyResult"
            $warnMsg | Tee-Object -FilePath $global:mainLogFile -Append
            Write-Host "⚠ $warnMsg" -ForegroundColor Yellow
        }
        
        # List what was actually copied
        $logFiles = Get-ChildItem (Join-Path $script:projectRoot "test-results/logs") -Filter "*.log" -ErrorAction SilentlyContinue
        if ($logFiles) {
            "Copied log files:" | Tee-Object -FilePath $global:mainLogFile -Append
            foreach ($logFile in $logFiles) {
                "  - $($logFile.Name) ($($logFile.Length) bytes)" | Tee-Object -FilePath $global:mainLogFile -Append
            }
        }
        
                 # List available reports
         $reports = Get-ChildItem -Path (Join-Path $script:projectRoot "test-results/reports") -ErrorAction SilentlyContinue
         if ($reports) {
             Write-Host "📊 Available reports:" -ForegroundColor Cyan
             "Available reports:" | Out-File -FilePath $global:mainLogFile -Append -Encoding UTF8
             foreach ($report in $reports) {
                 Write-Host "  - $($report.FullName)" -ForegroundColor White
                 "  - $($report.FullName)" | Out-File -FilePath $global:mainLogFile -Append -Encoding UTF8
             }
         }
        
    } catch {
        $warnMsg = "⚠ Failed to copy test results: $($_.Exception.Message)"
        $warnMsg | Tee-Object -FilePath $global:mainLogFile -Append
        Write-Host $warnMsg -ForegroundColor Yellow
    }
}

# Show container logs for debugging (use centralized utility)
function Show-TestContainerLogs {
    Write-TestSection "Container Logs"
    "Showing container logs for debugging..." | Tee-Object -FilePath $global:mainLogFile -Append
    Show-ContainerLogs -Lines 20 | Tee-Object -FilePath $global:mainLogFile -Append
}

# Cleanup function
function Stop-TestEnvironment {
    if (-not $KeepContainers) {
        Write-TestSection "Stopping Test Environment"
        "Stopping Docker test environment..." | Tee-Object -FilePath $global:mainLogFile -Append
        docker compose -f docker-compose.test.yml down --volumes 2>$null
        Write-Host "✓ Test environment stopped" -ForegroundColor Green
        "Test environment stopped" | Tee-Object -FilePath $global:mainLogFile -Append
    } else {
        Write-Host "🔄 Keeping containers running for debugging" -ForegroundColor Yellow
        "Containers kept running for debugging" | Tee-Object -FilePath $global:mainLogFile -Append
        Write-Host "To stop manually: docker compose -f docker-compose.test.yml down --volumes" -ForegroundColor Cyan
        Write-Host "To view logs: docker compose -f docker-compose.test.yml logs -f" -ForegroundColor Cyan
    }
}

# Cleanup test artifacts function
function Clean-TestArtifacts {
    if ($NoCleanup) {
        Write-Host "🧹 Skipping cleanup due to -NoCleanup flag" -ForegroundColor Yellow
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
                $errorMsg = "Failed to remove ${testDir}: $($_.Exception.Message)"
                $errorMsg | Tee-Object -FilePath $global:mainLogFile -Append
                Write-Host "⚠ $errorMsg" -ForegroundColor Yellow
            }
        }
    }
    
    "Cleanup completed" | Tee-Object -FilePath $global:mainLogFile -Append
    Write-Host "✓ Cleanup completed" -ForegroundColor Green
}

function Write-TestSummary {
    param($TestResult)
    
    Write-TestHeader "Test Summary"
    
    $successRate = if (($TestResult.Passed + $TestResult.Failed) -gt 0) {
        [math]::Round(($TestResult.Passed / ($TestResult.Passed + $TestResult.Failed)) * 100, 1)
    } else { 0 }
    
    # Write summary to both console and log in format expected by master test runner
    $summaryLines = @(
        "=== INTEGRATION TEST SUMMARY ===",
        "Completed: $(Get-Date)",
        "Total Tests Passed: $($TestResult.Passed)",
        "Total Tests Failed: $($TestResult.Failed)",
        "Total Tests Skipped: $($TestResult.Skipped)",
        "Success Rate: $successRate%",
        ""
    )
    
    foreach ($line in $summaryLines) {
        # Write to log file only
        $line | Out-File -FilePath $global:mainLogFile -Append -Encoding UTF8
        # Write to console with color
        $color = if ($line -match "Failed.*[1-9]") { "Red" } elseif ($line -match "Passed") { "Green" } else { "White" }
        Write-Host $line -ForegroundColor $color
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
            TotalPassed = $TestResult.Passed
            TotalFailed = $TestResult.Failed
            TotalSkipped = $TestResult.Skipped
            SuccessRate = $successRate
        }
        ExitCode = $TestResult.ExitCode
        Success = $TestResult.Success
    }
    
    $jsonReportPath = Join-Path $script:projectRoot "test-results/reports/integration-test-summary-$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').json"
    $jsonReport | ConvertTo-Json -Depth 4 | Out-File -FilePath $jsonReportPath -Encoding UTF8
    
    "JSON report generated: $jsonReportPath" | Tee-Object -FilePath $global:mainLogFile -Append
    Write-Host "📊 JSON report: $jsonReportPath" -ForegroundColor Cyan
}

# Main execution
try {
    Write-Host "🧪 Windows Melody Recovery - Integration Test Runner" -ForegroundColor Magenta
    Write-Host "=" * 60 -ForegroundColor Magenta
    Write-Host ""
    
    # Initialize environment and logging
    Initialize-TestEnvironment
    
    # Prerequisites check - centralized Docker management handles both Docker and Compose
    if (-not (Test-DockerAvailable)) {
        "Docker not available" | Tee-Object -FilePath $global:mainLogFile -Append
        exit 1
    }
    
    # Check if docker-compose.test.yml exists
    if (-not (Test-Path "docker-compose.test.yml")) {
        $errorMsg = "docker-compose.test.yml not found in current directory"
        $errorMsg | Tee-Object -FilePath $global:mainLogFile -Append
        Write-Host "✗ $errorMsg" -ForegroundColor Red
        Write-Host "Please run this script from the root of the Windows Melody Recovery repository" -ForegroundColor Yellow
        exit 1
    }
    
    # Cleanup if requested
    if ($Clean) {
        "Cleanup requested before test run" | Tee-Object -FilePath $global:mainLogFile -Append
        Invoke-Cleanup
    }
    
    # Start test environment
    Start-TestEnvironment
    
    # Run tests
    $testResult = Invoke-IntegrationTests
    
    # Copy results
    Copy-TestResults
    
    # Write summary
    Write-TestSummary -TestResult $testResult
    
         # Show final status
     Write-Host "`n" + "=" * 60 -ForegroundColor Magenta
     if ($testResult.Success) {
         $finalMsg = "🎉 Integration tests completed successfully!"
         $finalMsg | Out-File -FilePath $global:mainLogFile -Append -Encoding UTF8
         Write-Host $finalMsg -ForegroundColor Green
     } else {
         $finalMsg = "❌ Integration tests failed"
         $finalMsg | Out-File -FilePath $global:mainLogFile -Append -Encoding UTF8
         Write-Host $finalMsg -ForegroundColor Red
         Show-TestContainerLogs
     }
    
    # Final cleanup
    Stop-TestEnvironment
    
    # Clean test artifacts
    Clean-TestArtifacts
    
    # Final logging
    "Test run completed at $(Get-Date)" | Tee-Object -FilePath $global:mainLogFile -Append
    Write-Host "📄 Complete log: $global:mainLogFile" -ForegroundColor Cyan
    
    # Exit with proper code
    exit $testResult.ExitCode
    
} catch {
    $errorMsg = "💥 Integration test runner failed: $($_.Exception.Message)"
    if ($global:mainLogFile) {
        $errorMsg | Tee-Object -FilePath $global:mainLogFile -Append
        $_.ScriptStackTrace | Tee-Object -FilePath $global:mainLogFile -Append
    }
    Write-Host $errorMsg -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    
    Show-TestContainerLogs
    Stop-TestEnvironment
    
    # Clean test artifacts
    Clean-TestArtifacts
    
    exit 1
} 