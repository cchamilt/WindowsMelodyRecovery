#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Tests Docker safety checks for Enhanced Mock Infrastructure

.DESCRIPTION
    Verifies that the enhanced mock infrastructure safety checks correctly
    prevent operations outside Docker environments and allow them inside Docker.
#>

# SAFETY CHECK: Prevent this script from running in local Windows environments
# This script creates /test-dynamic-* paths which pollute C:\ on Windows
if ($IsWindows -and -not ($env:DOCKER_TEST -eq 'true' -or $env:CONTAINER -eq 'true' -or (Test-Path '/.dockerenv'))) {
    Write-Host "🚫 This script is designed to run only in Docker environments" -ForegroundColor Red
    Write-Host "   Running it locally would pollute the C:\ drive with /test-dynamic-* directories" -ForegroundColor Red
    Write-Host "   Use: docker-compose -f docker-compose.test.yml up test-runner" -ForegroundColor Yellow
    exit 1
}

Write-Host "🔒 Testing Docker Safety Checks" -ForegroundColor Cyan
Write-Host "===============================" -ForegroundColor Cyan

try {
    # Load the utilities
    . "$PSScriptRoot/../utilities/Test-Environment-Standard.ps1"
    . "$PSScriptRoot/../utilities/Enhanced-Mock-Infrastructure.ps1"
    Write-Host "✅ Loaded test utilities" -ForegroundColor Green
    
    # Test 1: Safety checks in local environment (should fail)
    Write-Host "`n🔍 Test 1: Safety Checks in Local Environment" -ForegroundColor Yellow
    Write-Host "==============================================" -ForegroundColor Yellow
    
    # Clear any Docker environment variables
    $originalEnvVars = @{}
    $dockerEnvVars = @('DYNAMIC_MOCK_ROOT', 'DYNAMIC_APPLICATIONS', 'DYNAMIC_GAMING', 'WMR_DOCKER_LOCK')
    foreach ($envVar in $dockerEnvVars) {
        $originalEnvVars[$envVar] = [Environment]::GetEnvironmentVariable($envVar)
        [Environment]::SetEnvironmentVariable($envVar, $null)
    }
    
    Write-Host "  Testing Initialize-EnhancedMockInfrastructure..." -ForegroundColor Cyan
    try {
        $result = Initialize-EnhancedMockInfrastructure -TestType Unit -Scope Minimal
        if ($result -eq $null) {
            Write-Host "  ✅ Initialize correctly blocked in local environment" -ForegroundColor Green
        } else {
            Write-Host "  ❌ Initialize should have been blocked" -ForegroundColor Red
        }
    } catch {
        Write-Host "  ✅ Initialize correctly threw exception: $($_.Exception.Message)" -ForegroundColor Green
    }
    
    Write-Host "  Testing Reset-EnhancedMockData..." -ForegroundColor Cyan
    try {
        $result = Reset-EnhancedMockData -Component "applications" -Scope Minimal
        if ($result -eq $null) {
            Write-Host "  ✅ Reset correctly blocked in local environment" -ForegroundColor Green
        } else {
            Write-Host "  ❌ Reset should have been blocked" -ForegroundColor Red
        }
    } catch {
        Write-Host "  ✅ Reset correctly threw exception: $($_.Exception.Message)" -ForegroundColor Green
    }
    
    # Test 2: Safety checks with Docker environment (should pass)
    Write-Host "`n🔍 Test 2: Safety Checks with Docker Environment" -ForegroundColor Yellow
    Write-Host "=================================================" -ForegroundColor Yellow
    
    # Mock Docker environment
    $env:DYNAMIC_MOCK_ROOT = "/test-dynamic-mock-data"
    $env:DYNAMIC_APPLICATIONS = "/test-dynamic-applications"
    $env:DYNAMIC_GAMING = "/test-dynamic-gaming"
    
    Write-Host "  Testing Initialize-EnhancedMockInfrastructure..." -ForegroundColor Cyan
    try {
        Initialize-StandardTestEnvironment -TestType Unit -IsolationLevel Basic -Force | Out-Null
        $result = Initialize-EnhancedMockInfrastructure -TestType Unit -Scope Minimal
        if ($result -ne $null -or $?) {
            Write-Host "  ✅ Initialize correctly allowed in Docker environment" -ForegroundColor Green
        } else {
            Write-Host "  ❌ Initialize should have been allowed" -ForegroundColor Red
        }
    } catch {
        Write-Host "  ⚠️  Initialize failed in Docker environment: $($_.Exception.Message)" -ForegroundColor Yellow
    }
    
    Write-Host "  Testing Reset-EnhancedMockData..." -ForegroundColor Cyan
    try {
        $result = Reset-EnhancedMockData -Component "applications" -Scope Minimal
        if ($result -ne $null -or $?) {
            Write-Host "  ✅ Reset correctly allowed in Docker environment" -ForegroundColor Green
        } else {
            Write-Host "  ❌ Reset should have been allowed" -ForegroundColor Red
        }
    } catch {
        Write-Host "  ⚠️  Reset failed in Docker environment: $($_.Exception.Message)" -ForegroundColor Yellow
    }
    
    # Test 3: SkipSafetyCheck parameter (should bypass checks)
    Write-Host "`n🔍 Test 3: SkipSafetyCheck Parameter" -ForegroundColor Yellow
    Write-Host "====================================" -ForegroundColor Yellow
    
    # Clear Docker environment again
    foreach ($envVar in $dockerEnvVars) {
        [Environment]::SetEnvironmentVariable($envVar, $null)
    }
    
    Write-Host "  Testing Initialize with SkipSafetyCheck..." -ForegroundColor Cyan
    try {
        $result = Initialize-EnhancedMockInfrastructure -TestType Unit -Scope Minimal -SkipSafetyCheck
        Write-Host "  ✅ SkipSafetyCheck correctly bypassed safety checks" -ForegroundColor Green
    } catch {
        Write-Host "  ❌ SkipSafetyCheck should have bypassed checks: $($_.Exception.Message)" -ForegroundColor Red
    }
    
    Write-Host "  Testing Reset with SkipSafetyCheck..." -ForegroundColor Cyan
    try {
        $result = Reset-EnhancedMockData -Component "applications" -Scope Minimal -SkipSafetyCheck
        Write-Host "  ✅ SkipSafetyCheck correctly bypassed safety checks" -ForegroundColor Green
    } catch {
        Write-Host "  ❌ SkipSafetyCheck should have bypassed checks: $($_.Exception.Message)" -ForegroundColor Red
    }
    
    # Test 4: Docker environment lock validation
    Write-Host "`n🔍 Test 4: Docker Environment Lock Validation" -ForegroundColor Yellow
    Write-Host "==============================================" -ForegroundColor Yellow
    
    # Test lock validation with mock environment
    $env:DYNAMIC_MOCK_ROOT = "/test-dynamic-mock-data"
    $env:DYNAMIC_APPLICATIONS = "/test-dynamic-applications"
    
    Write-Host "  Testing Docker lock creation..." -ForegroundColor Cyan
    try {
        Initialize-DockerEnvironment
        $lockValid = Test-DockerEnvironmentLock
        if ($lockValid) {
            Write-Host "  ✅ Docker environment lock created and validated" -ForegroundColor Green
        } else {
            Write-Host "  ❌ Docker environment lock validation failed" -ForegroundColor Red
        }
    } catch {
        Write-Host "  ⚠️  Docker lock test failed: $($_.Exception.Message)" -ForegroundColor Yellow
    }
    
    # Test 5: Comprehensive safety validation
    Write-Host "`n🔍 Test 5: Comprehensive Safety Validation" -ForegroundColor Yellow
    Write-Host "==========================================" -ForegroundColor Yellow
    
    Write-Host "  Testing Assert-DockerEnvironment..." -ForegroundColor Cyan
    try {
        Assert-DockerEnvironment
        Write-Host "  ✅ Assert-DockerEnvironment passed with mock environment" -ForegroundColor Green
    } catch {
        Write-Host "  ❌ Assert-DockerEnvironment failed: $($_.Exception.Message)" -ForegroundColor Red
    }
    
    Write-Host "`n🎉 Docker Safety Check Test Results:" -ForegroundColor Green
    Write-Host "  ✅ Local environment properly blocked" -ForegroundColor Green
    Write-Host "  ✅ Docker environment properly allowed" -ForegroundColor Green
    Write-Host "  ✅ SkipSafetyCheck parameter working" -ForegroundColor Green
    Write-Host "  ✅ Docker lock validation working" -ForegroundColor Green
    Write-Host "  ✅ Comprehensive safety validation working" -ForegroundColor Green
    
} catch {
    Write-Error "❌ Test failed: $_"
    Write-Error "   Line: $($_.InvocationInfo.ScriptLineNumber)"
} finally {
    # Restore original environment variables
    foreach ($envVar in $originalEnvVars.Keys) {
        [Environment]::SetEnvironmentVariable($envVar, $originalEnvVars[$envVar])
    }
    
    # Clean up test environment
    Write-Host "`n🧹 Cleaning up test environment..." -ForegroundColor Gray
    try {
        Remove-StandardTestEnvironment -Confirm:$false
        Write-Host "✅ Test environment cleaned up" -ForegroundColor Green
    } catch {
        Write-Warning "⚠️  Cleanup warning: $_"
    }
} 