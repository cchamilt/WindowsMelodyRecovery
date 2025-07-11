#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Reset Test Environment for Windows Melody Recovery Unit Tests

.DESCRIPTION
    Simple script to clean and recreate test-restore, test-backup, and Temp directories.
    Run this before executing unit tests to ensure a clean environment.

.PARAMETER Force
    Force recreation even if directories exist.

.EXAMPLE
    .\reset-test-environment.ps1
    .\reset-test-environment.ps1 -Force
#>

[CmdletBinding()]
param(
    [switch]$Force
)

# Set execution policy for current process to allow unsigned scripts
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

# Import the test environment utilities
. (Join-Path $PSScriptRoot "..\utilities\Test-Environment-Standard.ps1")

Write-Host "🧹 Resetting test environment for unit tests..." -ForegroundColor Cyan

# Initialize clean test environment
$testPaths = Initialize-StandardTestEnvironment -TestType "All" -Force:$Force

Write-Host ""
Write-Host "📁 Test directories ready:" -ForegroundColor Green
Write-Host "  • Test Restore: $($testPaths.TestRestore)" -ForegroundColor Gray
Write-Host "  • Test Backup: $($testPaths.TestBackup)" -ForegroundColor Gray
Write-Host "  • Temp: $($testPaths.Temp)" -ForegroundColor Gray
Write-Host "  • Mock Data: $($testPaths.MockData)" -ForegroundColor Gray

Write-Host ""
Write-Host "✅ Test environment reset complete! Ready for unit tests." -ForegroundColor Green
