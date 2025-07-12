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

Write-Information -MessageData "🧹 Resetting test environment for unit tests..." -InformationAction Continue

# Initialize clean test environment
$testPaths = Initialize-StandardTestEnvironment -TestType "All" -Force:$Force

Write-Information -MessageData "" -InformationAction Continue
Write-Information -MessageData "📁 Test directories ready:" -InformationAction Continue
Write-Verbose -Message "  • Test Restore: $($testPaths.TestRestore)"
Write-Verbose -Message "  • Test Backup: $($testPaths.TestBackup)"
Write-Verbose -Message "  • Temp: $($testPaths.Temp)"
Write-Verbose -Message "  • Mock Data: $($testPaths.MockData)"

Write-Information -MessageData "" -InformationAction Continue
Write-Information -MessageData "✅ Test environment reset complete! Ready for unit tests." -InformationAction Continue








