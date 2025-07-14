#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Run Windows-Only Tests for Windows Melody Recovery

.DESCRIPTION
    Runs Windows-only tests that require native Windows environment and may require administrative privileges.
    This script is designed for Windows CI/CD environments and includes comprehensive safety checks.

    Tests are organized into categories:
    - Unit tests: Windows-specific logic tests
    - Integration tests: Windows registry, services, and system integration
    - File operations: Windows file system specific operations
    - End-to-end: Full Windows workflows requiring admin privileges

.PARAMETER Category
    Test category to run. Options: 'unit', 'integration', 'file-operations', 'end-to-end', 'all'
    Default: 'unit'

.PARAMETER TestName
    Specific test file to run (without .Tests.ps1 extension).

.PARAMETER OutputFormat
    Pester output format. Default is 'Detailed'.

.PARAMETER RequireAdmin
    Require administrative privileges for tests. Default is false for unit tests.

.PARAMETER CreateRestorePoint
    Create system restore point before running destructive tests. Default is true.

.PARAMETER SkipCleanup
    Skip cleanup after tests (useful for debugging).

.PARAMETER GenerateReport
    Generate detailed test reports.

.PARAMETER Force
    Force execution even if not in Windows CI/CD environment.

.EXAMPLE
    .\run-windows-tests.ps1
    .\run-windows-tests.ps1 -Category integration
    .\run-windows-tests.ps1 -Category end-to-end -RequireAdmin -CreateRestorePoint
    .\run-windows-tests.ps1 -TestName "Windows-Principal-Unit" -Category unit
#>

[CmdletBinding()]
param(
    [ValidateSet('unit', 'integration', 'file-operations', 'end-to-end', 'all')]
    [string]$Category = 'unit',
    [string]$TestName,
    [ValidateSet('None', 'Normal', 'Detailed', 'Diagnostic')]
    [string]$OutputFormat = 'Detailed',
    [switch]$RequireAdmin,
    [switch]$CreateRestorePoint = $true,
    [switch]$SkipCleanup,
    [switch]$GenerateReport,
    [switch]$Force
)

# Set execution policy for current process (Windows only)
if ($IsWindows) {
    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
}

# Validate Windows environment
if (-not $IsWindows -and -not $Force) {
    Write-Error -Message "✗ This script requires Windows environment"
    Write-Warning -Message "  Use -Force to override this check for testing"
    exit 1
}

# Detect CI/CD environment
$isCICD = $env:CI -or $env:GITHUB_ACTIONS -or $env:BUILD_BUILDID -or $env:JENKINS_URL
if (-not $isCICD -and -not $Force) {
    Write-Warning -Message "⚠️  This script is designed for CI/CD environments"
    Write-Verbose -Message "   Use -Force to run in development environment"
    Write-Verbose -Message "   Consider using regular test scripts for development"
    if (-not (Read-Host "Continue? (y/N)").ToLower().StartsWith('y')) {
        exit 0
    }
}

# Determine if admin is needed for this category
$needsAdmin = $RequireAdmin -or $Category -in @('integration', 'end-to-end')

# Import test environment library
. (Join-Path $PSScriptRoot "..\utilities\Test-Environment.ps1")

Write-Information -MessageData "🪟 Windows-Only Test Runner" -InformationAction Continue
Write-Information -MessageData "Category: $Category" -InformationAction Continue
Write-Verbose -Message "Environment: $(if ($isCICD) { 'CI/CD' } else { 'Development' })"

try {
    # Initialize a dedicated, isolated environment for this Windows test run
    Write-Warning -Message "🧹 Initializing isolated Windows test environment..."
    $testEnvironment = Initialize-TestEnvironment -SuiteName 'Windows'
    Write-Information -MessageData "✅ Test environment ready in: $($testEnvironment.TestRoot)" -InformationAction Continue

    # Import the module
    $moduleRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $modulePath = Join-Path $moduleRoot "WindowsMelodyRecovery.psd1"
    Import-Module $modulePath -Force

    # Administrative privilege check using module function
    $adminInfo = Test-WmrAdministrativePrivilege -Quiet
    $isAdmin = $adminInfo.IsElevated
    Write-Verbose -Message "Admin Rights: $(if ($isAdmin) { 'Yes' } else { 'No' })"

    if ($needsAdmin -and -not $isAdmin) {
        Write-Error -Message "✗ Administrative privileges required for $Category tests"
        Write-Warning -Message "  Please run PowerShell as Administrator"
        exit 1
    }

    # Create restore point for destructive tests
    if ($CreateRestorePoint -and $needsAdmin -and $isAdmin) {
        Write-Warning -Message "Creating system restore point..."
        try {
            $restorePoint = "WMR-Tests-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
            Checkpoint-Computer -Description $restorePoint -RestorePointType "MODIFY_SETTINGS"
            Write-Information -MessageData "✓ Restore point created: $restorePoint" -InformationAction Continue
        }
        catch {
            Write-Warning -Message "⚠️  Failed to create restore point: $($_.Exception.Message)"
            Write-Verbose -Message "   Continuing without restore point..."
        }
    }

    # Determine test paths
    $testPaths = @()

    if ($Category -eq 'all') {
        $testPaths += Join-Path $PSScriptRoot ".." "windows-only" "unit"
        $testPaths += Join-Path $PSScriptRoot ".." "windows-only" "integration"
        # Add other categories as they exist
    }
    else {
        $categoryPath = Join-Path $PSScriptRoot ".." "windows-only" $Category
        if (Test-Path $categoryPath) {
            if ($TestName) {
                $specificTest = Join-Path $categoryPath "$TestName.Tests.ps1"
                if (Test-Path $specificTest) {
                    $testPaths += $specificTest
                }
                else {
                    Write-Error -Message "✗ Test file not found: $specificTest"
                    exit 1
                }
            }
            else {
                $testPaths += $categoryPath
            }
        }
        else {
            Write-Error -Message "✗ Test category not found: $categoryPath"
            Write-Warning -Message "Available categories:"
            Get-ChildItem -Path (Join-Path $PSScriptRoot ".." "windows-only") -Directory | ForEach-Object {
                Write-Verbose -Message "  - $($_.Name)"
            }
            exit 1
        }
    }

    # Run tests
    Write-Information -MessageData "Executing Windows-only tests..." -InformationAction Continue
    Write-Verbose -Message "Test paths: $($testPaths -join ', ')"

    $pesterConfig = @{
        Run    = @{
            Path = $testPaths
        }
        Output = @{
            Verbosity = $OutputFormat
        }
    }

    if ($GenerateReport) {
        # Write to standard test-results directory for CI/CD compatibility
        $moduleRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $testResultsDir = Join-Path $moduleRoot "test-results"
        $logsDir = Join-Path $testResultsDir "logs"

        # Ensure test-results directory exists (including logs for CI/CD compatibility)
        @($testResultsDir, $logsDir) | ForEach-Object {
            if (-not (Test-Path $_)) {
                New-Item -Path $_ -ItemType Directory -Force | Out-Null
            }
        }

        $pesterConfig.TestResult = @{
            Enabled      = $true
            OutputPath   = Join-Path $testResultsDir "windows-only-test-results.xml"
            OutputFormat = 'JUnitXml'
        }
    }

    $result = Invoke-Pester -Configuration $pesterConfig

    # Cleanup
    if (-not $SkipCleanup) {
        Write-Warning -Message "🧹 Cleaning up test environment..."
        Remove-TestEnvironment
        Write-Information -MessageData "✅ Cleanup complete." -InformationAction Continue
    }

    # Report results
    Write-Information -MessageData "" -InformationAction Continue
    Write-Information -MessageData "=== Windows-Only Test Results ===" -InformationAction Continue
    Write-Information -MessageData "Tests Passed: $($result.PassedCount)" -InformationAction Continue
    Write-Error -Message "Tests Failed: $($result.FailedCount)"
    Write-Warning -Message "Tests Skipped: $($result.SkippedCount)"
    Write-Information -MessageData "Total Tests: $($result.TotalCount)"  -InformationAction Continue

    if ($result.FailedCount -gt 0) {
        Write-Error -Message "✗ Some Windows-only tests failed"
        exit 1
    }
    else {
        Write-Information -MessageData "✓ All Windows-only tests passed!" -InformationAction Continue
        exit 0
    }

}
catch {
    Write-Error -Message "✗ Error running Windows-only tests: $($_.Exception.Message)"
    Write-Error -Message "Stack trace:"
    Write-Information -MessageData $_.ScriptStackTrace  -InformationAction Continue
    exit 1
}

# Model: claude-3-5-sonnet-20241022
# Confidence: 90%







