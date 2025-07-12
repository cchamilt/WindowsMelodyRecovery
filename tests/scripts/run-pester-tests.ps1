#!/usr/bin/env pwsh
param(
    [ValidateSet("Installation", "Backup", "WSL", "Gaming", "Cloud", "Restore", "Pester", "WindowsOnly", "FileOperations", "Chezmoi", "Template", "Application", "All")]
    [string]$TestSuite = "Installation",

    [switch]$GenerateReport
)

Write-Information -MessageData "🧪 Running Pester Tests - Suite: $TestSuite" -InformationAction Continue

# Check platform compatibility
if ($TestSuite -eq "WindowsOnly" -and -not $IsWindows) {
    Write-Error -Message "❌ WindowsOnly test suite can only run on Windows systems"
    exit 1
}

# Import Pester
Import-Module Pester -Force -ErrorAction Stop
Write-Information -MessageData "✓ Pester imported" -InformationAction Continue

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
        Write-Warning -Message "🎯 Running Installation Integration Tests"
    }
    "Backup" {
        $config.Run.Path = @(
            (Join-Path $basePath "tests/integration/Backup-Unified.Tests.ps1"),
            (Join-Path $basePath "tests/integration/Template-Coverage-Validation.Tests.ps1")
        )
        Write-Warning -Message "🎯 Running Backup Tests"
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
        Write-Warning -Message "🎯 Running WSL Tests"
    }
    "Gaming" {
        $config.Run.Path = @((Join-Path $basePath "tests/integration/Backup-Unified.Tests.ps1"))
        Write-Warning -Message "🎯 Running Gaming Tests"
    }
    "Cloud" {
        $config.Run.Path = @(
            (Join-Path $basePath "tests/integration/Backup-Unified.Tests.ps1"),
            (Join-Path $basePath "tests/integration/cloud-backup-restore.Tests.ps1"),
            (Join-Path $basePath "tests/integration/cloud-connectivity.Tests.ps1"),
            (Join-Path $basePath "tests/integration/cloud-failover.Tests.ps1"),
            (Join-Path $basePath "tests/integration/cloud-provider-detection.Tests.ps1")
        )
        Write-Warning -Message "🎯 Running Cloud Tests"
    }
    "Restore" {
        $config.Run.Path = @((Join-Path $basePath "tests/integration/restore-system-settings.Tests.ps1"))
        Write-Warning -Message "🎯 Running Restore Tests"
    }
    "FileOperations" {
        $config.Run.Path = @((Join-Path $basePath "tests/file-operations/FileState-FileOperations.Tests.ps1"))
        Write-Warning -Message "🎯 Running File Operations Tests"
    }
    "Chezmoi" {
        $config.Run.Path = @(
            (Join-Path $basePath "tests/integration/chezmoi-integration.Tests.ps1"),
            (Join-Path $basePath "tests/integration/chezmoi-wsl-integration.Tests.ps1")
        )
        Write-Warning -Message "🎯 Running Chezmoi Integration Tests"
    }
    "Template" {
        $config.Run.Path = @(
            (Join-Path $basePath "tests/integration/TemplateIntegration.Tests.ps1"),
            (Join-Path $basePath "tests/integration/Template-Coverage-Validation.Tests.ps1")
        )
        Write-Warning -Message "🎯 Running Template Integration Tests"
    }
    "Application" {
        $config.Run.Path = @(
            (Join-Path $basePath "tests/integration/application-backup-restore.Tests.ps1"),
            (Join-Path $basePath "tests/integration/Backup-Unified.Tests.ps1")
        )
        Write-Warning -Message "🎯 Running Application Backup/Restore Tests"
    }
    "Pester" {
        $config.Run.Path = @((Join-Path $basePath "tests/unit"))
        Write-Warning -Message "🎯 Running Unit Tests"
    }
    "WindowsOnly" {
        $config.Run.Path = @((Join-Path $basePath "tests/unit/Windows-Only.Tests.ps1"))
        Write-Warning -Message "🎯 Running Windows-only Tests"
    }
    "All" {
        if ($IsWindows) {
            # On Windows, include all tests including Windows-only tests
            $config.Run.Path = @((Join-Path $basePath "tests/unit"), (Join-Path $basePath "tests/integration"), (Join-Path $basePath "tests/file-operations"))
            Write-Warning -Message "🎯 Running All Tests (including Windows-only tests)"
        } else {
            # On non-Windows, exclude Windows-only tests by excluding the specific file
            $config.Run.Path = @((Join-Path $basePath "tests/unit"), (Join-Path $basePath "tests/integration"), (Join-Path $basePath "tests/file-operations"))
            $config.Run.ExcludePath = @((Join-Path $basePath "tests/unit/Windows-Only.Tests.ps1"))
            Write-Warning -Message "🎯 Running All Tests (excluding Windows-only tests)"
        }
    }
}

# Display configuration
Write-Information -MessageData "📋 Test Configuration:" -InformationAction Continue
Write-Verbose -Message "  Test Paths: $($config.Run.Path.Value -join ', ')"
Write-Verbose -Message "  JUnit Output: $($config.TestResult.OutputPath.Value)"
Write-Verbose -Message "  PassThru Enabled: $($config.Run.PassThru.Value)"

# Verify test files exist
$missingFiles = @()
foreach ($path in $config.Run.Path.Value) {
    if (-not (Test-Path $path)) {
        $missingFiles += $path
    }
}

if ($missingFiles.Count -gt 0) {
    Write-Error -Message "❌ Missing test files:"
    $missingFiles | ForEach-Object { Write-Error -Message "  - $_" }
    exit 1
}

Write-Information -MessageData "✓ All test files exist" -InformationAction Continue

# Run the tests
Write-Information -MessageData "🚀 Executing Pester tests..." -InformationAction Continue

try {
    $results = Invoke-Pester -Configuration $config

    # Display results
    Write-Information -MessageData "" -InformationAction Continue
    Write-Warning -Message "📊 Test Results Summary:"
    Write-Information -MessageData "  Total Tests: $($results.TotalCount)"  -InformationAction Continue-ForegroundColor White
    Write-Information -MessageData "  Passed: $($results.PassedCount)" -InformationAction Continue
    Write-Information -MessageData "  Failed: $($results.FailedCount)"  -InformationAction Continue-ForegroundColor $(if ($results.FailedCount -gt 0) { "Red" } else { "Green" })
    Write-Warning -Message "  Skipped: $($results.SkippedCount)"
    Write-Information -MessageData "  Duration: $($results.Duration)"  -InformationAction Continue-ForegroundColor White

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
        Write-Information -MessageData "💾 JSON results saved to: $jsonPath" -InformationAction Continue
    } catch {
        Write-Warning -Message "⚠️ Warning: Could not save JSON results: $($_.Exception.Message)"
    }

    # Verify files were created
    if (Test-Path (Join-Path $testResultsPath "junit/test-results.xml")) {
        $xmlSize = (Get-Item (Join-Path $testResultsPath "junit/test-results.xml")).Length
        Write-Information -MessageData "💾 JUnit XML created: $xmlSize bytes" -InformationAction Continue
    } else {
        Write-Error -Message "❌ JUnit XML not created"
    }

    # Generate additional report if requested
    if ($GenerateReport) {
        Write-Information -MessageData "📋 Generating additional reports..." -InformationAction Continue
        # Add HTML report generation here if needed
    }

    # Return appropriate exit code
    if ($results.FailedCount -gt 0) {
        Write-Error -Message "❌ Some tests failed!"
        exit 1
    } else {
        Write-Information -MessageData "✅ All tests passed!" -InformationAction Continue
        exit 0
    }

} catch {
    Write-Error -Message "❌ Test execution failed: $($_.Exception.Message)"
    Write-Information -MessageData $_.ScriptStackTrace  -InformationAction Continue-ForegroundColor Red
    exit 1
}







