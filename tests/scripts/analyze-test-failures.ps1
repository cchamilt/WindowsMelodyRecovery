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
    
    Write-Host "🔍 Analyzing test failures in: $TestDirectory" -ForegroundColor Cyan
    
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
        Write-Host "📝 Analyzing: $($testFile.Name)" -ForegroundColor Yellow
        
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

function Generate-MigrationPlan {
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
    Write-Host "✅ Analysis results exported to: $OutputFile" -ForegroundColor Green
}

# Main execution
Write-Host "🚀 Starting comprehensive test failure analysis..." -ForegroundColor Green

# Ensure we're in Docker environment for consistent testing
if (-not (Test-Path '/.dockerenv') -and $env:DOCKER_TEST -ne 'true') {
    Write-Host "⚠️  Running analysis in Docker environment for consistency..." -ForegroundColor Yellow
    
    # Check if Docker containers are running
    try {
        $containerStatus = docker exec wmr-test-runner pwsh -Command "Write-Host 'Docker environment ready'"
        if ($LASTEXITCODE -ne 0) {
            Write-Host "🐳 Starting Docker test environment..." -ForegroundColor Cyan
            docker-compose -f docker-compose.test.yml up -d
            Start-Sleep -Seconds 10
        }
        
        # Run analysis in Docker
        docker exec wmr-test-runner pwsh -Command "cd /workspace && pwsh -File 'tests/scripts/analyze-test-failures.ps1' -OutputPath '/workspace/$OutputPath'"
        
        Write-Host "✅ Analysis completed in Docker environment" -ForegroundColor Green
        return
        
    } catch {
        Write-Warning "Failed to run in Docker, proceeding with local analysis: $($_.Exception.Message)"
    }
}

# Run the analysis
$analysisResults = Get-TestFailureAnalysis -TestDirectory $TestPath
$migrationPlan = Generate-MigrationPlan -AnalysisResults $analysisResults

# Display summary
Write-Host "`n📊 ANALYSIS SUMMARY" -ForegroundColor Green
Write-Host "===================" -ForegroundColor Green
Write-Host "Total Tests Analyzed: $($analysisResults.TotalTests)" -ForegroundColor White
Write-Host "Currently Passing: $($analysisResults.PassedTests)" -ForegroundColor Green
Write-Host "Currently Failing: $($analysisResults.FailedTests)" -ForegroundColor Red

Write-Host "`n🐳 DOCKER ENVIRONMENT TARGET" -ForegroundColor Cyan
Write-Host "Docker-Fixable Tests: $($migrationPlan.DockerFixable.TotalTests)" -ForegroundColor Yellow
Write-Host "Current Passing: $($analysisResults.PassedTests)" -ForegroundColor Green
Write-Host "Target Docker Tests: $($migrationPlan.Summary.DockerTargetTests)" -ForegroundColor Cyan
Write-Host "Target Pass Rate: 100%" -ForegroundColor Green

Write-Host "`n🪟 WINDOWS CI/CD TARGET" -ForegroundColor Magenta
Write-Host "Windows-Only Tests: $($migrationPlan.WindowsOnly.TotalTests)" -ForegroundColor Yellow
Write-Host "Target Pass Rate: 90%+" -ForegroundColor Green

Write-Host "`n📂 CATEGORY BREAKDOWN" -ForegroundColor Yellow
foreach ($category in $migrationPlan.DockerFixable.Categories.Keys) {
    $count = $migrationPlan.DockerFixable.Categories[$category].Count
    Write-Host "  🔧 $category (Docker-Fixable): $count tests" -ForegroundColor Cyan
}
foreach ($category in $migrationPlan.WindowsOnly.Categories.Keys) {
    $count = $migrationPlan.WindowsOnly.Categories[$category].Count
    Write-Host "  🪟 $category (Windows-Only): $count tests" -ForegroundColor Magenta
}

# Export results
Export-AnalysisResults -AnalysisResults $analysisResults -MigrationPlan $migrationPlan -OutputFile $OutputPath

Write-Host "`n🎯 NEXT STEPS:" -ForegroundColor Green
Write-Host "1. Review detailed analysis in $OutputPath" -ForegroundColor White
Write-Host "2. Run test categorization script to begin segregation" -ForegroundColor White
Write-Host "3. Fix Docker-compatible tests for 100% pass rate" -ForegroundColor White
Write-Host "4. Move Windows-only tests to separate directory" -ForegroundColor White
Write-Host "5. Implement GitHub Actions dual-environment workflows" -ForegroundColor White

Write-Host "`n✅ Analysis completed successfully!" -ForegroundColor Green 