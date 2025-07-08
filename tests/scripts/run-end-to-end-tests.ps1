#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Run End-to-End Tests for Windows Melody Recovery

.DESCRIPTION
    Runs comprehensive end-to-end tests that validate complete user workflows using Docker containers.
    These tests simulate real user scenarios from installation to daily usage in isolated environments.

.PARAMETER TestName
    Specific test file to run (without .Tests.ps1 extension). If not specified, runs all end-to-end tests.

.PARAMETER OutputFormat
    Pester output format. Default is 'Detailed'.

.PARAMETER SkipCleanup
    Skip cleanup after tests (useful for debugging).

.PARAMETER KeepContainers
    Keep Docker containers running after tests.

.PARAMETER Timeout
    Timeout in minutes for end-to-end tests. Default is 15 minutes.

.PARAMETER GenerateReport
    Generate detailed test reports.

.PARAMETER Clean
    Clean up containers and artifacts before running tests.

.EXAMPLE
    .\run-end-to-end-tests.ps1
    .\run-end-to-end-tests.ps1 -TestName "User-Journey-Tests"
    .\run-end-to-end-tests.ps1 -Timeout 30 -KeepContainers
#>

[CmdletBinding()]
param(
    [string]$TestName,
    [ValidateSet('None', 'Normal', 'Detailed', 'Diagnostic')]
    [string]$OutputFormat = 'Detailed',
    [switch]$SkipCleanup,
    [switch]$KeepContainers,
    [int]$Timeout = 15,
    [switch]$GenerateReport,
    [switch]$Clean
)

# Set execution policy for current process to allow unsigned scripts
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

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

function Initialize-EndToEndTestEnvironment {
    Write-TestSection "Initializing End-to-End Test Environment"
    
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
    $global:mainLogFile = Join-Path $script:projectRoot "test-results/logs/end-to-end-test-run-$timestamp.log"
    
    "Windows Melody Recovery - End-to-End Test Run" | Tee-Object -FilePath $global:mainLogFile
    "Started: $(Get-Date)" | Tee-Object -FilePath $global:mainLogFile -Append
    "Test Name: $TestName" | Tee-Object -FilePath $global:mainLogFile -Append
    "Output Format: $OutputFormat" | Tee-Object -FilePath $global:mainLogFile -Append
    "Timeout: $Timeout minutes" | Tee-Object -FilePath $global:mainLogFile -Append
    "Host: $env:COMPUTERNAME" | Tee-Object -FilePath $global:mainLogFile -Append
    "PowerShell: $($PSVersionTable.PSVersion)" | Tee-Object -FilePath $global:mainLogFile -Append
    "=" * 80 | Tee-Object -FilePath $global:mainLogFile -Append
    "" | Tee-Object -FilePath $global:mainLogFile -Append
    
    Write-Host "✓ Test environment initialized" -ForegroundColor Green
    Write-Host "✓ Log file: $global:mainLogFile" -ForegroundColor Green
}

function Start-DockerEnvironment {
    Write-TestSection "Starting Docker Environment"
    "Starting Docker containers for end-to-end tests..." | Tee-Object -FilePath $global:mainLogFile -Append
    
    try {
        # Use centralized Docker management
        $startResult = Initialize-DockerEnvironment
        if (-not $startResult) {
            $errorMsg = "Failed to initialize Docker environment"
            $errorMsg | Tee-Object -FilePath $global:mainLogFile -Append
            throw $errorMsg
        }
        
        $successMsg = "Docker containers started successfully"
        $successMsg | Tee-Object -FilePath $global:mainLogFile -Append
        Write-Host "✓ $successMsg" -ForegroundColor Green
        
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
        # Use centralized Docker management
        $connectivityResult = Test-ContainerConnectivity
        if ($connectivityResult) {
            $successMsg = "Test runner container is accessible"
            $successMsg | Tee-Object -FilePath $global:mainLogFile -Append
            Write-Host "✓ $successMsg" -ForegroundColor Green
        } else {
            throw "Container connectivity test failed"
        }
    } catch {
        $errorMsg = "Cannot connect to test runner container: $($_.Exception.Message)"
        $errorMsg | Tee-Object -FilePath $global:mainLogFile -Append
        Write-Host "✗ $errorMsg" -ForegroundColor Red
        exit 1
    }
}

Write-TestHeader "🎯 End-to-End Tests for Windows Melody Recovery"

# Clean up if requested
if ($Clean) {
    Write-TestSection "Cleaning Up Previous Test Environment"
    Stop-DockerEnvironment
    Write-Host "✓ Previous environment cleaned up" -ForegroundColor Green
}

# Initialize test environment
Initialize-EndToEndTestEnvironment

# Start Docker environment
Start-DockerEnvironment

# Test container connectivity
Test-ContainerConnectivity

# Discover available end-to-end tests
Write-TestSection "Discovering End-to-End Tests"
$endToEndDir = "/workspace/tests/end-to-end"

# Get test list from container
$availableTestsOutput = docker exec wmr-test-runner pwsh -Command "
    if (Test-Path '$endToEndDir') {
        Get-ChildItem -Path '$endToEndDir' -Filter '*.Tests.ps1' | ForEach-Object { 
            `$_.BaseName -replace '\.Tests`$', '' 
        }
    } else {
        Write-Host 'End-to-end tests directory not found: $endToEndDir'
    }
" 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Host "✗ Failed to discover end-to-end tests" -ForegroundColor Red
    $availableTestsOutput | Tee-Object -FilePath $global:mainLogFile -Append
    exit 1
}

$availableTests = $availableTestsOutput | Where-Object { $_ -and $_.Trim() -ne "" }

if (-not $availableTests) {
    Write-Warning "No end-to-end tests found in $endToEndDir"
    "No end-to-end tests found in $endToEndDir" | Tee-Object -FilePath $global:mainLogFile -Append
    if (-not $KeepContainers) {
        Stop-DockerEnvironment
    }
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
        "Test '$TestName' not found. Available: $($availableTests -join ', ')" | Tee-Object -FilePath $global:mainLogFile -Append
        if (-not $KeepContainers) {
            Stop-DockerEnvironment
        }
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
    # Initialize test directories in container
    Write-Host "Initializing test environment in container..." -ForegroundColor Cyan
    "Initializing test directories in container..." | Tee-Object -FilePath $global:mainLogFile -Append
    
    docker exec wmr-test-runner pwsh -Command "
        New-Item -Path '/test-results/logs' -ItemType Directory -Force | Out-Null
        New-Item -Path '/test-results/reports' -ItemType Directory -Force | Out-Null
        New-Item -Path '/test-results/coverage' -ItemType Directory -Force | Out-Null
        New-Item -Path '/test-results/junit' -ItemType Directory -Force | Out-Null
        Write-Host '✓ Test directories created'
    " | Tee-Object -FilePath $global:mainLogFile -Append

    foreach ($test in $testsToRun) {
        $testFile = "$endToEndDir/$test.Tests.ps1"
        
        Write-Host "🎯 Running $test end-to-end tests..." -ForegroundColor Cyan
        Write-Host "  Test file: $testFile" -ForegroundColor Gray
        
        # Check if timeout job is still running
        if ($timeoutJob.State -ne "Running") {
            Write-Host "⏰ Test execution stopped due to timeout" -ForegroundColor Red
            "Test execution stopped due to timeout" | Tee-Object -FilePath $global:mainLogFile -Append
            break
        }
        
        try {
            $startTime = Get-Date
            
            # Run test in container with timeout protection
            $testOutput = docker exec wmr-test-runner pwsh -Command "
                if (Test-Path '$testFile') {
                    Import-Module Pester -Force
                    Invoke-Pester -Path '$testFile' -Output $OutputFormat -PassThru
                } else {
                    Write-Error 'Test file not found: $testFile'
                    exit 1
                }
            " 2>&1
            
            $testExitCode = $LASTEXITCODE
            $endTime = Get-Date
            $testTime = ($endTime - $startTime).TotalSeconds
            
            # Log test output
            "=== $test TEST OUTPUT ===" | Tee-Object -FilePath $global:mainLogFile -Append
            $testOutput | Tee-Object -FilePath $global:mainLogFile -Append
            "=== END $test TEST OUTPUT ===" | Tee-Object -FilePath $global:mainLogFile -Append
            "Test exit code: $testExitCode" | Tee-Object -FilePath $global:mainLogFile -Append
            
            # Parse test results
            $passedMatch = $testOutput | Select-String "Tests Passed: (\d+)" | Select-Object -Last 1
            $failedMatch = $testOutput | Select-String "Failed: (\d+)" | Select-Object -Last 1
            
            $passed = if ($passedMatch) { [int]$passedMatch.Matches[0].Groups[1].Value } else { 0 }
            $failed = if ($failedMatch) { [int]$failedMatch.Matches[0].Groups[1].Value } else { 0 }
            
            # Alternative parsing if standard format not found
            if ($passed -eq 0 -and $failed -eq 0) {
                $altPassedMatch = $testOutput | Select-String "(\d+) passed" | Select-Object -Last 1
                $altFailedMatch = $testOutput | Select-String "(\d+) failed" | Select-Object -Last 1
                
                if ($altPassedMatch) { $passed = [int]$altPassedMatch.Matches[0].Groups[1].Value }
                if ($altFailedMatch) { $failed = [int]$altFailedMatch.Matches[0].Groups[1].Value }
            }
            
            $testResult = @{
                TestName = $test
                PassedCount = $passed
                FailedCount = $failed
                Duration = $testTime
                Status = if ($testExitCode -eq 0 -and $failed -eq 0) { "Passed" } else { "Failed" }
                ExitCode = $testExitCode
            }
            $testResults += $testResult
            
            $totalPassed += $passed
            $totalFailed += $failed
            $totalTime += $testTime
            
            if ($testExitCode -eq 0 -and $failed -eq 0) {
                Write-Host "✅ $test tests passed ($passed tests, $([math]::Round($testTime, 2))s)" -ForegroundColor Green
            } else {
                Write-Host "❌ $test tests failed ($failed failed, $passed passed, $([math]::Round($testTime, 2))s)" -ForegroundColor Red
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
            
            "Test $test crashed: $($_.Exception.Message)" | Tee-Object -FilePath $global:mainLogFile -Append
        }
        
        Write-Host ""
        
        # Memory cleanup between tests
        [System.GC]::Collect()
        [System.GC]::WaitForPendingFinalizers()
    }
    
    # Generate additional reports if requested
    if ($GenerateReport) {
        Write-Host "📋 Generating additional reports..." -ForegroundColor Cyan
        "Generating additional reports..." | Tee-Object -FilePath $global:mainLogFile -Append
        docker exec wmr-test-runner pwsh -Command "
            if (Test-Path '/workspace/tests/scripts/generate-reports.ps1') {
                /workspace/tests/scripts/generate-reports.ps1
            } else {
                Write-Host 'Report generator not found'
            }
        " | Tee-Object -FilePath $global:mainLogFile -Append
    }
    
} finally {
    # Stop timeout job
    if ($timeoutJob.State -eq "Running") {
        Stop-Job $timeoutJob
    }
    Remove-Job $timeoutJob -Force
}

# Display summary
Write-TestHeader "📊 End-to-End Test Summary"

Write-Host "📋 Test Results:" -ForegroundColor Cyan
foreach ($result in $testResults) {
    $statusColor = if ($result.Status -eq "Passed") { "Green" } else { "Red" }
    $statusIcon = if ($result.Status -eq "Passed") { "✅" } else { "❌" }
    Write-Host "  $statusIcon $($result.TestName): $($result.Status) ($($result.PassedCount) passed, $($result.FailedCount) failed, $([math]::Round($result.Duration, 2))s)" -ForegroundColor $statusColor
    
    if ($result.Error) {
        Write-Host "    Error: $($result.Error)" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "📊 Overall Results:" -ForegroundColor Cyan
Write-Host "  Total Tests: $($totalPassed + $totalFailed)" -ForegroundColor White
Write-Host "  Passed: $totalPassed" -ForegroundColor Green
Write-Host "  Failed: $totalFailed" -ForegroundColor $(if ($totalFailed -eq 0) { "Green" } else { "Red" })
Write-Host "  Duration: $([math]::Round($totalTime, 2)) seconds" -ForegroundColor White

# Log final results
"=== FINAL RESULTS ===" | Tee-Object -FilePath $global:mainLogFile -Append
"Total Tests: $($totalPassed + $totalFailed)" | Tee-Object -FilePath $global:mainLogFile -Append
"Passed: $totalPassed" | Tee-Object -FilePath $global:mainLogFile -Append
"Failed: $totalFailed" | Tee-Object -FilePath $global:mainLogFile -Append
"Duration: $([math]::Round($totalTime, 2)) seconds" | Tee-Object -FilePath $global:mainLogFile -Append
"Ended: $(Get-Date)" | Tee-Object -FilePath $global:mainLogFile -Append

# Cleanup
if (-not $SkipCleanup -and -not $KeepContainers) {
    Write-TestSection "Cleaning Up Test Environment"
    Stop-DockerEnvironment
    Write-Host "✓ Test environment cleaned up" -ForegroundColor Green
}

# Exit with appropriate code
if ($totalFailed -eq 0) {
    Write-Host "🎉 All end-to-end tests passed!" -ForegroundColor Green
    exit 0
} else {
    Write-Host "💥 Some end-to-end tests failed!" -ForegroundColor Red
    exit 1
} 
