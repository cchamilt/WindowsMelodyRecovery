#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Health Check for Test Runner Container

.DESCRIPTION
    This script performs health checks for the test runner environment.
#>

Write-Host "🏥 Performing health checks..." -ForegroundColor Cyan

$healthStatus = @{
    PowerShell = $false
    Pester = $false
    Docker = $false
    TestDirectories = $false
}

# Check PowerShell
try {
    $psVersion = $PSVersionTable.PSVersion
    Write-Host "✓ PowerShell $psVersion is available" -ForegroundColor Green
    $healthStatus.PowerShell = $true
} catch {
    Write-Host "✗ PowerShell check failed" -ForegroundColor Red
}

# Check Pester
try {
    $pesterVersion = (Get-Module Pester -ListAvailable | Select-Object -First 1).Version
    Write-Host "✓ Pester $pesterVersion is available" -ForegroundColor Green
    $healthStatus.Pester = $true
} catch {
    Write-Host "✗ Pester check failed" -ForegroundColor Red
}

# Check Docker CLI
try {
    $dockerVersion = docker --version 2>$null
    if ($dockerVersion) {
        Write-Host "✓ Docker CLI is available: $dockerVersion" -ForegroundColor Green
        $healthStatus.Docker = $true
    } else {
        Write-Host "✗ Docker CLI not available" -ForegroundColor Red
    }
} catch {
    Write-Host "✗ Docker CLI check failed" -ForegroundColor Red
}

# Check test directories
$requiredDirs = @("/tests/unit", "/tests/integration", "/test-results")
$allDirsExist = $true

foreach ($dir in $requiredDirs) {
    if (Test-Path $dir) {
        Write-Host "✓ Directory exists: $dir" -ForegroundColor Green
    } else {
        Write-Host "✗ Directory missing: $dir" -ForegroundColor Red
        $allDirsExist = $false
    }
}

$healthStatus.TestDirectories = $allDirsExist

# Overall health status
$overallHealth = $healthStatus.Values -notcontains $false

if ($overallHealth) {
    Write-Host "✅ All health checks passed!" -ForegroundColor Green
    exit 0
} else {
    Write-Host "❌ Some health checks failed" -ForegroundColor Red
    exit 1
} 