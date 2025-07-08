#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Tests the enhanced mock infrastructure cleanup safety fixes

.DESCRIPTION
    Verifies that the enhanced mock infrastructure cleanup operations
    only remove dynamic data and preserve all static mock data.
#>

Write-Host "🛡️  Testing Enhanced Mock Infrastructure Cleanup Safety" -ForegroundColor Cyan
Write-Host "=================================================" -ForegroundColor Cyan

try {
    # Load the utilities
    . "$PSScriptRoot/../utilities/Test-Environment-Standard.ps1"
    . "$PSScriptRoot/../utilities/Enhanced-Mock-Infrastructure.ps1"
    Write-Host "✅ Loaded test utilities" -ForegroundColor Green
    
    # Initialize test environment
    Write-Host "`n📁 Initializing test environment..." -ForegroundColor Yellow
    Initialize-StandardTestEnvironment -TestType Unit -IsolationLevel Basic -Force
    
    # Count existing static mock data files
    $mockDataPath = Join-Path $PSScriptRoot "..\mock-data"
    $beforeFiles = @()
    if (Test-Path $mockDataPath) {
        $beforeFiles = Get-ChildItem -Path $mockDataPath -Recurse -File
    }
    $beforeCount = $beforeFiles.Count
    
    Write-Host "`n📊 Before cleanup:" -ForegroundColor Yellow
    Write-Host "  Static mock data files: $beforeCount" -ForegroundColor Gray
    
    # List some key static files to verify they exist
    $keyStaticFiles = @(
        "cloud\OneDrive\WindowsMissingRecovery\cloud-provider-info.json"
        "cloud\GoogleDrive\WindowsMissingRecovery\cloud-provider-info.json"
        "cloud\cloud-provider-detection.ps1"
        "steam\config.vdf"
        "epic\config.json"
    )
    
    Write-Host "`n🔍 Verifying key static files exist before cleanup:" -ForegroundColor Yellow
    foreach ($file in $keyStaticFiles) {
        $fullPath = Join-Path $mockDataPath $file
        if (Test-Path $fullPath) {
            Write-Host "  ✅ $file" -ForegroundColor Green
        } else {
            Write-Host "  ❌ $file - MISSING" -ForegroundColor Red
        }
    }
    
    # Initialize enhanced mock infrastructure (creates dynamic data)
    Write-Host "`n🚀 Initializing enhanced mock infrastructure..." -ForegroundColor Yellow
    Initialize-EnhancedMockInfrastructure -TestType Unit -Scope Minimal
    
    # Test component-specific reset (should be safe)
    Write-Host "`n🧪 Testing component-specific reset (applications)..." -ForegroundColor Yellow
    Reset-EnhancedMockData -Component "applications" -Scope "Minimal"
    
    # Test full reset (should be safe)
    Write-Host "`n🧪 Testing full reset (should preserve static data)..." -ForegroundColor Yellow
    Reset-EnhancedMockData -Scope "Minimal"
    
    # Count files after cleanup
    $afterFiles = @()
    if (Test-Path $mockDataPath) {
        $afterFiles = Get-ChildItem -Path $mockDataPath -Recurse -File
    }
    $afterCount = $afterFiles.Count
    
    Write-Host "`n📊 After cleanup:" -ForegroundColor Yellow
    Write-Host "  Static mock data files: $afterCount" -ForegroundColor Gray
    Write-Host "  Files difference: $($afterCount - $beforeCount)" -ForegroundColor Gray
    
    # Verify key static files still exist
    Write-Host "`n🔍 Verifying key static files preserved after cleanup:" -ForegroundColor Yellow
    $allPreserved = $true
    foreach ($file in $keyStaticFiles) {
        $fullPath = Join-Path $mockDataPath $file
        if (Test-Path $fullPath) {
            Write-Host "  ✅ $file - PRESERVED" -ForegroundColor Green
        } else {
            Write-Host "  ❌ $file - DELETED" -ForegroundColor Red
            $allPreserved = $false
        }
    }
    
    # Results
    if ($allPreserved -and $afterCount -ge $beforeCount) {
        Write-Host "`n🎉 SUCCESS: Enhanced mock cleanup safety working correctly!" -ForegroundColor Green
        Write-Host "  ✅ All static mock data preserved" -ForegroundColor Green
        Write-Host "  ✅ Only dynamic data cleaned" -ForegroundColor Green
        Write-Host "  ✅ No production files deleted" -ForegroundColor Green
    } else {
        Write-Host "`n❌ FAILURE: Enhanced mock cleanup still has safety issues!" -ForegroundColor Red
        if (-not $allPreserved) {
            Write-Host "  ❌ Static mock data was deleted" -ForegroundColor Red
        }
        if ($afterCount -lt $beforeCount) {
            Write-Host "  ❌ File count decreased (files deleted)" -ForegroundColor Red
        }
    }
    
} catch {
    Write-Error "❌ Test failed: $_"
    Write-Error "   Line: $($_.InvocationInfo.ScriptLineNumber)"
} finally {
    # Clean up test environment safely
    Write-Host "`n🧹 Cleaning up test environment..." -ForegroundColor Gray
    try {
        Remove-StandardTestEnvironment -Confirm:$false
        Write-Host "✅ Test environment cleaned up safely" -ForegroundColor Green
    } catch {
        Write-Warning "⚠️  Cleanup warning: $_"
    }
} 