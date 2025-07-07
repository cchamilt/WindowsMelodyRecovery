#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Windows-Only Test Runner for Windows Melody Recovery

.DESCRIPTION
    This script runs Windows-specific tests that require actual Windows functionality.
    It should only be run on Windows systems and is designed for Windows CI/CD pipelines
    and local Windows development testing.

.PARAMETER TestSuite
    The test suite to run. Options: WindowsOnly, All

.PARAMETER GenerateReport
    Generate additional test reports

.EXAMPLE
    .\run-windows-tests.ps1 -TestSuite WindowsOnly
    .\run-windows-tests.ps1 -TestSuite All
#>

param(
    [ValidateSet("WindowsOnly", "All")]
    [string]$TestSuite = "WindowsOnly",
    
    [switch]$GenerateReport
)

# Ensure we're running on Windows
if (-not $IsWindows) {
    Write-Host "❌ This script can only run on Windows systems" -ForegroundColor Red
    exit 1
}

Write-Host "🪟 Running Windows-Only Tests - Suite: $TestSuite" -ForegroundColor Cyan

# Import Pester
Import-Module Pester -Force -ErrorAction Stop
Write-Host "✓ Pester imported" -ForegroundColor Green

# Calculate project root (two levels up from this script)
$projectRoot = (Get-Item $PSScriptRoot).Parent.Parent.FullName

# Create output directories relative to project root
$outputDirs = @(
    (Join-Path $projectRoot "test-results/junit"),
    (Join-Path $projectRoot "test-results/coverage"), 
    (Join-Path $projectRoot "test-results/reports"),
    (Join-Path $projectRoot "test-results/logs")
)

foreach ($dir in $outputDirs) {
    if (-not (Test-Path $dir)) {
        New-Item -Path $dir -ItemType Directory -Force | Out-Null
    }
}

# Create Pester configuration
$config = New-PesterConfiguration

# Basic configuration
$config.Run.PassThru = $true
$config.Output.Verbosity = 'Normal'
$config.Output.RenderMode = 'Plaintext'

# Test result configuration
$config.TestResult.Enabled = $true
$config.TestResult.OutputFormat = 'NUnitXml'
$config.TestResult.OutputPath = Join-Path $projectRoot "test-results/junit/windows-test-results.xml"

# Set test paths based on suite
switch ($TestSuite) {
    "WindowsOnly" {
        $config.Run.Path = @((Join-Path $projectRoot "tests/unit/Windows-Only.Tests.ps1"))
        Write-Host "🎯 Running Windows-Only Tests" -ForegroundColor Yellow
    }
    "All" {
        $config.Run.Path = @((Join-Path $projectRoot "tests/unit"), (Join-Path $projectRoot "tests/integration"))
        Write-Host "🎯 Running All Tests (including Windows-only tests)" -ForegroundColor Yellow
    }
}

# Display configuration
Write-Host "📋 Test Configuration:" -ForegroundColor Cyan
Write-Host "  Test Paths: $($config.Run.Path.Value -join ', ')" -ForegroundColor Gray
Write-Host "  JUnit Output: $($config.TestResult.OutputPath.Value)" -ForegroundColor Gray
Write-Host "  Platform: Windows" -ForegroundColor Gray

# Verify test files exist
$missingFiles = @()
foreach ($path in $config.Run.Path.Value) {
    if (-not (Test-Path $path)) {
        $missingFiles += $path
    }
}

if ($missingFiles.Count -gt 0) {
    Write-Host "❌ Missing test files:" -ForegroundColor Red
    $missingFiles | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    exit 1
}

Write-Host "✓ All test files exist" -ForegroundColor Green

# Run the tests
Write-Host "🚀 Executing Windows tests..." -ForegroundColor Cyan

try {
    $results = Invoke-Pester -Configuration $config
    
    # Display results
    Write-Host "" 
    Write-Host "📊 Windows Test Results Summary:" -ForegroundColor Yellow
    Write-Host "  Total Tests: $($results.TotalCount)" -ForegroundColor White
    Write-Host "  Passed: $($results.PassedCount)" -ForegroundColor Green
    Write-Host "  Failed: $($results.FailedCount)" -ForegroundColor $(if ($results.FailedCount -gt 0) { "Red" } else { "Green" })
    Write-Host "  Skipped: $($results.SkippedCount)" -ForegroundColor Yellow
    Write-Host "  Duration: $($results.Duration)" -ForegroundColor White
    
    # Save detailed JSON results
    $jsonPath = Join-Path $projectRoot "test-results/reports/windows-pester-results.json"
    try {
        $simplifiedResults = @{
            TotalCount = $results.TotalCount
            PassedCount = $results.PassedCount
            FailedCount = $results.FailedCount
            SkippedCount = $results.SkippedCount
            Duration = $results.Duration.ToString()
            TestSuite = $TestSuite
            Platform = "Windows"
            Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        }
        $simplifiedResults | ConvertTo-Json -Depth 5 | Out-File $jsonPath -Encoding UTF8
        Write-Host "💾 JSON results saved to: $jsonPath" -ForegroundColor Green
    } catch {
        Write-Host "⚠️ Warning: Could not save JSON results: $($_.Exception.Message)" -ForegroundColor Yellow
    }
    
    # Return appropriate exit code
    if ($results.FailedCount -gt 0) {
        Write-Host "❌ Some Windows tests failed!" -ForegroundColor Red
        exit 1
    } else {
        Write-Host "✅ All Windows tests passed!" -ForegroundColor Green
        exit 0
    }
    
} catch {
    Write-Host "❌ Windows test execution failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    exit 1
} 