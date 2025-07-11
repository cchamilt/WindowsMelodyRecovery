#!/usr/bin/env pwsh
<#
.SYNOPSIS
Test wrapper for restoring templates from test directories.

.DESCRIPTION
This script provides a test environment for template-based restores without affecting
the live system. It uses backups from test-backups and simulates restore to test-restore.
By default, this runs in WhatIf mode to prevent actual system changes.

.PARAMETER TemplatePath
Path to the template file to test restore.

.PARAMETER BackupName
Name of the backup directory in test-backups (e.g., "word", "excel").

.PARAMETER Force
Actually perform the restore operations instead of just simulating them.
WARNING: This will make actual changes to the system!

.EXAMPLE
.\test-template-restore.ps1 -TemplatePath "word.yaml" -BackupName "word"

.EXAMPLE
.\test-template-restore.ps1 -TemplatePath "Templates\System\excel.yaml" -BackupName "excel" -Force

.NOTES
This uses the test-backups and test-restore directories for safe testing.
By default, runs in WhatIf mode to prevent system changes.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$TemplatePath,

    [Parameter(Mandatory=$true)]
    [string]$BackupName,

    [Parameter(Mandatory=$false)]
    [switch]$Force
)

# Ensure we're in the project root
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Push-Location $scriptRoot

# Define consistent test directory structure
$testDirectories = @{
    BackupsRoot = Join-Path $scriptRoot "test-backups"
    RestoreRoot = Join-Path $scriptRoot "test-restore"
}

$testPaths = @{
    MachineBackup = Join-Path $testDirectories.BackupsRoot "TEST-MACHINE"
    RestoreTarget = Join-Path $testDirectories.RestoreRoot "restored"
}

function Initialize-TestDirectories {
    foreach ($dir in $testDirectories.Values) {
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
    }

    if (-not (Test-Path $testPaths.RestoreTarget)) {
        New-Item -ItemType Directory -Path $testPaths.RestoreTarget -Force | Out-Null
    }
}

function Get-TestConfig {
    return @{
        BackupRoot = $testDirectories.BackupsRoot
        MachineName = "TEST-MACHINE"
        RestoreRoot = $testDirectories.RestoreRoot
    }
}

function Show-DirectoryContents {
    param(
        [string]$Path,
        [string]$BasePathForDisplay
    )

    if (Test-Path $Path) {
        Get-ChildItem $Path -Recurse | ForEach-Object {
            $relativePath = $_.FullName.Replace($BasePathForDisplay, "").TrimStart('\', '/')
            if ($_.PSIsContainer) {
                Write-Information -MessageData "📁 $relativePath" -InformationAction Continue
            } else {
                $size = if ($_.Length -lt 1KB) { "$($_.Length) B" } elseif ($_.Length -lt 1MB) { "{0:N1} KB" -f ($_.Length / 1KB) } else { "{0:N1} MB" -f ($_.Length / 1MB) }
                Write-Verbose -Message "📄 $relativePath ($size)"
            }
        }
    }
}

try {
    # Initialize test directories
    Initialize-TestDirectories

    # Import the module
    Import-Module .\WindowsMelodyRecovery.psm1 -Force -WarningAction SilentlyContinue

    # Get current config and set test config
    $originalConfig = Get-WindowsMelodyRecovery
    $testConfig = Get-TestConfig
    $global:WindowsMelodyRecovery = [PSCustomObject]$testConfig

    Write-Information -MessageData "=== TEMPLATE RESTORE TEST ===" -InformationAction Continue
    Write-Warning -Message "Template: $TemplatePath"
    Write-Warning -Message "Backup Name: $BackupName"

    # Determine source directory - templates create their own subdirectories
    $sourceDir = $testPaths.MachineBackup
    $restoreStateDir = $testPaths.RestoreTarget

    Write-Warning -Message "Source Directory: $sourceDir"
    Write-Warning -Message "Restore State Directory: $restoreStateDir"
    Write-Information -MessageData "" -InformationAction Continue

    # Validate source directory exists
    $componentSourceDir = Join-Path $sourceDir $BackupName
    if (-not (Test-Path $componentSourceDir)) {
        throw "Backup directory not found: $componentSourceDir. Run test-template-backup.ps1 first."
    }

    # Show what's available to restore
    Write-Information -MessageData "=== AVAILABLE BACKUP DATA ===" -InformationAction Continue
    Show-DirectoryContents -Path $componentSourceDir -BasePathForDisplay $componentSourceDir
    Write-Information -MessageData "" -InformationAction Continue

    # Copy source data to restore location with correct structure
    Write-Information -MessageData "Copying backup data to restore location..." -InformationAction Continue

    # Copy the component-specific directory from source to restore location
    $componentRestoreDir = Join-Path $restoreStateDir $BackupName
    if (Test-Path $componentRestoreDir) {
        Remove-Item $componentRestoreDir -Recurse -Force
    }
    Copy-Item $componentSourceDir $componentRestoreDir -Recurse -Force

    # Resolve template path
    $templateFullPath = if (Test-Path $TemplatePath) {
        $TemplatePath
    } else {
        Join-Path $scriptRoot "Templates\System\$TemplatePath"
    }

    if (-not (Test-Path $templateFullPath)) {
        throw "Template file not found: $templateFullPath"
    }

    Write-Information -MessageData "Testing template restore..." -InformationAction Continue

    if (-not $Force) {
        Write-Warning -Message "*** RUNNING IN SAFE WHATIF MODE - NO SYSTEM CHANGES WILL BE MADE ***" -BackgroundColor DarkRed
        Write-Warning -Message "*** Use -Force parameter to make actual changes (NOT RECOMMENDED for testing) ***" -BackgroundColor DarkRed
        Write-Information -MessageData "" -InformationAction Continue
    }

    # Dot-source the InvokeWmrTemplate module
    . (Join-Path $scriptRoot "Private\Core\InvokeWmrTemplate.ps1")

    # Perform the restore operation using the copied data
    if ($Force) {
        Invoke-WmrTemplate -TemplatePath $templateFullPath -Operation "Restore" -StateFilesDirectory $restoreStateDir
    } else {
        Invoke-WmrTemplate -TemplatePath $templateFullPath -Operation "Restore" -StateFilesDirectory $restoreStateDir -WhatIf
    }
    Write-Information -MessageData "✓ Template restore completed successfully" -InformationAction Continue

    # Show restore results
    Write-Information -MessageData "`n=== RESTORE SIMULATION RESULTS ===" -InformationAction Continue
    if ($Force) {
        Write-Error -Message "Note: Actual restore operations were performed on the live system."
    } else {
        Write-Information -MessageData "Note: This was a safe simulation. No actual system changes were made." -InformationAction Continue
    }
    Write-Information -MessageData "Restore data processed from: $restoreStateDir" -InformationAction Continue

    Write-Information -MessageData "`nTest restore completed! Check the console output above for details." -InformationAction Continue

} catch {
    Write-Error -Message "Test restore failed: $($_.Exception.Message)"
    Write-Information -MessageData $_.ScriptStackTrace  -InformationAction Continue-ForegroundColor DarkRed
    exit 1
} finally {
    # Restore original config
    if ($originalConfig) {
        $global:WindowsMelodyRecovery = $originalConfig
    }
    Pop-Location
}






