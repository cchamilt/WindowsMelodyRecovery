# PowerShell Profile for Test Runner Container

# Set up environment
$env:PSModulePath = "/workspace/Public:/workspace/Private:$env:PSModulePath"

# Import required modules for testing
try {
    # Try to import Pester, but don't fail if it's not available
    $pesterModule = Get-Module -ListAvailable Pester -ErrorAction SilentlyContinue
    if ($pesterModule) {
        Import-Module Pester -Force -ErrorAction SilentlyContinue
        Write-Verbose "✓ Pester module imported successfully"
    } else {
        Write-Verbose "⚠ Pester module not found - will attempt installation on demand"
    }
} catch {
    Write-Verbose "Failed to import Pester module: $_"
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
    Write-Information -MessageData "Mock Setup-Chezmoi completed" -InformationAction Continue
    return @{ Success = $true; Message = "Chezmoi setup completed" }
}

# Mock Invoke-WSLScript function for tests that don't use the real container
function Global:Invoke-WSLScript {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ScriptContent,

        [Parameter(Mandatory=$false)]
        [string]$Distribution,

        [Parameter(Mandatory=$false)]
        [string]$WorkingDirectory,

        [Parameter(Mandatory=$false)]
        [switch]$AsRoot,

        [Parameter(Mandatory=$false)]
        [switch]$PassThru
    )

    # In test environment, simulate WSL script execution
    Write-Verbose "Mock WSL Script Execution:"
    Write-Verbose "Distribution: $($Distribution ?? 'default')"
    Write-Verbose "AsRoot: $AsRoot"
    Write-Verbose "WorkingDirectory: $($WorkingDirectory ?? 'default')"
    Write-Verbose "Script: $($ScriptContent.Substring(0, [Math]::Min(100, $ScriptContent.Length)))..."

    # Simulate successful execution
    $output = "Mock WSL script execution completed successfully"

    if ($PassThru) {
        return @{
            ExitCode = 0
            Output = $output
            Error = ""
            Success = $true
        }
    }

    Write-Information -MessageData $output  -InformationAction Continue-ForegroundColor Green
}

# Function to simulate module installation
function Install-TestModule {
    param(
        [switch]$Force,
        [switch]$CleanInstall,
        [switch]$Verbose
    )

    Write-Information -MessageData "🔧 Installing WindowsMelodyRecovery module for testing..." -InformationAction Continue

    # Run the installation simulation script
    $installResult = & "/tests/scripts/simulate-installation.ps1" -Force:$Force -CleanInstall:$CleanInstall -Verbose:$Verbose

    if ($installResult.Success) {
        Write-Information -MessageData "✅ Module installed successfully for testing" -InformationAction Continue
        return $true
    } else {
        Write-Error -Message "❌ Module installation failed"
        return $false
    }
}

# Function to run quick health check
function Test-Environment {
    Write-Information -MessageData "🔍 Testing test environment..." -InformationAction Continue

    # Check if we're in Docker
    if (Test-Path "/.dockerenv") {
        Write-Information -MessageData "✓ Running in Docker container" -InformationAction Continue
    } else {
        Write-Warning -Message "⚠ Not running in Docker container"
    }

    # Check test directories
    $testDirs = @("/tests/unit", "/tests/integration", "/test-results")
    foreach ($dir in $testDirs) {
        if (Test-Path $dir) {
            Write-Information -MessageData "✓ $dir exists" -InformationAction Continue
        } else {
            Write-Error -Message "✗ $dir missing"
        }
    }

    # Check modules
    $modules = @("Pester", "PSScriptAnalyzer")
    foreach ($module in $modules) {
        if (Get-Module -ListAvailable -Name $module) {
            $version = (Get-Module -ListAvailable -Name $module | Select-Object -First 1).Version
            Write-Information -MessageData "✓ $module $version available" -InformationAction Continue
        } else {
            Write-Error -Message "✗ $module not available"
        }
    }

    # Check if WindowsMelodyRecovery module is installed
    if (Get-Module -ListAvailable -Name "WindowsMelodyRecovery") {
        Write-Information -MessageData "✓ WindowsMelodyRecovery module installed" -InformationAction Continue
    } else {
        Write-Warning -Message "⚠ WindowsMelodyRecovery module not installed (run Install-TestModule)"
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

    # Ensure Pester is available
    try {
        $pesterModule = Get-Module -ListAvailable Pester -ErrorAction SilentlyContinue
        if (-not $pesterModule) {
            Write-Warning -Message "⚠ Pester module not available - attempting installation..."
            Install-Module -Name Pester -Force -Scope CurrentUser -ErrorAction SilentlyContinue
        }
        Import-Module Pester -Force -ErrorAction SilentlyContinue
        Write-Verbose "✓ Pester module loaded for test run"
    } catch {
        Write-Error -Message "❌ Failed to load Pester module: $_"
        Write-Warning -Message "Tests may not run properly without Pester"
    }

    # Install module if requested or if not already installed
    if ($InstallModule -or -not (Get-Module -ListAvailable -Name "WindowsMelodyRecovery")) {
        Write-Information -MessageData "📦 Installing module for test run..." -InformationAction Continue
        if (-not (Install-TestModule -Force -Verbose:$Verbose)) {
            Write-Error -Message "❌ Failed to install module, aborting test run"
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
    Write-Information -MessageData "🧪 Running tests from: $TestPath" -InformationAction Continue
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

        Write-Information -MessageData "`n📊 Test Summary:" -InformationAction Continue
        Write-Information -MessageData "  Total: $total"  -InformationAction Continue-ForegroundColor White
        Write-Information -MessageData "  Passed: $passed" -InformationAction Continue
        Write-Information -MessageData "  Failed: $failed"  -InformationAction Continue-ForegroundColor $(if ($failed -eq 0) { 'Green' } else { 'Red' })
        Write-Warning -Message "  Skipped: $skipped"

        if ($failed -eq 0) {
            Write-Information -MessageData "✅ All tests passed!" -InformationAction Continue
        } else {
            Write-Warning -Message "⚠️ Some tests failed"
        }
    }

    return $results
}

Write-Information -MessageData "🧪 Test Runner environment loaded" -InformationAction Continue
Write-Information -MessageData "Available commands: Test-Environment, Start-TestRun, Install-TestModule" -InformationAction Continue
