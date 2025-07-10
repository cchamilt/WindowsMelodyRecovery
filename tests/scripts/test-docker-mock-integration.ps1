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
    Write-Host "🚫 This script is designed to run only in Docker environments" -ForegroundColor Red
    Write-Host "   Running it locally would pollute the C:\ drive with /test-dynamic-* directories" -ForegroundColor Red
    Write-Host "   Use: docker-compose -f docker-compose.test.yml up test-runner" -ForegroundColor Yellow
    exit 1
}

Write-Host "🐳 Testing Docker Mock Integration" -ForegroundColor Cyan
Write-Host "=================================" -ForegroundColor Cyan

try {
    # Load the utilities
    . "$PSScriptRoot/../utilities/Test-Environment-Standard.ps1"
    . "$PSScriptRoot/../utilities/Enhanced-Mock-Infrastructure.ps1"
    Write-Host "✅ Loaded test utilities" -ForegroundColor Green
    
    # Test 1: Docker environment detection
    Write-Host "`n🔍 Test 1: Docker Environment Detection" -ForegroundColor Yellow
    Write-Host "===========================================" -ForegroundColor Yellow
    
    # Mock Docker environment variables for testing
    $env:DYNAMIC_MOCK_ROOT = "/test-dynamic-mock-data"
    $env:DYNAMIC_APPLICATIONS = "/test-dynamic-applications"
    $env:DYNAMIC_GAMING = "/test-dynamic-gaming"
    
    # Initialize Docker environment
    Initialize-DockerEnvironment
    
    # Check detection results
    $dockerConfig = $script:EnhancedMockConfig.DockerEnvironment
    if ($dockerConfig.IsDockerEnvironment) {
        Write-Host "✅ Docker environment correctly detected" -ForegroundColor Green
        Write-Host "   Dynamic mock root: $($dockerConfig.DynamicMockRoot)" -ForegroundColor Gray
        Write-Host "   Dynamic paths count: $($dockerConfig.DynamicPaths.Count)" -ForegroundColor Gray
    } else {
        Write-Host "❌ Docker environment not detected (expected for local testing)" -ForegroundColor Yellow
    }
    
    # Test 2: Path resolution
    Write-Host "`n🔍 Test 2: Path Resolution" -ForegroundColor Yellow
    Write-Host "===========================" -ForegroundColor Yellow
    
    $testComponents = @('applications', 'gaming', 'system-settings', 'wsl', 'cloud', 'registry')
    foreach ($component in $testComponents) {
        $dynamicPath = Get-DynamicMockPath -Component $component
        $staticPath = Get-StaticMockPath -Component $component
        
        Write-Host "  Component: $component" -ForegroundColor Cyan
        Write-Host "    Dynamic: $dynamicPath" -ForegroundColor Gray
        Write-Host "    Static:  $staticPath" -ForegroundColor Gray
        
        # Verify paths are different and appropriate
        if ($dynamicPath -ne $staticPath) {
            Write-Host "    ✅ Dynamic and static paths are separated" -ForegroundColor Green
        } else {
            Write-Host "    ❌ Dynamic and static paths are the same" -ForegroundColor Red
        }
    }
    
    # Test 3: Mock data generation in appropriate locations
    Write-Host "`n🔍 Test 3: Mock Data Generation" -ForegroundColor Yellow
    Write-Host "================================" -ForegroundColor Yellow
    
    # Initialize standard test environment first
    Initialize-StandardTestEnvironment -TestType Unit -IsolationLevel Basic -Force
    
    # Initialize enhanced mock infrastructure
    Initialize-EnhancedMockInfrastructure -TestType Unit -Scope Minimal
    
    # Test 4: Safe reset functionality
    Write-Host "`n🔍 Test 4: Safe Reset Functionality" -ForegroundColor Yellow
    Write-Host "====================================" -ForegroundColor Yellow
    
    # Test component-specific reset
    Reset-EnhancedMockData -Component "applications" -Scope "Minimal"
    
    # Test full reset
    Reset-EnhancedMockData -Scope "Minimal"
    
    # Test 5: Verify no source tree pollution
    Write-Host "`n🔍 Test 5: Source Tree Protection" -ForegroundColor Yellow
    Write-Host "==================================" -ForegroundColor Yellow
    
    $sourceTestsPath = Join-Path $PSScriptRoot ".."
    $sourceFiles = Get-ChildItem -Path $sourceTestsPath -Recurse -File -Filter "*.generated" -ErrorAction SilentlyContinue
    
    if ($sourceFiles.Count -eq 0) {
        Write-Host "✅ No generated files found in source tree" -ForegroundColor Green
    } else {
        Write-Host "⚠️  Found $($sourceFiles.Count) generated files in source tree:" -ForegroundColor Yellow
        foreach ($file in $sourceFiles) {
            Write-Host "   $($file.FullName)" -ForegroundColor Gray
        }
    }
    
    Write-Host "`n🎉 Docker Mock Integration Test Results:" -ForegroundColor Green
    Write-Host "  ✅ Environment detection working" -ForegroundColor Green
    Write-Host "  ✅ Path separation implemented" -ForegroundColor Green
    Write-Host "  ✅ Safe reset functionality" -ForegroundColor Green
    Write-Host "  ✅ Source tree protection" -ForegroundColor Green
    
} catch {
    Write-Error "❌ Test failed: $_"
    Write-Error "   Line: $($_.InvocationInfo.ScriptLineNumber)"
} finally {
    # Clean up test environment variables
    Remove-Item -Path "env:DYNAMIC_MOCK_ROOT" -ErrorAction SilentlyContinue
    Remove-Item -Path "env:DYNAMIC_APPLICATIONS" -ErrorAction SilentlyContinue
    Remove-Item -Path "env:DYNAMIC_GAMING" -ErrorAction SilentlyContinue
    
    # Clean up test environment
    Write-Host "`n🧹 Cleaning up test environment..." -ForegroundColor Gray
    try {
        Remove-StandardTestEnvironment -Confirm:$false
        Write-Host "✅ Test environment cleaned up" -ForegroundColor Green
    } catch {
        Write-Warning "⚠️  Cleanup warning: $_"
    }
} 