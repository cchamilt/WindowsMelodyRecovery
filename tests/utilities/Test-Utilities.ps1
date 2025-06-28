#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Test Utilities for Windows Missing Recovery Integration Tests

.DESCRIPTION
    Common utility functions for test execution, reporting, and environment management.
#>

# Test execution utilities
function Invoke-TestWithRetry {
    param(
        [scriptblock]$TestScript,
        [int]$MaxRetries = 3,
        [int]$RetryDelaySeconds = 5
    )
    
    for ($i = 1; $i -le $MaxRetries; $i++) {
        try {
            $result = & $TestScript
            return $result
        } catch {
            if ($i -eq $MaxRetries) {
                throw "Test failed after $MaxRetries attempts: $($_.Exception.Message)"
            }
            Write-Host "Test attempt $i failed, retrying in $RetryDelaySeconds seconds..." -ForegroundColor Yellow
            Start-Sleep -Seconds $RetryDelaySeconds
        }
    }
}

function Write-TestResult {
    param(
        [string]$TestName,
        [bool]$Passed,
        [string]$Message = "",
        [object]$Details = $null
    )
    
    $status = if ($Passed) { "✓ PASS" } else { "✗ FAIL" }
    $color = if ($Passed) { "Green" } else { "Red" }
    
    Write-Host "$status $TestName" -ForegroundColor $color
    if ($Message) {
        Write-Host "  $Message" -ForegroundColor Gray
    }
    if ($Details) {
        Write-Host "  Details: $($Details | ConvertTo-Json -Compress)" -ForegroundColor Gray
    }
}

function Get-TestSummary {
    param(
        [array]$TestResults
    )
    
    $summary = @{
        Total = $TestResults.Count
        Passed = ($TestResults | Where-Object { $_.Result -eq "Passed" }).Count
        Failed = ($TestResults | Where-Object { $_.Result -eq "Failed" }).Count
        Duration = ($TestResults | Measure-Object -Property Duration -Sum).Sum
    }
    
    return $summary
} 