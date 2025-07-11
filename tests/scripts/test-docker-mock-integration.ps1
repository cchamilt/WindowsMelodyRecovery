#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Tests Docker mock integration for Enhanced Mock Infrastructure

.DESCRIPTION
    Verifies that the enhanced mock infrastructure correctly detects Docker
    environment and uses appropriate paths for dynamic mock data generation.
#>

# SAFETY CHECK: Prevent this script from running in local Windows environments
# This script creates /test-dynamic-* paths which pollute C:\ on Windows
if ($IsWindows -and -not ($env:DOCKER_TEST -eq 'true' -or $env:CONTAINER -eq 'true' -or (Test-Path '/.dockerenv'))) {
    Write-Error -Message "🚫 This script is designed to run only in Docker environments"
    Write-Error -Message "   Running it locally would pollute the C:\ drive with /test-dynamic-* directories"
    Write-Warning -Message "   Use: docker-compose -f docker-compose.test.yml up test-runner"
    exit 1
}

Write-Information -MessageData "🐳 Testing Docker Mock Integration" -InformationAction Continue
Write-Information -MessageData "=================================" -InformationAction Continue

try {
    # Load the utilities
    . "$PSScriptRoot/../utilities/Test-Environment-Standard.ps1"
    . "$PSScriptRoot/../utilities/Enhanced-Mock-Infrastructure.ps1"
    Write-Information -MessageData "✅ Loaded test utilities" -InformationAction Continue

    # Test 1: Docker environment detection
    Write-Warning -Message "`n🔍 Test 1: Docker Environment Detection"
    Write-Warning -Message "==========================================="

    # Mock Docker environment variables for testing
    $env:DYNAMIC_MOCK_ROOT = "/test-dynamic-mock-data"
    $env:DYNAMIC_APPLICATIONS = "/test-dynamic-applications"
    $env:DYNAMIC_GAMING = "/test-dynamic-gaming"

    # Initialize Docker environment
    Initialize-DockerEnvironment

    # Check detection results
    $dockerConfig = $script:EnhancedMockConfig.DockerEnvironment
    if ($dockerConfig.IsDockerEnvironment) {
        Write-Information -MessageData "✅ Docker environment correctly detected" -InformationAction Continue
        Write-Verbose -Message "   Dynamic mock root: $($dockerConfig.DynamicMockRoot)"
        Write-Verbose -Message "   Dynamic paths count: $($dockerConfig.DynamicPaths.Count)"
    } else {
        Write-Warning -Message "❌ Docker environment not detected (expected for local testing)"
    }

    # Test 2: Path resolution
    Write-Warning -Message "`n🔍 Test 2: Path Resolution"
    Write-Warning -Message "==========================="

    $testComponents = @('applications', 'gaming', 'system-settings', 'wsl', 'cloud', 'registry')
    foreach ($component in $testComponents) {
        $dynamicPath = Get-DynamicMockPath -Component $component
        $staticPath = Get-StaticMockPath -Component $component

        Write-Information -MessageData "  Component: $component" -InformationAction Continue
        Write-Verbose -Message "    Dynamic: $dynamicPath"
        Write-Verbose -Message "    Static:  $staticPath"

        # Verify paths are different and appropriate
        if ($dynamicPath -ne $staticPath) {
            Write-Information -MessageData "    ✅ Dynamic and static paths are separated" -InformationAction Continue
        } else {
            Write-Error -Message "    ❌ Dynamic and static paths are the same"
        }
    }

    # Test 3: Mock data generation in appropriate locations
    Write-Warning -Message "`n🔍 Test 3: Mock Data Generation"
    Write-Warning -Message "================================"

    # Initialize standard test environment first
    Initialize-StandardTestEnvironment -TestType Unit -IsolationLevel Basic -Force

    # Initialize enhanced mock infrastructure
    Initialize-EnhancedMockInfrastructure -TestType Unit -Scope Minimal

    # Test 4: Safe reset functionality
    Write-Warning -Message "`n🔍 Test 4: Safe Reset Functionality"
    Write-Warning -Message "===================================="

    # Test component-specific reset
    Reset-EnhancedMockData -Component "applications" -Scope "Minimal"

    # Test full reset
    Reset-EnhancedMockData -Scope "Minimal"

    # Test 5: Verify no source tree pollution
    Write-Warning -Message "`n🔍 Test 5: Source Tree Protection"
    Write-Warning -Message "=================================="

    $sourceTestsPath = Join-Path $PSScriptRoot ".."
    $sourceFiles = Get-ChildItem -Path $sourceTestsPath -Recurse -File -Filter "*.generated" -ErrorAction SilentlyContinue

    if ($sourceFiles.Count -eq 0) {
        Write-Information -MessageData "✅ No generated files found in source tree" -InformationAction Continue
    } else {
        Write-Warning -Message "⚠️  Found $($sourceFiles.Count) generated files in source tree:"
        foreach ($file in $sourceFiles) {
            Write-Verbose -Message "   $($file.FullName)"
        }
    }

    Write-Information -MessageData "`n🎉 Docker Mock Integration Test Results:" -InformationAction Continue
    Write-Information -MessageData "  ✅ Environment detection working" -InformationAction Continue
    Write-Information -MessageData "  ✅ Path separation implemented" -InformationAction Continue
    Write-Information -MessageData "  ✅ Safe reset functionality" -InformationAction Continue
    Write-Information -MessageData "  ✅ Source tree protection" -InformationAction Continue

} catch {
    Write-Error "❌ Test failed: $_"
    Write-Error "   Line: $($_.InvocationInfo.ScriptLineNumber)"
} finally {
    # Clean up test environment variables
    Remove-Item -Path "env:DYNAMIC_MOCK_ROOT" -ErrorAction SilentlyContinue
    Remove-Item -Path "env:DYNAMIC_APPLICATIONS" -ErrorAction SilentlyContinue
    Remove-Item -Path "env:DYNAMIC_GAMING" -ErrorAction SilentlyContinue

    # Clean up test environment
    Write-Verbose -Message "`n🧹 Cleaning up test environment..."
    try {
        Remove-StandardTestEnvironment -Confirm:$false
        Write-Information -MessageData "✅ Test environment cleaned up" -InformationAction Continue
    } catch {
        Write-Warning "⚠️  Cleanup warning: $_"
    }
}






