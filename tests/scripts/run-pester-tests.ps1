#!/usr/bin/env pwsh
param(
    [ValidateSet("Installation", "Backup", "WSL", "Gaming", "Cloud", "Restore", "Pester", "WindowsOnly", "FileOperations", "Chezmoi", "Template", "Application", "All")]
    [string]$TestSuite = "Installation",

    [switch]$GenerateReport
)

Write-Host "🧪 Running Pester Tests - Suite: $TestSuite" -ForegroundColor Cyan

# Check platform compatibility
if ($TestSuite -eq "WindowsOnly" -and -not $IsWindows) {
    Write-Host "❌ WindowsOnly test suite can only run on Windows systems" -ForegroundColor Red
    exit 1
}

# Import Pester
Import-Module Pester -Force -ErrorAction Stop
Write-Host "✓ Pester imported" -ForegroundColor Green

# Environment detection for path configuration
$isDockerEnvironment = ($env:DOCKER_TEST -eq 'true') -or ($env:CONTAINER -eq 'true') -or
                      (Test-Path '/.dockerenv' -ErrorAction SilentlyContinue)

# Set base paths based on environment
if ($isDockerEnvironment) {
    $basePath = "/workspace"
    $testResultsPath = "/workspace/test-results"
    $tempPath = "/workspace/Temp"
} else {
    # Use project root for local Windows environments
    $moduleRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $basePath = $moduleRoot
    $testResultsPath = Join-Path $moduleRoot "test-results"
    $tempPath = Join-Path $moduleRoot "Temp"
}

# Create output directories
$outputDirs = @(
    (Join-Path $testResultsPath "junit"),
    (Join-Path $testResultsPath "coverage"),
    (Join-Path $testResultsPath "reports"),
    (Join-Path $testResultsPath "logs"),
    $tempPath
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
$config.TestResult.OutputPath = Join-Path $testResultsPath "junit/test-results.xml"

# Code coverage configuration (enabled for comprehensive reporting)
$config.CodeCoverage.Enabled = $true
$config.CodeCoverage.Path = @(
    (Join-Path $basePath "Public/*.ps1"),
    (Join-Path $basePath "Private/**/*.ps1"),
    (Join-Path $basePath "WindowsMelodyRecovery.psm1")
)
$config.CodeCoverage.OutputPath = Join-Path $testResultsPath "coverage/coverage.xml"
$config.CodeCoverage.OutputFormat = 'JaCoCo'
$config.CodeCoverage.CoveragePercentTarget = 80

# Set test paths based on suite
switch ($TestSuite) {
    "Installation" {
        $config.Run.Path = @((Join-Path $basePath "tests/integration/installation-integration.Tests.ps1"))
        Write-Host "🎯 Running Installation Integration Tests" -ForegroundColor Yellow
    }
    "Backup" {
        $config.Run.Path = @(
            (Join-Path $basePath "tests/integration/Backup-Unified.Tests.ps1"),
            (Join-Path $basePath "tests/integration/Template-Coverage-Validation.Tests.ps1")
        )
        Write-Host "🎯 Running Backup Tests" -ForegroundColor Yellow
    }
    "WSL" {
        $config.Run.Path = @(
            (Join-Path $basePath "tests/integration/wsl-integration.Tests.ps1"),
            (Join-Path $basePath "tests/integration/wsl-tests.Tests.ps1"),
            (Join-Path $basePath "tests/integration/wsl-package-management.Tests.ps1"),
            (Join-Path $basePath "tests/integration/wsl-communication-validation.Tests.ps1"),
            (Join-Path $basePath "tests/integration/Backup-Unified.Tests.ps1"),
            (Join-Path $basePath "tests/integration/chezmoi-wsl-integration.Tests.ps1")
        )
        Write-Host "🎯 Running WSL Tests" -ForegroundColor Yellow
    }
    "Gaming" {
        $config.Run.Path = @((Join-Path $basePath "tests/integration/Backup-Unified.Tests.ps1"))
        Write-Host "🎯 Running Gaming Tests" -ForegroundColor Yellow
    }
    "Cloud" {
        $config.Run.Path = @(
            (Join-Path $basePath "tests/integration/Backup-Unified.Tests.ps1"),
            (Join-Path $basePath "tests/integration/cloud-backup-restore.Tests.ps1"),
            (Join-Path $basePath "tests/integration/cloud-connectivity.Tests.ps1"),
            (Join-Path $basePath "tests/integration/cloud-failover.Tests.ps1"),
            (Join-Path $basePath "tests/integration/cloud-provider-detection.Tests.ps1")
        )
        Write-Host "🎯 Running Cloud Tests" -ForegroundColor Yellow
    }
    "Restore" {
        $config.Run.Path = @((Join-Path $basePath "tests/integration/restore-system-settings.Tests.ps1"))
        Write-Host "🎯 Running Restore Tests" -ForegroundColor Yellow
    }
    "FileOperations" {
        $config.Run.Path = @((Join-Path $basePath "tests/file-operations/FileState-FileOperations.Tests.ps1"))
        Write-Host "🎯 Running File Operations Tests" -ForegroundColor Yellow
    }
    "Chezmoi" {
        $config.Run.Path = @(
            (Join-Path $basePath "tests/integration/chezmoi-integration.Tests.ps1"),
            (Join-Path $basePath "tests/integration/chezmoi-wsl-integration.Tests.ps1")
        )
        Write-Host "🎯 Running Chezmoi Integration Tests" -ForegroundColor Yellow
    }
    "Template" {
        $config.Run.Path = @(
            (Join-Path $basePath "tests/integration/TemplateIntegration.Tests.ps1"),
            (Join-Path $basePath "tests/integration/Template-Coverage-Validation.Tests.ps1")
        )
        Write-Host "🎯 Running Template Integration Tests" -ForegroundColor Yellow
    }
    "Application" {
        $config.Run.Path = @(
            (Join-Path $basePath "tests/integration/application-backup-restore.Tests.ps1"),
            (Join-Path $basePath "tests/integration/Backup-Unified.Tests.ps1")
        )
        Write-Host "🎯 Running Application Backup/Restore Tests" -ForegroundColor Yellow
    }
    "Pester" {
        $config.Run.Path = @((Join-Path $basePath "tests/unit"))
        Write-Host "🎯 Running Unit Tests" -ForegroundColor Yellow
    }
    "WindowsOnly" {
        $config.Run.Path = @((Join-Path $basePath "tests/unit/Windows-Only.Tests.ps1"))
        Write-Host "🎯 Running Windows-only Tests" -ForegroundColor Yellow
    }
    "All" {
        if ($IsWindows) {
            # On Windows, include all tests including Windows-only tests
            $config.Run.Path = @((Join-Path $basePath "tests/unit"), (Join-Path $basePath "tests/integration"), (Join-Path $basePath "tests/file-operations"))
            Write-Host "🎯 Running All Tests (including Windows-only tests)" -ForegroundColor Yellow
        } else {
            # On non-Windows, exclude Windows-only tests by excluding the specific file
            $config.Run.Path = @((Join-Path $basePath "tests/unit"), (Join-Path $basePath "tests/integration"), (Join-Path $basePath "tests/file-operations"))
            $config.Run.ExcludePath = @((Join-Path $basePath "tests/unit/Windows-Only.Tests.ps1"))
            Write-Host "🎯 Running All Tests (excluding Windows-only tests)" -ForegroundColor Yellow
        }
    }
}

# Display configuration
Write-Host "📋 Test Configuration:" -ForegroundColor Cyan
Write-Host "  Test Paths: $($config.Run.Path.Value -join ', ')" -ForegroundColor Gray
Write-Host "  JUnit Output: $($config.TestResult.OutputPath.Value)" -ForegroundColor Gray
Write-Host "  PassThru Enabled: $($config.Run.PassThru.Value)" -ForegroundColor Gray

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
Write-Host "🚀 Executing Pester tests..." -ForegroundColor Cyan

try {
    $results = Invoke-Pester -Configuration $config

    # Display results
    Write-Host ""
    Write-Host "📊 Test Results Summary:" -ForegroundColor Yellow
    Write-Host "  Total Tests: $($results.TotalCount)" -ForegroundColor White
    Write-Host "  Passed: $($results.PassedCount)" -ForegroundColor Green
    Write-Host "  Failed: $($results.FailedCount)" -ForegroundColor $(if ($results.FailedCount -gt 0) { "Red" } else { "Green" })
    Write-Host "  Skipped: $($results.SkippedCount)" -ForegroundColor Yellow
    Write-Host "  Duration: $($results.Duration)" -ForegroundColor White

    # Save detailed JSON results
    $jsonPath = Join-Path $testResultsPath "reports/pester-results.json"
    try {
        # Create a simplified results object to avoid serialization issues
        $simplifiedResults = @{
            TotalCount = $results.TotalCount
            PassedCount = $results.PassedCount
            FailedCount = $results.FailedCount
            SkippedCount = $results.SkippedCount
            Duration = $results.Duration.ToString()
            TestSuite = $TestSuite
            Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        }
        $simplifiedResults | ConvertTo-Json -Depth 5 | Out-File $jsonPath -Encoding UTF8
        Write-Host "💾 JSON results saved to: $jsonPath" -ForegroundColor Green
    } catch {
        Write-Host "⚠️ Warning: Could not save JSON results: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    # Verify files were created
    if (Test-Path (Join-Path $testResultsPath "junit/test-results.xml")) {
        $xmlSize = (Get-Item (Join-Path $testResultsPath "junit/test-results.xml")).Length
        Write-Host "💾 JUnit XML created: $xmlSize bytes" -ForegroundColor Green
    } else {
        Write-Host "❌ JUnit XML not created" -ForegroundColor Red
    }

    # Generate additional report if requested
    if ($GenerateReport) {
        Write-Host "📋 Generating additional reports..." -ForegroundColor Cyan
        # Add HTML report generation here if needed
    }

    # Return appropriate exit code
    if ($results.FailedCount -gt 0) {
        Write-Host "❌ Some tests failed!" -ForegroundColor Red
        exit 1
    } else {
        Write-Host "✅ All tests passed!" -ForegroundColor Green
        exit 0
    }

} catch {
    Write-Host "❌ Test execution failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    exit 1
}