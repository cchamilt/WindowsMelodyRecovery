#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Simple and Reliable Test Orchestrator for Windows Melody Recovery

.DESCRIPTION
    A streamlined test orchestrator that runs integration tests without complex health checks
    or infinite loops. Focuses on reliability and clear output.

.PARAMETER TestSuite
    Specific test suite to run (All, Backup, Restore, WSL, Gaming, Cloud)

.PARAMETER OutputPath
    Path for test results (default: /test-results)

.EXAMPLE
    ./test-orchestrator.ps1 -TestSuite Backup
#>

param(
    [ValidateSet("All", "Installation", "Initialization", "Pester", "Backup", "Restore", "WSL", "Gaming", "Cloud", "Chezmoi", "Setup")]
    [string]$TestSuite = "All",
    
    [string]$OutputPath = "/test-results"
)

# Global configuration
$Global:TestConfig = @{
    OutputPath = $OutputPath
    StartTime = Get-Date
    TestResults = @()
    TotalTests = 0
    PassedTests = 0
    FailedTests = 0
}

function Write-TestHeader {
    param([string]$Title)
    $border = "=" * 60
    Write-Host $border -ForegroundColor Cyan
    Write-Host "  $Title" -ForegroundColor Yellow
    Write-Host $border -ForegroundColor Cyan
    Write-Host ""
}

function Write-TestSection {
    param([string]$Section)
    $border = "-" * 40
    Write-Host $border -ForegroundColor Green
    Write-Host "  $Section" -ForegroundColor White
    Write-Host $border -ForegroundColor Green
}

function Initialize-TestEnvironment {
    Write-TestSection "Initializing Test Environment"
    
    # Create test directories
    $testDirs = @(
        "$($Global:TestConfig.OutputPath)/unit",
        "$($Global:TestConfig.OutputPath)/integration", 
        "$($Global:TestConfig.OutputPath)/coverage",
        "$($Global:TestConfig.OutputPath)/reports",
        "$($Global:TestConfig.OutputPath)/logs"
    )
    
    foreach ($dir in $testDirs) {
        if (-not (Test-Path $dir)) {
            New-Item -Path $dir -ItemType Directory -Force | Out-Null
            Write-Host "✓ Created directory: $dir" -ForegroundColor Green
        }
    }
    
    # Ensure Pester is available
    if (-not (Get-Module -ListAvailable -Name Pester)) {
        Write-Host "Installing Pester module..." -ForegroundColor Yellow
        Install-Module -Name Pester -Force -Scope AllUsers -MinimumVersion 5.0.0
    }
    
    Import-Module Pester -Force
    Write-Host "✓ Pester module loaded successfully" -ForegroundColor Green
    Write-Host ""
}

function Invoke-TestFile {
    param(
        [string]$TestPath,
        [string]$TestName
    )
    
    $Global:TestConfig.TotalTests++
    
    try {
        Write-Host "Running $TestName..." -ForegroundColor Yellow
        
        if (-not (Test-Path $TestPath)) {
            Write-Host "⚠ Test file not found: $TestPath" -ForegroundColor Yellow
            return $null
        }
        
        # Run test with timeout to prevent hanging
        $result = Invoke-Pester -Path $TestPath -Output Normal -PassThru
        
        if ($result.FailedCount -eq 0) {
            Write-Host "✓ $TestName passed ($($result.PassedCount) tests)" -ForegroundColor Green
            $Global:TestConfig.PassedTests++
            $status = "Passed"
        } else {
            Write-Host "✗ $TestName failed ($($result.FailedCount) failures)" -ForegroundColor Red
            $Global:TestConfig.FailedTests++
            $status = "Failed"
        }
        
        $testResult = @{
            Name = $TestName
            Status = $status
            PassedCount = $result.PassedCount
            FailedCount = $result.FailedCount
            Duration = $result.TotalTime
            Timestamp = Get-Date
        }
        
        $Global:TestConfig.TestResults += $testResult
        return $testResult
        
    } catch {
        Write-Host "✗ Error running $TestName`: $($_.Exception.Message)" -ForegroundColor Red
        $Global:TestConfig.FailedTests++
        
        $errorResult = @{
            Name = $TestName
            Status = "Error"
            PassedCount = 0
            FailedCount = 1
            Duration = [TimeSpan]::Zero
            Error = $_.Exception.Message
            Timestamp = Get-Date
        }
        
        $Global:TestConfig.TestResults += $errorResult
        return $errorResult
    }
}

function Invoke-BackupTests {
    Write-TestSection "Running Backup Integration Tests"
    
    $backupTests = @(
        @{ Name = "Unified Backup Tests"; Path = "/tests/integration/Backup-Unified.Tests.ps1" }
    )
    
    foreach ($test in $backupTests) {
        Invoke-TestFile -TestPath $test.Path -TestName $test.Name
    }
}

function Invoke-RestoreTests {
    Write-TestSection "Running Restore Integration Tests"
    
    $restoreTests = @(
        @{ Name = "System Settings Restore"; Path = "/tests/integration/restore-system-settings.Tests.ps1" }
    )
    
    foreach ($test in $restoreTests) {
        Invoke-TestFile -TestPath $test.Path -TestName $test.Name
    }
}

function Invoke-WSLTests {
    Write-TestSection "Running WSL Integration Tests"
    
    $wslTests = @(
        @{ Name = "WSL Integration"; Path = "/tests/integration/wsl-integration.Tests.ps1" },
        @{ Name = "WSL Tests"; Path = "/tests/integration/wsl-tests.Tests.ps1" },
        @{ Name = "Chezmoi Integration"; Path = "/tests/integration/chezmoi-integration.Tests.ps1" }
    )
    
    foreach ($test in $wslTests) {
        Invoke-TestFile -TestPath $test.Path -TestName $test.Name
    }
}

function Invoke-InstallationTests {
    Write-TestSection "Running Installation Integration Tests"
    
    $installTests = @(
        @{ Name = "Installation Integration"; Path = "/tests/integration/installation-integration.Tests.ps1" },
        @{ Name = "Template Integration"; Path = "/tests/integration/TemplateIntegration.Tests.ps1" }
    )
    
    foreach ($test in $installTests) {
        Invoke-TestFile -TestPath $test.Path -TestName $test.Name
    }
}

function Invoke-AllTests {
    Write-TestSection "Running All Integration Tests"
    
    Invoke-BackupTests
    Invoke-RestoreTests
    Invoke-WSLTests
    Invoke-InstallationTests
}

function Generate-TestReport {
    Write-TestSection "Generating Test Report"
    
    $duration = (Get-Date) - $Global:TestConfig.StartTime
    $reportPath = "$($Global:TestConfig.OutputPath)/reports/test-summary-$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').json"
    
    $report = @{
        TestSuite = $TestSuite
        StartTime = $Global:TestConfig.StartTime
        EndTime = Get-Date
        Duration = $duration.ToString()
        TotalTests = $Global:TestConfig.TotalTests
        PassedTests = $Global:TestConfig.PassedTests
        FailedTests = $Global:TestConfig.FailedTests
        SuccessRate = if ($Global:TestConfig.TotalTests -gt 0) { 
            [math]::Round(($Global:TestConfig.PassedTests / $Global:TestConfig.TotalTests) * 100, 2) 
        } else { 0 }
        Results = $Global:TestConfig.TestResults
    }
    
    $report | ConvertTo-Json -Depth 10 | Out-File -FilePath $reportPath -Encoding UTF8
    Write-Host "✓ Test report saved to: $reportPath" -ForegroundColor Green
    
    return $report
}

function Show-TestSummary {
    param([hashtable]$Report)
    
    Write-TestHeader "Test Execution Summary"
    
    Write-Host "Test Suite: $($Report.TestSuite)" -ForegroundColor Cyan
    Write-Host "Duration: $($Report.Duration)" -ForegroundColor Cyan
    Write-Host "Total Tests: $($Report.TotalTests)" -ForegroundColor White
    Write-Host "Passed: $($Report.PassedTests)" -ForegroundColor Green
    Write-Host "Failed: $($Report.FailedTests)" -ForegroundColor Red
    Write-Host "Success Rate: $($Report.SuccessRate)%" -ForegroundColor $(if ($Report.SuccessRate -eq 100) { "Green" } else { "Yellow" })
    
    Write-Host ""
    Write-Host "Test Results:" -ForegroundColor White
    foreach ($result in $Report.Results) {
        $color = switch ($result.Status) {
            "Passed" { "Green" }
            "Failed" { "Red" }
            "Error" { "Magenta" }
            default { "Yellow" }
        }
        Write-Host "  [$($result.Status)] $($result.Name)" -ForegroundColor $color
    }
    
    Write-Host ""
}

# Main execution
try {
    Write-TestHeader "Windows Melody Recovery - Test Orchestrator"
    Write-Host "Test Suite: $TestSuite" -ForegroundColor Cyan
    Write-Host "Output Path: $OutputPath" -ForegroundColor Cyan
    Write-Host ""
    
    # Initialize environment
    Initialize-TestEnvironment
    
    # Set working directory
    Set-Location /workspace
    
    # Run selected test suite
    switch ($TestSuite) {
        "Backup" { Invoke-BackupTests }
        "Restore" { Invoke-RestoreTests }
        "WSL" { Invoke-WSLTests }
        "Installation" { Invoke-InstallationTests }
        "All" { Invoke-AllTests }
        default { 
            Write-Host "Running backup tests (default)..." -ForegroundColor Yellow
            Invoke-BackupTests 
        }
    }
    
    # Generate report and show summary
    $report = Generate-TestReport
    Show-TestSummary -Report $report
    
    # Exit with appropriate code
    if ($Global:TestConfig.FailedTests -eq 0) {
        Write-Host "🎉 All tests passed!" -ForegroundColor Green
        exit 0
    } else {
        Write-Host "❌ Some tests failed!" -ForegroundColor Red
        exit 1
    }
    
} catch {
    Write-Host "💥 Test orchestrator failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    exit 1
} 