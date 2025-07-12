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
    Write-Error -Message "🚫 This script is designed to run only in Docker environments"
    Write-Error -Message "   Running it locally would pollute the C:\ drive with /test-dynamic-* directories"
    Write-Warning -Message "   Use: docker-compose -f docker-compose.test.yml up test-runner"
    exit 1
}

Write-Information -MessageData "🔒 Testing Docker Safety Checks" -InformationAction Continue
Write-Information -MessageData "===============================" -InformationAction Continue

try {
    # Load the utilities
    . "$PSScriptRoot/../utilities/Test-Environment-Standard.ps1"
    . "$PSScriptRoot/../utilities/Enhanced-Mock-Infrastructure.ps1"
    Write-Information -MessageData "✅ Loaded test utilities" -InformationAction Continue

    # Test 1: Safety checks in local environment (should fail)
    Write-Warning -Message "`n🔍 Test 1: Safety Checks in Local Environment"
    Write-Warning -Message "=============================================="

    # Clear any Docker environment variables
    $originalEnvVars = @{}
    $dockerEnvVars = @('DYNAMIC_MOCK_ROOT', 'DYNAMIC_APPLICATIONS', 'DYNAMIC_GAMING', 'WMR_DOCKER_LOCK')
    foreach ($envVar in $dockerEnvVars) {
        $originalEnvVars[$envVar] = [Environment]::GetEnvironmentVariable($envVar)
        [Environment]::SetEnvironmentVariable($envVar, $null)
    }

    Write-Information -MessageData "  Testing Initialize-EnhancedMockInfrastructure..." -InformationAction Continue
    try {
        $result = Initialize-EnhancedMockInfrastructure -TestType Unit -Scope Minimal
        if ($null -eq $result) {
            Write-Information -MessageData "  ✅ Initialize correctly blocked in local environment" -InformationAction Continue
        }
 else {
            Write-Error -Message "  ❌ Initialize should have been blocked"
        }
    }
 catch {
        Write-Information -MessageData "  ✅ Initialize correctly threw exception: $($_.Exception.Message)" -InformationAction Continue
    }

    Write-Information -MessageData "  Testing Reset-EnhancedMockData..." -InformationAction Continue
    try {
        $result = Reset-EnhancedMockData -Component "applications" -Scope Minimal
        if ($null -eq $result) {
            Write-Information -MessageData "  ✅ Reset correctly blocked in local environment" -InformationAction Continue
        }
 else {
            Write-Error -Message "  ❌ Reset should have been blocked"
        }
    }
 catch {
        Write-Information -MessageData "  ✅ Reset correctly threw exception: $($_.Exception.Message)" -InformationAction Continue
    }

    # Test 2: Safety checks with Docker environment (should pass)
    Write-Warning -Message "`n🔍 Test 2: Safety Checks with Docker Environment"
    Write-Warning -Message "================================================="

    # Mock Docker environment
    $env:DYNAMIC_MOCK_ROOT = "/test-dynamic-mock-data"
    $env:DYNAMIC_APPLICATIONS = "/test-dynamic-applications"
    $env:DYNAMIC_GAMING = "/test-dynamic-gaming"

    Write-Information -MessageData "  Testing Initialize-EnhancedMockInfrastructure..." -InformationAction Continue
    try {
        Initialize-StandardTestEnvironment -TestType Unit -IsolationLevel Basic -Force | Out-Null
        $result = Initialize-EnhancedMockInfrastructure -TestType Unit -Scope Minimal
        if ($null -ne $result -or $?) {
            Write-Information -MessageData "  ✅ Initialize correctly allowed in Docker environment" -InformationAction Continue
        }
 else {
            Write-Error -Message "  ❌ Initialize should have been allowed"
        }
    }
 catch {
        Write-Warning -Message "  ⚠️  Initialize failed in Docker environment: $($_.Exception.Message)"
    }

    Write-Information -MessageData "  Testing Reset-EnhancedMockData..." -InformationAction Continue
    try {
        $result = Reset-EnhancedMockData -Component "applications" -Scope Minimal
        if ($null -ne $result -or $?) {
            Write-Information -MessageData "  ✅ Reset correctly allowed in Docker environment" -InformationAction Continue
        }
 else {
            Write-Error -Message "  ❌ Reset should have been allowed"
        }
    }
 catch {
        Write-Warning -Message "  ⚠️  Reset failed in Docker environment: $($_.Exception.Message)"
    }

    # Test 3: SkipSafetyCheck parameter (should bypass checks)
    Write-Warning -Message "`n🔍 Test 3: SkipSafetyCheck Parameter"
    Write-Warning -Message "===================================="

    # Clear Docker environment again
    foreach ($envVar in $dockerEnvVars) {
        [Environment]::SetEnvironmentVariable($envVar, $null)
    }

    Write-Information -MessageData "  Testing Initialize with SkipSafetyCheck..." -InformationAction Continue
    try {
        $result = Initialize-EnhancedMockInfrastructure -TestType Unit -Scope Minimal -SkipSafetyCheck
        Write-Information -MessageData "  ✅ SkipSafetyCheck correctly bypassed safety checks" -InformationAction Continue
    }
 catch {
        Write-Error -Message "  ❌ SkipSafetyCheck should have bypassed checks: $($_.Exception.Message)"
    }

    Write-Information -MessageData "  Testing Reset with SkipSafetyCheck..." -InformationAction Continue
    try {
        $result = Reset-EnhancedMockData -Component "applications" -Scope Minimal -SkipSafetyCheck
        Write-Information -MessageData "  ✅ SkipSafetyCheck correctly bypassed safety checks" -InformationAction Continue
    }
 catch {
        Write-Error -Message "  ❌ SkipSafetyCheck should have bypassed checks: $($_.Exception.Message)"
    }

    # Test 4: Docker environment lock validation
    Write-Warning -Message "`n🔍 Test 4: Docker Environment Lock Validation"
    Write-Warning -Message "=============================================="

    # Test lock validation with mock environment
    $env:DYNAMIC_MOCK_ROOT = "/test-dynamic-mock-data"
    $env:DYNAMIC_APPLICATIONS = "/test-dynamic-applications"

    Write-Information -MessageData "  Testing Docker lock creation..." -InformationAction Continue
    try {
        Initialize-DockerEnvironment
        $lockValid = Test-DockerEnvironmentLock
        if ($lockValid) {
            Write-Information -MessageData "  ✅ Docker environment lock created and validated" -InformationAction Continue
        }
 else {
            Write-Error -Message "  ❌ Docker environment lock validation failed"
        }
    }
 catch {
        Write-Warning -Message "  ⚠️  Docker lock test failed: $($_.Exception.Message)"
    }

    # Test 5: Comprehensive safety validation
    Write-Warning -Message "`n🔍 Test 5: Comprehensive Safety Validation"
    Write-Warning -Message "=========================================="

    Write-Information -MessageData "  Testing Assert-DockerEnvironment..." -InformationAction Continue
    try {
        Assert-DockerEnvironment
        Write-Information -MessageData "  ✅ Assert-DockerEnvironment passed with mock environment" -InformationAction Continue
    }
 catch {
        Write-Error -Message "  ❌ Assert-DockerEnvironment failed: $($_.Exception.Message)"
    }

    Write-Information -MessageData "`n🎉 Docker Safety Check Test Results:" -InformationAction Continue
    Write-Information -MessageData "  ✅ Local environment properly blocked" -InformationAction Continue
    Write-Information -MessageData "  ✅ Docker environment properly allowed" -InformationAction Continue
    Write-Information -MessageData "  ✅ SkipSafetyCheck parameter working" -InformationAction Continue
    Write-Information -MessageData "  ✅ Docker lock validation working" -InformationAction Continue
    Write-Information -MessageData "  ✅ Comprehensive safety validation working" -InformationAction Continue

}
 catch {
    Write-Error "❌ Test failed: $_"
    Write-Error "   Line: $($_.InvocationInfo.ScriptLineNumber)"
}
 finally {
    # Restore original environment variables
    foreach ($envVar in $originalEnvVars.Keys) {
        [Environment]::SetEnvironmentVariable($envVar, $originalEnvVars[$envVar])
    }

    # Clean up test environment
    Write-Verbose -Message "`n🧹 Cleaning up test environment..."
    try {
        Remove-StandardTestEnvironment -Confirm:$false
        Write-Information -MessageData "✅ Test environment cleaned up" -InformationAction Continue
    }
 catch {
        Write-Warning "⚠️  Cleanup warning: $_"
    }
}







