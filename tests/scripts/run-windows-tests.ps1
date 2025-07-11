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

# Set execution policy for current process
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

# Validate Windows environment
if (-not $IsWindows -and -not $Force) {
    Write-Host "✗ This script requires Windows environment" -ForegroundColor Red
    Write-Host "  Use -Force to override this check for testing" -ForegroundColor Yellow
    exit 1
}

# Detect CI/CD environment
$isCICD = $env:CI -or $env:GITHUB_ACTIONS -or $env:BUILD_BUILDID -or $env:JENKINS_URL
if (-not $isCICD -and -not $Force) {
    Write-Host "⚠️  This script is designed for CI/CD environments" -ForegroundColor Yellow
    Write-Host "   Use -Force to run in development environment" -ForegroundColor Gray
    Write-Host "   Consider using regular test scripts for development" -ForegroundColor Gray
    if (-not (Read-Host "Continue? (y/N)").ToLower().StartsWith('y')) {
        exit 0
    }
}

# Administrative privilege check
function Test-AdminPrivileges {
    try {
        $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
        return $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

$isAdmin = Test-AdminPrivileges
$needsAdmin = $RequireAdmin -or $Category -in @('integration', 'end-to-end')

if ($needsAdmin -and -not $isAdmin) {
    Write-Host "✗ Administrative privileges required for $Category tests" -ForegroundColor Red
    Write-Host "  Please run PowerShell as Administrator" -ForegroundColor Yellow
    exit 1
}

Write-Host "🪟 Windows-Only Test Runner" -ForegroundColor Cyan
Write-Host "Category: $Category" -ForegroundColor White
Write-Host "Environment: $(if ($isCICD) { 'CI/CD' } else { 'Development' })" -ForegroundColor Gray
Write-Host "Admin Rights: $(if ($isAdmin) { 'Yes' } else { 'No' })" -ForegroundColor Gray

# Create restore point for destructive tests
if ($CreateRestorePoint -and $needsAdmin -and $isAdmin) {
    Write-Host "Creating system restore point..." -ForegroundColor Yellow
    try {
        $restorePoint = "WMR-Tests-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Checkpoint-Computer -Description $restorePoint -RestorePointType "MODIFY_SETTINGS"
        Write-Host "✓ Restore point created: $restorePoint" -ForegroundColor Green
    } catch {
        Write-Host "⚠️  Failed to create restore point: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "   Continuing without restore point..." -ForegroundColor Gray
    }
}

try {
    # Import test environment
    $testEnvPath = Join-Path $PSScriptRoot ".." "utilities" "Test-Environment.ps1"
    if (Test-Path $testEnvPath) {
        . $testEnvPath
    } else {
        Write-Host "✗ Test environment not found at: $testEnvPath" -ForegroundColor Red
        exit 1
    }

    # Initialize test environment
    Initialize-TestEnvironment

    # Import the module
    $moduleRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $modulePath = Join-Path $moduleRoot "WindowsMelodyRecovery.psd1"
    Import-Module $modulePath -Force

    # Determine test paths
    $testPaths = @()

    if ($Category -eq 'all') {
        $testPaths += Join-Path $PSScriptRoot ".." "windows-only" "unit"
        $testPaths += Join-Path $PSScriptRoot ".." "windows-only" "integration"
        # Add other categories as they exist
    } else {
        $categoryPath = Join-Path $PSScriptRoot ".." "windows-only" $Category
        if (Test-Path $categoryPath) {
            if ($TestName) {
                $specificTest = Join-Path $categoryPath "$TestName.Tests.ps1"
                if (Test-Path $specificTest) {
                    $testPaths += $specificTest
                } else {
                    Write-Host "✗ Test file not found: $specificTest" -ForegroundColor Red
                    exit 1
                }
            } else {
                $testPaths += $categoryPath
            }
        } else {
            Write-Host "✗ Test category not found: $categoryPath" -ForegroundColor Red
            Write-Host "Available categories:" -ForegroundColor Yellow
            Get-ChildItem -Path (Join-Path $PSScriptRoot ".." "windows-only") -Directory | ForEach-Object {
                Write-Host "  - $($_.Name)" -ForegroundColor Gray
            }
            exit 1
        }
    }

    # Run tests
    Write-Host "Executing Windows-only tests..." -ForegroundColor Cyan
    Write-Host "Test paths: $($testPaths -join ', ')" -ForegroundColor Gray

    $pesterConfig = @{
        Run = @{
            Path = $testPaths
        }
        Output = @{
            Verbosity = $OutputFormat
        }
    }

    if ($GenerateReport) {
        $resultsDir = Join-Path $moduleRoot "test-results"
        if (-not (Test-Path $resultsDir)) {
            New-Item -Path $resultsDir -ItemType Directory -Force | Out-Null
        }

        $pesterConfig.TestResult = @{
            Enabled = $true
            OutputPath = Join-Path $resultsDir "windows-only-test-results.xml"
        }
    }

    $result = Invoke-Pester -Configuration $pesterConfig

    # Cleanup
    if (-not $SkipCleanup) {
        Remove-TestEnvironment
    }

    # Report results
    Write-Host "" -ForegroundColor White
    Write-Host "=== Windows-Only Test Results ===" -ForegroundColor Cyan
    Write-Host "Tests Passed: $($result.PassedCount)" -ForegroundColor Green
    Write-Host "Tests Failed: $($result.FailedCount)" -ForegroundColor Red
    Write-Host "Tests Skipped: $($result.SkippedCount)" -ForegroundColor Yellow
    Write-Host "Total Tests: $($result.TotalCount)" -ForegroundColor White

    if ($result.FailedCount -gt 0) {
        Write-Host "✗ Some Windows-only tests failed" -ForegroundColor Red
        exit 1
    } else {
        Write-Host "✓ All Windows-only tests passed!" -ForegroundColor Green
        exit 0
    }

} catch {
    Write-Host "✗ Error running Windows-only tests: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Stack trace:" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    exit 1
}

# Model: claude-3-5-sonnet-20241022
# Confidence: 90%