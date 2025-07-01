# PowerShell Profile for Test Runner Container

# Set up environment
$env:PSModulePath = "/workspace/Public:/workspace/Private:$env:PSModulePath"

# Import required modules for testing
try {
    Import-Module Pester -Force -ErrorAction Stop
    Write-Verbose "✓ Pester module imported successfully"
} catch {
    Write-Warning "Failed to import Pester module: $_"
}

try {
    Import-Module PSScriptAnalyzer -Force -ErrorAction SilentlyContinue
    Write-Verbose "✓ PSScriptAnalyzer module imported successfully"
} catch {
    Write-Verbose "PSScriptAnalyzer module not available"
}

# Import test utilities
if (Test-Path "/tests/utilities/TestHelper.ps1") {
    . "/tests/utilities/TestHelper.ps1"
}

# Set up aliases for common test commands
Set-Alias -Name "trun" -Value "Invoke-Pester"
Set-Alias -Name "thealth" -Value "health-check.ps1"

# Mock Setup-Chezmoi function for integration tests
function Global:Setup-Chezmoi {
    param(
        [string]$SourcePath,
        [string]$ConfigPath,
        [switch]$Force
    )
    Write-Host "Mock Setup-Chezmoi completed" -ForegroundColor Green
    return @{ Success = $true; Message = "Chezmoi setup completed" }
}

# Function to simulate module installation
function Install-TestModule {
    param(
        [switch]$Force,
        [switch]$CleanInstall,
        [switch]$Verbose
    )
    
    Write-Host "🔧 Installing WindowsMelodyRecovery module for testing..." -ForegroundColor Cyan
    
    # Run the installation simulation script
    $installResult = & "/tests/scripts/simulate-installation.ps1" -Force:$Force -CleanInstall:$CleanInstall -Verbose:$Verbose
    
    if ($installResult.Success) {
        Write-Host "✅ Module installed successfully for testing" -ForegroundColor Green
        return $true
    } else {
        Write-Host "❌ Module installation failed" -ForegroundColor Red
        return $false
    }
}

# Function to run quick health check
function Test-Environment {
    Write-Host "🔍 Testing test environment..." -ForegroundColor Cyan
    
    # Check if we're in Docker
    if (Test-Path "/.dockerenv") {
        Write-Host "✓ Running in Docker container" -ForegroundColor Green
    } else {
        Write-Host "⚠ Not running in Docker container" -ForegroundColor Yellow
    }
    
    # Check test directories
    $testDirs = @("/tests/unit", "/tests/integration", "/test-results")
    foreach ($dir in $testDirs) {
        if (Test-Path $dir) {
            Write-Host "✓ $dir exists" -ForegroundColor Green
        } else {
            Write-Host "✗ $dir missing" -ForegroundColor Red
        }
    }
    
    # Check modules
    $modules = @("Pester", "PSScriptAnalyzer")
    foreach ($module in $modules) {
        if (Get-Module -ListAvailable -Name $module) {
            $version = (Get-Module -ListAvailable -Name $module | Select-Object -First 1).Version
            Write-Host "✓ $module $version available" -ForegroundColor Green
        } else {
            Write-Host "✗ $module not available" -ForegroundColor Red
        }
    }
    
    # Check if WindowsMelodyRecovery module is installed
    if (Get-Module -ListAvailable -Name "WindowsMelodyRecovery") {
        Write-Host "✓ WindowsMelodyRecovery module installed" -ForegroundColor Green
    } else {
        Write-Host "⚠ WindowsMelodyRecovery module not installed (run Install-TestModule)" -ForegroundColor Yellow
    }
}

# Function to run tests with common options
function Start-TestRun {
    param(
        [string]$TestPath = "/tests/unit",
        [switch]$GenerateReport,
        [switch]$Verbose,
        [switch]$InstallModule
    )
    
    # Ensure Pester is imported
    try {
        Import-Module Pester -Force -ErrorAction Stop
        Write-Verbose "✓ Pester module loaded for test run"
    } catch {
        Write-Host "❌ Failed to import Pester module: $_" -ForegroundColor Red
        return
    }
    
    # Install module if requested or if not already installed
    if ($InstallModule -or -not (Get-Module -ListAvailable -Name "WindowsMelodyRecovery")) {
        Write-Host "📦 Installing module for test run..." -ForegroundColor Cyan
        if (-not (Install-TestModule -Force -Verbose:$Verbose)) {
            Write-Host "❌ Failed to install module, aborting test run" -ForegroundColor Red
            return
        }
    }
    
    $params = @{
        Path = $TestPath
        PassThru = $true
        Output = 'Detailed'
    }
    
    if ($Verbose) {
        $params.Verbose = $true
    }
    
    # Run the tests
    Write-Host "🧪 Running tests from: $TestPath" -ForegroundColor Cyan
    $results = Invoke-Pester @params
    
    if ($GenerateReport) {
        & "/tests/scripts/generate-reports.ps1" -TestResults $results
    }
    
    # Display summary
    if ($results) {
        $total = $results.TotalCount
        $passed = $results.PassedCount
        $failed = $results.FailedCount
        $skipped = $results.SkippedCount
        
        Write-Host "`n📊 Test Summary:" -ForegroundColor Cyan
        Write-Host "  Total: $total" -ForegroundColor White
        Write-Host "  Passed: $passed" -ForegroundColor Green
        Write-Host "  Failed: $failed" -ForegroundColor $(if ($failed -eq 0) { 'Green' } else { 'Red' })
        Write-Host "  Skipped: $skipped" -ForegroundColor Yellow
        
        if ($failed -eq 0) {
            Write-Host "✅ All tests passed!" -ForegroundColor Green
        } else {
            Write-Host "⚠️ Some tests failed" -ForegroundColor Yellow
        }
    }
    
    return $results
}

Write-Host "🧪 Test Runner environment loaded" -ForegroundColor Green
Write-Host "Available commands: Test-Environment, Start-TestRun, Install-TestModule" -ForegroundColor Cyan 