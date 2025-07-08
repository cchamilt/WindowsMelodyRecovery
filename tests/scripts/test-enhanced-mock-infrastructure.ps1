#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Enhanced Mock Infrastructure Test Runner and Demonstration

.DESCRIPTION
    Comprehensive test runner that demonstrates and validates the enhanced
    mock infrastructure capabilities across all test types and scenarios.

.PARAMETER TestType
    Type of mock infrastructure test to run.

.PARAMETER Scope
    Scope of mock data to generate and test.

.PARAMETER Validate
    Run validation tests only.

.PARAMETER Demo
    Run demonstration of capabilities.

.PARAMETER Clean
    Clean up mock data before running tests.

.EXAMPLE
    ./test-enhanced-mock-infrastructure.ps1 -TestType "All" -Scope "Standard"
    ./test-enhanced-mock-infrastructure.ps1 -Validate -TestType "Integration"
    ./test-enhanced-mock-infrastructure.ps1 -Demo -Scope "Comprehensive"
#>

[CmdletBinding()]
param(
    [ValidateSet('Unit', 'Integration', 'FileOperations', 'EndToEnd', 'All')]
    [string]$TestType = 'All',
    
    [ValidateSet('Minimal', 'Standard', 'Comprehensive', 'Enterprise')]
    [string]$Scope = 'Standard',
    
    [switch]$Validate,
    [switch]$Demo,
    [switch]$Clean
)

# Import required modules and utilities
$ProjectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Import-Module (Join-Path $ProjectRoot "WindowsMelodyRecovery.psd1") -Force
. (Join-Path $PSScriptRoot "..\utilities\Test-Environment-Standard.ps1")
. (Join-Path $PSScriptRoot "..\utilities\Enhanced-Mock-Infrastructure.ps1")
. (Join-Path $PSScriptRoot "..\utilities\Mock-Integration.ps1")

# Initialize standardized test environment
$testEnvironment = Initialize-StandardTestEnvironment -TestType "Integration" -IsolationLevel "Standard"

Write-Host "🧪 Enhanced Mock Infrastructure Test Runner" -ForegroundColor Cyan
Write-Host "=" * 60 -ForegroundColor Cyan
Write-Host "Test Type: $TestType" -ForegroundColor White
Write-Host "Scope: $Scope" -ForegroundColor White
Write-Host "Validate: $Validate" -ForegroundColor White
Write-Host "Demo: $Demo" -ForegroundColor White
Write-Host "Clean: $Clean" -ForegroundColor White
Write-Host ""

try {
    # Clean mock data if requested
    if ($Clean) {
        Write-Host "🧹 Cleaning existing mock data..." -ForegroundColor Yellow
        Reset-EnhancedMockData -Scope $Scope
        Write-Host ""
    }
    
    if ($Demo) {
        # Run comprehensive demonstration
        Write-Host "🎯 Running Enhanced Mock Infrastructure Demonstration" -ForegroundColor Magenta
        Write-Host ""
        
        # Demo 1: Basic Infrastructure Initialization
        Write-Host "📋 Demo 1: Basic Infrastructure Initialization" -ForegroundColor Yellow
        Write-Host "-" * 50 -ForegroundColor Gray
        
        Write-Host "Initializing mock infrastructure for different test types..." -ForegroundColor Gray
        foreach ($demoTestType in @('Unit', 'Integration', 'FileOperations', 'EndToEnd')) {
            Write-Host "  Testing $demoTestType..." -ForegroundColor Gray
            Initialize-EnhancedMockInfrastructure -TestType $demoTestType -Scope "Minimal"
            Write-Host "  ✓ $demoTestType infrastructure initialized" -ForegroundColor Green
        }
        Write-Host ""
        
        # Demo 2: Data Generation and Retrieval
        Write-Host "📋 Demo 2: Data Generation and Retrieval" -ForegroundColor Yellow
        Write-Host "-" * 50 -ForegroundColor Gray
        
        # Initialize with comprehensive data
        Initialize-EnhancedMockInfrastructure -TestType "All" -Scope $Scope
        
        Write-Host "Testing data retrieval for different components..." -ForegroundColor Gray
        
        # Test application data retrieval
        $wingetData = Get-EnhancedMockData -Component "applications" -DataType "winget"
        if ($wingetData) {
            Write-Host "  ✓ Winget data: $($wingetData.Packages.Count) applications" -ForegroundColor Green
        } else {
            Write-Host "  ❌ Failed to retrieve Winget data" -ForegroundColor Red
        }
        
        # Test gaming data retrieval
        $steamData = Get-EnhancedMockData -Component "gaming" -DataType "steam"
        if ($steamData) {
            Write-Host "  ✓ Steam data: $($steamData.Apps.Count) games" -ForegroundColor Green
        } else {
            Write-Host "  ❌ Failed to retrieve Steam data" -ForegroundColor Red
        }
        
        # Test cloud data retrieval
        $cloudData = Get-EnhancedMockData -Component "cloud"
        if ($cloudData) {
            $providerCount = ($cloudData.Keys | Measure-Object).Count
            Write-Host "  ✓ Cloud data: $providerCount providers" -ForegroundColor Green
        } else {
            Write-Host "  ❌ Failed to retrieve Cloud data" -ForegroundColor Red
        }
        
        # Test WSL data retrieval
        $wslData = Get-EnhancedMockData -Component "wsl" -DataType "distributions"
        if ($wslData) {
            Write-Host "  ✓ WSL data: $($wslData.Distributions.Count) distributions" -ForegroundColor Green
        } else {
            Write-Host "  ❌ Failed to retrieve WSL data" -ForegroundColor Red
        }
        Write-Host ""
        
        # Demo 3: Context-Specific Initialization
        Write-Host "📋 Demo 3: Context-Specific Initialization" -ForegroundColor Yellow
        Write-Host "-" * 50 -ForegroundColor Gray
        
        Write-Host "Testing context-specific mock data initialization..." -ForegroundColor Gray
        
        $testContexts = @(
            @{ TestType = "Integration"; Context = "ApplicationBackup" }
            @{ TestType = "Integration"; Context = "GamingIntegration" }
            @{ TestType = "Integration"; Context = "CloudSync" }
            @{ TestType = "EndToEnd"; Context = "CompleteWorkflow" }
        )
        
        foreach ($contextTest in $testContexts) {
            Write-Host "  Testing $($contextTest.TestType)/$($contextTest.Context)..." -ForegroundColor Gray
            Initialize-MockForTestType -TestType $contextTest.TestType -TestContext $contextTest.Context -Scope "Standard"
            Write-Host "  ✓ $($contextTest.TestType)/$($contextTest.Context) initialized" -ForegroundColor Green
        }
        Write-Host ""
        
        # Demo 4: Data Validation and Integrity
        Write-Host "📋 Demo 4: Data Validation and Integrity" -ForegroundColor Yellow
        Write-Host "-" * 50 -ForegroundColor Gray
        
        Write-Host "Testing mock data validation..." -ForegroundColor Gray
        
        foreach ($validationTestType in @('Unit', 'Integration', 'EndToEnd', 'All')) {
            Write-Host "  Validating $validationTestType mock data..." -ForegroundColor Gray
            $validation = Validate-MockDataIntegrity -TestType $validationTestType
            
            if ($validation.Valid) {
                Write-Host "  ✓ $validationTestType validation passed ($($validation.Summary.ValidComponents)/$($validation.Summary.TotalComponents) components)" -ForegroundColor Green
            } else {
                Write-Host "  ❌ $validationTestType validation failed ($($validation.Summary.IssuesFound) issues)" -ForegroundColor Red
                foreach ($issue in $validation.Issues) {
                    Write-Host "    • $issue" -ForegroundColor Red
                }
            }
        }
        Write-Host ""
        
        # Demo 5: Test Integration Examples
        Write-Host "📋 Demo 5: Test Integration Examples" -ForegroundColor Yellow
        Write-Host "-" * 50 -ForegroundColor Gray
        
        Write-Host "Demonstrating test-specific data retrieval..." -ForegroundColor Gray
        
        # Example 1: Application Backup Test
        Write-Host "  Example 1: Application Backup Test" -ForegroundColor Gray
        $appBackupData = Get-MockDataForTest -TestName "ApplicationBackup" -Component "winget" -DataFormat "json"
        if ($appBackupData) {
            Write-Host "    ✓ Retrieved winget data for application backup test" -ForegroundColor Green
            Write-Host "    • Applications: $($appBackupData.Packages.Count)" -ForegroundColor Gray
        }
        
        # Example 2: WSL Package Discovery Test
        Write-Host "  Example 2: WSL Package Discovery Test" -ForegroundColor Gray
        $wslPackageData = Get-MockDataForTest -TestName "WSLPackageDiscovery" -Component "Ubuntu" -DataFormat "packagelist"
        if ($wslPackageData) {
            Write-Host "    ✓ Retrieved Ubuntu package list for WSL discovery test" -ForegroundColor Green
            Write-Host "    • Packages: $($wslPackageData.Count)" -ForegroundColor Gray
        }
        
        # Example 3: Gaming Integration Test
        Write-Host "  Example 3: Gaming Integration Test" -ForegroundColor Gray
        $gamingData = Get-MockDataForTest -TestName "GamingIntegration" -Component "steam" -DataFormat "config"
        if ($gamingData) {
            Write-Host "    ✓ Retrieved Steam configuration for gaming integration test" -ForegroundColor Green
            Write-Host "    • Config size: $($gamingData.Length) characters" -ForegroundColor Gray
        }
        
        Write-Host ""
        
        Write-Host "🎉 Enhanced Mock Infrastructure Demonstration Completed!" -ForegroundColor Green
        Write-Host ""
    }
    
    if ($Validate -or -not $Demo) {
        # Run validation tests
        Write-Host "🔍 Running Enhanced Mock Infrastructure Validation" -ForegroundColor Cyan
        Write-Host ""
        
        # Initialize infrastructure for testing
        if (-not $Demo) {
            Write-Host "Initializing mock infrastructure for validation..." -ForegroundColor Gray
            Initialize-EnhancedMockInfrastructure -TestType $TestType -Scope $Scope
            Write-Host ""
        }
        
        # Validation Test 1: Infrastructure Initialization
        Write-Host "🧪 Test 1: Infrastructure Initialization" -ForegroundColor Yellow
        Write-Host "-" * 40 -ForegroundColor Gray
        
        $initTests = @()
        foreach ($testTypeToValidate in @('Unit', 'Integration', 'FileOperations', 'EndToEnd')) {
            try {
                Initialize-EnhancedMockInfrastructure -TestType $testTypeToValidate -Scope "Minimal"
                $initTests += @{ TestType = $testTypeToValidate; Result = "Pass"; Error = $null }
                Write-Host "  ✓ $testTypeToValidate initialization: PASS" -ForegroundColor Green
            } catch {
                $initTests += @{ TestType = $testTypeToValidate; Result = "Fail"; Error = $_.Exception.Message }
                Write-Host "  ❌ $testTypeToValidate initialization: FAIL" -ForegroundColor Red
                Write-Host "     Error: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
        Write-Host ""
        
        # Validation Test 2: Data Generation
        Write-Host "🧪 Test 2: Data Generation Validation" -ForegroundColor Yellow
        Write-Host "-" * 40 -ForegroundColor Gray
        
        $dataTests = @()
        $components = @('applications', 'gaming', 'cloud', 'wsl', 'system-settings')
        
        foreach ($component in $components) {
            try {
                $componentData = Get-EnhancedMockData -Component $component
                if ($componentData) {
                    $dataTests += @{ Component = $component; Result = "Pass"; Error = $null }
                    Write-Host "  ✓ $component data generation: PASS" -ForegroundColor Green
                } else {
                    $dataTests += @{ Component = $component; Result = "Fail"; Error = "No data returned" }
                    Write-Host "  ❌ $component data generation: FAIL (No data)" -ForegroundColor Red
                }
            } catch {
                $dataTests += @{ Component = $component; Result = "Fail"; Error = $_.Exception.Message }
                Write-Host "  ❌ $component data generation: FAIL" -ForegroundColor Red
                Write-Host "     Error: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
        Write-Host ""
        
        # Validation Test 3: Data Integrity
        Write-Host "🧪 Test 3: Data Integrity Validation" -ForegroundColor Yellow
        Write-Host "-" * 40 -ForegroundColor Gray
        
        $integrityTests = @()
        foreach ($testTypeToValidate in @('Unit', 'Integration', 'FileOperations', 'EndToEnd')) {
            try {
                $validation = Validate-MockDataIntegrity -TestType $testTypeToValidate
                $integrityTests += @{ 
                    TestType = $testTypeToValidate
                    Result = if ($validation.Valid) { "Pass" } else { "Fail" }
                    Issues = $validation.Summary.IssuesFound
                    Components = "$($validation.Summary.ValidComponents)/$($validation.Summary.TotalComponents)"
                    Error = $null
                }
                
                if ($validation.Valid) {
                    Write-Host "  ✓ $testTypeToValidate integrity: PASS ($($validation.Summary.ValidComponents)/$($validation.Summary.TotalComponents))" -ForegroundColor Green
                } else {
                    Write-Host "  ❌ $testTypeToValidate integrity: FAIL ($($validation.Summary.IssuesFound) issues)" -ForegroundColor Red
                }
            } catch {
                $integrityTests += @{ 
                    TestType = $testTypeToValidate
                    Result = "Error"
                    Issues = 0
                    Components = "0/0"
                    Error = $_.Exception.Message
                }
                Write-Host "  ❌ $testTypeToValidate integrity: ERROR" -ForegroundColor Red
                Write-Host "     Error: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
        Write-Host ""
        
        # Validation Test 4: Legacy Compatibility
        Write-Host "🧪 Test 4: Legacy Compatibility Validation" -ForegroundColor Yellow
        Write-Host "-" * 40 -ForegroundColor Gray
        
        $legacyTests = @()
        try {
            # Test legacy function calls
            $mockPath = Get-MockDataPath -DataType "applications"
            $dataExists = Test-MockDataExists -DataType "applications" -Path "winget.json"
            Initialize-MockEnvironment -Environment "Legacy" -TestType "Integration"
            
            $legacyTests += @{ Function = "Get-MockDataPath"; Result = "Pass"; Error = $null }
            $legacyTests += @{ Function = "Test-MockDataExists"; Result = "Pass"; Error = $null }
            $legacyTests += @{ Function = "Initialize-MockEnvironment"; Result = "Pass"; Error = $null }
            
            Write-Host "  ✓ Legacy function compatibility: PASS" -ForegroundColor Green
        } catch {
            $legacyTests += @{ Function = "Legacy"; Result = "Fail"; Error = $_.Exception.Message }
            Write-Host "  ❌ Legacy function compatibility: FAIL" -ForegroundColor Red
            Write-Host "     Error: $($_.Exception.Message)" -ForegroundColor Red
        }
        Write-Host ""
        
        # Generate comprehensive validation report
        Write-Host "📊 Validation Summary Report" -ForegroundColor Magenta
        Write-Host "=" * 50 -ForegroundColor Magenta
        
        # Calculate overall results
        $totalTests = $initTests.Count + $dataTests.Count + $integrityTests.Count + $legacyTests.Count
        $passedTests = ($initTests | Where-Object { $_.Result -eq "Pass" }).Count +
                      ($dataTests | Where-Object { $_.Result -eq "Pass" }).Count +
                      ($integrityTests | Where-Object { $_.Result -eq "Pass" }).Count +
                      ($legacyTests | Where-Object { $_.Result -eq "Pass" }).Count
        
        $successRate = [math]::Round(($passedTests / $totalTests) * 100, 2)
        
        Write-Host "Overall Results:" -ForegroundColor White
        Write-Host "  Total Tests: $totalTests" -ForegroundColor Gray
        Write-Host "  Passed: $passedTests" -ForegroundColor Green
        Write-Host "  Failed: $($totalTests - $passedTests)" -ForegroundColor Red
        Write-Host "  Success Rate: $successRate%" -ForegroundColor $(if ($successRate -ge 90) { "Green" } elseif ($successRate -ge 70) { "Yellow" } else { "Red" })
        Write-Host ""
        
        Write-Host "Test Category Breakdown:" -ForegroundColor White
        Write-Host "  Infrastructure Init: $($initTests.Count) tests, $(($initTests | Where-Object { $_.Result -eq "Pass" }).Count) passed" -ForegroundColor Gray
        Write-Host "  Data Generation: $($dataTests.Count) tests, $(($dataTests | Where-Object { $_.Result -eq "Pass" }).Count) passed" -ForegroundColor Gray
        Write-Host "  Data Integrity: $($integrityTests.Count) tests, $(($integrityTests | Where-Object { $_.Result -eq "Pass" }).Count) passed" -ForegroundColor Gray
        Write-Host "  Legacy Compatibility: $($legacyTests.Count) tests, $(($legacyTests | Where-Object { $_.Result -eq "Pass" }).Count) passed" -ForegroundColor Gray
        Write-Host ""
        
        if ($successRate -ge 90) {
            Write-Host "🎉 Enhanced Mock Infrastructure Validation: EXCELLENT" -ForegroundColor Green
        } elseif ($successRate -ge 70) {
            Write-Host "⚠️  Enhanced Mock Infrastructure Validation: GOOD (some issues)" -ForegroundColor Yellow
        } else {
            Write-Host "❌ Enhanced Mock Infrastructure Validation: NEEDS ATTENTION" -ForegroundColor Red
        }
    }
    
} catch {
    Write-Host "❌ Test runner encountered an error:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Gray
    exit 1
} finally {
    # Cleanup test environment
    if ($testEnvironment) {
        Write-Host ""
        Write-Host "🧹 Cleaning up test environment..." -ForegroundColor Gray
        Cleanup-StandardTestEnvironment -TestEnvironment $testEnvironment
        Write-Host "✓ Test environment cleaned up" -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "🏁 Enhanced Mock Infrastructure Test Runner Completed" -ForegroundColor Cyan
Write-Host "" 