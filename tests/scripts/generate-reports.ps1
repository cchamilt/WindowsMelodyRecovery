#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Comprehensive Test Result Aggregation and Reporting System

.DESCRIPTION
    This script aggregates test results from multiple sources (Pester, JUnit, custom JSON)
    and generates comprehensive reports including HTML dashboards, trend analysis, and
    detailed analytics for the Windows Melody Recovery testing framework.

.PARAMETER TestResults
    Pester test results object (optional if aggregating from files)

.PARAMETER OutputPath
    Directory to save reports (default: /test-results/reports)

.PARAMETER InputPath
    Directory containing test result files to aggregate (default: /test-results)

.PARAMETER IncludeTrends
    Include trend analysis in reports (requires historical data)

.PARAMETER GenerateAll
    Generate all report formats (HTML, JSON, XML, CSV)

.PARAMETER Verbose
    Enable verbose logging

.PARAMETER EmailNotification
    Send email notification with report summary

.PARAMETER EmailTo
    Email recipients for notifications

.PARAMETER EmailSubject
    Email subject line

.PARAMETER SlackWebhook
    Slack webhook URL for notifications

.PARAMETER SaveToCloud
    Save reports to cloud storage (OneDrive, Dropbox, etc.)

.PARAMETER CloudPath
    Cloud storage path for saving reports

.EXAMPLE
    ./generate-reports.ps1 -GenerateAll -IncludeTrends -EmailNotification -EmailTo "team@company.com"

.EXAMPLE
    ./generate-reports.ps1 -GenerateAll -SlackWebhook "https://hooks.slack.com/..." -SaveToCloud
#>

param(
    [Parameter(Mandatory=$false)]
    [object]$TestResults,

    [string]$OutputPath = "/test-results/reports",

    [string]$InputPath = "/test-results",

    [switch]$IncludeTrends,

    [switch]$GenerateAll,

    [switch]$VerboseLogging,

    [switch]$EmailNotification,

    [string]$EmailTo,

    [string]$EmailSubject,

    [string]$SlackWebhook,

    [switch]$SaveToCloud,

    [string]$CloudPath
)

# Enhanced logging function
function Write-ReportLog {
    param(
        [string]$Message,
        [ValidateSet("INFO", "SUCCESS", "WARN", "ERROR")]
        [string]$Level = "INFO",
        [string]$Component = "REPORT"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $colorMap = @{
        "INFO" = "White"
        "SUCCESS" = "Green"
        "WARN" = "Yellow"
        "ERROR" = "Red"
    }

    $logMessage = "[$timestamp] [$Level] [$Component] $Message"
    Write-Information -MessageData $logMessage  -InformationAction Continue-ForegroundColor $colorMap[$Level]

    if ($VerboseLogging) {
        $logFile = Join-Path $OutputPath "report-generation.log"
        $logMessage | Out-File -FilePath $logFile -Append -Encoding UTF8
    }
}

# Test result aggregation class
class TestResultAggregator {
    [System.Collections.ArrayList]$AllResults = @()
    [hashtable]$Summary = @{}
    [hashtable]$TrendData = @{}
    [string]$GeneratedAt
    [string]$Version = "1.0.0"

    TestResultAggregator() {
        $this.GeneratedAt = Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"
        $this.Summary = @{
            TotalTestSuites = 0
            TotalTests = 0
            TotalPassed = 0
            TotalFailed = 0
            TotalSkipped = 0
            OverallSuccessRate = 0.0
            TotalDuration = [TimeSpan]::Zero
            TestSuiteBreakdown = @{}
            CategoryBreakdown = @{}
        }
    }

    [void] AddPesterResults([object]$PesterResults, [string]$TestSuite) {
        Write-ReportLog "Adding Pester results for test suite: $TestSuite" "INFO" "AGGREGATOR"

        $testSuiteResult = @{
            Type = "Pester"
            TestSuite = $TestSuite
            TotalCount = $PesterResults.TotalCount
            PassedCount = $PesterResults.PassedCount
            FailedCount = $PesterResults.FailedCount
            SkippedCount = $PesterResults.SkippedCount
            Duration = $PesterResults.Duration
            SuccessRate = if ($PesterResults.TotalCount -gt 0) {
                [math]::Round(($PesterResults.PassedCount / $PesterResults.TotalCount) * 100, 2)
            } else { 0 }
            Timestamp = $this.GeneratedAt
            Tests = @()
        }

        # Extract individual test details if available
        if ($PesterResults.Tests) {
            foreach ($test in $PesterResults.Tests) {
                $testSuiteResult.Tests += @{
                    Name = $test.Name
                    Result = $test.Result
                    Duration = $test.Duration
                    ErrorRecord = if ($test.ErrorRecord) { $test.ErrorRecord.ToString() } else { $null }
                }
            }
        }

        $this.AllResults.Add($testSuiteResult)
        $this.UpdateSummary($testSuiteResult)
    }

    [void] AddJsonResults([string]$JsonPath) {
        Write-ReportLog "Adding JSON results from: $JsonPath" "INFO" "AGGREGATOR"

        try {
            $jsonContent = Get-Content $JsonPath -Raw | ConvertFrom-Json

            # Handle different JSON formats
            if ($jsonContent.TestSuite) {
                # Custom test suite format
                $testSuiteResult = @{
                    Type = "JSON"
                    TestSuite = $jsonContent.TestSuite
                    TotalCount = $jsonContent.Summary.TotalPassed + $jsonContent.Summary.TotalFailed + $jsonContent.Summary.TotalSkipped
                    PassedCount = $jsonContent.Summary.TotalPassed
                    FailedCount = $jsonContent.Summary.TotalFailed
                    SkippedCount = $jsonContent.Summary.TotalSkipped
                    Duration = [TimeSpan]::Parse("00:00:00")  # Default if not available
                    SuccessRate = $jsonContent.Summary.SuccessRate
                    Timestamp = $jsonContent.TestRun.StartTime
                    Tests = $jsonContent.Results
                }

                $this.AllResults.Add($testSuiteResult)
                $this.UpdateSummary($testSuiteResult)
            }
        } catch {
            Write-ReportLog "Failed to parse JSON file $JsonPath`: $($_.Exception.Message)" "ERROR" "AGGREGATOR"
        }
    }

    [void] AddJUnitResults([string]$JUnitPath) {
        Write-ReportLog "Adding JUnit XML results from: $JUnitPath" "INFO" "AGGREGATOR"

        try {
            [xml]$junitXml = Get-Content $JUnitPath

            foreach ($testSuite in $junitXml.SelectNodes("//test-suite[@type='TestFixture']")) {
                $testSuiteResult = @{
                    Type = "JUnit"
                    TestSuite = $testSuite.name
                    TotalCount = [int]$testSuite.asserts
                    PassedCount = 0
                    FailedCount = 0
                    SkippedCount = 0
                    Duration = [TimeSpan]::FromSeconds([double]$testSuite.time)
                    SuccessRate = 0
                    Timestamp = $this.GeneratedAt
                    Tests = @()
                }

                # Count test results
                foreach ($testCase in $testSuite.SelectNodes(".//test-case")) {
                    $testResult = @{
                        Name = $testCase.name
                        Duration = [TimeSpan]::FromSeconds([double]$testCase.time)
                    }

                    if ($testCase.success -eq "True") {
                        $testSuiteResult.PassedCount++
                        $testResult.Result = "Passed"
                    } else {
                        $testSuiteResult.FailedCount++
                        $testResult.Result = "Failed"
                        $testResult.ErrorRecord = $testCase.SelectSingleNode(".//message")?.InnerText
                    }

                    $testSuiteResult.Tests += $testResult
                }

                $testSuiteResult.TotalCount = $testSuiteResult.PassedCount + $testSuiteResult.FailedCount + $testSuiteResult.SkippedCount
                if ($testSuiteResult.TotalCount -gt 0) {
                    $testSuiteResult.SuccessRate = [math]::Round(($testSuiteResult.PassedCount / $testSuiteResult.TotalCount) * 100, 2)
                }

                $this.AllResults.Add($testSuiteResult)
                $this.UpdateSummary($testSuiteResult)
            }
        } catch {
            Write-ReportLog "Failed to parse JUnit XML file $JUnitPath`: $($_.Exception.Message)" "ERROR" "AGGREGATOR"
        }
    }

    [void] UpdateSummary([hashtable]$TestSuiteResult) {
        $this.Summary.TotalTestSuites++
        $this.Summary.TotalTests += $TestSuiteResult.TotalCount
        $this.Summary.TotalPassed += $TestSuiteResult.PassedCount
        $this.Summary.TotalFailed += $TestSuiteResult.FailedCount
        $this.Summary.TotalSkipped += $TestSuiteResult.SkippedCount
        $this.Summary.TotalDuration = $this.Summary.TotalDuration.Add($TestSuiteResult.Duration)

        # Calculate overall success rate
        if ($this.Summary.TotalTests -gt 0) {
            $this.Summary.OverallSuccessRate = [math]::Round(($this.Summary.TotalPassed / $this.Summary.TotalTests) * 100, 2)
        }

        # Update test suite breakdown
        $this.Summary.TestSuiteBreakdown[$TestSuiteResult.TestSuite] = @{
            TotalCount = $TestSuiteResult.TotalCount
            PassedCount = $TestSuiteResult.PassedCount
            FailedCount = $TestSuiteResult.FailedCount
            SkippedCount = $TestSuiteResult.SkippedCount
            SuccessRate = $TestSuiteResult.SuccessRate
            Duration = $TestSuiteResult.Duration
        }

        # Update category breakdown (categorize by test suite name)
        $category = $this.CategorizeTestSuite($TestSuiteResult.TestSuite)
        if (-not $this.Summary.CategoryBreakdown.ContainsKey($category)) {
            $this.Summary.CategoryBreakdown[$category] = @{
                TotalCount = 0
                PassedCount = 0
                FailedCount = 0
                SkippedCount = 0
                TestSuites = @()
            }
        }

        $this.Summary.CategoryBreakdown[$category].TotalCount += $TestSuiteResult.TotalCount
        $this.Summary.CategoryBreakdown[$category].PassedCount += $TestSuiteResult.PassedCount
        $this.Summary.CategoryBreakdown[$category].FailedCount += $TestSuiteResult.FailedCount
        $this.Summary.CategoryBreakdown[$category].SkippedCount += $TestSuiteResult.SkippedCount
        $this.Summary.CategoryBreakdown[$category].TestSuites += $TestSuiteResult.TestSuite
    }

    [string] CategorizeTestSuite([string]$TestSuiteName) {
        $categories = @{
            "Unit" = @("unit", "module", "function", "class")
            "Integration" = @("integration", "backup", "restore", "wsl", "installation")
            "System" = @("system", "registry", "file", "application")
            "Network" = @("network", "cloud", "connectivity")
            "Security" = @("security", "encryption", "auth")
            "Performance" = @("performance", "load", "stress")
        }

        $lowerName = $TestSuiteName.ToLower()
        foreach ($category in $categories.Keys) {
            foreach ($keyword in $categories[$category]) {
                if ($lowerName -contains $keyword) {
                    return $category
                }
            }
        }

        return "Other"
    }

    [hashtable] GetAggregatedResults() {
        return @{
            Metadata = @{
                GeneratedAt = $this.GeneratedAt
                Version = $this.Version
                AggregatorType = "WindowsMelodyRecovery"
            }
            Summary = $this.Summary
            TestSuites = $this.AllResults
            TrendData = $this.TrendData
        }
    }

    [void] LoadHistoricalData([string]$HistoryPath) {
        Write-ReportLog "Loading historical test data from: $HistoryPath" "INFO" "TREND"

        if (Test-Path $HistoryPath) {
            try {
                $historicalFiles = Get-ChildItem $HistoryPath -Filter "*.json" | Sort-Object LastWriteTime -Descending | Select-Object -First 10

                foreach ($file in $historicalFiles) {
                    $historicalData = Get-Content $file.FullName | ConvertFrom-Json

                    if ($historicalData.Summary -and $historicalData.Metadata) {
                        $trendPoint = @{
                            Date = $historicalData.Metadata.GeneratedAt
                            TotalTests = $historicalData.Summary.TotalTests
                            PassedTests = $historicalData.Summary.TotalPassed
                            FailedTests = $historicalData.Summary.TotalFailed
                            SuccessRate = $historicalData.Summary.OverallSuccessRate
                            Duration = $historicalData.Summary.TotalDuration
                            TestSuites = $historicalData.Summary.TotalTestSuites
                            FileName = $file.Name
                        }

                        if (-not $this.TrendData.ContainsKey("Historical")) {
                            $this.TrendData["Historical"] = @()
                        }

                        $this.TrendData["Historical"] += $trendPoint
                    }
                }

                Write-ReportLog "Loaded $($this.TrendData["Historical"].Count) historical data points" "SUCCESS" "TREND"
            } catch {
                Write-ReportLog "Failed to load historical data: $($_.Exception.Message)" "ERROR" "TREND"
            }
        } else {
            Write-ReportLog "No historical data directory found at: $HistoryPath" "WARN" "TREND"
        }
    }

    [hashtable] CalculateTrends() {
        Write-ReportLog "Calculating test trends and metrics" "INFO" "TREND"

        $trends = @{
            SuccessRateTrend = "stable"
            SuccessRateChange = 0
            TestCountTrend = "stable"
            TestCountChange = 0
            DurationTrend = "stable"
            DurationChange = 0
            RecentPerformance = @()
            Recommendations = @()
        }

        if ($this.TrendData.ContainsKey("Historical") -and $this.TrendData["Historical"].Count -gt 1) {
            $historicalData = $this.TrendData["Historical"] | Sort-Object Date
            $latest = $historicalData[-1]
            $previous = $historicalData[-2]

            # Calculate success rate trend
            $successRateChange = $latest.SuccessRate - $previous.SuccessRate
            $trends.SuccessRateChange = [math]::Round($successRateChange, 2)

            if ($successRateChange -gt 5) {
                $trends.SuccessRateTrend = "improving"
            } elseif ($successRateChange -lt -5) {
                $trends.SuccessRateTrend = "declining"
            }

            # Calculate test count trend
            $testCountChange = $latest.TotalTests - $previous.TotalTests
            $trends.TestCountChange = $testCountChange

            if ($testCountChange -gt 10) {
                $trends.TestCountTrend = "increasing"
            } elseif ($testCountChange -lt -10) {
                $trends.TestCountTrend = "decreasing"
            }

            # Calculate duration trend (if available)
            if ($latest.Duration -and $previous.Duration) {
                try {
                    $latestDuration = [TimeSpan]::Parse($latest.Duration)
                    $previousDuration = [TimeSpan]::Parse($previous.Duration)
                    $durationChange = $latestDuration.TotalSeconds - $previousDuration.TotalSeconds
                    $trends.DurationChange = [math]::Round($durationChange, 2)

                    if ($durationChange -gt 60) {
                        $trends.DurationTrend = "slower"
                    } elseif ($durationChange -lt -60) {
                        $trends.DurationTrend = "faster"
                    }
                } catch {
                    Write-ReportLog "Could not parse duration data for trend analysis" "WARN" "TREND"
                }
            }

            # Generate recent performance summary
            $recentData = $historicalData | Select-Object -Last 5
            foreach ($dataPoint in $recentData) {
                $trends.RecentPerformance += @{
                    Date = $dataPoint.Date
                    SuccessRate = $dataPoint.SuccessRate
                    TotalTests = $dataPoint.TotalTests
                    Duration = $dataPoint.Duration
                }
            }

            # Generate recommendations
            if ($trends.SuccessRateTrend -eq "declining") {
                $trends.Recommendations += "🔴 Success rate is declining. Review failed tests and improve test stability."
            } elseif ($trends.SuccessRateTrend -eq "improving") {
                $trends.Recommendations += "🟢 Success rate is improving. Continue current testing practices."
            }

            if ($trends.DurationTrend -eq "slower") {
                $trends.Recommendations += "🟡 Test execution is getting slower. Consider optimizing test performance."
            } elseif ($trends.DurationTrend -eq "faster") {
                $trends.Recommendations += "🟢 Test execution is getting faster. Good optimization work!"
            }

            if ($trends.TestCountTrend -eq "increasing") {
                $trends.Recommendations += "📈 Test coverage is expanding. Ensure new tests are meaningful and maintainable."
            }

            # Quality trend analysis
            $avgSuccessRate = ($recentData | Measure-Object -Property SuccessRate -Average).Average
            if ($avgSuccessRate -lt 70) {
                $trends.Recommendations += "⚠️ Average success rate is below 70%. Focus on test stability and bug fixes."
            } elseif ($avgSuccessRate -gt 90) {
                $trends.Recommendations += "🎉 Excellent test success rate! Consider adding more challenging test scenarios."
            }
        } else {
            $trends.Recommendations += "📊 Insufficient historical data for trend analysis. Continue running tests to build trend data."
        }

        return $trends
    }

    [void] SaveCurrentResults([string]$HistoryPath) {
        Write-ReportLog "Saving current results to history: $HistoryPath" "INFO" "TREND"

        try {
            if (-not (Test-Path $HistoryPath)) {
                New-Item -Path $HistoryPath -ItemType Directory -Force | Out-Null
            }

            $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
            $historyFile = Join-Path $HistoryPath "test-results-$timestamp.json"

            $currentResults = $this.GetAggregatedResults()
            $currentResults | ConvertTo-Json -Depth 10 | Out-File -FilePath $historyFile -Encoding UTF8

            Write-ReportLog "Current results saved to: $historyFile" "SUCCESS" "TREND"

            # Clean up old files (keep last 30)
            $oldFiles = Get-ChildItem $HistoryPath -Filter "*.json" | Sort-Object LastWriteTime -Descending | Select-Object -Skip 30
            foreach ($oldFile in $oldFiles) {
                Remove-Item $oldFile.FullName -Force
                Write-ReportLog "Cleaned up old history file: $($oldFile.Name)" "INFO" "TREND"
            }
        } catch {
            Write-ReportLog "Failed to save current results to history: $($_.Exception.Message)" "ERROR" "TREND"
        }
    }
}

# Report generator functions
function New-HtmlDashboard {
    param(
        [hashtable]$AggregatedResults,
        [string]$OutputPath
    )

    Write-ReportLog "Generating enhanced HTML dashboard with advanced analytics" "INFO" "HTML"

    $summary = $AggregatedResults.Summary
    $testSuites = $AggregatedResults.TestSuites
    $trends = $AggregatedResults.TrendData["CurrentTrends"]
    $historicalData = $AggregatedResults.TrendData["Historical"]

    # Calculate additional analytics
    $analytics = @{
        AverageTestsPerSuite = if ($summary.TotalTestSuites -gt 0) { [math]::Round($summary.TotalTests / $summary.TotalTestSuites, 1) } else { 0 }
        AverageDurationPerTest = if ($summary.TotalTests -gt 0) { [math]::Round($summary.TotalDuration.TotalSeconds / $summary.TotalTests, 2) } else { 0 }
        FastestSuite = ($testSuites | Sort-Object { [double]$_.Duration.TotalSeconds } | Select-Object -First 1)
        SlowestSuite = ($testSuites | Sort-Object { [double]$_.Duration.TotalSeconds } -Descending | Select-Object -First 1)
        MostTestsSuite = ($testSuites | Sort-Object TotalCount -Descending | Select-Object -First 1)
        HighestSuccessRate = ($testSuites | Sort-Object SuccessRate -Descending | Select-Object -First 1)
        LowestSuccessRate = ($testSuites | Sort-Object SuccessRate | Select-Object -First 1)
    }

    $htmlContent = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Windows Melody Recovery - Advanced Test Dashboard</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: #333;
            min-height: 100vh;
        }
        .container { max-width: 1400px; margin: 0 auto; padding: 20px; }
        .header {
            background: rgba(255, 255, 255, 0.95);
            color: #333;
            padding: 30px;
            border-radius: 15px;
            margin-bottom: 30px;
            text-align: center;
            backdrop-filter: blur(10px);
            box-shadow: 0 8px 32px rgba(0,0,0,0.1);
        }
        .header h1 { font-size: 3em; margin-bottom: 10px; background: linear-gradient(135deg, #667eea, #764ba2); -webkit-background-clip: text; -webkit-text-fill-color: transparent; }
        .header p { font-size: 1.2em; opacity: 0.8; }
        .nav-tabs { display: flex; justify-content: center; margin-bottom: 30px; }
        .nav-tab {
            background: rgba(255, 255, 255, 0.9);
            border: none;
            padding: 15px 30px;
            margin: 0 5px;
            border-radius: 10px;
            cursor: pointer;
            font-size: 1em;
            transition: all 0.3s ease;
            box-shadow: 0 4px 15px rgba(0,0,0,0.1);
        }
        .nav-tab:hover, .nav-tab.active {
            background: rgba(255, 255, 255, 1);
            transform: translateY(-2px);
            box-shadow: 0 6px 20px rgba(0,0,0,0.15);
        }
        .tab-content { display: none; }
        .tab-content.active { display: block; }
        .summary-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(280px, 1fr)); gap: 20px; margin-bottom: 30px; }
        .summary-card {
            background: rgba(255, 255, 255, 0.95);
            padding: 25px;
            border-radius: 15px;
            text-align: center;
            backdrop-filter: blur(10px);
            box-shadow: 0 8px 32px rgba(0,0,0,0.1);
            transition: transform 0.3s ease;
        }
        .summary-card:hover { transform: translateY(-5px); }
        .summary-card h3 { color: #666; font-size: 0.9em; text-transform: uppercase; letter-spacing: 1px; margin-bottom: 10px; }
        .summary-card .value { font-size: 2.5em; font-weight: bold; margin-bottom: 5px; }
        .summary-card .subvalue { font-size: 0.9em; color: #666; }
        .success { color: #4CAF50; }
        .warning { color: #FF9800; }
        .error { color: #f44336; }
        .info { color: #2196F3; }
        .analytics-section, .charts-section, .test-suites-section {
            background: rgba(255, 255, 255, 0.95);
            padding: 30px;
            border-radius: 15px;
            margin-bottom: 30px;
            backdrop-filter: blur(10px);
            box-shadow: 0 8px 32px rgba(0,0,0,0.1);
        }
        .analytics-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 20px; }
        .analytics-card { padding: 20px; border: 1px solid #e0e0e0; border-radius: 10px; background: #f8f9fa; }
        .analytics-card h4 { color: #667eea; margin-bottom: 15px; }
        .analytics-item { display: flex; justify-content: space-between; margin-bottom: 10px; }
        .analytics-item:last-child { margin-bottom: 0; }
        .filter-controls { margin-bottom: 20px; display: flex; gap: 15px; flex-wrap: wrap; align-items: center; }
        .filter-control { padding: 8px 15px; border: 1px solid #ddd; border-radius: 5px; background: white; }
        .test-suite { border: 1px solid #e0e0e0; border-radius: 10px; margin-bottom: 15px; overflow: hidden; transition: all 0.3s ease; }
        .test-suite:hover { box-shadow: 0 4px 15px rgba(0,0,0,0.1); }
        .test-suite-header {
            background: linear-gradient(135deg, #f8f9fa, #e9ecef);
            padding: 20px;
            cursor: pointer;
            display: flex;
            justify-content: space-between;
            align-items: center;
            transition: background 0.3s ease;
        }
        .test-suite-header:hover { background: linear-gradient(135deg, #e9ecef, #dee2e6); }
        .test-suite-content { padding: 20px; display: none; background: #fafafa; }
        .test-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(250px, 1fr)); gap: 15px; }
        .test-item { padding: 15px; border-radius: 8px; border-left: 4px solid; transition: transform 0.2s ease; }
        .test-item:hover { transform: translateX(5px); }
        .test-passed { background: #e8f5e9; border-color: #4CAF50; }
        .test-failed { background: #ffebee; border-color: #f44336; }
        .test-skipped { background: #fff3e0; border-color: #FF9800; }
        .progress-bar { width: 100%; height: 20px; background: #e0e0e0; border-radius: 10px; overflow: hidden; margin: 10px 0; }
        .progress-fill { height: 100%; background: linear-gradient(90deg, #4CAF50, #8BC34A); transition: width 0.3s ease; }
        .timestamp { color: #666; font-size: 0.9em; }
        .footer { text-align: center; margin-top: 30px; color: rgba(255,255,255,0.8); }
        .chart-container { position: relative; height: 400px; margin: 20px 0; }
        .metric-trend { display: flex; align-items: center; gap: 10px; }
        .trend-indicator { font-size: 1.2em; }
        .trend-up { color: #4CAF50; }
        .trend-down { color: #f44336; }
        .trend-stable { color: #666; }
        @media (max-width: 768px) {
            .summary-grid, .analytics-grid { grid-template-columns: 1fr; }
            .container { padding: 10px; }
            .nav-tabs { flex-direction: column; }
            .filter-controls { flex-direction: column; align-items: stretch; }
        }
        .loading { display: none; text-align: center; padding: 50px; }
        .loading.show { display: block; }
        .fade-in { animation: fadeIn 0.5s ease-in; }
        @keyframes fadeIn { from { opacity: 0; } to { opacity: 1; } }
    </style>
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/chartjs-adapter-date-fns/dist/chartjs-adapter-date-fns.bundle.min.js"></script>
</head>
<body>
    <div class="container">
        <div class="header fade-in">
            <h1>🎵 Windows Melody Recovery</h1>
            <p>Advanced Test Analytics Dashboard - Generated $($AggregatedResults.Metadata.GeneratedAt)</p>
        </div>

        <div class="nav-tabs">
            <button class="nav-tab active" onclick="showTab('overview')">📊 Overview</button>
            <button class="nav-tab" onclick="showTab('analytics')">🔍 Analytics</button>
            <button class="nav-tab" onclick="showTab('charts')">📈 Charts</button>
            $(if ($trends) { '<button class="nav-tab" onclick="showTab(''trends'')">📈 Trends</button>' })
            <button class="nav-tab" onclick="showTab('test-suites')">🧪 Test Suites</button>
        </div>

        <div id="overview" class="tab-content active">
            <div class="summary-grid fade-in">
                <div class="summary-card">
                    <h3>Total Test Suites</h3>
                    <div class="value info">$($summary.TotalTestSuites)</div>
                    <div class="subvalue">Across $($summary.CategoryBreakdown.Keys.Count) categories</div>
                </div>
                <div class="summary-card">
                    <h3>Total Tests</h3>
                    <div class="value info">$($summary.TotalTests)</div>
                    <div class="subvalue">Avg $($analytics.AverageTestsPerSuite) per suite</div>
                </div>
                <div class="summary-card">
                    <h3>Passed Tests</h3>
                    <div class="value success">$($summary.TotalPassed)</div>
                    <div class="subvalue">$([math]::Round(($summary.TotalPassed / $summary.TotalTests) * 100, 1))% of total</div>
                </div>
                <div class="summary-card">
                    <h3>Failed Tests</h3>
                    <div class="value error">$($summary.TotalFailed)</div>
                    <div class="subvalue">$([math]::Round(($summary.TotalFailed / $summary.TotalTests) * 100, 1))% of total</div>
                </div>
                <div class="summary-card">
                    <h3>Success Rate</h3>
                    <div class="value $(if ($summary.OverallSuccessRate -ge 90) { 'success' } elseif ($summary.OverallSuccessRate -ge 70) { 'warning' } else { 'error' })">$($summary.OverallSuccessRate)%</div>
                    <div class="progress-bar">
                        <div class="progress-fill" style="width: $($summary.OverallSuccessRate)%"></div>
                    </div>
                </div>
                <div class="summary-card">
                    <h3>Total Duration</h3>
                    <div class="value info">$($summary.TotalDuration.ToString('hh\:mm\:ss'))</div>
                    <div class="subvalue">Avg $($analytics.AverageDurationPerTest)s per test</div>
                </div>
            </div>
        </div>

        <div id="analytics" class="tab-content">
            <div class="analytics-section fade-in">
                <h2>📊 Detailed Analytics</h2>
                <div class="analytics-grid">
                    <div class="analytics-card">
                        <h4>🏆 Performance Leaders</h4>
                        <div class="analytics-item">
                            <span>Fastest Suite:</span>
                            <span><strong>$($analytics.FastestSuite.TestSuite)</strong> ($($analytics.FastestSuite.Duration.TotalSeconds)s)</span>
                        </div>
                        <div class="analytics-item">
                            <span>Highest Success Rate:</span>
                            <span><strong>$($analytics.HighestSuccessRate.TestSuite)</strong> ($($analytics.HighestSuccessRate.SuccessRate)%)</span>
                        </div>
                        <div class="analytics-item">
                            <span>Most Tests:</span>
                            <span><strong>$($analytics.MostTestsSuite.TestSuite)</strong> ($($analytics.MostTestsSuite.TotalCount) tests)</span>
                        </div>
                    </div>

                    <div class="analytics-card">
                        <h4>⚠️ Areas for Improvement</h4>
                        <div class="analytics-item">
                            <span>Slowest Suite:</span>
                            <span><strong>$($analytics.SlowestSuite.TestSuite)</strong> ($($analytics.SlowestSuite.Duration.TotalSeconds)s)</span>
                        </div>
                        <div class="analytics-item">
                            <span>Lowest Success Rate:</span>
                            <span><strong>$($analytics.LowestSuccessRate.TestSuite)</strong> ($($analytics.LowestSuccessRate.SuccessRate)%)</span>
                        </div>
                        <div class="analytics-item">
                            <span>Failed Test Ratio:</span>
                            <span><strong>$([math]::Round(($summary.TotalFailed / $summary.TotalTests) * 100, 1))%</strong> need attention</span>
                        </div>
                    </div>

                    <div class="analytics-card">
                        <h4>📈 Test Distribution</h4>
"@

    # Add category breakdown to analytics
    foreach ($category in $summary.CategoryBreakdown.Keys) {
        $categoryData = $summary.CategoryBreakdown[$category]
        $categorySuccessRate = if ($categoryData.TotalCount -gt 0) { [math]::Round(($categoryData.PassedCount / $categoryData.TotalCount) * 100, 1) } else { 0 }
        $htmlContent += @"
                        <div class="analytics-item">
                            <span>$category Tests:</span>
                            <span><strong>$($categoryData.TotalCount)</strong> ($categorySuccessRate% success)</span>
                        </div>
"@
    }

    $htmlContent += @"
                    </div>
                </div>
            </div>
        </div>

        <div id="charts" class="tab-content">
            <div class="charts-section fade-in">
                <h2>📈 Visual Analytics</h2>
                <div class="chart-container">
                    <canvas id="categoryChart"></canvas>
                </div>
                <div class="chart-container">
                    <canvas id="successRateChart"></canvas>
                </div>
                <div class="chart-container">
                    <canvas id="durationChart"></canvas>
                </div>
            </div>
        </div>
"@

    # Add trends section if trend data is available
    if ($trends) {
        $htmlContent += @"

        <div id="trends" class="tab-content">
            <div class="analytics-section fade-in">
                <h2>📈 Trend Analysis & Historical Comparison</h2>

                <div class="analytics-grid">
                    <div class="analytics-card">
                        <h4>🎯 Current Trends</h4>
                        <div class="analytics-item">
                            <span>Success Rate Trend:</span>
                            <span class="metric-trend">
                                <strong>$($trends.SuccessRateTrend)</strong> ($($trends.SuccessRateChange)%)
                            </span>
                        </div>
                        <div class="analytics-item">
                            <span>Test Count Trend:</span>
                            <span class="metric-trend">
                                <strong>$($trends.TestCountTrend)</strong> ($($trends.TestCountChange))
                            </span>
                        </div>
                        <div class="analytics-item">
                            <span>Duration Trend:</span>
                            <span class="metric-trend">
                                <strong>$($trends.DurationTrend)</strong> ($($trends.DurationChange)s)
                            </span>
                        </div>
                    </div>

                    <div class="analytics-card">
                        <h4>💡 Recommendations</h4>
"@

        foreach ($recommendation in $trends.Recommendations) {
            $htmlContent += @"
                        <div class="analytics-item">
                            <span>$recommendation</span>
                        </div>
"@
        }

        $htmlContent += @"
                    </div>
                </div>
            </div>
        </div>
"@
    }

    $htmlContent += @"

        <div id="test-suites" class="tab-content">
            <div class="test-suites-section fade-in">
                <h2>🧪 Test Suite Details</h2>
                <div class="filter-controls">
                    <select id="categoryFilter" class="filter-control" onchange="filterTestSuites()">
                        <option value="">All Categories</option>
"@

    # Add category filter options
    foreach ($category in $summary.CategoryBreakdown.Keys) {
        $htmlContent += "<option value='$category'>$category</option>"
    }

    $htmlContent += @"
                    </select>
                    <select id="statusFilter" class="filter-control" onchange="filterTestSuites()">
                        <option value="">All Results</option>
                        <option value="passed">Passed Only</option>
                        <option value="failed">Failed Only</option>
                        <option value="mixed">Mixed Results</option>
                    </select>
                    <input type="text" id="searchFilter" class="filter-control" placeholder="Search test suites..." onkeyup="filterTestSuites()">
                </div>
                <div id="testSuitesContainer">
"@

    # Add test suite details with enhanced information
    foreach ($testSuite in ($testSuites | Sort-Object SuccessRate)) {
        $statusClass = if ($testSuite.SuccessRate -eq 100) { "success" } elseif ($testSuite.SuccessRate -ge 70) { "warning" } else { "error" }
        $category = $aggregator.CategorizeTestSuite($testSuite.TestSuite)

        $htmlContent += @"
                    <div class="test-suite" data-category="$category" data-status="$(if ($testSuite.SuccessRate -eq 100) { 'passed' } elseif ($testSuite.FailedCount -eq 0) { 'passed' } elseif ($testSuite.PassedCount -eq 0) { 'failed' } else { 'mixed' })" data-name="$($testSuite.TestSuite.ToLower())">
                        <div class="test-suite-header" onclick="toggleTestSuite('$($testSuite.TestSuite.Replace(' ', '_').Replace('-', '_').Replace('.', '_'))')">
                            <div>
                                <strong>$($testSuite.TestSuite)</strong>
                                <div class="timestamp">
                                    <span class="info">$($testSuite.Type)</span> •
                                    <span class="info">$category</span> •
                                    <span class="info">Duration: $($testSuite.Duration.TotalSeconds)s</span>
                                </div>
                            </div>
                            <div>
                                <span class="$statusClass">$($testSuite.PassedCount)/$($testSuite.TotalCount) passed ($($testSuite.SuccessRate)%)</span>
                            </div>
                        </div>
                        <div class="test-suite-content" id="content_$($testSuite.TestSuite.Replace(' ', '_').Replace('-', '_').Replace('.', '_'))">
                            <div class="test-grid">
"@

        # Add individual test details if available
        if ($testSuite.Tests -and $testSuite.Tests.Count -gt 0) {
            foreach ($test in ($testSuite.Tests | Select-Object -First 20)) {  # Limit to first 20 for performance
                $testClass = switch ($test.Result) {
                    "Passed" { "test-passed" }
                    "Failed" { "test-failed" }
                    default { "test-skipped" }
                }

                $htmlContent += @"
                                <div class="test-item $testClass">
                                    <strong>$($test.Name)</strong><br>
                                    <small>Result: $($test.Result)</small>
                                    $(if ($test.Duration) { "<br><small>Duration: $($test.Duration)</small>" })
                                    $(if ($test.ErrorRecord) { "<br><small style='color: red;'>Error: $([System.Web.HttpUtility]::HtmlEncode($test.ErrorRecord.Substring(0, [Math]::Min(100, $test.ErrorRecord.Length))))</small>" })
                                </div>
"@
            }

            if ($testSuite.Tests.Count -gt 20) {
                $htmlContent += @"
                                <div class="test-item">
                                    <p><em>... and $($testSuite.Tests.Count - 20) more tests</em></p>
                                </div>
"@
            }
        } else {
            $htmlContent += @"
                                <div class="test-item">
                                    <p>No detailed test information available for this suite.</p>
                                </div>
"@
        }

        $htmlContent += @"
                            </div>
                        </div>
                    </div>
"@
    }

    $htmlContent += @"
                </div>
            </div>
        </div>

        <div class="footer">
            <p>Generated by Windows Melody Recovery Test Framework v$($AggregatedResults.Metadata.Version)</p>
            <p class="timestamp">$($AggregatedResults.Metadata.GeneratedAt)</p>
        </div>
    </div>

    <script>
        // Tab management
        function showTab(tabName) {
            // Hide all tab contents
            document.querySelectorAll('.tab-content').forEach(tab => {
                tab.classList.remove('active');
            });

            // Remove active class from all tabs
            document.querySelectorAll('.nav-tab').forEach(tab => {
                tab.classList.remove('active');
            });

            // Show selected tab
            document.getElementById(tabName).classList.add('active');
            event.target.classList.add('active');

            // Initialize charts when charts tab is shown
            if (tabName === 'charts') {
                setTimeout(initializeCharts, 100);
            }
        }

        // Test suite toggle
        function toggleTestSuite(id) {
            const content = document.getElementById('content_' + id);
            if (content) {
                content.style.display = content.style.display === 'none' ? 'block' : 'none';
            }
        }

        // Filter test suites
        function filterTestSuites() {
            const categoryFilter = document.getElementById('categoryFilter').value.toLowerCase();
            const statusFilter = document.getElementById('statusFilter').value.toLowerCase();
            const searchFilter = document.getElementById('searchFilter').value.toLowerCase();

            document.querySelectorAll('.test-suite').forEach(suite => {
                const category = suite.getAttribute('data-category').toLowerCase();
                const status = suite.getAttribute('data-status').toLowerCase();
                const name = suite.getAttribute('data-name').toLowerCase();

                const categoryMatch = !categoryFilter || category === categoryFilter;
                const statusMatch = !statusFilter || status === statusFilter;
                const searchMatch = !searchFilter || name.includes(searchFilter);

                suite.style.display = (categoryMatch && statusMatch && searchMatch) ? 'block' : 'none';
            });
        }

        // Initialize charts
        function initializeCharts() {
            // Category distribution chart
            const categoryCtx = document.getElementById('categoryChart');
            if (categoryCtx && !categoryCtx.chart) {
                const categoryData = {
                    labels: [$(($summary.CategoryBreakdown.Keys | ForEach-Object { "'$_'" }) -join ', ')],
                    datasets: [{
                        label: 'Passed Tests',
                        data: [$(($summary.CategoryBreakdown.Values | ForEach-Object { $_.PassedCount }) -join ', ')],
                        backgroundColor: 'rgba(76, 175, 80, 0.8)',
                        borderColor: 'rgba(76, 175, 80, 1)',
                        borderWidth: 1
                    }, {
                        label: 'Failed Tests',
                        data: [$(($summary.CategoryBreakdown.Values | ForEach-Object { $_.FailedCount }) -join ', ')],
                        backgroundColor: 'rgba(244, 67, 54, 0.8)',
                        borderColor: 'rgba(244, 67, 54, 1)',
                        borderWidth: 1
                    }]
                };

                categoryCtx.chart = new Chart(categoryCtx, {
                    type: 'bar',
                    data: categoryData,
                    options: {
                        responsive: true,
                        maintainAspectRatio: false,
                        plugins: {
                            title: {
                                display: true,
                                text: 'Test Results by Category'
                            }
                        },
                        scales: {
                            x: { stacked: true },
                            y: { stacked: true }
                        }
                    }
                });
            }

            // Success rate chart
            const successCtx = document.getElementById('successRateChart');
            if (successCtx && !successCtx.chart) {
                const suiteNames = [$(($testSuites | ForEach-Object { "'$($_.TestSuite)'" }) -join ', ')];
                const successRates = [$(($testSuites | ForEach-Object { $_.SuccessRate }) -join ', ')];

                successCtx.chart = new Chart(successCtx, {
                    type: 'line',
                    data: {
                        labels: suiteNames,
                        datasets: [{
                            label: 'Success Rate (%)',
                            data: successRates,
                            borderColor: 'rgba(102, 126, 234, 1)',
                            backgroundColor: 'rgba(102, 126, 234, 0.1)',
                            tension: 0.4,
                            fill: true
                        }]
                    },
                    options: {
                        responsive: true,
                        maintainAspectRatio: false,
                        plugins: {
                            title: {
                                display: true,
                                text: 'Success Rate by Test Suite'
                            }
                        },
                        scales: {
                            y: {
                                beginAtZero: true,
                                max: 100
                            }
                        }
                    }
                });
            }

            // Duration chart
            const durationCtx = document.getElementById('durationChart');
            if (durationCtx && !durationCtx.chart) {
                const durations = [$(($testSuites | ForEach-Object { [math]::Round($_.Duration.TotalSeconds, 2) }) -join ', ')];

                durationCtx.chart = new Chart(durationCtx, {
                    type: 'bar',
                    data: {
                        labels: suiteNames,
                        datasets: [{
                            label: 'Duration (seconds)',
                            data: durations,
                            backgroundColor: 'rgba(255, 152, 0, 0.8)',
                            borderColor: 'rgba(255, 152, 0, 1)',
                            borderWidth: 1
                        }]
                    },
                    options: {
                        responsive: true,
                        maintainAspectRatio: false,
                        plugins: {
                            title: {
                                display: true,
                                text: 'Test Duration by Suite'
                            }
                        },
                        scales: {
                            y: {
                                beginAtZero: true
                            }
                        }
                    }
                });
            }
        }

        // Initialize on page load
        document.addEventListener('DOMContentLoaded', function() {
            // Add fade-in animation to elements
            document.querySelectorAll('.fade-in').forEach((el, index) => {
                setTimeout(() => {
                    el.style.opacity = '1';
                }, index * 100);
            });
        });
    </script>
</body>
</html>
"@

    $htmlPath = Join-Path $OutputPath "test-dashboard.html"
    $htmlContent | Out-File -FilePath $htmlPath -Encoding UTF8
    Write-ReportLog "Enhanced HTML dashboard saved: $htmlPath" "SUCCESS" "HTML"

    return $htmlPath
}

function New-JsonReport {
    param(
        [hashtable]$AggregatedResults,
        [string]$OutputPath
    )

    Write-ReportLog "Generating comprehensive JSON report" "INFO" "JSON"

    $jsonPath = Join-Path $OutputPath "comprehensive-test-report.json"
    $AggregatedResults | ConvertTo-Json -Depth 10 | Out-File -FilePath $jsonPath -Encoding UTF8
    Write-ReportLog "JSON report saved: $jsonPath" "SUCCESS" "JSON"

    return $jsonPath
}

function New-CsvReport {
    param(
        [hashtable]$AggregatedResults,
        [string]$OutputPath
    )

    Write-ReportLog "Generating CSV report" "INFO" "CSV"

    $csvData = @()
    foreach ($testSuite in $AggregatedResults.TestSuites) {
        $csvData += [PSCustomObject]@{
            TestSuite = $testSuite.TestSuite
            Type = $testSuite.Type
            TotalTests = $testSuite.TotalCount
            PassedTests = $testSuite.PassedCount
            FailedTests = $testSuite.FailedCount
            SkippedTests = $testSuite.SkippedCount
            SuccessRate = $testSuite.SuccessRate
            Duration = $testSuite.Duration
            Timestamp = $testSuite.Timestamp
        }
    }

    $csvPath = Join-Path $OutputPath "test-results-summary.csv"
    $csvData | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
    Write-ReportLog "CSV report saved: $csvPath" "SUCCESS" "CSV"

    return $csvPath
}

# Notification and delivery functions
function Send-EmailNotification {
    param(
        [hashtable]$Summary,
        [array]$GeneratedReports,
        [hashtable]$Trends,
        [string]$EmailTo,
        [string]$EmailSubject
    )

    Write-ReportLog "Preparing email notification" "INFO" "EMAIL"

    if (-not $EmailTo) {
        Write-ReportLog "No email recipients specified" "WARN" "EMAIL"
        return
    }

    $defaultSubject = "Windows Melody Recovery - Test Report $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
    $subject = if ($EmailSubject) { $EmailSubject } else { $defaultSubject }

    # Create email body
    $successIcon = if ($Summary.OverallSuccessRate -ge 90) { "✅" } elseif ($Summary.OverallSuccessRate -ge 70) { "⚠️" } else { "❌" }
    $trendIcon = if ($Trends -and $Trends.SuccessRateTrend -eq "improving") { "📈" } elseif ($Trends -and $Trends.SuccessRateTrend -eq "declining") { "📉" } else { "➡️" }

    $emailBody = @"
$successIcon Windows Melody Recovery Test Report

📊 SUMMARY
• Test Suites: $($Summary.TotalTestSuites)
• Total Tests: $($Summary.TotalTests)
• Passed: $($Summary.TotalPassed) ✅
• Failed: $($Summary.TotalFailed) ❌
• Success Rate: $($Summary.OverallSuccessRate)% $successIcon
• Duration: $($Summary.TotalDuration)

$trendIcon TRENDS $(if ($Trends) { "(vs Previous Run)" } else { "(First Run)" })
$(if ($Trends) { @"
• Success Rate: $($Trends.SuccessRateTrend) ($($Trends.SuccessRateChange)%)
• Test Count: $($Trends.TestCountTrend) ($($Trends.TestCountChange))
• Performance: $($Trends.DurationTrend) ($($Trends.DurationChange)s)
"@ } else { "• Insufficient data for trend analysis" })

📈 CATEGORY BREAKDOWN
"@

    if ($Summary.CategoryBreakdown) {
        foreach ($category in $Summary.CategoryBreakdown.Keys) {
            $categoryData = $Summary.CategoryBreakdown[$category]
            $categoryRate = if ($categoryData.TotalCount -gt 0) { [math]::Round(($categoryData.PassedCount / $categoryData.TotalCount) * 100, 1) } else { 0 }
            $emailBody += "• $category`: $($categoryData.TotalCount) tests ($categoryRate% success)`n"
        }
    }

    $emailBody += @"

📋 RECOMMENDATIONS
$(if ($Trends -and $Trends.Recommendations) { ($Trends.Recommendations | ForEach-Object { "• $_" }) -join "`n" } else { "• Continue running tests to build trend data" })

🔗 REPORTS GENERATED
$(($GeneratedReports | ForEach-Object { "• $(Split-Path $_ -Leaf)" }) -join "`n")

Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss UTC')
Windows Melody Recovery Test Framework
"@

    try {
        # Try to use Send-MailMessage if available (Windows PowerShell)
        if (Get-Command Send-MailMessage -ErrorAction SilentlyContinue) {
            # Note: This requires SMTP configuration
            Write-ReportLog "Send-MailMessage available but requires SMTP configuration" "WARN" "EMAIL"
            Write-ReportLog "Email body prepared for manual sending or external integration" "INFO" "EMAIL"
        } else {
            Write-ReportLog "Send-MailMessage not available in this environment" "WARN" "EMAIL"
        }

        # Save email content for external processing
        $emailFile = Join-Path $OutputPath "email-notification.txt"
        @"
TO: $EmailTo
SUBJECT: $subject

$emailBody
"@ | Out-File -FilePath $emailFile -Encoding UTF8

        Write-ReportLog "Email content saved to: $emailFile" "SUCCESS" "EMAIL"

    } catch {
        Write-ReportLog "Failed to prepare email notification: $($_.Exception.Message)" "ERROR" "EMAIL"
    }
}

function Send-SlackNotification {
    param(
        [hashtable]$Summary,
        [hashtable]$Trends,
        [string]$SlackWebhook
    )

    Write-ReportLog "Sending Slack notification" "INFO" "SLACK"

    if (-not $SlackWebhook) {
        Write-ReportLog "No Slack webhook URL provided" "WARN" "SLACK"
        return
    }

    $successIcon = if ($Summary.OverallSuccessRate -ge 90) { ":white_check_mark:" } elseif ($Summary.OverallSuccessRate -ge 70) { ":warning:" } else { ":x:" }
    $color = if ($Summary.OverallSuccessRate -ge 90) { "good" } elseif ($Summary.OverallSuccessRate -ge 70) { "warning" } else { "danger" }

    $slackPayload = @{
        text = "Windows Melody Recovery Test Report"
        attachments = @(
            @{
                color = $color
                title = "Test Execution Summary"
                fields = @(
                    @{
                        title = "Success Rate"
                        value = "$($Summary.OverallSuccessRate)% $successIcon"
                        short = $true
                    },
                    @{
                        title = "Total Tests"
                        value = "$($Summary.TotalPassed)/$($Summary.TotalTests) passed"
                        short = $true
                    },
                    @{
                        title = "Test Suites"
                        value = "$($Summary.TotalTestSuites)"
                        short = $true
                    },
                    @{
                        title = "Duration"
                        value = "$($Summary.TotalDuration)"
                        short = $true
                    }
                )
                footer = "Windows Melody Recovery"
                ts = [int][double]::Parse((Get-Date -UFormat %s))
            }
        )
    }

    if ($Trends) {
        $trendIcon = if ($Trends.SuccessRateTrend -eq "improving") { ":chart_with_upwards_trend:" } elseif ($Trends.SuccessRateTrend -eq "declining") { ":chart_with_downwards_trend:" } else { ":arrow_right:" }

        $slackPayload.attachments += @{
            color = "#36a64f"
            title = "Trend Analysis $trendIcon"
            text = "Success Rate: $($Trends.SuccessRateTrend) ($($Trends.SuccessRateChange)%) • Test Count: $($Trends.TestCountTrend) ($($Trends.TestCountChange)) • Performance: $($Trends.DurationTrend)"
        }
    }

    try {
        $jsonPayload = $slackPayload | ConvertTo-Json -Depth 10

        if (Get-Command Invoke-RestMethod -ErrorAction SilentlyContinue) {
            $response = Invoke-RestMethod -Uri $SlackWebhook -Method Post -Body $jsonPayload -ContentType "application/json"
            Write-ReportLog "Slack notification sent successfully" "SUCCESS" "SLACK"
        } else {
            # Save payload for external processing
            $slackFile = Join-Path $OutputPath "slack-notification.json"
            $jsonPayload | Out-File -FilePath $slackFile -Encoding UTF8
            Write-ReportLog "Slack payload saved to: $slackFile (Invoke-RestMethod not available)" "INFO" "SLACK"
        }

    } catch {
        Write-ReportLog "Failed to send Slack notification: $($_.Exception.Message)" "ERROR" "SLACK"
    }
}

function Save-ReportsToCloud {
    param(
        [array]$GeneratedReports,
        [string]$CloudPath
    )

    Write-ReportLog "Saving reports to cloud storage" "INFO" "CLOUD"

    if (-not $CloudPath) {
        # Try to detect common cloud storage paths
        $possiblePaths = @(
            "$env:OneDrive\WindowsMelodyRecovery\TestReports",
            "$env:USERPROFILE\OneDrive\WindowsMelodyRecovery\TestReports",
            "$env:USERPROFILE\Dropbox\WindowsMelodyRecovery\TestReports",
            "$env:USERPROFILE\Google Drive\WindowsMelodyRecovery\TestReports"
        )

        foreach ($path in $possiblePaths) {
            if ($path -and (Test-Path (Split-Path $path -Parent))) {
                $CloudPath = $path
                Write-ReportLog "Auto-detected cloud path: $CloudPath" "INFO" "CLOUD"
                break
            }
        }

        if (-not $CloudPath) {
            Write-ReportLog "No cloud storage path specified or detected" "WARN" "CLOUD"
            return
        }
    }

    try {
        # Create cloud directory if it doesn't exist
        if (-not (Test-Path $CloudPath)) {
            New-Item -Path $CloudPath -ItemType Directory -Force | Out-Null
            Write-ReportLog "Created cloud directory: $CloudPath" "SUCCESS" "CLOUD"
        }

        # Copy reports to cloud storage
        $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
        $cloudReportDir = Join-Path $CloudPath "TestRun_$timestamp"
        New-Item -Path $cloudReportDir -ItemType Directory -Force | Out-Null

        foreach ($report in $GeneratedReports) {
            $fileName = Split-Path $report -Leaf
            $destination = Join-Path $cloudReportDir $fileName
            Copy-Item -Path $report -Destination $destination -Force
            Write-ReportLog "Copied $fileName to cloud storage" "SUCCESS" "CLOUD"
        }

        # Create a summary file
        $summaryFile = Join-Path $cloudReportDir "README.txt"
        @"
Windows Melody Recovery Test Reports
Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss UTC')

Files in this directory:
$(($GeneratedReports | ForEach-Object { "- $(Split-Path $_ -Leaf)" }) -join "`n")

To view the interactive dashboard, open test-dashboard.html in a web browser.
For detailed analysis, refer to comprehensive-test-report.json.
For spreadsheet analysis, use test-results-summary.csv.
"@ | Out-File -FilePath $summaryFile -Encoding UTF8

        Write-ReportLog "Reports successfully saved to cloud storage: $cloudReportDir" "SUCCESS" "CLOUD"

    } catch {
        Write-ReportLog "Failed to save reports to cloud storage: $($_.Exception.Message)" "ERROR" "CLOUD"
    }
}

function Invoke-ReportDelivery {
    param(
        [hashtable]$Summary,
        [array]$GeneratedReports,
        [hashtable]$Trends
    )

    Write-ReportLog "Starting automated report delivery" "INFO" "DELIVERY"

    # Email notification
    if ($EmailNotification) {
        Send-EmailNotification -Summary $Summary -GeneratedReports $GeneratedReports -Trends $Trends -EmailTo $EmailTo -EmailSubject $EmailSubject
    }

    # Slack notification
    if ($SlackWebhook) {
        Send-SlackNotification -Summary $Summary -Trends $Trends -SlackWebhook $SlackWebhook
    }

    # Cloud storage
    if ($SaveToCloud) {
        Save-ReportsToCloud -GeneratedReports $GeneratedReports -CloudPath $CloudPath
    }

    Write-ReportLog "Automated report delivery completed" "SUCCESS" "DELIVERY"
}

# Main execution
function Invoke-ReportGeneration {
    Write-ReportLog "Starting comprehensive test report generation" "INFO" "MAIN"

    # Create output directory
    if (-not (Test-Path $OutputPath)) {
        New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
        Write-ReportLog "Created output directory: $OutputPath" "INFO" "MAIN"
    }

    # Initialize aggregator
    $aggregator = [TestResultAggregator]::new()

    # Load historical data if trend analysis is enabled
    if ($IncludeTrends) {
        $historyPath = Join-Path $OutputPath "history"
        $aggregator.LoadHistoricalData($historyPath)
    }

    # Add Pester results if provided
    if ($TestResults) {
        $aggregator.AddPesterResults($TestResults, "Direct-Pester")
    }

    # Discover and aggregate existing test results
    Write-ReportLog "Discovering test result files in: $InputPath" "INFO" "MAIN"

    # Aggregate JSON reports
    $jsonFiles = Get-ChildItem -Path $InputPath -Filter "*.json" -Recurse -ErrorAction SilentlyContinue
    foreach ($jsonFile in $jsonFiles) {
        if ($jsonFile.Name -notlike "*comprehensive*" -and $jsonFile.Name -notlike "*report-generation*") {
            $aggregator.AddJsonResults($jsonFile.FullName)
        }
    }

    # Aggregate JUnit XML reports
    $xmlFiles = Get-ChildItem -Path $InputPath -Filter "*.xml" -Recurse -ErrorAction SilentlyContinue
    foreach ($xmlFile in $xmlFiles) {
        if ($xmlFile.Name -like "*test*" -or $xmlFile.Name -like "*junit*") {
            $aggregator.AddJUnitResults($xmlFile.FullName)
        }
    }

    # Get aggregated results
    $aggregatedResults = $aggregator.GetAggregatedResults()

    # Calculate trends if enabled
    if ($IncludeTrends) {
        $trends = $aggregator.CalculateTrends()
        $aggregatedResults.TrendData["CurrentTrends"] = $trends
        Write-ReportLog "Trend analysis complete. Trend: $($trends.SuccessRateTrend) success rate, $($trends.TestCountTrend) test count" "SUCCESS" "MAIN"
    }

    Write-ReportLog "Aggregation complete. Found $($aggregatedResults.Summary.TotalTestSuites) test suites with $($aggregatedResults.Summary.TotalTests) total tests" "SUCCESS" "MAIN"

    # Generate reports
    $generatedReports = @()

    if ($GenerateAll -or -not $TestResults) {
        # Generate HTML dashboard
        $htmlPath = New-HtmlDashboard -AggregatedResults $aggregatedResults -OutputPath $OutputPath
        $generatedReports += $htmlPath

        # Generate comprehensive JSON report
        $jsonPath = New-JsonReport -AggregatedResults $aggregatedResults -OutputPath $OutputPath
        $generatedReports += $jsonPath

        # Generate CSV summary
        $csvPath = New-CsvReport -AggregatedResults $aggregatedResults -OutputPath $OutputPath
        $generatedReports += $csvPath
    }

    # Generate summary report for single test results
    if ($TestResults) {
        $summaryPath = Join-Path $OutputPath "single-test-report.json"
        @{
            TestResults = $TestResults
            GeneratedAt = Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"
        } | ConvertTo-Json -Depth 10 | Out-File -FilePath $summaryPath -Encoding UTF8
        $generatedReports += $summaryPath
    }

    # Display summary
    Write-ReportLog "Report generation completed successfully!" "SUCCESS" "MAIN"
    Write-ReportLog "Overall Statistics:" "INFO" "SUMMARY"
    Write-ReportLog "  Test Suites: $($aggregatedResults.Summary.TotalTestSuites)" "INFO" "SUMMARY"
    Write-ReportLog "  Total Tests: $($aggregatedResults.Summary.TotalTests)" "INFO" "SUMMARY"
    Write-ReportLog "  Passed: $($aggregatedResults.Summary.TotalPassed)" "SUCCESS" "SUMMARY"
    Write-ReportLog "  Failed: $($aggregatedResults.Summary.TotalFailed)" $(if ($aggregatedResults.Summary.TotalFailed -gt 0) { "ERROR" } else { "SUCCESS" }) "SUMMARY"
    Write-ReportLog "  Success Rate: $($aggregatedResults.Summary.OverallSuccessRate)%" $(if ($aggregatedResults.Summary.OverallSuccessRate -ge 90) { "SUCCESS" } elseif ($aggregatedResults.Summary.OverallSuccessRate -ge 70) { "WARN" } else { "ERROR" }) "SUMMARY"

    Write-ReportLog "Generated Reports:" "INFO" "SUMMARY"
    foreach ($report in $generatedReports) {
        Write-ReportLog "  - $report" "INFO" "SUMMARY"
    }

    # Save current results to history for future trend analysis
    if ($IncludeTrends) {
        $historyPath = Join-Path $OutputPath "history"
        $aggregator.SaveCurrentResults($historyPath)
    }

    # Automated report delivery
    $trends = if ($IncludeTrends) { $aggregatedResults.TrendData["CurrentTrends"] } else { $null }
    if ($EmailNotification -or $SlackWebhook -or $SaveToCloud) {
        Invoke-ReportDelivery -Summary $aggregatedResults.Summary -GeneratedReports $generatedReports -Trends $trends
    }

    return @{
        AggregatedResults = $aggregatedResults
        GeneratedReports = $generatedReports
        Summary = $aggregatedResults.Summary
        Trends = $trends
    }
}

# Execute main function
Invoke-ReportGeneration







