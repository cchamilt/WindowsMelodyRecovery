#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Health Check for Test Runner Container

.DESCRIPTION
    This script performs health checks for the test runner environment.
#>

Write-Information -MessageData "🏥 Performing health checks..." -InformationAction Continue

$healthStatus = @{
    PowerShell = $false
    Pester = $false
    Docker = $false
    TestDirectories = $false
}

# Check PowerShell
try {
    $psVersion = $PSVersionTable.PSVersion
    Write-Information -MessageData "✓ PowerShell $psVersion is available" -InformationAction Continue
    $healthStatus.PowerShell = $true
}
catch {
    Write-Error -Message "✗ PowerShell check failed"
}

# Check Pester
try {
    $pesterVersion = (Get-Module Pester -ListAvailable | Select-Object -First 1).Version
    Write-Information -MessageData "✓ Pester $pesterVersion is available" -InformationAction Continue
    $healthStatus.Pester = $true
}
catch {
    Write-Error -Message "✗ Pester check failed"
}

# Check Docker CLI
try {
    $dockerVersion = docker --version 2>$null
    if ($dockerVersion) {
        Write-Information -MessageData "✓ Docker CLI is available: $dockerVersion" -InformationAction Continue
        $healthStatus.Docker = $true
    }
    else {
        Write-Error -Message "✗ Docker CLI not available"
    }
}
catch {
    Write-Error -Message "✗ Docker CLI check failed"
}

# Check test directories
$requiredDirs = @("/tests/unit", "/tests/integration", "/test-results")
$allDirsExist = $true

foreach ($dir in $requiredDirs) {
    if (Test-Path $dir) {
        Write-Information -MessageData "✓ Directory exists: $dir" -InformationAction Continue
    }
    else {
        Write-Error -Message "✗ Directory missing: $dir"
        $allDirsExist = $false
    }
}

$healthStatus.TestDirectories = $allDirsExist

# Overall health status
$overallHealth = $healthStatus.Values -notcontains $false

if ($overallHealth) {
    Write-Information -MessageData "✅ All health checks passed!" -InformationAction Continue
    exit 0
}
else {
    Write-Error -Message "❌ Some health checks failed"
    exit 1
}







