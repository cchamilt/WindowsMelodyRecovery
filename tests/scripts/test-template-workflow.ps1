#!/usr/bin/env pwsh
<#
.SYNOPSIS
Unified test manager for template backup and restore workflows.

.DESCRIPTION
This script provides a unified interface for testing template-based backup and restore
operations with consistent path structures. It manages test directories and provides
clean workflows for testing without affecting the development environment.

.PARAMETER Operation
The operation to perform: "backup", "restore", "clean", "list", or "workflow"

.PARAMETER TemplatePath
Path to the template file to test, or "ALL" to test all templates.

.PARAMETER BackupName
Name of the backup component (e.g., "word", "excel"). Required for restore operations.

.PARAMETER UseTestData
For restore operations, use prepared test data instead of actual backup data.

.PARAMETER Force
Actually perform restore operations instead of just simulating them.
WARNING: This will make actual changes to the system!

.EXAMPLE
.\test-template-workflow.ps1 -Operation backup -TemplatePath "word.yaml"
Backs up Word settings to test directory.

.EXAMPLE
.\test-template-workflow.ps1 -Operation restore -TemplatePath "word.yaml" -BackupName "word"
Restores Word settings from backup test data.

.EXAMPLE
.\test-template-workflow.ps1 -Operation restore -TemplatePath "word.yaml" -BackupName "word" -Force
Restores Word settings from backup test data and makes actual changes.

.EXAMPLE
.\test-template-workflow.ps1 -Operation workflow -TemplatePath "word.yaml"
Performs complete backup->restore workflow test.

.EXAMPLE
.\test-template-workflow.ps1 -Operation clean
Cleans all test directories.

.EXAMPLE
.\test-template-workflow.ps1 -Operation list
Lists available test backups.

.NOTES
This manages test-backups and test-restore directories with consistent structures.
By default, restore operations run in WhatIf mode to prevent system changes.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("backup", "restore", "clean", "list", "workflow")]
    [string]$Operation,

    [Parameter(Mandatory=$false)]
    [string]$TemplatePath,

    [Parameter(Mandatory=$false)]
    [string]$BackupName,

    [Parameter(Mandatory=$false)]
    [switch]$UseTestData,

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
    TestDataRoot = Join-Path $scriptRoot "test-template-state"
}

$testPaths = @{
    MachineBackup = Join-Path $testDirectories.BackupsRoot "TEST-MACHINE"
    RestoreTarget = Join-Path $testDirectories.RestoreRoot "restored"
    TestData = $testDirectories.TestDataRoot
}

function Initialize-TestDirectory {
    foreach ($dir in $testDirectories.Values) {
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
    }

    if (-not (Test-Path $testPaths.MachineBackup)) {
        New-Item -ItemType Directory -Path $testPaths.MachineBackup -Force | Out-Null
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

function Invoke-TestBackup {
    param(
        [string]$TemplatePath
    )

    Write-Information -MessageData "=== TEMPLATE BACKUP TEST ===" -InformationAction Continue
    Write-Warning -Message "Template: $TemplatePath"
    Write-Warning -Message "Test Backup Directory: $($testDirectories.BackupsRoot)"
    Write-Information -MessageData "" -InformationAction Continue

    try {
        # Import module and set test config
        Import-Module .\WindowsMelodyRecovery.psm1 -Force -WarningAction SilentlyContinue
        $originalConfig = Get-WindowsMelodyRecovery
        $testConfig = Get-TestConfig
        $global:WindowsMelodyRecovery = [PSCustomObject]$testConfig

        if ($TemplatePath -eq "ALL") {
            # Test all templates
            Write-Information -MessageData "Testing all available templates..." -InformationAction Continue
            $templatesPath = Join-Path $scriptRoot "Templates\System"
            $templateFiles = Get-ChildItem -Path $templatesPath -Filter "*.yaml" -ErrorAction SilentlyContinue

            $successCount = 0
            $failCount = 0

            foreach ($templateFile in $templateFiles) {
                Write-Information -MessageData "`n--- Testing: $($templateFile.Name) ---" -InformationAction Continue
                try {
                    . (Join-Path $scriptRoot "Private\Core\InvokeWmrTemplate.ps1")

                    $componentBackupDir = Join-Path $testPaths.MachineBackup $templateFile.BaseName
                    if (-not (Test-Path $componentBackupDir)) {
                        New-Item -ItemType Directory -Path $componentBackupDir -Force | Out-Null
                    }

                    Invoke-WmrTemplate -TemplatePath $templateFile.FullName -Operation "Backup" -StateFilesDirectory $componentBackupDir
                    Write-Information -MessageData "✓ $($templateFile.Name) backup completed successfully" -InformationAction Continue
                    $successCount++
                } catch {
                    Write-Error -Message "✗ $($templateFile.Name) backup failed: $($_.Exception.Message)"
                    $failCount++
                }
            }

            Write-Information -MessageData "`n=== BACKUP SUMMARY ===" -InformationAction Continue
            Write-Information -MessageData "Successful: $successCount" -InformationAction Continue
            Write-Error -Message "Failed: $failCount"
            Write-Warning -Message "Total: $($successCount + $failCount)"

        } else {
            # Test single template
            $templateFullPath = if (Test-Path $TemplatePath) {
                $TemplatePath
            } else {
                Join-Path $scriptRoot "Templates\System\$TemplatePath"
            }

            if (-not (Test-Path $templateFullPath)) {
                throw "Template file not found: $templateFullPath"
            }

            . (Join-Path $scriptRoot "Private\Core\InvokeWmrTemplate.ps1")

            $templateName = (Get-Item $templateFullPath).BaseName

            # Pass the machine backup directory directly - templates handle their own subdirectories
            Invoke-WmrTemplate -TemplatePath $templateFullPath -Operation "Backup" -StateFilesDirectory $testPaths.MachineBackup
            Write-Information -MessageData "✓ Template backup completed successfully" -InformationAction Continue

            # Show what was backed up
            Write-Information -MessageData "`n=== BACKUP CONTENTS ===" -InformationAction Continue
            Show-DirectoryContents -Path $componentBackupDir -BasePathForDisplay $componentBackupDir
        }

        Write-Information -MessageData "`nTest backup completed! Use 'list' operation to see available backups." -InformationAction Continue
        return $true

    } catch {
        Write-Error -Message "Test backup failed: $($_.Exception.Message)"
        Write-Information -MessageData $_.ScriptStackTrace  -InformationAction Continue-ForegroundColor DarkRed
        return $false
    } finally {
        if ($originalConfig) {
            $global:WindowsMelodyRecovery = $originalConfig
        }
    }
}

function Invoke-TestRestore {
    param(
        [string]$TemplatePath,
        [string]$BackupName,
        [switch]$UseTestData,
        [switch]$Force
    )

    Write-Information -MessageData "=== TEMPLATE RESTORE TEST ===" -InformationAction Continue
    Write-Warning -Message "Template: $TemplatePath"
    Write-Warning -Message "Backup Name: $BackupName"

    if (-not $Force) {
        Write-Warning -Message "*** RUNNING IN SAFE WHATIF MODE - NO SYSTEM CHANGES WILL BE MADE ***" -BackgroundColor DarkRed
        Write-Warning -Message "*** Use -Force parameter to make actual changes (NOT RECOMMENDED for testing) ***" -BackgroundColor DarkRed
        Write-Information -MessageData "" -InformationAction Continue
    }

    try {
        # Import module and set test config
        Import-Module .\WindowsMelodyRecovery.psm1 -Force -WarningAction SilentlyContinue
        $originalConfig = Get-WindowsMelodyRecovery
        $testConfig = Get-TestConfig
        $global:WindowsMelodyRecovery = [PSCustomObject]$testConfig

        # Determine source directory - templates create their own subdirectories
        if ($UseTestData) {
            $sourceDir = $testPaths.TestData
            Write-Warning -Message "Source: Test Data Directory"
        } else {
            $sourceDir = $testPaths.MachineBackup
            Write-Warning -Message "Source: Backup Test Directory"
        }

        $restoreStateDir = $testPaths.RestoreTarget

        Write-Warning -Message "Source Directory: $sourceDir"
        Write-Warning -Message "Restore State Directory: $restoreStateDir"
        Write-Information -MessageData "" -InformationAction Continue

        # Validate source directory exists
        $componentSourceDir = Join-Path $sourceDir $BackupName
        if (-not (Test-Path $componentSourceDir)) {
            if ($UseTestData) {
                throw "Test data directory not found: $componentSourceDir. Create test data first."
            } else {
                throw "Backup directory not found: $componentSourceDir. Run backup operation first."
            }
        }

        # Ensure restore directory exists
        if (-not (Test-Path $restoreStateDir)) {
            New-Item -ItemType Directory -Path $restoreStateDir -Force | Out-Null
        }

        # Show what's available to restore
        Write-Information -MessageData "=== AVAILABLE BACKUP DATA ===" -InformationAction Continue
        Show-DirectoryContents -Path $componentSourceDir -BasePathForDisplay $componentSourceDir
        Write-Information -MessageData "" -InformationAction Continue

        # Copy source data to restore location with correct structure
        Write-Information -MessageData "Copying backup data to restore location..." -InformationAction Continue

        # Copy the component-specific directory from source to restore location
        $componentSourceDir = Join-Path $sourceDir $BackupName
        if (-not (Test-Path $componentSourceDir)) {
            throw "Component backup directory not found: $componentSourceDir"
        }

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

        return $true

    } catch {
        Write-Error -Message "Test restore failed: $($_.Exception.Message)"
        Write-Information -MessageData $_.ScriptStackTrace  -InformationAction Continue-ForegroundColor DarkRed
        return $false
    } finally {
        if ($originalConfig) {
            $global:WindowsMelodyRecovery = $originalConfig
        }
    }
}

function Invoke-TestWorkflow {
    param(
        [string]$TemplatePath,
        [switch]$Force
    )

    Write-Verbose -Message "=== COMPLETE TEMPLATE WORKFLOW TEST ==="
    Write-Warning -Message "Template: $TemplatePath"

    if (-not $Force) {
        Write-Warning -Message "*** RESTORE WILL RUN IN SAFE WHATIF MODE ***" -BackgroundColor DarkRed
    }
    Write-Information -MessageData "" -InformationAction Continue

    # Step 1: Backup
    Write-Information -MessageData "STEP 1: Performing backup..." -InformationAction Continue
    $backupSuccess = Invoke-TestBackup -TemplatePath $TemplatePath

    if (-not $backupSuccess) {
        Write-Error -Message "❌ Workflow failed at backup step"
        return $false
    }

    Write-Information -MessageData "" -InformationAction Continue
    Start-Sleep -Seconds 2

    # Step 2: Restore
    Write-Information -MessageData "STEP 2: Performing restore..." -InformationAction Continue
    if ($TemplatePath -eq "ALL") {
        Write-Error -Message "❌ Workflow restore not supported for 'ALL' templates"
        return $false
    }

    $templateFullPath = if (Test-Path $TemplatePath) { $TemplatePath } else { Join-Path $scriptRoot "Templates\System\$TemplatePath" }
    $templateName = (Get-Item $templateFullPath).BaseName

    $restoreSuccess = Invoke-TestRestore -TemplatePath $TemplatePath -BackupName $templateName -Force:$Force

    if (-not $restoreSuccess) {
        Write-Error -Message "❌ Workflow failed at restore step"
        return $false
    }

    Write-Information -MessageData "" -InformationAction Continue
    Write-Information -MessageData "🎉 COMPLETE WORKFLOW SUCCESS!" -InformationAction Continue
    Write-Information -MessageData "Both backup and restore operations completed successfully." -InformationAction Continue
    return $true
}

function Show-DirectoryContent {
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

function Invoke-CleanTest {
    Write-Warning -Message "=== CLEANING TEST DIRECTORIES ==="

    foreach ($dir in $testDirectories.Values) {
        if (Test-Path $dir) {
            Write-Information -MessageData "Removing: $dir" -InformationAction Continue
            Remove-Item $dir -Recurse -Force
        }
    }

    Write-Information -MessageData "✓ All test directories cleaned" -InformationAction Continue
}

function Invoke-ListBackup {
    Write-Information -MessageData "=== AVAILABLE TEST BACKUPS ===" -InformationAction Continue

    if (-not (Test-Path $testPaths.MachineBackup)) {
        Write-Warning -Message "No test backups found. Run backup operation first."
        return
    }

    $backups = Get-ChildItem $testPaths.MachineBackup -Directory -ErrorAction SilentlyContinue

    if ($backups.Count -eq 0) {
        Write-Warning -Message "No test backups found. Run backup operation first."
        return
    }

    foreach ($backup in $backups) {
        Write-Information -MessageData "`n📦 $($backup.Name)" -InformationAction Continue
        Write-Verbose -Message "   Created: $($backup.CreationTime)"
        Write-Verbose -Message "   Location: $($backup.FullName)"

        # Show contents summary
        $files = Get-ChildItem $backup.FullName -Recurse -File
        $totalSize = ($files | Measure-Object Length -Sum).Sum
        $sizeDisplay = if ($totalSize -lt 1KB) { "$totalSize B" } elseif ($totalSize -lt 1MB) { "{0:N1} KB" -f ($totalSize / 1KB) } else { "{0:N1} MB" -f ($totalSize / 1MB) }

        Write-Verbose -Message "   Files: $($files.Count), Total Size: $sizeDisplay"

        # Usage example
        Write-Information -MessageData "   Usage: .\test-template-workflow.ps1 -Operation restore -TemplatePath `" -InformationAction Continue$($backup.Name).yaml`" -BackupName `"$($backup.Name)`"" -ForegroundColor DarkGray
    }
}

# Main execution
try {
    Initialize-TestDirectories

    switch ($Operation) {
        "backup" {
            if (-not $TemplatePath) {
                throw "TemplatePath parameter is required for backup operation"
            }
            Invoke-TestBackup -TemplatePath $TemplatePath
        }

        "restore" {
            if (-not $TemplatePath -or -not $BackupName) {
                throw "TemplatePath and BackupName parameters are required for restore operation"
            }
            Invoke-TestRestore -TemplatePath $TemplatePath -BackupName $BackupName -UseTestData:$UseTestData -Force:$Force
        }

        "workflow" {
            if (-not $TemplatePath) {
                throw "TemplatePath parameter is required for workflow operation"
            }
            Invoke-TestWorkflow -TemplatePath $TemplatePath -Force:$Force
        }

        "clean" {
            Invoke-CleanTest
        }

        "list" {
            Invoke-ListBackups
        }
    }

} catch {
    Write-Error -Message "Operation failed: $($_.Exception.Message)"
    exit 1
} finally {
    Pop-Location
}







