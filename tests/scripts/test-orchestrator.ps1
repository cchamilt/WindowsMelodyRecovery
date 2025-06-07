#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Test Orchestrator for Windows Missing Recovery Integration Tests

.DESCRIPTION
    Orchestrates comprehensive integration testing across mock Windows, WSL, and cloud environments.
    Runs full backup/restore cycles and validates functionality across all components.

.PARAMETER TestSuite
    Specific test suite to run (All, Backup, Restore, WSL, Gaming, Cloud)

.PARAMETER Environment
    Test environment (Docker, Local)

.PARAMETER Parallel
    Run tests in parallel where possible

.PARAMETER GenerateReport
    Generate comprehensive test report

.EXAMPLE
    ./test-orchestrator.ps1 -TestSuite All -GenerateReport
#>

param(
    [ValidateSet("All", "Backup", "Restore", "WSL", "Gaming", "Cloud", "Setup")]
    [string]$TestSuite = "All",
    
    [ValidateSet("Docker", "Local")]
    [string]$Environment = "Docker",
    
    [switch]$Parallel,
    
    [switch]$GenerateReport,
    
    [string]$OutputPath = "/test-results"
)

# Import test utilities
. /tests/utilities/Test-Utilities.ps1
. /tests/utilities/Mock-Utilities.ps1
. /tests/utilities/Docker-Utilities.ps1

# Global test configuration
$Global:TestConfig = @{
    WindowsHost = $env:MOCK_WINDOWS_HOST ?? "windows-mock"
    WSLHost = $env:MOCK_WSL_HOST ?? "wsl-mock"
    CloudHost = $env:MOCK_CLOUD_HOST ?? "mock-cloud-server"
    OutputPath = $OutputPath
    StartTime = Get-Date
    TestResults = @()
    FailedTests = @()
    PassedTests = @()
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

function Test-ContainerHealth {
    Write-TestSection "Checking Container Health"
    
    $containers = @($Global:TestConfig.WindowsHost, $Global:TestConfig.WSLHost, $Global:TestConfig.CloudHost)
    $healthyContainers = @()
    
    foreach ($container in $containers) {
        try {
            $result = docker exec $container echo "healthy" 2>$null
            if ($result -eq "healthy") {
                Write-Host "✓ $container is healthy" -ForegroundColor Green
                $healthyContainers += $container
            } else {
                Write-Host "✗ $container is not responding" -ForegroundColor Red
            }
        } catch {
            Write-Host "✗ $container is not accessible: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    
    if ($healthyContainers.Count -ne $containers.Count) {
        throw "Not all containers are healthy. Cannot proceed with testing."
    }
    
    Write-Host ""
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
    
    # Initialize mock environments
    Write-Host "Initializing Windows Mock Environment..." -ForegroundColor Yellow
    docker exec $Global:TestConfig.WindowsHost pwsh -Command "Import-Module /workspace/WindowsMissingRecovery.psm1 -Force"
    
    Write-Host "Initializing WSL Mock Environment..." -ForegroundColor Yellow
    docker exec $Global:TestConfig.WSLHost bash -c "echo 'WSL environment ready'"
    
    Write-Host "Checking Cloud Mock Server..." -ForegroundColor Yellow
    $cloudHealth = Invoke-RestMethod -Uri "http://$($Global:TestConfig.CloudHost):8080/health" -Method Get
    if ($cloudHealth.status -eq "healthy") {
        Write-Host "✓ Cloud mock server is ready" -ForegroundColor Green
    }
    
    Write-Host ""
}

function Invoke-BackupTests {
    Write-TestSection "Running Backup Tests"
    
    $backupTests = @(
        @{ Name = "System Settings"; Script = "backup-system-settings.Tests.ps1" },
        @{ Name = "Applications"; Script = "backup-applications.Tests.ps1" },
        @{ Name = "Gaming Platforms"; Script = "backup-gaming.Tests.ps1" },
        @{ Name = "WSL Environment"; Script = "backup-wsl.Tests.ps1" },
        @{ Name = "Cloud Integration"; Script = "backup-cloud.Tests.ps1" }
    )
    
    foreach ($test in $backupTests) {
        try {
            Write-Host "Running $($test.Name) backup tests..." -ForegroundColor Yellow
            
            $result = docker exec $Global:TestConfig.WindowsHost pwsh -Command @"
                Set-Location /workspace
                Import-Module Pester -Force
                Invoke-Pester -Path '/tests/integration/$($test.Script)' -Output Detailed -PassThru
"@
            
            if ($result.FailedCount -eq 0) {
                Write-Host "✓ $($test.Name) backup tests passed" -ForegroundColor Green
                $Global:TestConfig.PassedTests += $test.Name
            } else {
                Write-Host "✗ $($test.Name) backup tests failed" -ForegroundColor Red
                $Global:TestConfig.FailedTests += $test.Name
            }
            
            $Global:TestConfig.TestResults += @{
                Suite = "Backup"
                Test = $test.Name
                Result = if ($result.FailedCount -eq 0) { "Passed" } else { "Failed" }
                Duration = $result.TotalTime
                Details = $result
            }
            
        } catch {
            Write-Host "✗ Error running $($test.Name) backup tests: $($_.Exception.Message)" -ForegroundColor Red
            $Global:TestConfig.FailedTests += $test.Name
        }
    }
    
    Write-Host ""
}

function Invoke-RestoreTests {
    Write-TestSection "Running Restore Tests"
    
    $restoreTests = @(
        @{ Name = "System Settings"; Script = "restore-system-settings.Tests.ps1" },
        @{ Name = "Applications"; Script = "restore-applications.Tests.ps1" },
        @{ Name = "Gaming Platforms"; Script = "restore-gaming.Tests.ps1" },
        @{ Name = "WSL Environment"; Script = "restore-wsl.Tests.ps1" },
        @{ Name = "Cloud Integration"; Script = "restore-cloud.Tests.ps1" }
    )
    
    foreach ($test in $restoreTests) {
        try {
            Write-Host "Running $($test.Name) restore tests..." -ForegroundColor Yellow
            
            $result = docker exec $Global:TestConfig.WindowsHost pwsh -Command @"
                Set-Location /workspace
                Import-Module Pester -Force
                Invoke-Pester -Path '/tests/integration/$($test.Script)' -Output Detailed -PassThru
"@
            
            if ($result.FailedCount -eq 0) {
                Write-Host "✓ $($test.Name) restore tests passed" -ForegroundColor Green
                $Global:TestConfig.PassedTests += $test.Name
            } else {
                Write-Host "✗ $($test.Name) restore tests failed" -ForegroundColor Red
                $Global:TestConfig.FailedTests += $test.Name
            }
            
            $Global:TestConfig.TestResults += @{
                Suite = "Restore"
                Test = $test.Name
                Result = if ($result.FailedCount -eq 0) { "Passed" } else { "Failed" }
                Duration = $result.TotalTime
                Details = $result
            }
            
        } catch {
            Write-Host "✗ Error running $($test.Name) restore tests: $($_.Exception.Message)" -ForegroundColor Red
            $Global:TestConfig.FailedTests += $test.Name
        }
    }
    
    Write-Host ""
}

function Invoke-WSLIntegrationTests {
    Write-TestSection "Running WSL Integration Tests"
    
    try {
        Write-Host "Testing WSL backup and restore cycle..." -ForegroundColor Yellow
        
        # Test WSL backup
        $backupResult = docker exec $Global:TestConfig.WindowsHost pwsh -Command @"
            Set-Location /workspace
            Import-Module ./WindowsMissingRecovery.psm1 -Force
            . ./Private/backup/backup-wsl.ps1
            Backup-WSL -BackupRootPath '/workspace/test-backups' -WSLHost '$($Global:TestConfig.WSLHost)'
"@
        
        if ($backupResult.Success) {
            Write-Host "✓ WSL backup completed successfully" -ForegroundColor Green
        } else {
            Write-Host "✗ WSL backup failed" -ForegroundColor Red
        }
        
        # Test WSL restore
        $restoreResult = docker exec $Global:TestConfig.WindowsHost pwsh -Command @"
            Set-Location /workspace
            Import-Module ./WindowsMissingRecovery.psm1 -Force
            . ./Private/restore/restore-wsl.ps1
            Restore-WSL -BackupRootPath '/workspace/test-backups' -WSLHost '$($Global:TestConfig.WSLHost)'
"@
        
        if ($restoreResult.Success) {
            Write-Host "✓ WSL restore completed successfully" -ForegroundColor Green
        } else {
            Write-Host "✗ WSL restore failed" -ForegroundColor Red
        }
        
        # Test chezmoi integration
        Write-Host "Testing chezmoi integration..." -ForegroundColor Yellow
        $chezmoiResult = docker exec $Global:TestConfig.WSLHost bash -c @"
            chezmoi --version && echo 'chezmoi available' || echo 'chezmoi not available'
"@
        
        if ($chezmoiResult -like "*chezmoi available*") {
            Write-Host "✓ chezmoi integration working" -ForegroundColor Green
        } else {
            Write-Host "✗ chezmoi integration failed" -ForegroundColor Red
        }
        
    } catch {
        Write-Host "✗ WSL integration tests failed: $($_.Exception.Message)" -ForegroundColor Red
        $Global:TestConfig.FailedTests += "WSL Integration"
    }
    
    Write-Host ""
}

function Invoke-CloudIntegrationTests {
    Write-TestSection "Running Cloud Integration Tests"
    
    try {
        Write-Host "Testing cloud provider detection..." -ForegroundColor Yellow
        
        # Test OneDrive detection
        $oneDriveTest = Invoke-RestMethod -Uri "http://$($Global:TestConfig.CloudHost):8080/api/onedrive/status" -Method Get
        if ($oneDriveTest.available) {
            Write-Host "✓ OneDrive mock available" -ForegroundColor Green
        }
        
        # Test Google Drive detection
        $googleDriveTest = Invoke-RestMethod -Uri "http://$($Global:TestConfig.CloudHost):8080/api/googledrive/status" -Method Get
        if ($googleDriveTest.available) {
            Write-Host "✓ Google Drive mock available" -ForegroundColor Green
        }
        
        # Test Dropbox detection
        $dropboxTest = Invoke-RestMethod -Uri "http://$($Global:TestConfig.CloudHost):8080/api/dropbox/status" -Method Get
        if ($dropboxTest.available) {
            Write-Host "✓ Dropbox mock available" -ForegroundColor Green
        }
        
        # Test backup upload
        Write-Host "Testing backup upload to cloud..." -ForegroundColor Yellow
        $uploadTest = docker exec $Global:TestConfig.WindowsHost pwsh -Command @"
            Set-Location /workspace
            Import-Module ./WindowsMissingRecovery.psm1 -Force
            # Test cloud backup functionality
            Test-Path '/mock-cloud/OneDrive' -and (Test-Path '/mock-cloud/GoogleDrive') -and (Test-Path '/mock-cloud/Dropbox')
"@
        
        if ($uploadTest) {
            Write-Host "✓ Cloud storage paths accessible" -ForegroundColor Green
        } else {
            Write-Host "✗ Cloud storage paths not accessible" -ForegroundColor Red
        }
        
    } catch {
        Write-Host "✗ Cloud integration tests failed: $($_.Exception.Message)" -ForegroundColor Red
        $Global:TestConfig.FailedTests += "Cloud Integration"
    }
    
    Write-Host ""
}

function Invoke-FullIntegrationTest {
    Write-TestSection "Running Full Integration Test"
    
    try {
        Write-Host "Starting complete backup/restore cycle..." -ForegroundColor Yellow
        
        # Full backup
        $fullBackupResult = docker exec $Global:TestConfig.WindowsHost pwsh -Command @"
            Set-Location /workspace
            Import-Module ./WindowsMissingRecovery.psm1 -Force
            Backup-WindowsMissingRecovery -BackupRootPath '/workspace/test-backups' -Force
"@
        
        if ($fullBackupResult.Success) {
            Write-Host "✓ Full backup completed" -ForegroundColor Green
        } else {
            Write-Host "✗ Full backup failed" -ForegroundColor Red
            return
        }
        
        # Full restore
        $fullRestoreResult = docker exec $Global:TestConfig.WindowsHost pwsh -Command @"
            Set-Location /workspace
            Import-Module ./WindowsMissingRecovery.psm1 -Force
            Restore-WindowsMissingRecovery -BackupRootPath '/workspace/test-backups' -Force
"@
        
        if ($fullRestoreResult.Success) {
            Write-Host "✓ Full restore completed" -ForegroundColor Green
            $Global:TestConfig.PassedTests += "Full Integration"
        } else {
            Write-Host "✗ Full restore failed" -ForegroundColor Red
            $Global:TestConfig.FailedTests += "Full Integration"
        }
        
    } catch {
        Write-Host "✗ Full integration test failed: $($_.Exception.Message)" -ForegroundColor Red
        $Global:TestConfig.FailedTests += "Full Integration"
    }
    
    Write-Host ""
}

function Generate-TestReport {
    if (-not $GenerateReport) { return }
    
    Write-TestSection "Generating Test Report"
    
    $endTime = Get-Date
    $duration = $endTime - $Global:TestConfig.StartTime
    
    $report = @{
        TestRun = @{
            StartTime = $Global:TestConfig.StartTime
            EndTime = $endTime
            Duration = $duration
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
    }
    
    # Save JSON report
    $jsonReport = $report | ConvertTo-Json -Depth 10
    $jsonPath = "$($Global:TestConfig.OutputPath)/reports/integration-test-report.json"
    $jsonReport | Out-File -FilePath $jsonPath -Encoding UTF8
    
    # Generate HTML report
    $htmlReport = @"
<!DOCTYPE html>
<html>
<head>
    <title>Windows Missing Recovery - Integration Test Report</title>
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
        <h1>Windows Missing Recovery - Integration Test Report</h1>
        <p><strong>Test Suite:</strong> $($report.TestRun.TestSuite)</p>
        <p><strong>Environment:</strong> $($report.TestRun.Environment)</p>
        <p><strong>Duration:</strong> $($report.TestRun.Duration)</p>
        <p><strong>Generated:</strong> $($report.TestRun.EndTime)</p>
    </div>
    
    <div class="summary">
        <h2>Test Summary</h2>
        <p><strong>Total Tests:</strong> $($report.Summary.TotalTests)</p>
        <p><strong>Passed:</strong> <span class="passed">$($report.Summary.PassedTests)</span></p>
        <p><strong>Failed:</strong> <span class="failed-text">$($report.Summary.FailedTests)</span></p>
        <p><strong>Success Rate:</strong> $($report.Summary.SuccessRate)%</p>
    </div>
    
    <h2>Test Results</h2>
    <table>
        <tr>
            <th>Suite</th>
            <th>Test</th>
            <th>Result</th>
            <th>Duration</th>
        </tr>
"@
    
    foreach ($result in $Global:TestConfig.TestResults) {
        $resultClass = if ($result.Result -eq "Passed") { "passed" } else { "failed-text" }
        $htmlReport += @"
        <tr>
            <td>$($result.Suite)</td>
            <td>$($result.Test)</td>
            <td class="$resultClass">$($result.Result)</td>
            <td>$($result.Duration)</td>
        </tr>
"@
    }
    
    $htmlReport += @"
    </table>
</body>
</html>
"@
    
    $htmlPath = "$($Global:TestConfig.OutputPath)/reports/integration-test-report.html"
    $htmlReport | Out-File -FilePath $htmlPath -Encoding UTF8
    
    Write-Host "✓ Test report generated:" -ForegroundColor Green
    Write-Host "  JSON: $jsonPath" -ForegroundColor Cyan
    Write-Host "  HTML: $htmlPath" -ForegroundColor Cyan
    Write-Host ""
}

function Show-TestSummary {
    Write-TestHeader "Test Summary"
    
    $endTime = Get-Date
    $duration = $endTime - $Global:TestConfig.StartTime
    
    Write-Host "Test Suite: $TestSuite" -ForegroundColor Cyan
    Write-Host "Environment: $Environment" -ForegroundColor Cyan
    Write-Host "Duration: $duration" -ForegroundColor Cyan
    Write-Host ""
    
    Write-Host "Results:" -ForegroundColor Yellow
    Write-Host "  Total Tests: $($Global:TestConfig.TestResults.Count)" -ForegroundColor White
    Write-Host "  Passed: $($Global:TestConfig.PassedTests.Count)" -ForegroundColor Green
    Write-Host "  Failed: $($Global:TestConfig.FailedTests.Count)" -ForegroundColor Red
    
    if ($Global:TestConfig.TestResults.Count -gt 0) {
        $successRate = [math]::Round(($Global:TestConfig.PassedTests.Count / $Global:TestConfig.TestResults.Count) * 100, 2)
        Write-Host "  Success Rate: $successRate%" -ForegroundColor $(if ($successRate -ge 90) { "Green" } elseif ($successRate -ge 70) { "Yellow" } else { "Red" })
    }
    
    if ($Global:TestConfig.FailedTests.Count -gt 0) {
        Write-Host ""
        Write-Host "Failed Tests:" -ForegroundColor Red
        foreach ($failed in $Global:TestConfig.FailedTests) {
            Write-Host "  - $failed" -ForegroundColor Red
        }
    }
    
    Write-Host ""
}

# Main execution
try {
    Write-TestHeader "Windows Missing Recovery - Integration Test Suite"
    
    if ($Environment -eq "Docker") {
        Test-ContainerHealth
    }
    
    Initialize-TestEnvironment
    
    switch ($TestSuite) {
        "All" {
            Invoke-BackupTests
            Invoke-RestoreTests
            Invoke-WSLIntegrationTests
            Invoke-CloudIntegrationTests
            Invoke-FullIntegrationTest
        }
        "Backup" { Invoke-BackupTests }
        "Restore" { Invoke-RestoreTests }
        "WSL" { Invoke-WSLIntegrationTests }
        "Cloud" { Invoke-CloudIntegrationTests }
        "Setup" { Invoke-FullIntegrationTest }
    }
    
    Generate-TestReport
    Show-TestSummary
    
    # Exit with appropriate code
    if ($Global:TestConfig.FailedTests.Count -eq 0) {
        Write-Host "All tests passed! 🎉" -ForegroundColor Green
        exit 0
    } else {
        Write-Host "Some tests failed. Check the report for details." -ForegroundColor Red
        exit 1
    }
    
} catch {
    Write-Host "Test orchestrator failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    exit 1
} 