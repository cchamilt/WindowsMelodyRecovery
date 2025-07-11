# Docker Test Runner Script
# Runs PowerShell tests in Docker containers for cross-platform validation

param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('unit', 'integration', 'file-operations', 'all')]
    [string]$TestCategory = 'all',

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = "test-results",

    [Parameter(Mandatory = $false)]
    [switch]$CleanupAfter = $true,

    [Parameter(Mandatory = $false)]
    [switch]$StopOnFirstFailure = $false
)

# Configuration
$DockerComposeFile = "docker-compose.test.yml"
$ContainerName = "wmr-test-runner"
$WorkspaceDir = "/workspace"

# Global variable to store the detected Docker Compose command
$script:DockerComposeCommand = ""

function Write-TestLog {
    param(
        [string]$Message,
        [ValidateSet('Info', 'Success', 'Warning', 'Error')]
        [string]$Level = 'Info'
    )

    $color = switch ($Level) {
        'Info' { 'White' }
        'Success' { 'Green' }
        'Warning' { 'Yellow' }
        'Error' { 'Red' }
    }

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"

    Write-Host $logMessage -ForegroundColor $color
}

function Test-DockerComposeCommand {
    # Test modern Docker Compose command first
    try {
        $null = docker compose version 2>$null
        if ($LASTEXITCODE -eq 0) {
            $script:DockerComposeCommand = "docker compose"
            Write-TestLog "Using modern Docker Compose command: docker compose" -Level Success
            return $true
        }
    } catch {
        # Continue to test legacy command
    }

    # Test legacy Docker Compose command
    try {
        $null = docker-compose --version 2>$null
        if ($LASTEXITCODE -eq 0) {
            $script:DockerComposeCommand = "docker-compose"
            Write-TestLog "Using legacy Docker Compose command: docker-compose" -Level Success
            return $true
        }
    } catch {
        # Neither command is available
    }

    Write-TestLog "Neither 'docker compose' nor 'docker-compose' is available" -Level Error
    return $false
}

function Test-DockerEnvironment {
    Write-TestLog "Validating Docker environment..." -Level Info

    # Check if Docker is available
    try {
        docker --version | Out-Null
        Write-TestLog "Docker is available" -Level Success
    } catch {
        Write-TestLog "Docker is not available. Please install Docker." -Level Error
        throw "Docker not found"
    }

    # Check if Docker Compose is available and determine which command to use
    if (-not (Test-DockerComposeCommand)) {
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
        $cleanupCmd = "$script:DockerComposeCommand -f $DockerComposeFile down -v"
        Write-TestLog "Cleaning up existing containers: $cleanupCmd" -Level Info
        Invoke-Expression "$cleanupCmd" 2>$null

        # Build and start containers
        Write-TestLog "Building Docker containers..." -Level Info
        $buildCmd = "$script:DockerComposeCommand -f $DockerComposeFile build --parallel"
        Write-TestLog "Build command: $buildCmd" -Level Info
        Invoke-Expression $buildCmd

        Write-TestLog "Starting Docker containers..." -Level Info
        $startCmd = "$script:DockerComposeCommand -f $DockerComposeFile up -d"
        Write-TestLog "Start command: $startCmd" -Level Info
        Invoke-Expression $startCmd

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
            $logsCmd = "$script:DockerComposeCommand -f $DockerComposeFile logs"
            Invoke-Expression "$logsCmd" > "$OutputPath/docker-logs.txt" 2>&1

            # Stop and remove containers
            $downCmd = "$script:DockerComposeCommand -f $DockerComposeFile down -v"
            Write-TestLog "Stopping containers: $downCmd" -Level Info
            Invoke-Expression $downCmd

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
        [string]$TestCategory,
        [string]$OutputFile
    )

    $status = if ($Success) { "✅ PASSED" } else { "❌ FAILED" }
    $summary = @"

=== DOCKER TEST SUMMARY ===
Test Category: $TestCategory
Status: $status
Environment: Docker (Cross-platform)
Output: $OutputFile

Container: $ContainerName
Compose File: $DockerComposeFile
Docker Compose Command: $script:DockerComposeCommand
Cleanup: $CleanupAfter
=========================

"@

    Write-Host $summary -ForegroundColor $(if ($Success) { 'Green' } else { 'Red' })

    # Write summary to file
    $summary | Out-File -FilePath "$OutputPath/docker-test-summary.txt" -Append
}

# Main execution
try {
    Write-TestLog "Starting Docker test execution..." -Level Info
    Write-TestLog "Test Category: $TestCategory" -Level Info
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
    $testResult = Invoke-DockerTests -TestCategory $TestCategory -OutputFile "$OutputPath/docker-test-results.xml"

    # Generate summary
    Write-TestSummary -Success $testResult -TestCategory $TestCategory -OutputFile "$OutputPath/docker-test-results.xml"

    if ($testResult) {
        Write-TestLog "Docker tests completed successfully" -Level Success
        exit 0
    } else {
        Write-TestLog "Docker tests failed" -Level Error
        exit 1
    }

} catch {
    Write-TestLog "Docker test execution failed: $($_.Exception.Message)" -Level Error
    Write-TestSummary -Success $false -TestCategory $TestCategory -OutputFile "$OutputPath/docker-test-results.xml"
    exit 1

} finally {
    # Always cleanup
    Stop-DockerTestEnvironment
}