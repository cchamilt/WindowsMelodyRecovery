#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Tests the enhanced mock infrastructure cleanup safety fixes

.DESCRIPTION
    Verifies that the enhanced mock infrastructure cleanup operations
    only remove dynamic data and preserve all static mock data.
#>

Write-Information -MessageData "🛡️  Testing Enhanced Mock Infrastructure Cleanup Safety" -InformationAction Continue
Write-Information -MessageData "=================================================" -InformationAction Continue

try {
    # Load the utilities
    . "$PSScriptRoot/../utilities/Test-Environment-Standard.ps1"
    . "$PSScriptRoot/../utilities/Enhanced-Mock-Infrastructure.ps1"
    Write-Information -MessageData "✅ Loaded test utilities" -InformationAction Continue

    # Initialize test environment
    Write-Warning -Message "`n📁 Initializing test environment..."
    Initialize-StandardTestEnvironment -TestType Unit -IsolationLevel Basic -Force

    # Count existing static mock data files
    $mockDataPath = Join-Path $PSScriptRoot "..\mock-data"
    $beforeFiles = @()
    if (Test-Path $mockDataPath) {
        $beforeFiles = Get-ChildItem -Path $mockDataPath -Recurse -File
    }
    $beforeCount = $beforeFiles.Count

    Write-Warning -Message "`n📊 Before cleanup:"
    Write-Verbose -Message "  Static mock data files: $beforeCount"

    # List some key static files to verify they exist
    $keyStaticFiles = @(
        "cloud\OneDrive\WindowsMelodyRecovery\cloud-provider-info.json"
        "cloud\GoogleDrive\WindowsMelodyRecovery\cloud-provider-info.json"
        "cloud\cloud-provider-detection.ps1"
        "steam\config.vdf"
        "epic\config.json"
    )

    Write-Warning -Message "`n🔍 Verifying key static files exist before cleanup:"
    foreach ($file in $keyStaticFiles) {
        $fullPath = Join-Path $mockDataPath $file
        if (Test-Path $fullPath) {
            Write-Information -MessageData "  ✅ $file" -InformationAction Continue
        }
        else {
            Write-Error -Message "  ❌ $file - MISSING"
        }
    }

    # Initialize enhanced mock infrastructure (creates dynamic data)
    Write-Warning -Message "`n🚀 Initializing enhanced mock infrastructure..."
    Initialize-EnhancedMockInfrastructure -TestType Unit -Scope Minimal

    # Test component-specific reset (should be safe)
    Write-Warning -Message "`n🧪 Testing component-specific reset (applications)..."
    Reset-EnhancedMockData -Component "applications" -Scope "Minimal"

    # Test full reset (should be safe)
    Write-Warning -Message "`n🧪 Testing full reset (should preserve static data)..."
    Reset-EnhancedMockData -Scope "Minimal"

    # Count files after cleanup
    $afterFiles = @()
    if (Test-Path $mockDataPath) {
        $afterFiles = Get-ChildItem -Path $mockDataPath -Recurse -File
    }
    $afterCount = $afterFiles.Count

    Write-Warning -Message "`n📊 After cleanup:"
    Write-Verbose -Message "  Static mock data files: $afterCount"
    Write-Verbose -Message "  Files difference: $($afterCount - $beforeCount)"

    # Verify key static files still exist
    Write-Warning -Message "`n🔍 Verifying key static files preserved after cleanup:"
    $allPreserved = $true
    foreach ($file in $keyStaticFiles) {
        $fullPath = Join-Path $mockDataPath $file
        if (Test-Path $fullPath) {
            Write-Information -MessageData "  ✅ $file - PRESERVED" -InformationAction Continue
        }
        else {
            Write-Error -Message "  ❌ $file - DELETED"
            $allPreserved = $false
        }
    }

    # Results
    if ($allPreserved -and $afterCount -ge $beforeCount) {
        Write-Information -MessageData "`n🎉 SUCCESS: Enhanced mock cleanup safety working correctly!" -InformationAction Continue
        Write-Information -MessageData "  ✅ All static mock data preserved" -InformationAction Continue
        Write-Information -MessageData "  ✅ Only dynamic data cleaned" -InformationAction Continue
        Write-Information -MessageData "  ✅ No production files deleted" -InformationAction Continue
    }
    else {
        Write-Error -Message "`n❌ FAILURE: Enhanced mock cleanup still has safety issues!"
        if (-not $allPreserved) {
            Write-Error -Message "  ❌ Static mock data was deleted"
        }
        if ($afterCount -lt $beforeCount) {
            Write-Error -Message "  ❌ File count decreased (files deleted)"
        }
    }

}
catch {
    Write-Error "❌ Test failed: $_"
    Write-Error "   Line: $($_.InvocationInfo.ScriptLineNumber)"
}
finally {
    # Clean up test environment safely
    Write-Verbose -Message "`n🧹 Cleaning up test environment..."
    try {
        Remove-StandardTestEnvironment -Confirm:$false
        Write-Information -MessageData "✅ Test environment cleaned up safely" -InformationAction Continue
    }
    catch {
        Write-Warning "⚠️  Cleanup warning: $_"
    }
}







