# run-docker-tests.ps1
# Comprehensive Docker test runner for 100% pass rate validation

[CmdletBinding()]
param(
    [ValidateSet('unit', 'integration', 'file-operations', 'all')]
    [string]$Category = 'all',

    [switch]$Parallel = $true,
    [switch]$Coverage = $false,
    [switch]$Verbose = $false,
    [switch]$StopOnFirstFailure = $false,
    [string]$OutputPath = "docker-test-results",
    [switch]$CleanupAfter = $true
)

# Set error handling
$ErrorActionPreference = 'Stop'

# Docker test configuration
$DockerComposeFile = "docker-compose.test.yml"
$ContainerName = "wmr-test-runner"
$WorkspaceDir = "/workspace"

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

function Test-DockerEnvironment {
    Write-TestLog "Checking Docker environment..." -Level Info

    # Check if Docker is available
    try {
        docker --version | Out-Null
        Write-TestLog "Docker is available" -Level Success
    } catch {
        Write-TestLog "Docker is not available. Please install Docker." -Level Error
        throw "Docker not found"
    }

    # Check if docker-compose is available
    try {
        docker-compose --version | Out-Null
        Write-TestLog "Docker Compose is available" -Level Success
    } catch {
        Write-TestLog "Docker Compose is not available. Please install Docker Compose." -Level Error
        throw "Docker Compose not found"
    }

    # Check if compose file exists
    if (-not (Test-Path $DockerComposeFile)) {
        Write-TestLog "Docker Compose file not found: $DockerComposeFile" -Level Error
        throw "Docker Compose file not found"
    }

    Write-TestLog "Docker environment validation completed" -Level Success
}

function Start-DockerTestEnvironment {
    Write-TestLog "Starting Docker test environment..." -Level Info

    try {
        # Clean up any existing containers
        docker-compose -f $DockerComposeFile down -v 2>$null

        # Build and start containers
        Write-TestLog "Building Docker containers..." -Level Info
        docker-compose -f $DockerComposeFile build --parallel

        Write-TestLog "Starting Docker containers..." -Level Info
        docker-compose -f $DockerComposeFile up -d

        # Wait for container to be ready
        Write-TestLog "Waiting for test environment to be ready..." -Level Info
        $maxAttempts = 30
        $attempt = 0

        do {
            $attempt++
            Start-Sleep -Seconds 2

            try {
                $result = docker exec $ContainerName pwsh -Command "Write-Host 'Ready'; exit 0" 2>$null
                if ($LASTEXITCODE -eq 0) {
                    Write-TestLog "Docker test environment is ready" -Level Success
                    return $true
                }
            } catch {
                # Continue trying
            }

            if ($attempt -ge $maxAttempts) {
                Write-TestLog "Timeout waiting for Docker environment" -Level Error
                return $false
            }

            Write-TestLog "Waiting for environment... (attempt $attempt/$maxAttempts)" -Level Info
        } while ($true)

    } catch {
        Write-TestLog "Failed to start Docker environment: $($_.Exception.Message)" -Level Error
        throw
    }
}

function Invoke-DockerTests {
    param(
        [string]$TestCategory,
        [string]$OutputFile
    )

    Write-TestLog "Running $TestCategory tests in Docker environment..." -Level Info

    # Determine test path based on category
    $testPath = switch ($TestCategory) {
        'unit' { './tests/unit/' }
        'integration' { './tests/integration/' }
        'file-operations' { './tests/file-operations/' }
        'all' { './tests/unit/', './tests/integration/', './tests/file-operations/' }
    }

    # Build PowerShell command for Docker
    $dockerCommand = @"
cd $WorkspaceDir
Import-Module ./WindowsMelodyRecovery.psd1 -Force

# Set environment variables for Docker testing
`$env:DOCKER_TEST = 'true'
`$env:CONTAINER = 'true'

Write-Host "🐳 Docker test environment initialized"
Write-Host "Running $TestCategory tests..."

`$allResults = @()
`$testPaths = @($($testPath -join ', '))

foreach (`$testPath in `$testPaths) {
    if (Test-Path `$testPath) {
        Write-Host "📁 Running tests from: `$testPath"
        `$result = Invoke-Pester -Path `$testPath -PassThru -Show Detailed
        `$allResults += `$result

        Write-Host "Results for `$testPath - Passed: `$(`$result.PassedCount), Failed: `$(`$result.FailedCount)"

        if (`$result.FailedCount -gt 0 -and '$StopOnFirstFailure' -eq 'True') {
            Write-Host "❌ Stopping on first failure as requested"
            break
        }
    } else {
        Write-Host "⚠️ Test path `$testPath does not exist, skipping..."
    }
}

# Calculate totals
`$totalPassed = (`$allResults | Measure-Object -Property PassedCount -Sum).Sum
`$totalFailed = (`$allResults | Measure-Object -Property FailedCount -Sum).Sum
`$totalTests = `$totalPassed + `$totalFailed

Write-Host ""
Write-Host "=== DOCKER TEST RESULTS ==="
Write-Host "Total Tests: `$totalTests"
Write-Host "Passed: `$totalPassed"
Write-Host "Failed: `$totalFailed"
if (`$totalTests -gt 0) {
    `$passRate = [math]::Round((`$totalPassed / `$totalTests) * 100, 2)
    Write-Host "Pass Rate: `$passRate%"

    # Docker environment target: 100% pass rate
    if (`$totalFailed -eq 0) {
        Write-Host "✅ Docker environment achieved 100% pass rate!"
        exit 0
    } else {
        Write-Host "❌ Docker environment failed to achieve 100% pass rate. `$totalFailed tests failed."
        Write-Host "Docker tests should be 100% reliable. Please fix failing tests."
        exit 1
    }
} else {
    Write-Host "⚠️ No tests found in specified paths"
    exit 0
}
"@

    # Execute tests in Docker container
    try {
        docker exec $ContainerName pwsh -Command $dockerCommand
        $dockerExitCode = $LASTEXITCODE

        if ($dockerExitCode -eq 0) {
            Write-TestLog "$TestCategory tests completed successfully" -Level Success
            return $true
        } else {
            Write-TestLog "$TestCategory tests failed with exit code: $dockerExitCode" -Level Error
            return $false
        }

    } catch {
        Write-TestLog "Error running Docker tests: $($_.Exception.Message)" -Level Error
        return $false
    }
}

function Stop-DockerTestEnvironment {
    if ($CleanupAfter) {
        Write-TestLog "Cleaning up Docker environment..." -Level Info

        try {
            # Get logs before cleanup (for debugging)
            Write-TestLog "Saving Docker logs..." -Level Info
            docker-compose -f $DockerComposeFile logs > "$OutputPath/docker-logs.txt" 2>&1

            # Stop and remove containers
            docker-compose -f $DockerComposeFile down -v

            # Clean up Docker system
            docker system prune -f > $null 2>&1

            Write-TestLog "Docker cleanup completed" -Level Success
        } catch {
            Write-TestLog "Warning: Docker cleanup failed: $($_.Exception.Message)" -Level Warning
        }
    } else {
        Write-TestLog "Skipping Docker cleanup (CleanupAfter = false)" -Level Info
    }
}

function New-OutputDirectory {
    if (-not (Test-Path $OutputPath)) {
        New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
        Write-TestLog "Created output directory: $OutputPath" -Level Info
    }
}

function Write-TestSummary {
    param(
        [bool]$Success,
        [string]$Category
    )

    $summary = @{
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Environment = "Docker"
        Category = $Category
        Success = $Success
        TargetPassRate = "100%"
        Status = if ($Success) { "✅ PASSED" } else { "❌ FAILED" }
        Notes = @(
            "Docker environment tests must achieve 100% pass rate",
            "All Docker-compatible tests should be reliable and deterministic",
            "Failing tests should be fixed or moved to Windows-only category"
        )
    }

    $summaryPath = "$OutputPath/test-summary.json"
    $summary | ConvertTo-Json -Depth 3 | Out-File -FilePath $summaryPath -Encoding UTF8
    Write-TestLog "Test summary saved to: $summaryPath" -Level Info
}

# Main execution
try {
    Write-TestLog "🚀 Starting Docker test execution..." -Level Info
    Write-TestLog "Category: $Category" -Level Info
    Write-TestLog "Output Path: $OutputPath" -Level Info

    # Create output directory
    New-OutputDirectory

    # Validate Docker environment
    Test-DockerEnvironment

    # Start Docker test environment
    if (-not (Start-DockerTestEnvironment)) {
        throw "Failed to start Docker test environment"
    }

    # Run tests
    $testSuccess = Invoke-DockerTests -TestCategory $Category -OutputFile "$OutputPath/test-results.xml"

    # Write summary
    Write-TestSummary -Success $testSuccess -Category $Category

    if ($testSuccess) {
        Write-TestLog "🎉 All Docker tests completed successfully!" -Level Success
        Write-TestLog "Docker environment achieved 100% pass rate target" -Level Success
    } else {
        Write-TestLog "💥 Docker tests failed" -Level Error
        Write-TestLog "Please review failing tests and fix for Docker compatibility" -Level Error
    }

    # Final status
    if ($testSuccess) {
        Write-TestLog "✅ DOCKER TESTS: SUCCESS" -Level Success
    } else {
        Write-TestLog "❌ DOCKER TESTS: FAILED" -Level Error
    }

} catch {
    Write-TestLog "Fatal error: $($_.Exception.Message)" -Level Error
    $testSuccess = $false
} finally {
    # Always cleanup
    Stop-DockerTestEnvironment
}

# Exit with appropriate code
if ($testSuccess) {
    exit 0
} else {
    exit 1
}