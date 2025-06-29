#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Generate Test Reports

.DESCRIPTION
    This script generates various test reports from Pester results.

.PARAMETER TestResults
    Pester test results object

.PARAMETER OutputPath
    Directory to save reports
#>

param(
    [Parameter(Mandatory)]
    [object]$TestResults,
    
    [string]$OutputPath = "/test-results/reports"
)

Write-Host "📊 Generating test reports..." -ForegroundColor Cyan

# Create output directory
New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null

# Generate NUnit XML report
$nunitPath = Join-Path $OutputPath "test-results.xml"
$TestResults | Export-NUnitReport -Path $nunitPath
Write-Host "✓ NUnit XML report: $nunitPath" -ForegroundColor Green

# Generate HTML report
$htmlPath = Join-Path $OutputPath "test-results.html"
$htmlContent = @"
<!DOCTYPE html>
<html>
<head>
    <title>Windows Melody Recovery Test Results</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .summary { background: #f5f5f5; padding: 15px; border-radius: 5px; margin-bottom: 20px; }
        .passed { color: green; }
        .failed { color: red; }
        .skipped { color: orange; }
        table { border-collapse: collapse; width: 100%; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #f2f2f2; }
    </style>
</head>
<body>
    <h1>Windows Melody Recovery Test Results</h1>
    <div class="summary">
        <h2>Summary</h2>
        <p><strong>Total Tests:</strong> $($TestResults.TotalCount)</p>
        <p><strong>Passed:</strong> <span class="passed">$($TestResults.PassedCount)</span></p>
        <p><strong>Failed:</strong> <span class="failed">$($TestResults.FailedCount)</span></p>
        <p><strong>Skipped:</strong> <span class="skipped">$($TestResults.SkippedCount)</span></p>
        <p><strong>Duration:</strong> $($TestResults.Duration)</p>
    </div>
</body>
</html>
"@
$htmlContent | Out-File -FilePath $htmlPath -Encoding UTF8
Write-Host "✓ HTML report: $htmlPath" -ForegroundColor Green

# Generate JSON report
$jsonPath = Join-Path $OutputPath "test-results.json"
$TestResults | ConvertTo-Json -Depth 10 | Out-File -FilePath $jsonPath -Encoding UTF8
Write-Host "✓ JSON report: $jsonPath" -ForegroundColor Green

Write-Host "📊 All reports generated successfully!" -ForegroundColor Green 