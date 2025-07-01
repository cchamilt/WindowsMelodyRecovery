# Pester Test Runner Module for Windows Melody Recovery
# Handles execution of Pester integration tests with proper logging

. /tests/scripts/test-logging.ps1

function Test-PesterAvailability {
    param([string]$LogFile = $null)
    
    Write-TestLog "Checking Pester availability..." "INFO" "PESTER" $LogFile
    
    try {
        $pesterModule = Get-Module -ListAvailable Pester | Select-Object -First 1
        if ($pesterModule) {
            Write-TestLog "Pester $($pesterModule.Version) is available" "SUCCESS" "PESTER" $LogFile
            return $true
        } else {
            Write-TestLog "Pester module not found - attempting installation..." "WARN" "PESTER" $LogFile
            
            # Try to install Pester
            try {
                Write-TestLog "Installing Pester module..." "INFO" "PESTER" $LogFile
                Install-Module -Name Pester -Force -Scope AllUsers -ErrorAction Stop
                
                # Check again after installation
                $pesterModule = Get-Module -ListAvailable Pester | Select-Object -First 1
                if ($pesterModule) {
                    Write-TestLog "Pester $($pesterModule.Version) installed successfully" "SUCCESS" "PESTER" $LogFile
                    return $true
                } else {
                    Write-TestLog "Pester installation failed - module still not found" "ERROR" "PESTER" $LogFile
                    return $false
                }
            } catch {
                Write-TestLog "Failed to install Pester: $($_.Exception.Message)" "ERROR" "PESTER" $LogFile
                return $false
            }
        }
    } catch {
        Write-TestLog "Error checking Pester availability: $($_.Exception.Message)" "ERROR" "PESTER" $LogFile
        return $false
    }
}

function Invoke-SinglePesterTest {
    param(
        [string]$TestFile,
        [string]$LogPath = "/test-results/logs"
    )
    
    $testName = [System.IO.Path]::GetFileNameWithoutExtension($TestFile)
    $testLogFile = Start-TestLog -TestName $testName -LogPath $LogPath
    
    Write-TestLog "Starting test: $testName" "INFO" "PESTER" $testLogFile
    Write-TestLog "Test file: $TestFile" "INFO" "PESTER" $testLogFile
    
    try {
        # Execute the test and capture both stdout and stderr
        Write-TestLog "Executing: cd /workspace && Import-Module Pester -Force && Invoke-Pester $TestFile -Output Normal" "DEBUG" "PESTER" $testLogFile
        
        $testOutput = docker exec wmr-test-runner pwsh -Command "cd /workspace && Import-Module Pester -Force && Invoke-Pester $TestFile -Output Normal" 2>&1
        $exitCode = $LASTEXITCODE
        
        # Log all output to the test-specific log file
        Write-TestLog "=== TEST OUTPUT START ===" "INFO" "PESTER" $testLogFile
        foreach ($line in $testOutput) {
            $line | Out-File -FilePath $testLogFile -Append -Encoding UTF8
        }
        Write-TestLog "=== TEST OUTPUT END ===" "INFO" "PESTER" $testLogFile
        Write-TestLog "Test exit code: $exitCode" "INFO" "PESTER" $testLogFile
        
        # Parse test results
        $result = @{
            TestName = $testName
            TestFile = $TestFile
            LogFile = $testLogFile
            ExitCode = $exitCode
            PassedCount = 0
            FailedCount = 0
            SkippedCount = 0
            Status = "Unknown"
            Output = $testOutput
        }
        
        if ($exitCode -eq 0) {
            # Parse successful test output
            $passedMatch = $testOutput | Select-String "Tests Passed: (\d+)" | Select-Object -First 1
            $failedMatch = $testOutput | Select-String "Failed: (\d+)" | Select-Object -First 1
            $skippedMatch = $testOutput | Select-String "Skipped: (\d+)" | Select-Object -First 1
            
            $result.PassedCount = if ($passedMatch) { [int]$passedMatch.Matches[0].Groups[1].Value } else { 0 }
            $result.FailedCount = if ($failedMatch) { [int]$failedMatch.Matches[0].Groups[1].Value } else { 0 }
            $result.SkippedCount = if ($skippedMatch) { [int]$skippedMatch.Matches[0].Groups[1].Value } else { 0 }
            
            if ($result.FailedCount -gt 0) {
                $result.Status = "Failed"
                Write-TestLog "$testName: $($result.PassedCount) passed, $($result.FailedCount) failed" "WARN" "PESTER" $testLogFile
            } else {
                $result.Status = "Passed"
                Write-TestLog "$testName: $($result.PassedCount) passed" "SUCCESS" "PESTER" $testLogFile
            }
        } else {
            $result.Status = "Error"
            $result.FailedCount = 1
            Write-TestLog "$testName: Test execution failed (exit code: $exitCode)" "ERROR" "PESTER" $testLogFile
        }
        
        Stop-TestLog -TestName $testName -LogFile $testLogFile -Result $result.Status
        return $result
        
    } catch {
        Write-TestLog "$testName: Exception occurred: $($_.Exception.Message)" "ERROR" "PESTER" $testLogFile
        Stop-TestLog -TestName $testName -LogFile $testLogFile -Result "Exception"
        
        return @{
            TestName = $testName
            TestFile = $TestFile
            LogFile = $testLogFile
            ExitCode = -1
            PassedCount = 0
            FailedCount = 1
            SkippedCount = 0
            Status = "Exception"
            Output = @("Exception: $($_.Exception.Message)")
        }
    }
}

function Invoke-CoreIntegrationTests {
    param(
        [string]$LogPath = "/test-results/logs"
    )
    
    $mainLogFile = Join-Path $LogPath "pester-runner.log"
    Write-TestHeader "Running Core Integration Tests" $mainLogFile
    
    # Check Pester availability first
    if (-not (Test-PesterAvailability -LogFile $mainLogFile)) {
        Write-TestLog "Pester not available, cannot run tests" "ERROR" "PESTER" $mainLogFile
        return @{
            Success = $false
            Results = @()
            Summary = @{
                TotalTests = 0
                PassedTests = 0
                FailedTests = 1
                ErrorTests = 0
            }
        }
    }
    
    # Define core integration tests
    $coreTests = @(
        "tests/integration/backup-applications.Tests.ps1",
        "tests/integration/backup-gaming.Tests.ps1",
        "tests/integration/backup-cloud.Tests.ps1",
        "tests/integration/backup-system-settings.Tests.ps1"
    )
    
    Write-TestLog "Will run $($coreTests.Count) core integration tests" "INFO" "PESTER" $mainLogFile
    
    $allResults = @()
    $summary = @{
        TotalTests = 0
        PassedTests = 0
        FailedTests = 0
        ErrorTests = 0
    }
    
    # Run each test
    foreach ($testFile in $coreTests) {
        Write-TestLog "Running test: $testFile" "INFO" "PESTER" $mainLogFile
        
        $testResult = Invoke-SinglePesterTest -TestFile $testFile -LogPath $LogPath
        $allResults += $testResult
        
        # Update summary
        $summary.TotalTests += 1
        switch ($testResult.Status) {
            "Passed" { $summary.PassedTests += 1 }
            "Failed" { $summary.FailedTests += 1 }
            "Error" { $summary.ErrorTests += 1 }
            "Exception" { $summary.ErrorTests += 1 }
        }
        
        Write-TestLog "Test $($testResult.TestName) completed: $($testResult.Status)" "INFO" "PESTER" $mainLogFile
    }
    
    # Log summary
    Write-TestLog "=== CORE INTEGRATION TESTS SUMMARY ===" "INFO" "PESTER" $mainLogFile
    Write-TestLog "Total Tests: $($summary.TotalTests)" "INFO" "PESTER" $mainLogFile
    Write-TestLog "Passed: $($summary.PassedTests)" "SUCCESS" "PESTER" $mainLogFile
    Write-TestLog "Failed: $($summary.FailedTests)" $(if ($summary.FailedTests -gt 0) { "WARN" } else { "INFO" }) "PESTER" $mainLogFile
    Write-TestLog "Errors: $($summary.ErrorTests)" $(if ($summary.ErrorTests -gt 0) { "ERROR" } else { "INFO" }) "PESTER" $mainLogFile
    
    $success = ($summary.FailedTests -eq 0 -and $summary.ErrorTests -eq 0)
    Write-TestLog "Overall result: $(if ($success) { 'SUCCESS' } else { 'FAILURE' })" $(if ($success) { "SUCCESS" } else { "ERROR" }) "PESTER" $mainLogFile
    
    return @{
        Success = $success
        Results = $allResults
        Summary = $summary
        MainLogFile = $mainLogFile
    }
}

# Export functions
Export-ModuleMember -Function Test-PesterAvailability, Invoke-SinglePesterTest, Invoke-CoreIntegrationTests 