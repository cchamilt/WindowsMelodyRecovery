#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Resets the test environment by forcefully removing and recreating test directories.
.DESCRIPTION
    This script provides a simple way to ensure a clean slate for testing. It uses
    the unified test environment system to initialize an environment with the -Force
    switch, which deletes any existing test directories, and then immediately
    removes the newly created environment, leaving the Temp directory clean.
.PARAMETER SuiteName
    The test suite context for which to reset the environment. This ensures the
    correct temporary directory naming convention is used for cleanup.
.EXAMPLE
    .\reset-test-environment.ps1 -SuiteName 'FileOps'
#>

[CmdletBinding()]
param(
    [ValidateSet('Unit', 'FileOps', 'Integration', 'E2E', 'Windows', 'All')]
    [string]$SuiteName = 'All'
)

# Set execution policy for current process to allow unsigned scripts
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

# Import the unified test environment utilities
. (Join-Path $PSScriptRoot "..\utilities\Test-Environment.ps1")

Write-Information -MessageData "🧹 Resetting test environment for suite: $SuiteName..." -InformationAction Continue

# Initialize a clean test environment with -Force, which handles cleanup.
# A SessionId is used to ensure we only clean up a specific, temporary folder.
$sessionId = "reset-$(New-Guid -AsPlainText | Select-Object -First 8)"
$testEnvironment = Initialize-WmrTestEnvironment -SuiteName $SuiteName -Force -SessionId $sessionId

# The goal is just to clean, so we remove the environment immediately after creating it.
if ($testEnvironment) {
    Write-Information -MessageData "✅ Test environment directories created successfully at $($testEnvironment.TestRoot)" -InformationAction Continue
    Remove-WmrTestEnvironment
    Write-Information -MessageData "✅ Test environment reset complete!" -InformationAction Continue
}
else {
    Write-Error "Failed to initialize and reset the test environment."
}








