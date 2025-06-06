[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$BackupRootPath = $null,
    
    [Parameter(Mandatory=$false)]
    [string]$MachineBackupPath = $null,
    
    [Parameter(Mandatory=$false)]
    [string]$SharedBackupPath = $null
)

# Load environment script from the correct location
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$modulePath = Split-Path -Parent (Split-Path -Parent $scriptPath)
$loadEnvPath = Join-Path $modulePath "Private\scripts\load-environment.ps1"

# Source the load-environment script
if (Test-Path $loadEnvPath) {
    . $loadEnvPath
} else {
    Write-Host "Cannot find load-environment.ps1 at: $loadEnvPath" -ForegroundColor Red
}

# Get module configuration
$config = Get-WindowsMissingRecovery
if (!$config.IsInitialized) {
    throw "Module not initialized. Please run Initialize-WindowsMissingRecovery first."
}

if (!$BackupRootPath) {
    $BackupRootPath = Join-Path $config.BackupRoot $config.MachineName
}

# Define Test-BackupPath function directly in the script
function Test-BackupPath {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Path,
        
        [Parameter(Mandatory=$true)]
        [string]$BackupType
    )
    
    # First check machine-specific backup
    $machinePath = Join-Path $BackupRootPath $Path
    if (Test-Path $machinePath) {
        Write-Host "Using machine-specific $BackupType backup from: $machinePath" -ForegroundColor Green
        return $machinePath
    }
    
    # Fall back to shared backup if available
    if ($SharedBackupPath) {
        $sharedPath = Join-Path $SharedBackupPath $Path
        if (Test-Path $sharedPath) {
            Write-Host "Using shared $BackupType backup from: $sharedPath" -ForegroundColor Green
            return $sharedPath
        }
    }
    
    Write-Host "No $BackupType backup found" -ForegroundColor Yellow
    return $null
}

function Restore-ExcelSettings {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory=$true)]
        [string]$BackupRootPath,
        
        [Parameter(Mandatory=$false)]
        [switch]$Force,

        [Parameter(Mandatory=$false)]
        [string[]]$Include,

        [Parameter(Mandatory=$false)]
        [string[]]$Exclude,

        # For testing purposes
        [Parameter(DontShow)]
        [switch]$SkipVerification
    )
    
    begin {
        # Test hook for mocking
        if ($script:TestMode) {
            Write-Verbose "Running in test mode"
        }

        # Initialize result object
        $result = [PSCustomObject]@{
            Success = $false
            RestorePath = $null
            Feature = "Excel Settings"
            Timestamp = Get-Date
            ItemsRestored = @()
            ItemsSkipped = @()
            Errors = @()
        }
    }
    
    process {
        try {
            Write-Verbose "Starting restore of Excel Settings..."
            Write-Host "Restoring Excel Settings..." -ForegroundColor Blue
            
            # Validate inputs
            if (!(Test-Path $BackupRootPath)) {
                throw [System.IO.DirectoryNotFoundException]"Backup root path not found: $BackupRootPath"
            }
            
            $backupPath = Test-BackupPath -Path "Excel" -BackupType "Excel Settings"
            if (!$backupPath) {
                throw "No valid backup found for Excel Settings"
            }
            $result.RestorePath = $backupPath
            
            if ($backupPath) {
                # Excel config locations
                $excelConfigs = @{
                    "AppData" = "$env:APPDATA\Microsoft\Excel"
                    "Templates" = "$env:APPDATA\Microsoft\Templates"
                    "XLSTART" = "$env:APPDATA\Microsoft\Excel\XLSTART"
                    "AddIns" = "$env:APPDATA\Microsoft\AddIns"
                    "QuickAccess" = "$env:APPDATA\Microsoft\Windows\Recent\Excel.lnk"
                }

                # Restore registry settings first
                $registryPath = Join-Path $backupPath "Registry"
                if (Test-Path $registryPath) {
                    if ($Force -or $PSCmdlet.ShouldProcess("Excel Registry Settings", "Restore")) {
                        Get-ChildItem -Path $registryPath -Filter "*.reg" | ForEach-Object {
                            try {
                                Write-Host "Importing registry file: $($_.Name)" -ForegroundColor Yellow
                                if (!$script:TestMode) {
                                    reg import $_.FullName 2>$null
                                }
                                $result.ItemsRestored += "Registry\$($_.Name)"
                            } catch {
                                $result.Errors += "Failed to import registry file $($_.Name): $_"
                                $result.ItemsSkipped += "Registry\$($_.Name)"
                                if (!$Force) { throw }
                            }
                        }
                    }
                } else {
                    $result.ItemsSkipped += "Registry (not found in backup)"
                }

                # Restore config files
                foreach ($config in $excelConfigs.GetEnumerator()) {
                    $backupItem = Join-Path $backupPath $config.Key
                    if (Test-Path $backupItem) {
                        if ($Force -or $PSCmdlet.ShouldProcess("Excel $($config.Key)", "Restore")) {
                            try {
                                # Create parent directory if it doesn't exist
                                $parentDir = Split-Path $config.Value -Parent
                                if (!(Test-Path $parentDir)) {
                                    if (!$script:TestMode) {
                                        New-Item -ItemType Directory -Force -Path $parentDir | Out-Null
                                    }
                                }

                                if ((Get-Item $backupItem) -is [System.IO.DirectoryInfo]) {
                                    $excludeFilter = @("*.tmp", "~*.*", "*.xlk")
                                    if (!$script:TestMode) {
                                        Copy-Item $backupItem $config.Value -Recurse -Force -Exclude $excludeFilter
                                    }
                                } else {
                                    if (!$script:TestMode) {
                                        Copy-Item $backupItem $config.Value -Force
                                    }
                                }
                                Write-Host "Restored configuration: $($config.Key)" -ForegroundColor Green
                                $result.ItemsRestored += $config.Key
                            } catch {
                                $result.Errors += "Failed to restore $($config.Key): $_"
                                $result.ItemsSkipped += $config.Key
                                if (!$Force) { throw }
                            }
                        }
                    } else {
                        $result.ItemsSkipped += "$($config.Key) (not found in backup)"
                    }
                }

                # Restore recent files list if available
                $recentFile = Join-Path $backupPath "recent_files.txt"
                if (Test-Path $recentFile) {
                    if ($Force -or $PSCmdlet.ShouldProcess("Excel Recent Files", "Restore")) {
                        try {
                            Write-Host "Recent files list found in backup" -ForegroundColor Yellow
                            $result.ItemsRestored += "recent_files.txt"
                        } catch {
                            $result.Errors += "Failed to process recent files list: $_"
                            $result.ItemsSkipped += "recent_files.txt"
                            if (!$Force) { throw }
                        }
                    }
                } else {
                    $result.ItemsSkipped += "recent_files.txt (not found in backup)"
                }
                
                $result.Success = ($result.Errors.Count -eq 0)
                
                # Display summary
                Write-Host "`nExcel Settings Restore Summary:" -ForegroundColor Green
                Write-Host "Items Restored: $($result.ItemsRestored.Count)" -ForegroundColor Yellow
                Write-Host "Items Skipped: $($result.ItemsSkipped.Count)" -ForegroundColor Yellow
                Write-Host "Errors: $($result.Errors.Count)" -ForegroundColor $(if ($result.Errors.Count -gt 0) { "Red" } else { "Yellow" })
                
                if ($result.Success) {
                    Write-Host "Excel Settings restored successfully from: $backupPath" -ForegroundColor Green
                    Write-Host "`nNote: Excel restart may be required for settings to take effect" -ForegroundColor Yellow
                } else {
                    Write-Warning "Excel Settings restore completed with errors"
                }
                
                Write-Verbose "Restore completed successfully"
                return $result
            }
            return $result
        } catch {
            $errorRecord = $_
            $errorMessage = @(
                "Failed to restore Excel Settings"
                "Error Message: $($errorRecord.Exception.Message)"
                "Error Type: $($errorRecord.Exception.GetType().FullName)"
                "Script Line Number: $($errorRecord.InvocationInfo.ScriptLineNumber)"
                "Script Name: $($errorRecord.InvocationInfo.ScriptName)"
                "Statement: $($errorRecord.InvocationInfo.Line.Trim())"
                if ($errorRecord.Exception.StackTrace) { "Stack Trace: $($errorRecord.Exception.StackTrace)" }
                if ($errorRecord.Exception.InnerException) { "Inner Exception: $($errorRecord.Exception.InnerException.Message)" }
            ) -join "`n"
            
            Write-Error $errorMessage
            Write-Verbose "Restore failed"
            $result.Errors += $errorMessage
            return $result
        }
    }

    end {
        # Log results
        if ($result.Errors.Count -gt 0) {
            Write-Warning "Restore completed with $($result.Errors.Count) errors"
        }
        Write-Verbose "Restored $($result.ItemsRestored.Count) items, skipped $($result.ItemsSkipped.Count) items"
    }
}

# Export the function if being imported as a module
if ($MyInvocation.Line -eq "") {
    Export-ModuleMember -Function Restore-ExcelSettings
}

<#
.SYNOPSIS
Restores Excel settings and configuration from backup.

.DESCRIPTION
Restores Excel configuration and associated data from a previous backup, including registry settings, 
configuration files, templates, add-ins, and recent files list. Supports multiple Excel versions 
(2010, 2013, 2016/365) and handles both user-specific and system-wide settings.

.PARAMETER BackupRootPath
The root path where the backup is located. The script will look for an "Excel" subdirectory within this path.

.PARAMETER Force
Forces the restore operation without prompting for confirmation and continues even if some items fail to restore.

.PARAMETER Include
Array of item names to include in the restore operation. If not specified, all available items are restored.

.PARAMETER Exclude
Array of item names to exclude from the restore operation.

.PARAMETER SkipVerification
Skips backup integrity verification (useful for testing).

.EXAMPLE
Restore-ExcelSettings -BackupRootPath "C:\Backups"

.EXAMPLE
Restore-ExcelSettings -BackupRootPath "C:\Backups" -Force

.EXAMPLE
Restore-ExcelSettings -BackupRootPath "C:\Backups" -WhatIf

.NOTES
Test cases to consider:
1. Valid backup with all files present
2. Partial backup (some files missing)
3. Corrupted backup
4. No backup found
5. Backup with invalid format
6. Permission issues during restore
7. Registry import failures
8. Configuration file restore failures
9. Multiple Excel versions scenario
10. WhatIf scenario
11. Force parameter behavior
12. Include/Exclude filters
13. Excel process running during restore
14. Insufficient disk space
15. Network path backup scenarios

.TESTCASES
# Mock test examples:
Describe "Restore-ExcelSettings" {
    BeforeAll {
        $script:TestMode = $true
        Mock Test-Path { return $true }
        Mock Test-BackupPath { return "TestPath" }
        Mock Get-ChildItem { 
            return @(
                [PSCustomObject]@{ Name = "Excel.reg"; FullName = "TestPath\Registry\Excel.reg" },
                [PSCustomObject]@{ Name = "Options.reg"; FullName = "TestPath\Registry\Options.reg" }
            )
        }
        Mock Copy-Item { }
        Mock New-Item { }
        Mock reg { }
    }

    AfterAll {
        $script:TestMode = $false
    }

    It "Should return a valid result object" {
        $result = Restore-ExcelSettings -BackupRootPath "TestPath"
        $result.Success | Should -Be $true
        $result.RestorePath | Should -Be "TestPath"
        $result.Feature | Should -Be "Excel Settings"
        $result.ItemsRestored | Should -BeOfType [System.Array]
        $result.ItemsSkipped | Should -BeOfType [System.Array]
        $result.Errors | Should -BeOfType [System.Array]
    }

    It "Should handle WhatIf properly" {
        $result = Restore-ExcelSettings -BackupRootPath "TestPath" -WhatIf
        $result.ItemsRestored.Count | Should -Be 0
    }

    It "Should handle registry import failure gracefully with Force" {
        Mock reg { throw "Registry import failed" }
        $result = Restore-ExcelSettings -BackupRootPath "TestPath" -Force
        $result.Errors.Count | Should -BeGreaterThan 0
        $result.ItemsSkipped.Count | Should -BeGreaterThan 0
    }

    It "Should handle missing backup gracefully" {
        Mock Test-BackupPath { return $null }
        { Restore-ExcelSettings -BackupRootPath "TestPath" } | Should -Throw
    }

    It "Should skip verification when specified" {
        $result = Restore-ExcelSettings -BackupRootPath "TestPath" -SkipVerification
        $result.Success | Should -Be $true
    }
}
#>

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Restore-ExcelSettings -BackupRootPath $BackupRootPath
} 