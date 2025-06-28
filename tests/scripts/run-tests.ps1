#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Run Windows Missing Recovery Tests

.DESCRIPTION
    This script runs the specified test suite in the test environment.

.PARAMETER TestSuite
    Which test suite to run (All, Backup, Restore, WSL, Gaming, Cloud, Setup)

.PARAMETER Environment
    Test environment (Docker, Local)

.PARAMETER GenerateReport
    Generate detailed test reports

.PARAMETER Parallel
    Run tests in parallel where possible
#>

param(
    [ValidateSet("All", "Backup", "Restore", "WSL", "Gaming", "Cloud", "Setup")]
    [string]$TestSuite = "All",
    
    [ValidateSet("Docker", "Local")]
    [string]$Environment = "Docker",
    
    [switch]$GenerateReport,
    
    [switch]$Parallel
)

Write-Host "🧪 Running $TestSuite tests in $Environment environment..." -ForegroundColor Cyan

# Import test modules
Import-Module Pester -Force

# Set up test paths
$testPaths = @()

switch ($TestSuite) {
    "All" {
        $testPaths = @("/tests/unit", "/tests/integration")
    }
    "Backup" {
        $testPaths = @("/tests/integration/backup-tests.Tests.ps1")
    }
    "WSL" {
        $testPaths = @("/tests/integration/wsl-tests.Tests.ps1")
    }
    default {
        $testPaths = @("/tests/unit", "/tests/integration")
    }
}

# Run tests
$testResults = Invoke-Pester -Path $testPaths -PassThru -OutputFormat Detailed

# Generate reports if requested
if ($GenerateReport) {
    $reportPath = "/test-results/reports"
    New-Item -Path $reportPath -ItemType Directory -Force | Out-Null
    
    # Generate NUnit XML report
    $nunitPath = Join-Path $reportPath "test-results.xml"
    $testResults | Export-NUnitReport -Path $nunitPath
    
    # Generate HTML report
    $htmlPath = Join-Path $reportPath "test-results.html"
    $testResults | ConvertTo-Html -Title "Windows Missing Recovery Test Results" | Out-File -FilePath $htmlPath
    
    Write-Host "📊 Test reports generated in: $reportPath" -ForegroundColor Green
}

# Return exit code
exit $testResults.FailedCount 