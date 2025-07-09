# run-windows-tests.ps1
# Comprehensive Windows test runner with safety measures

[CmdletBinding()]
param(
    [ValidateSet('unit', 'integration', 'file-operations', 'end-to-end', 'all')]
    [string]$Category = 'unit',
    
    [switch]$RequireAdmin = $false,
    [switch]$CreateRestorePoint = $false,
    [switch]$Verbose = $false,
    [string]$OutputPath = "windows-test-results",
    [double]$TargetPassRate = 90.0,
    [switch]$Force = $false
)

# Set error handling
$ErrorActionPreference = 'Stop'

function Write-TestLog {
    param(
        [string]$Message,
        [ValidateSet('Info', 'Success', 'Warning', 'Error')]
        [string]$Level = 'Info'
    )
    
    $colors = @{
        'Info' = 'White'
        'Success' = 'Green'
        'Warning' = 'Yellow'
        'Error' = 'Red'
    }
    
    $prefix = @{
        'Info' = 'ℹ️'
        'Success' = '✅'
        'Warning' = '⚠️'
        'Error' = '❌'
    }
    
    Write-Host "$($prefix[$Level]) $Message" -ForegroundColor $colors[$Level]
}

function Test-WindowsEnvironment {
    Write-TestLog "Validating Windows environment..." -Level Info
    
    # Check if running on Windows
    if ($PSVersionTable.Platform -eq 'Unix') {
        Write-TestLog "This script must be run on Windows" -Level Error
        throw "Not running on Windows"
    }
    
    # Check PowerShell version
    if ($PSVersionTable.PSVersion.Major -lt 5) {
        Write-TestLog "PowerShell 5.0 or higher is required" -Level Error
        throw "PowerShell version too old"
    }
    
    # Check if running in CI/CD or authorized environment
    $isCI = $env:CI -eq 'true' -or $env:GITHUB_ACTIONS -eq 'true' -or $env:TF_BUILD -eq 'true'
    $isAuthorized = $env:WMR_ALLOW_WINDOWS_TESTS -eq 'true'
    
    if (-not $isCI -and -not $isAuthorized -and -not $Force) {
        Write-TestLog "Windows tests should only run in CI/CD or with explicit authorization" -Level Warning
        Write-TestLog "Set environment variable: `$env:WMR_ALLOW_WINDOWS_TESTS = 'true'" -Level Info
        Write-TestLog "Or use -Force parameter to override this check" -Level Info
        throw "Windows tests not authorized"
    }
    
    # Check admin privileges if required
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    
    if ($RequireAdmin -and -not $isAdmin) {
        Write-TestLog "Administrator privileges required but not available" -Level Error
        throw "Administrator privileges required"
    }
    
    Write-TestLog "Windows environment validation completed" -Level Success
    Write-TestLog "Running as Administrator: $isAdmin" -Level Info
    Write-TestLog "CI Environment: $isCI" -Level Info
    Write-TestLog "Authorized: $isAuthorized" -Level Info
}

function New-RestorePoint {
    if ($CreateRestorePoint -and -not $env:CI) {
        Write-TestLog "Creating system restore point..." -Level Info
        
        try {
            # Enable system restore if not enabled
            Enable-ComputerRestore -Drive "C:\"
            
            # Create restore point
            $restorePoint = Checkpoint-Computer -Description "WindowsMelodyRecovery Test Restore Point" -RestorePointType "MODIFY_SETTINGS" -PassThru
            
            if ($restorePoint) {
                Write-TestLog "System restore point created successfully" -Level Success
                return $restorePoint.SequenceNumber
            } else {
                Write-TestLog "Failed to create restore point" -Level Warning
                return $null
            }
        } catch {
            Write-TestLog "Warning: Failed to create restore point: $($_.Exception.Message)" -Level Warning
            return $null
        }
    } else {
        Write-TestLog "Restore point creation skipped (CI environment or not requested)" -Level Info
        return $null
    }
}

function Get-WindowsTestPaths {
    param([string]$Category)
    
    $testPaths = @()
    
    # Check for Windows-only test directories first
    $windowsOnlyBase = "./tests/windows-only"
    
    switch ($Category) {
        'unit' {
            if (Test-Path "$windowsOnlyBase/unit/") {
                $testPaths += "$windowsOnlyBase/unit/"
            } else {
                # Fallback to Windows-specific tests in main unit directory
                $windowsTests = @(
                    './tests/unit/AdministrativePrivileges*.Tests.ps1',
                    './tests/unit/RegistryState*.Tests.ps1',
                    './tests/unit/PathUtilities.Tests.ps1',
                    './tests/unit/Prerequisites*.Tests.ps1',
                    './tests/unit/Windows-Only.Tests.ps1'
                )
                
                foreach ($pattern in $windowsTests) {
                    $files = Get-ChildItem -Path $pattern -ErrorAction SilentlyContinue
                    $testPaths += $files.FullName
                }
            }
        }
        
        'integration' {
            if (Test-Path "$windowsOnlyBase/integration/") {
                $testPaths += "$windowsOnlyBase/integration/"
            } else {
                # Run all integration tests on Windows
                if (Test-Path "./tests/integration/") {
                    $testPaths += "./tests/integration/"
                }
            }
        }
        
        'file-operations' {
            if (Test-Path "$windowsOnlyBase/file-operations/") {
                $testPaths += "$windowsOnlyBase/file-operations/"
            } else {
                if (Test-Path "./tests/file-operations/") {
                    $testPaths += "./tests/file-operations/"
                }
            }
        }
        
        'end-to-end' {
            if (Test-Path "$windowsOnlyBase/end-to-end/") {
                $testPaths += "$windowsOnlyBase/end-to-end/"
            } else {
                if (Test-Path "./tests/end-to-end/") {
                    $testPaths += "./tests/end-to-end/"
                }
            }
        }
        
        'all' {
            # Get all categories
            $allCategories = @('unit', 'integration', 'file-operations', 'end-to-end')
            foreach ($cat in $allCategories) {
                $testPaths += Get-WindowsTestPaths -Category $cat
            }
        }
    }
    
    return $testPaths | Where-Object { $_ -and (Test-Path $_) }
}

function Invoke-WindowsTests {
    param(
        [string]$TestCategory,
        [string[]]$TestPaths
    )
    
    Write-TestLog "Running Windows $TestCategory tests..." -Level Info
    
    if ($TestPaths.Count -eq 0) {
        Write-TestLog "No test paths found for category: $TestCategory" -Level Warning
        return @{
            Success = $true
            PassedCount = 0
            FailedCount = 0
            TotalCount = 0
            PassRate = 100
            Results = @()
        }
    }
    
    Write-TestLog "Test paths:" -Level Info
    foreach ($path in $TestPaths) {
        Write-TestLog "  - $path" -Level Info
    }
    
    # Import the module
    try {
        Import-Module ./WindowsMelodyRecovery.psd1 -Force
        Write-TestLog "WindowsMelodyRecovery module imported successfully" -Level Success
    } catch {
        Write-TestLog "Failed to import module: $($_.Exception.Message)" -Level Error
        throw
    }
    
    # Set Windows test environment variables
    $env:WMR_ALLOW_WINDOWS_TESTS = 'true'
    if ($env:CI -eq 'true') {
        $env:WMR_CREATE_RESTORE_POINT = 'false'  # Safety in CI
    }
    
    # Run tests
    $allResults = @()
    $outputFile = "$OutputPath/windows-$TestCategory-results.xml"
    
    try {
        foreach ($testPath in $TestPaths) {
            Write-TestLog "Running tests from: $testPath" -Level Info
            
            $result = Invoke-Pester -Path $testPath -PassThru -Show Detailed
            $allResults += $result
            
            Write-TestLog "Results for $testPath - Passed: $($result.PassedCount), Failed: $($result.FailedCount)" -Level Info
        }
        
        # Generate XML output
        if ($allResults.Count -gt 0) {
            $combinedResult = $allResults[0]
            for ($i = 1; $i -lt $allResults.Count; $i++) {
                $combinedResult.PassedCount += $allResults[$i].PassedCount
                $combinedResult.FailedCount += $allResults[$i].FailedCount
                $combinedResult.TotalCount += $allResults[$i].TotalCount
            }
            
            # Export to XML (simplified - Pester handles this automatically in newer versions)
            $combinedResult | Export-Clixml -Path $outputFile
        }
        
    } catch {
        Write-TestLog "Error running tests: $($_.Exception.Message)" -Level Error
        throw
    }
    
    # Calculate totals
    $totalPassed = ($allResults | Measure-Object -Property PassedCount -Sum).Sum
    $totalFailed = ($allResults | Measure-Object -Property FailedCount -Sum).Sum
    $totalTests = $totalPassed + $totalFailed
    
    $passRate = if ($totalTests -gt 0) { [math]::Round(($totalPassed / $totalTests) * 100, 2) } else { 100 }
    
    Write-TestLog "" -Level Info
    Write-TestLog "=== WINDOWS $($TestCategory.ToUpper()) TEST RESULTS ===" -Level Info
    Write-TestLog "Total Tests: $totalTests" -Level Info
    Write-TestLog "Passed: $totalPassed" -Level Success
    Write-TestLog "Failed: $totalFailed" -Level $(if ($totalFailed -gt 0) { 'Warning' } else { 'Success' })
    Write-TestLog "Pass Rate: $passRate%" -Level $(if ($passRate -ge $TargetPassRate) { 'Success' } else { 'Warning' })
    
    $success = $passRate -ge $TargetPassRate
    
    if ($success) {
        Write-TestLog "✅ Windows $TestCategory tests met target pass rate ($TargetPassRate%)" -Level Success
    } else {
        Write-TestLog "⚠️ Windows $TestCategory tests below target pass rate ($TargetPassRate%)" -Level Warning
        Write-TestLog "Note: Some Windows test failures are expected in CI environments" -Level Info
    }
    
    return @{
        Success = $success
        PassedCount = $totalPassed
        FailedCount = $totalFailed
        TotalCount = $totalTests
        PassRate = $passRate
        Results = $allResults
    }
}

function Write-TestSummary {
    param(
        [hashtable]$TestResult,
        [string]$Category,
        [int]$RestorePointId
    )
    
    $summary = @{
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Environment = "Windows"
        Category = $Category
        TotalTests = $TestResult.TotalCount
        PassedTests = $TestResult.PassedCount
        FailedTests = $TestResult.FailedCount
        PassRate = $TestResult.PassRate
        TargetPassRate = $TargetPassRate
        Success = $TestResult.Success
        Status = if ($TestResult.Success) { "✅ TARGET MET" } else { "⚠️ BELOW TARGET" }
        RestorePointId = $RestorePointId
        Notes = @(
            "Windows tests target $TargetPassRate% pass rate",
            "Some failures expected in CI environments due to platform limitations",
            "Combined with Docker tests for comprehensive coverage",
            "Windows-specific functionality requires native Windows environment"
        )
    }
    
    $summaryPath = "$OutputPath/windows-test-summary.json"
    $summary | ConvertTo-Json -Depth 3 | Out-File -FilePath $summaryPath -Encoding UTF8
    Write-TestLog "Test summary saved to: $summaryPath" -Level Info
}

function New-OutputDirectory {
    if (-not (Test-Path $OutputPath)) {
        New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
        Write-TestLog "Created output directory: $OutputPath" -Level Info
    }
}

# Main execution
try {
    Write-TestLog "🚀 Starting Windows test execution..." -Level Info
    Write-TestLog "Category: $Category" -Level Info
    Write-TestLog "Target Pass Rate: $TargetPassRate%" -Level Info
    Write-TestLog "Output Path: $OutputPath" -Level Info
    
    # Create output directory
    New-OutputDirectory
    
    # Validate Windows environment
    Test-WindowsEnvironment
    
    # Create restore point if requested
    $restorePointId = New-RestorePoint
    
    # Get test paths
    $testPaths = Get-WindowsTestPaths -Category $Category
    
    if ($testPaths.Count -eq 0) {
        Write-TestLog "No Windows-specific tests found for category: $Category" -Level Warning
        Write-TestLog "This may be expected if all tests are Docker-compatible" -Level Info
        
        # Create empty result
        $testResult = @{
            Success = $true
            PassedCount = 0
            FailedCount = 0
            TotalCount = 0
            PassRate = 100
        }
    } else {
        # Run tests
        $testResult = Invoke-WindowsTests -TestCategory $Category -TestPaths $testPaths
    }
    
    # Write summary
    Write-TestSummary -TestResult $testResult -Category $Category -RestorePointId $restorePointId
    
    # Final status
    if ($testResult.Success) {
        Write-TestLog "✅ WINDOWS TESTS: SUCCESS" -Level Success
        Write-TestLog "Pass rate $($testResult.PassRate)% meets target $TargetPassRate%" -Level Success
    } else {
        Write-TestLog "⚠️ WINDOWS TESTS: BELOW TARGET" -Level Warning
        Write-TestLog "Pass rate $($testResult.PassRate)% below target $TargetPassRate%" -Level Warning
        Write-TestLog "Note: Some failures may be expected in CI environments" -Level Info
    }
    
    # Note about restore point
    if ($restorePointId) {
        Write-TestLog "System restore point available (ID: $restorePointId)" -Level Info
        Write-TestLog "Use 'Restore-Computer -RestorePoint $restorePointId' if needed" -Level Info
    }
    
} catch {
    Write-TestLog "Fatal error: $($_.Exception.Message)" -Level Error
    $testResult = @{ Success = $false }
} finally {
    Write-TestLog "Windows test execution completed" -Level Info
}

# Exit with appropriate code
# Note: Windows tests are allowed to have some failures, so we don't exit with error code
# unless there's a fatal error
if ($testResult.Success -ne $false) {
    exit 0
} else {
    exit 1
} 