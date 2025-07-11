# analyze-test-failures.ps1
# Comprehensive analysis of failing tests to categorize for Docker vs Windows-only environments

[CmdletBinding()]
param(
    [string]$TestPath = "tests/unit/",
    [string]$OutputPath = "test-analysis-results.json",
    [switch]$Detailed = $true
)

# Categories for test classification
$TestCategories = @{
    'WindowsPrincipal' = @{
        Description = 'Tests requiring Windows security context, UAC, or administrative privileges'
        Keywords = @('Test-WmrAdminPrivilege', 'Get-WmrPrivilegeRequirements', 'Invoke-WmrWithElevation', 'Principal', 'Elevation', 'Admin')
        TargetEnvironment = 'Windows-Only'
        Priority = 'High'
    }
    'RegistryOperations' = @{
        Description = 'Tests requiring actual Windows registry access'
        Keywords = @('HKLM:', 'HKCU:', 'HKCR:', 'Registry', 'Get-ItemProperty', 'Set-ItemProperty', 'Test-RegistryPath')
        TargetEnvironment = 'Windows-Only'
        Priority = 'High'
    }
    'ScheduledTasks' = @{
        Description = 'Tests requiring Windows Task Scheduler'
        Keywords = @('ScheduledTask', 'Task Scheduler', 'Register-ScheduledTask', 'Get-ScheduledTask')
        TargetEnvironment = 'Windows-Only'
        Priority = 'Medium'
    }
    'WindowsFeatures' = @{
        Description = 'Tests requiring Windows capabilities and optional features'
        Keywords = @('Windows-Features', 'Get-WindowsCapability', 'Enable-WindowsOptionalFeature', 'DISM')
        TargetEnvironment = 'Windows-Only'
        Priority = 'Medium'
    }
    'FileSystemSpecific' = @{
        Description = 'Tests requiring Windows-specific file system features'
        Keywords = @('Cannot find drive', 'drive with the name', 'NTFS', 'file attributes', 'ACL')
        TargetEnvironment = 'Docker-Fixable'
        Priority = 'High'
    }
    'PathIssues' = @{
        Description = 'Tests with hardcoded Windows paths that can be mocked'
        Keywords = @('C:\\', 'C:/', 'Join-Path.*C:', 'Path.*null', 'Cannot bind argument to parameter.*Path')
        TargetEnvironment = 'Docker-Fixable'
        Priority = 'High'
    }
    'FunctionNotFound' = @{
        Description = 'Tests failing due to missing function definitions'
        Keywords = @('not recognized as a name of a cmdlet', 'Could not find Command', 'function.*not found')
        TargetEnvironment = 'Docker-Fixable'
        Priority = 'High'
    }
    'EncryptionEdgeCases' = @{
        Description = 'Expected failures in encryption/decryption edge case testing'
        Keywords = @('Failed to decrypt data', 'Invalid key or corrupted data', 'Decryption failed', 'Invalid Base64')
        TargetEnvironment = 'Docker-Fixable'
        Priority = 'Low'
    }
    'ConfigurationValidation' = @{
        Description = 'Configuration validation edge cases that can be improved'
        Keywords = @('Measure-Object.*not numeric', 'Input object.*is not numeric', 'null.*empty collection')
        TargetEnvironment = 'Docker-Fixable'
        Priority = 'Medium'
    }
    'MockingIssues' = @{
        Description = 'Tests that need better mocking infrastructure'
        Keywords = @('Export-ModuleMember.*only be called from inside a module', 'Mock.*failed', 'Should -Invoke.*0 times')
        TargetEnvironment = 'Docker-Fixable'
        Priority = 'Medium'
    }
}

function Get-TestFailureAnalysis {
    [CmdletBinding()]
    param(
        [string]$TestDirectory
    )

    Write-Information -MessageData "🔍 Analyzing test failures in: $TestDirectory" -InformationAction Continue

    # Run tests and capture detailed failure information
    $testResults = @{
        TotalTests = 0
        PassedTests = 0
        FailedTests = 0
        FailureAnalysis = @()
        CategorySummary = @{}
    }

    # Initialize category counters
    foreach ($category in $TestCategories.Keys) {
        $testResults.CategorySummary[$category] = @{
            Count = 0
            Tests = @()
            TargetEnvironment = $TestCategories[$category].TargetEnvironment
            Priority = $TestCategories[$category].Priority
        }
    }

    # Get all test files
    $testFiles = Get-ChildItem -Path $TestDirectory -Filter "*.Tests.ps1" -Recurse

    foreach ($testFile in $testFiles) {
        Write-Warning -Message "📝 Analyzing: $($testFile.Name)"

        try {
            # Run individual test file to get specific failures
            $result = Invoke-Pester -Path $testFile.FullName -PassThru -Show None

            $testResults.TotalTests += $result.TotalCount
            $testResults.PassedTests += $result.PassedCount
            $testResults.FailedTests += $result.FailedCount

            # Analyze each failed test
            foreach ($failedTest in $result.Failed) {
                $failureInfo = @{
                    TestFile = $testFile.Name
                    TestName = $failedTest.Name
                    ErrorMessage = $failedTest.ErrorRecord.Exception.Message
                    Categories = @()
                    RecommendedAction = ""
                    TargetEnvironment = "Unknown"
                    Priority = "Unknown"
                }

                # Categorize the failure
                $categorized = $false
                foreach ($categoryName in $TestCategories.Keys) {
                    $category = $TestCategories[$categoryName]

                    foreach ($keyword in $category.Keywords) {
                        if ($failureInfo.ErrorMessage -match $keyword -or $failureInfo.TestName -match $keyword) {
                            $failureInfo.Categories += $categoryName
                            $failureInfo.TargetEnvironment = $category.TargetEnvironment
                            $failureInfo.Priority = $category.Priority

                            $testResults.CategorySummary[$categoryName].Count++
                            $testResults.CategorySummary[$categoryName].Tests += $failureInfo.TestName

                            $categorized = $true
                            break
                        }
                    }
                    if ($categorized) { break }
                }

                # Generate recommended action
                if ($failureInfo.TargetEnvironment -eq "Windows-Only") {
                    $failureInfo.RecommendedAction = "Move to tests/windows-only/ directory for CI/CD-only execution"
                } elseif ($failureInfo.TargetEnvironment -eq "Docker-Fixable") {
                    $failureInfo.RecommendedAction = "Fix for Docker compatibility with enhanced mocking"
                } else {
                    $failureInfo.RecommendedAction = "Requires manual analysis to determine proper environment"
                }

                $testResults.FailureAnalysis += $failureInfo
            }

        } catch {
            Write-Warning "Failed to analyze $($testFile.Name): $($_.Exception.Message)"
        }
    }

    return $testResults
}

function New-MigrationPlan {
    param(
        [hashtable]$AnalysisResults
    )

    $migrationPlan = @{
        DockerFixable = @{
            TotalTests = 0
            Categories = @{}
            Files = @()
        }
        WindowsOnly = @{
            TotalTests = 0
            Categories = @{}
            Files = @()
        }
        Summary = @{
            TotalAnalyzed = $AnalysisResults.TotalTests
            CurrentPassed = $AnalysisResults.PassedTests
            CurrentFailed = $AnalysisResults.FailedTests
            DockerTargetTests = 0
            WindowsTargetTests = 0
        }
    }

    # Group by target environment
    foreach ($category in $AnalysisResults.CategorySummary.Keys) {
        $categoryData = $AnalysisResults.CategorySummary[$category]

        if ($categoryData.TargetEnvironment -eq "Docker-Fixable") {
            $migrationPlan.DockerFixable.Categories[$category] = $categoryData
            $migrationPlan.DockerFixable.TotalTests += $categoryData.Count
        } elseif ($categoryData.TargetEnvironment -eq "Windows-Only") {
            $migrationPlan.WindowsOnly.Categories[$category] = $categoryData
            $migrationPlan.WindowsOnly.TotalTests += $categoryData.Count
        }
    }

    $migrationPlan.Summary.DockerTargetTests = $AnalysisResults.PassedTests + $migrationPlan.DockerFixable.TotalTests
    $migrationPlan.Summary.WindowsTargetTests = $migrationPlan.WindowsOnly.TotalTests

    return $migrationPlan
}

function Export-AnalysisResults {
    param(
        [hashtable]$AnalysisResults,
        [hashtable]$MigrationPlan,
        [string]$OutputFile
    )

    $exportData = @{
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Analysis = $AnalysisResults
        MigrationPlan = $MigrationPlan
        Recommendations = @{
            ImmediateActions = @(
                "Fix $($MigrationPlan.DockerFixable.TotalTests) Docker-compatible tests",
                "Move $($MigrationPlan.WindowsOnly.TotalTests) Windows-only tests to separate directory",
                "Target: $($MigrationPlan.Summary.DockerTargetTests) tests in Docker environment (100% pass rate)",
                "Target: $($MigrationPlan.Summary.WindowsTargetTests) tests in Windows CI/CD environment"
            )
            NextSteps = @(
                "Create enhanced Docker mocking for function availability issues",
                "Implement comprehensive path conversion system",
                "Develop Windows-only test safety measures",
                "Set up dual GitHub Actions workflows"
            )
        }
    }

    $exportData | ConvertTo-Json -Depth 10 | Out-File -FilePath $OutputFile -Encoding UTF8
    Write-Information -MessageData "✅ Analysis results exported to: $OutputFile" -InformationAction Continue
}

# Main execution
Write-Information -MessageData "🚀 Starting comprehensive test failure analysis..." -InformationAction Continue

# Ensure we're in Docker environment for consistent testing
if (-not (Test-Path '/.dockerenv') -and $env:DOCKER_TEST -ne 'true') {
    Write-Warning -Message "⚠️  Running analysis in Docker environment for consistency..."

    # Check if Docker containers are running
    try {
        $containerStatus = docker exec wmr-test-runner pwsh -Command "Write-Information -MessageData 'Docker environment ready'" -InformationAction Continue
        if ($LASTEXITCODE -ne 0) {
            Write-Information -MessageData "🐳 Starting Docker test environment..." -InformationAction Continue
            docker-compose -f docker-compose.test.yml up -d
            Start-Sleep -Seconds 10
        }

        # Run analysis in Docker
        docker exec wmr-test-runner pwsh -Command "cd /workspace && pwsh -File 'tests/scripts/analyze-test-failures.ps1' -OutputPath '/workspace/$OutputPath'"

        Write-Information -MessageData "✅ Analysis completed in Docker environment" -InformationAction Continue
        return

    } catch {
        Write-Warning "Failed to run in Docker, proceeding with local analysis: $($_.Exception.Message)"
    }
}

# Run the analysis
$analysisResults = Get-TestFailureAnalysis -TestDirectory $TestPath
$migrationPlan = New-MigrationPlan -AnalysisResults $analysisResults

# Display summary
Write-Information -MessageData "`n📊 ANALYSIS SUMMARY" -InformationAction Continue
Write-Information -MessageData "===================" -InformationAction Continue
Write-Information -MessageData "Total Tests Analyzed: $($analysisResults.TotalTests)"  -InformationAction Continue-ForegroundColor White
Write-Information -MessageData "Currently Passing: $($analysisResults.PassedTests)" -InformationAction Continue
Write-Error -Message "Currently Failing: $($analysisResults.FailedTests)"

Write-Information -MessageData "`n🐳 DOCKER ENVIRONMENT TARGET" -InformationAction Continue
Write-Warning -Message "Docker-Fixable Tests: $($migrationPlan.DockerFixable.TotalTests)"
Write-Information -MessageData "Current Passing: $($analysisResults.PassedTests)" -InformationAction Continue
Write-Information -MessageData "Target Docker Tests: $($migrationPlan.Summary.DockerTargetTests)" -InformationAction Continue
Write-Information -MessageData "Target Pass Rate: 100%" -InformationAction Continue

Write-Verbose -Message "`n🪟 WINDOWS CI/CD TARGET"
Write-Warning -Message "Windows-Only Tests: $($migrationPlan.WindowsOnly.TotalTests)"
Write-Information -MessageData "Target Pass Rate: 90%+" -InformationAction Continue

Write-Warning -Message "`n📂 CATEGORY BREAKDOWN"
foreach ($category in $migrationPlan.DockerFixable.Categories.Keys) {
    $count = $migrationPlan.DockerFixable.Categories[$category].Count
    Write-Information -MessageData "  🔧 $category (Docker-Fixable): $count tests" -InformationAction Continue
}
foreach ($category in $migrationPlan.WindowsOnly.Categories.Keys) {
    $count = $migrationPlan.WindowsOnly.Categories[$category].Count
    Write-Verbose -Message "  🪟 $category (Windows-Only): $count tests"
}

# Export results
Export-AnalysisResults -AnalysisResults $analysisResults -MigrationPlan $migrationPlan -OutputFile $OutputPath

Write-Information -MessageData "`n🎯 NEXT STEPS:" -InformationAction Continue
Write-Information -MessageData "1. Review detailed analysis in $OutputPath"  -InformationAction Continue-ForegroundColor White
Write-Information -MessageData "2. Run test categorization script to begin segregation"  -InformationAction Continue-ForegroundColor White
Write-Information -MessageData "3. Fix Docker -InformationAction Continue-compatible tests for 100% pass rate" -ForegroundColor White
Write-Information -MessageData "4. Move Windows -InformationAction Continue-only tests to separate directory" -ForegroundColor White
Write-Information -MessageData "5. Implement GitHub Actions dual -InformationAction Continue-environment workflows" -ForegroundColor White

Write-Information -MessageData "`n✅ Analysis completed successfully!" -InformationAction Continue






