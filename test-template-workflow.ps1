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

function Initialize-TestDirectories {
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
    
    Write-Host "=== TEMPLATE BACKUP TEST ===" -ForegroundColor Cyan
    Write-Host "Template: $TemplatePath" -ForegroundColor Yellow
    Write-Host "Test Backup Directory: $($testDirectories.BackupsRoot)" -ForegroundColor Yellow
    Write-Host ""
    
    try {
        # Import module and set test config
        Import-Module .\WindowsMelodyRecovery.psm1 -Force -WarningAction SilentlyContinue
        $originalConfig = Get-WindowsMelodyRecovery
        $testConfig = Get-TestConfig
        $global:WindowsMelodyRecovery = [PSCustomObject]$testConfig
        
        if ($TemplatePath -eq "ALL") {
            # Test all templates
            Write-Host "Testing all available templates..." -ForegroundColor Green
            $templatesPath = Join-Path $scriptRoot "Templates\System"
            $templateFiles = Get-ChildItem -Path $templatesPath -Filter "*.yaml" -ErrorAction SilentlyContinue
            
            $successCount = 0
            $failCount = 0
            
            foreach ($templateFile in $templateFiles) {
                Write-Host "`n--- Testing: $($templateFile.Name) ---" -ForegroundColor Cyan
                try {
                    . (Join-Path $scriptRoot "Private\Core\InvokeWmrTemplate.ps1")
                    
                    $componentBackupDir = Join-Path $testPaths.MachineBackup $templateFile.BaseName
                    if (-not (Test-Path $componentBackupDir)) {
                        New-Item -ItemType Directory -Path $componentBackupDir -Force | Out-Null
                    }
                    
                    Invoke-WmrTemplate -TemplatePath $templateFile.FullName -Operation "Backup" -StateFilesDirectory $componentBackupDir
                    Write-Host "✓ $($templateFile.Name) backup completed successfully" -ForegroundColor Green
                    $successCount++
                } catch {
                    Write-Host "✗ $($templateFile.Name) backup failed: $($_.Exception.Message)" -ForegroundColor Red
                    $failCount++
                }
            }
            
            Write-Host "`n=== BACKUP SUMMARY ===" -ForegroundColor Cyan
            Write-Host "Successful: $successCount" -ForegroundColor Green
            Write-Host "Failed: $failCount" -ForegroundColor Red
            Write-Host "Total: $($successCount + $failCount)" -ForegroundColor Yellow
            
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
            Write-Host "✓ Template backup completed successfully" -ForegroundColor Green
            
            # Show what was backed up
            Write-Host "`n=== BACKUP CONTENTS ===" -ForegroundColor Cyan
            Show-DirectoryContents -Path $componentBackupDir -BasePathForDisplay $componentBackupDir
        }
        
        Write-Host "`nTest backup completed! Use 'list' operation to see available backups." -ForegroundColor Green
        return $true
        
    } catch {
        Write-Host "Test backup failed: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host $_.ScriptStackTrace -ForegroundColor DarkRed
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
    
    Write-Host "=== TEMPLATE RESTORE TEST ===" -ForegroundColor Cyan
    Write-Host "Template: $TemplatePath" -ForegroundColor Yellow
    Write-Host "Backup Name: $BackupName" -ForegroundColor Yellow
    
    if (-not $Force) {
        Write-Host "*** RUNNING IN SAFE WHATIF MODE - NO SYSTEM CHANGES WILL BE MADE ***" -ForegroundColor Yellow -BackgroundColor DarkRed
        Write-Host "*** Use -Force parameter to make actual changes (NOT RECOMMENDED for testing) ***" -ForegroundColor Yellow -BackgroundColor DarkRed
        Write-Host ""
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
            Write-Host "Source: Test Data Directory" -ForegroundColor Yellow
        } else {
            $sourceDir = $testPaths.MachineBackup
            Write-Host "Source: Backup Test Directory" -ForegroundColor Yellow
        }
        
        $restoreStateDir = $testPaths.RestoreTarget
        
        Write-Host "Source Directory: $sourceDir" -ForegroundColor Yellow
        Write-Host "Restore State Directory: $restoreStateDir" -ForegroundColor Yellow
        Write-Host ""
        
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
        Write-Host "=== AVAILABLE BACKUP DATA ===" -ForegroundColor Green
        Show-DirectoryContents -Path $componentSourceDir -BasePathForDisplay $componentSourceDir
        Write-Host ""
        
        # Copy source data to restore location with correct structure
        Write-Host "Copying backup data to restore location..." -ForegroundColor Cyan
        
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
        
        Write-Host "Testing template restore..." -ForegroundColor Green
        
        # Dot-source the InvokeWmrTemplate module
        . (Join-Path $scriptRoot "Private\Core\InvokeWmrTemplate.ps1")
        
        # Perform the restore operation using the copied data
        if ($Force) {
            Invoke-WmrTemplate -TemplatePath $templateFullPath -Operation "Restore" -StateFilesDirectory $restoreStateDir
        } else {
            Invoke-WmrTemplate -TemplatePath $templateFullPath -Operation "Restore" -StateFilesDirectory $restoreStateDir -WhatIf
        }
        Write-Host "✓ Template restore completed successfully" -ForegroundColor Green
        
        # Show restore results
        Write-Host "`n=== RESTORE SIMULATION RESULTS ===" -ForegroundColor Green
        if ($Force) {
            Write-Host "Note: Actual restore operations were performed on the live system." -ForegroundColor Red
        } else {
            Write-Host "Note: This was a safe simulation. No actual system changes were made." -ForegroundColor Green
        }
        Write-Host "Restore data processed from: $restoreStateDir" -ForegroundColor Cyan
        
        return $true
        
    } catch {
        Write-Host "Test restore failed: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host $_.ScriptStackTrace -ForegroundColor DarkRed
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
    
    Write-Host "=== COMPLETE TEMPLATE WORKFLOW TEST ===" -ForegroundColor Magenta
    Write-Host "Template: $TemplatePath" -ForegroundColor Yellow
    
    if (-not $Force) {
        Write-Host "*** RESTORE WILL RUN IN SAFE WHATIF MODE ***" -ForegroundColor Yellow -BackgroundColor DarkRed
    }
    Write-Host ""
    
    # Step 1: Backup
    Write-Host "STEP 1: Performing backup..." -ForegroundColor Cyan
    $backupSuccess = Invoke-TestBackup -TemplatePath $TemplatePath
    
    if (-not $backupSuccess) {
        Write-Host "❌ Workflow failed at backup step" -ForegroundColor Red
        return $false
    }
    
    Write-Host ""
    Start-Sleep -Seconds 2
    
    # Step 2: Restore
    Write-Host "STEP 2: Performing restore..." -ForegroundColor Cyan
    if ($TemplatePath -eq "ALL") {
        Write-Host "❌ Workflow restore not supported for 'ALL' templates" -ForegroundColor Red
        return $false
    }
    
    $templateFullPath = if (Test-Path $TemplatePath) { $TemplatePath } else { Join-Path $scriptRoot "Templates\System\$TemplatePath" }
    $templateName = (Get-Item $templateFullPath).BaseName
    
    $restoreSuccess = Invoke-TestRestore -TemplatePath $TemplatePath -BackupName $templateName -Force:$Force
    
    if (-not $restoreSuccess) {
        Write-Host "❌ Workflow failed at restore step" -ForegroundColor Red
        return $false
    }
    
    Write-Host ""
    Write-Host "🎉 COMPLETE WORKFLOW SUCCESS!" -ForegroundColor Green
    Write-Host "Both backup and restore operations completed successfully." -ForegroundColor Green
    return $true
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
                Write-Host "📁 $relativePath" -ForegroundColor Blue
            } else {
                $size = if ($_.Length -lt 1KB) { "$($_.Length) B" } elseif ($_.Length -lt 1MB) { "{0:N1} KB" -f ($_.Length / 1KB) } else { "{0:N1} MB" -f ($_.Length / 1MB) }
                Write-Host "📄 $relativePath ($size)" -ForegroundColor Gray
            }
        }
    }
}

function Invoke-CleanTest {
    Write-Host "=== CLEANING TEST DIRECTORIES ===" -ForegroundColor Yellow
    
    foreach ($dir in $testDirectories.Values) {
        if (Test-Path $dir) {
            Write-Host "Removing: $dir" -ForegroundColor Cyan
            Remove-Item $dir -Recurse -Force
        }
    }
    
    Write-Host "✓ All test directories cleaned" -ForegroundColor Green
}

function Invoke-ListBackups {
    Write-Host "=== AVAILABLE TEST BACKUPS ===" -ForegroundColor Cyan
    
    if (-not (Test-Path $testPaths.MachineBackup)) {
        Write-Host "No test backups found. Run backup operation first." -ForegroundColor Yellow
        return
    }
    
    $backups = Get-ChildItem $testPaths.MachineBackup -Directory -ErrorAction SilentlyContinue
    
    if ($backups.Count -eq 0) {
        Write-Host "No test backups found. Run backup operation first." -ForegroundColor Yellow
        return
    }
    
    foreach ($backup in $backups) {
        Write-Host "`n📦 $($backup.Name)" -ForegroundColor Green
        Write-Host "   Created: $($backup.CreationTime)" -ForegroundColor Gray
        Write-Host "   Location: $($backup.FullName)" -ForegroundColor Gray
        
        # Show contents summary
        $files = Get-ChildItem $backup.FullName -Recurse -File
        $totalSize = ($files | Measure-Object Length -Sum).Sum
        $sizeDisplay = if ($totalSize -lt 1KB) { "$totalSize B" } elseif ($totalSize -lt 1MB) { "{0:N1} KB" -f ($totalSize / 1KB) } else { "{0:N1} MB" -f ($totalSize / 1MB) }
        
        Write-Host "   Files: $($files.Count), Total Size: $sizeDisplay" -ForegroundColor Gray
        
        # Usage example
        Write-Host "   Usage: .\test-template-workflow.ps1 -Operation restore -TemplatePath `"$($backup.Name).yaml`" -BackupName `"$($backup.Name)`"" -ForegroundColor DarkGray
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
    Write-Host "Operation failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
} finally {
    Pop-Location
} 